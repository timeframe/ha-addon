# frozen_string_literal: true

# Replaces inner_performance with rails_pulse.
#
# This migration is self-contained: it does NOT depend on the rails_pulse gem or
# its db/rails_pulse_schema.rb file. The engine and its migrations are shared by
# multiple apps (cloud and the ha-addon), and only some of them bundle the
# rails_pulse gem. Creating the tables inline (mirroring the gem's own schema)
# keeps the migration runnable everywhere, exactly like the legacy
# inner_performance migrations did.
class InstallRailsPulseTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :inner_performance_traces, if_exists: true
    drop_table :inner_performance_events, if_exists: true

    adapter = connection.adapter_name.downcase

    unless table_exists?(:rails_pulse_routes)
      create_table :rails_pulse_routes do |t|
        t.string :method, null: false
        t.string :path, null: false
        t.text :tags
        t.timestamps
      end
      add_index :rails_pulse_routes, [:method, :path], unique: true, name: "index_rails_pulse_routes_on_method_and_path"
      add_index :rails_pulse_routes, :path, name: "index_rails_pulse_routes_on_path"
    end

    unless table_exists?(:rails_pulse_queries)
      create_table :rails_pulse_queries do |t|
        t.string :hashed_sql, limit: 32, null: false
        t.text :normalized_sql, null: false
        t.datetime :analyzed_at
        t.text :explain_plan
        t.text :issues
        t.text :metadata
        t.text :query_stats
        t.text :backtrace_analysis
        t.text :index_recommendations
        t.text :n_plus_one_analysis
        t.text :suggestions
        t.text :tags
        t.timestamps
      end
      add_index :rails_pulse_queries, :hashed_sql, unique: true, name: "index_rails_pulse_queries_on_hashed_sql"
    end

    unless table_exists?(:rails_pulse_requests)
      create_table :rails_pulse_requests do |t|
        t.references :route, null: false, foreign_key: {to_table: :rails_pulse_routes}
        t.decimal :duration, precision: 15, scale: 6, null: false
        t.integer :status, null: false
        t.boolean :is_error, null: false, default: false
        t.string :request_uuid, null: false
        t.string :controller_action
        t.timestamp :occurred_at, null: false
        t.text :tags
        t.integer :response_size_bytes
        t.timestamps
      end
      add_index :rails_pulse_requests, :occurred_at, name: "index_rails_pulse_requests_on_occurred_at"
      add_index :rails_pulse_requests, :request_uuid, unique: true, name: "index_rails_pulse_requests_on_request_uuid"
      add_index :rails_pulse_requests, [:route_id, :occurred_at], name: "index_rails_pulse_requests_on_route_id_and_occurred_at"
    end

    unless table_exists?(:rails_pulse_jobs)
      create_table :rails_pulse_jobs do |t|
        t.string :name, null: false
        t.string :queue_name
        t.text :description
        t.integer :runs_count, null: false, default: 0
        t.integer :failures_count, null: false, default: 0
        t.integer :retries_count, null: false, default: 0
        t.decimal :avg_duration, precision: 15, scale: 6
        t.decimal :p95_duration, precision: 15, scale: 6
        t.decimal :p99_duration, precision: 15, scale: 6
        t.text :tags
        t.timestamps
      end
      add_index :rails_pulse_jobs, :name, unique: true, name: "index_rails_pulse_jobs_on_name"
      add_index :rails_pulse_jobs, :queue_name, name: "index_rails_pulse_jobs_on_queue"
      add_index :rails_pulse_jobs, :runs_count, name: "index_rails_pulse_jobs_on_runs_count"
    end

    unless table_exists?(:rails_pulse_job_runs)
      create_table :rails_pulse_job_runs do |t|
        t.references :job, null: false, foreign_key: {to_table: :rails_pulse_jobs}
        t.string :run_id, null: false
        t.decimal :duration, precision: 15, scale: 6
        t.string :status, null: false
        t.string :error_class
        t.text :error_message
        t.integer :attempts, null: false, default: 0
        t.timestamp :occurred_at, null: false
        t.timestamp :enqueued_at
        t.text :arguments
        t.string :adapter
        t.text :tags
        t.timestamps
      end
      add_index :rails_pulse_job_runs, :run_id, unique: true, name: "index_rails_pulse_job_runs_on_run_id"
      add_index :rails_pulse_job_runs, [:job_id, :occurred_at], name: "index_rails_pulse_job_runs_on_job_and_occurred"
      add_index :rails_pulse_job_runs, :occurred_at, name: "index_rails_pulse_job_runs_on_occurred_at"
      add_index :rails_pulse_job_runs, :status, name: "index_rails_pulse_job_runs_on_status"
      add_index :rails_pulse_job_runs, [:job_id, :status], name: "index_rails_pulse_job_runs_on_job_and_status"
    end

    unless table_exists?(:rails_pulse_operations)
      create_table :rails_pulse_operations do |t|
        t.references :request, null: true, foreign_key: {to_table: :rails_pulse_requests}
        t.references :job_run, null: true, foreign_key: {to_table: :rails_pulse_job_runs}
        t.references :query, foreign_key: {to_table: :rails_pulse_queries}, index: false
        t.string :operation_type, null: false
        t.string :label, null: false
        t.decimal :duration, precision: 15, scale: 6, null: false
        t.string :codebase_location
        t.float :start_time, null: false, default: 0.0
        t.timestamp :occurred_at, null: false
        t.integer :row_count
        t.boolean :cache_hit
        t.text :actual_sql
        t.text :repeated_query_group
        t.integer :repetition_count
        t.timestamps
      end
      add_index :rails_pulse_operations, :operation_type, name: "index_rails_pulse_operations_on_operation_type"
      add_index :rails_pulse_operations, [:query_id, :occurred_at], name: "index_rails_pulse_operations_on_query_and_time"
      add_index :rails_pulse_operations, [:query_id, :duration, :occurred_at], name: "index_rails_pulse_operations_query_performance"
      add_index :rails_pulse_operations, [:occurred_at, :duration, :operation_type], name: "index_rails_pulse_operations_on_time_duration_type"

      if adapter.include?("postgres") || adapter.include?("mysql")
        add_check_constraint :rails_pulse_operations,
          "(request_id IS NOT NULL OR job_run_id IS NOT NULL)",
          name: "rails_pulse_operations_request_or_job_run"
      end
    end

    unless table_exists?(:rails_pulse_summaries)
      create_table :rails_pulse_summaries do |t|
        t.datetime :period_start, null: false
        t.datetime :period_end, null: false
        t.string :period_type, null: false
        t.references :summarizable, polymorphic: true, null: false, index: true
        t.integer :count, default: 0, null: false
        t.float :avg_duration
        t.float :min_duration
        t.float :max_duration
        t.float :p50_duration
        t.float :p95_duration
        t.float :p99_duration
        t.float :total_duration
        t.float :stddev_duration
        t.integer :error_count, default: 0
        t.integer :success_count, default: 0
        t.integer :status_2xx, default: 0
        t.integer :status_3xx, default: 0
        t.integer :status_4xx, default: 0
        t.integer :status_5xx, default: 0
        t.timestamps
      end
      add_index :rails_pulse_summaries, [:summarizable_type, :summarizable_id, :period_type, :period_start], unique: true, name: "idx_pulse_summaries_unique"
      add_index :rails_pulse_summaries, [:period_type, :period_start], name: "index_rails_pulse_summaries_on_period"
      add_index :rails_pulse_summaries, :created_at, name: "index_rails_pulse_summaries_on_created_at"
      add_index :rails_pulse_summaries, :summarizable_id, name: "index_rails_pulse_summaries_on_summarizable_id"
      add_index :rails_pulse_summaries, :period_start, name: "index_rails_pulse_summaries_on_period_start"
    end

    unless table_exists?(:rails_pulse_deployments)
      create_table :rails_pulse_deployments do |t|
        t.string :revision, null: false
        t.datetime :started_at, null: false
        t.datetime :finished_at
        t.text :metadata
        t.timestamps
      end
      add_index :rails_pulse_deployments, :started_at, name: "index_rails_pulse_deployments_on_started_at"
      add_index :rails_pulse_deployments, :revision, name: "index_rails_pulse_deployments_on_revision"
    end

    unless index_exists?(:rails_pulse_requests, [:created_at, :route_id], name: "idx_requests_for_aggregation")
      add_index :rails_pulse_requests, [:created_at, :route_id], name: "idx_requests_for_aggregation"
    end

    unless index_exists?(:rails_pulse_operations, [:created_at, :query_id], name: "idx_operations_for_aggregation")
      add_index :rails_pulse_operations, [:created_at, :query_id], name: "idx_operations_for_aggregation"
    end
  end

  def down
    drop_table :rails_pulse_operations, if_exists: true
    drop_table :rails_pulse_job_runs, if_exists: true
    drop_table :rails_pulse_jobs, if_exists: true
    drop_table :rails_pulse_summaries, if_exists: true
    drop_table :rails_pulse_deployments, if_exists: true
    drop_table :rails_pulse_requests, if_exists: true
    drop_table :rails_pulse_routes, if_exists: true
    drop_table :rails_pulse_queries, if_exists: true
  end
end
