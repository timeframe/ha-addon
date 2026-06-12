# frozen_string_literal: true

# Removes the rails_pulse and active_analytics tables. Both gems were removed
# because their telemetry filled the 1 GB database. Drops are idempotent so this
# runs cleanly whether or not the tables exist (e.g. fresh databases that never
# ran the original create migrations).
class DropRailsPulseAndActiveAnalyticsTables < ActiveRecord::Migration[8.1]
  def up
    # rails_pulse (drop in FK-dependency order)
    drop_table :rails_pulse_operations, if_exists: true
    drop_table :rails_pulse_job_runs, if_exists: true
    drop_table :rails_pulse_jobs, if_exists: true
    drop_table :rails_pulse_summaries, if_exists: true
    drop_table :rails_pulse_deployments, if_exists: true
    drop_table :rails_pulse_requests, if_exists: true
    drop_table :rails_pulse_routes, if_exists: true
    drop_table :rails_pulse_queries, if_exists: true

    # active_analytics
    drop_table :active_analytics_views_per_days, if_exists: true
    drop_table :active_analytics_browsers_per_days, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
