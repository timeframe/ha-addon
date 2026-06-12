# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 23) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "account_users", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "owner", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "role"], name: "index_account_users_on_account_id_unique_owner", unique: true, where: "((role)::text = 'owner'::text)"
    t.index ["account_id", "user_id"], name: "index_account_users_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_account_users_on_account_id"
    t.index ["user_id"], name: "index_account_users_on_user_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "name", null: false
    t.string "precipitation_unit", default: "in", null: false
    t.string "speed_unit", default: "mph", null: false
    t.datetime "support_access_at"
    t.string "temperature_unit", default: "F", null: false
    t.datetime "updated_at", null: false
  end

  create_table "active_analytics_browsers_per_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "name", null: false
    t.string "site", null: false
    t.bigint "total", default: 1, null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["date", "site", "name", "version"], name: "idx_on_date_site_name_version_eeccd0371c"
  end

  create_table "active_analytics_views_per_days", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "page", null: false
    t.string "referrer_host"
    t.string "referrer_path"
    t.string "site", null: false
    t.bigint "total", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["date", "site", "page"], name: "idx_on_date_site_page_bfd4b98166"
    t.index ["date", "site", "referrer_host", "referrer_path"], name: "index_views_per_days_on_date_site_referrer_host_referrer_path"
  end

  create_table "apple_accounts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "app_specific_password", null: false
    t.string "caldav_principal_url"
    t.string "calendar_home_url"
    t.datetime "created_at", null: false
    t.text "email", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "email"], name: "index_apple_accounts_on_account_id_and_email", unique: true
    t.index ["account_id"], name: "index_apple_accounts_on_account_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.json "metadata"
    t.string "result_type"
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["event_type"], name: "index_audit_logs_on_event_type"
    t.index ["subject_type", "subject_id"], name: "index_audit_logs_on_subject"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "calendar_events", force: :cascade do |t|
    t.bigint "calendar_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "end_timezone"
    t.datetime "ends_at", null: false
    t.string "external_id", null: false
    t.boolean "has_attachment", default: false, null: false
    t.string "location"
    t.string "provider_etag"
    t.string "provider_url"
    t.string "start_timezone"
    t.datetime "starts_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["calendar_id", "external_id"], name: "index_calendar_events_on_calendar_id_and_external_id", unique: true
    t.index ["calendar_id"], name: "index_calendar_events_on_calendar_id"
    t.index ["ends_at"], name: "index_calendar_events_on_ends_at"
    t.index ["starts_at"], name: "index_calendar_events_on_starts_at"
  end

  create_table "calendars", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "apple_account_id"
    t.string "caldav_url"
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
    t.string "external_id"
    t.bigint "google_account_id"
    t.string "icon"
    t.datetime "last_synced_at"
    t.bigint "microsoft_account_id"
    t.string "name", null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "webhook_channel_id"
    t.datetime "webhook_expires_at"
    t.string "webhook_resource_id"
    t.index ["account_id", "source_type", "url"], name: "index_calendars_on_account_id_and_source_type_and_url", unique: true
    t.index ["account_id"], name: "index_calendars_on_account_id"
    t.index ["apple_account_id"], name: "index_calendars_on_apple_account_id"
    t.index ["google_account_id", "external_id"], name: "index_calendars_on_google_account_id_and_external_id", unique: true
    t.index ["google_account_id"], name: "index_calendars_on_google_account_id"
    t.index ["microsoft_account_id"], name: "index_calendars_on_microsoft_account_id"
  end

  create_table "devices", force: :cascade do |t|
    t.text "api_key"
    t.float "battery_level"
    t.text "cached_image"
    t.datetime "cached_image_at"
    t.jsonb "configuration", default: {}, null: false
    t.string "confirmation_code"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.boolean "demo_mode_enabled", default: false, null: false
    t.text "display_key"
    t.bigint "display_state_crc"
    t.string "display_template", default: "default", null: false
    t.string "excluded_calendar_identifiers", default: [], null: false, array: true
    t.string "firmware_version"
    t.string "friendly_id"
    t.datetime "last_connection_at"
    t.bigint "location_id"
    t.text "mac_address"
    t.string "model", null: false
    t.string "name", null: false
    t.integer "rssi"
    t.text "session_token"
    t.float "temperature"
    t.datetime "updated_at", null: false
    t.text "visionect_serial"
    t.index ["api_key"], name: "index_devices_on_api_key", unique: true
    t.index ["confirmation_code"], name: "index_devices_on_confirmation_code", unique: true
    t.index ["display_key"], name: "index_devices_on_display_key", unique: true
    t.index ["location_id"], name: "index_devices_on_location_id"
    t.index ["mac_address"], name: "index_devices_on_mac_address", unique: true
    t.index ["session_token"], name: "index_devices_on_session_token", unique: true
    t.index ["visionect_serial"], name: "index_devices_on_visionect_serial", unique: true
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "callback_priority"
    t.text "callback_queue_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discarded_at"
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.text "on_discard"
    t.text "on_finish"
    t.text "on_success"
    t.jsonb "serialized_properties"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id", null: false
    t.datetime "created_at", null: false
    t.interval "duration"
    t.text "error"
    t.text "error_backtrace", array: true
    t.integer "error_event", limit: 2
    t.datetime "finished_at"
    t.text "job_class"
    t.uuid "process_id"
    t.text "queue_name"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_good_job_executions_on_active_job_id"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_type", limit: 2
    t.jsonb "state"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "key"
    t.datetime "updated_at", null: false
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id"
    t.uuid "batch_callback_id"
    t.uuid "batch_id"
    t.text "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "cron_at"
    t.text "cron_key"
    t.text "error"
    t.integer "error_event", limit: 2
    t.integer "executions_count"
    t.datetime "finished_at"
    t.boolean "is_discrete"
    t.text "job_class"
    t.text "labels", array: true
    t.datetime "locked_at"
    t.uuid "locked_by_id"
    t.datetime "performed_at"
    t.integer "priority"
    t.text "queue_name"
    t.uuid "retried_good_job_id"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_good_jobs_on_active_job_id"
    t.index ["cron_key"], name: "index_good_jobs_on_cron_key"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "google_accounts", force: :cascade do |t|
    t.text "access_token", null: false
    t.bigint "account_id", null: false
    t.string "calendar_list_webhook_channel_id"
    t.datetime "calendar_list_webhook_expires_at"
    t.string "calendar_list_webhook_resource_id"
    t.datetime "created_at", null: false
    t.text "email", null: false
    t.text "google_uid", null: false
    t.text "refresh_token", null: false
    t.text "scopes"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "google_uid"], name: "index_google_accounts_on_account_id_and_google_uid", unique: true
    t.index ["account_id"], name: "index_google_accounts_on_account_id"
    t.index ["calendar_list_webhook_channel_id"], name: "index_google_accounts_on_calendar_list_webhook_channel_id", unique: true
  end

  create_table "ha_syncs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "entities", default: {}, null: false
    t.bigint "location_id", null: false
    t.datetime "synced_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_ha_syncs_on_location_id", unique: true
  end

  create_table "locations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "country_code", limit: 2
    t.datetime "created_at", null: false
    t.text "ha_sync_api_key"
    t.text "latitude", null: false
    t.text "longitude", null: false
    t.text "name", null: false
    t.string "time_zone", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_locations_on_account_id"
    t.index ["ha_sync_api_key"], name: "index_locations_on_ha_sync_api_key", unique: true
  end

  create_table "microsoft_accounts", force: :cascade do |t|
    t.text "access_token", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.text "email", null: false
    t.text "microsoft_uid", null: false
    t.text "refresh_token", null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "microsoft_uid"], name: "index_microsoft_accounts_on_account_id_and_microsoft_uid", unique: true
    t.index ["account_id"], name: "index_microsoft_accounts_on_account_id"
  end

  create_table "pending_devices", force: :cascade do |t|
    t.text "api_key"
    t.bigint "claimed_device_id"
    t.datetime "created_at", null: false
    t.string "friendly_id"
    t.text "mac_address"
    t.text "pairing_code", null: false
    t.datetime "updated_at", null: false
    t.index ["claimed_device_id"], name: "index_pending_devices_on_claimed_device_id"
    t.index ["mac_address"], name: "index_pending_devices_on_mac_address", unique: true
    t.index ["pairing_code"], name: "index_pending_devices_on_pairing_code", unique: true
  end

  create_table "rails_pulse_deployments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "finished_at", comment: "When the deployment finished (nil if still in progress or unknown)"
    t.text "metadata", comment: "JSON object of arbitrary deployment metadata"
    t.string "revision", null: false, comment: "Git SHA, tag, or version string"
    t.datetime "started_at", null: false, comment: "When the deployment started"
    t.datetime "updated_at", null: false
    t.index ["revision"], name: "index_rails_pulse_deployments_on_revision"
    t.index ["started_at"], name: "index_rails_pulse_deployments_on_started_at"
  end

  create_table "rails_pulse_job_runs", force: :cascade do |t|
    t.string "adapter", comment: "Queue adapter"
    t.text "arguments", comment: "Serialized arguments"
    t.integer "attempts", default: 0, null: false, comment: "Retry attempts"
    t.datetime "created_at", null: false
    t.decimal "duration", precision: 15, scale: 6, comment: "Execution duration in milliseconds"
    t.datetime "enqueued_at", precision: nil, comment: "When the job was enqueued"
    t.string "error_class", comment: "Error class name"
    t.text "error_message", comment: "Error message"
    t.bigint "job_id", null: false, comment: "Link to job definition"
    t.datetime "occurred_at", precision: nil, null: false, comment: "When the job started"
    t.string "run_id", null: false, comment: "Adapter specific run id"
    t.string "status", null: false, comment: "Execution status"
    t.text "tags", comment: "Execution tags"
    t.datetime "updated_at", null: false
    t.index ["job_id", "occurred_at"], name: "index_rails_pulse_job_runs_on_job_and_occurred"
    t.index ["job_id", "status"], name: "index_rails_pulse_job_runs_on_job_and_status"
    t.index ["job_id"], name: "index_rails_pulse_job_runs_on_job_id"
    t.index ["occurred_at"], name: "index_rails_pulse_job_runs_on_occurred_at"
    t.index ["run_id"], name: "index_rails_pulse_job_runs_on_run_id", unique: true
    t.index ["status"], name: "index_rails_pulse_job_runs_on_status"
  end

  create_table "rails_pulse_jobs", force: :cascade do |t|
    t.decimal "avg_duration", precision: 15, scale: 6, comment: "Average duration in milliseconds"
    t.datetime "created_at", null: false
    t.text "description", comment: "Optional description"
    t.integer "failures_count", default: 0, null: false, comment: "Cache of failed runs"
    t.string "name", null: false, comment: "Job class name"
    t.decimal "p95_duration", precision: 15, scale: 6, comment: "95th percentile duration in milliseconds"
    t.decimal "p99_duration", precision: 15, scale: 6, comment: "99th percentile duration in milliseconds"
    t.string "queue_name", comment: "Default queue"
    t.integer "retries_count", default: 0, null: false, comment: "Cache of retried runs"
    t.integer "runs_count", default: 0, null: false, comment: "Cache of total runs"
    t.text "tags", comment: "JSON array of tags"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_rails_pulse_jobs_on_name", unique: true
    t.index ["queue_name"], name: "index_rails_pulse_jobs_on_queue"
    t.index ["runs_count"], name: "index_rails_pulse_jobs_on_runs_count"
  end

  create_table "rails_pulse_operations", force: :cascade do |t|
    t.text "actual_sql", comment: "Actual SQL that ran for sql operations — comment-stripped, unparameterized, unbounded"
    t.boolean "cache_hit", comment: "Whether a cache_read operation hit the cache"
    t.string "codebase_location", comment: "File and line number (e.g., app/models/user.rb:25)"
    t.datetime "created_at", null: false
    t.decimal "duration", precision: 15, scale: 6, null: false, comment: "Operation duration in milliseconds"
    t.bigint "job_run_id", comment: "Link to a background job execution"
    t.string "label", null: false, comment: "Display label: normalized SQL (≤255) for sql ops, controller#action / render path / cache key etc. for others"
    t.datetime "occurred_at", precision: nil, null: false, comment: "When the request started"
    t.string "operation_type", null: false, comment: "Type of operation (e.g., database, view, gem_call)"
    t.bigint "query_id", comment: "Link to the normalized SQL query"
    t.text "repeated_query_group", comment: "Normalized SQL key identifying an N+1 group"
    t.integer "repetition_count", comment: "Number of times this query pattern repeated in the request"
    t.bigint "request_id", comment: "Link to the request"
    t.integer "row_count", comment: "Number of rows returned (SQL operations, Rails 7.1+)"
    t.float "start_time", default: 0.0, null: false, comment: "Operation start time in milliseconds"
    t.datetime "updated_at", null: false
    t.index ["created_at", "query_id"], name: "idx_operations_for_aggregation"
    t.index ["job_run_id"], name: "index_rails_pulse_operations_on_job_run_id"
    t.index ["occurred_at", "duration", "operation_type"], name: "index_rails_pulse_operations_on_time_duration_type"
    t.index ["operation_type"], name: "index_rails_pulse_operations_on_operation_type"
    t.index ["query_id", "duration", "occurred_at"], name: "index_rails_pulse_operations_query_performance"
    t.index ["query_id", "occurred_at"], name: "index_rails_pulse_operations_on_query_and_time"
    t.index ["request_id"], name: "index_rails_pulse_operations_on_request_id"
    t.check_constraint "request_id IS NOT NULL OR job_run_id IS NOT NULL", name: "rails_pulse_operations_request_or_job_run"
  end

  create_table "rails_pulse_queries", force: :cascade do |t|
    t.datetime "analyzed_at", comment: "When query analysis was last performed"
    t.text "backtrace_analysis", comment: "JSON object with call chain and N+1 detection"
    t.datetime "created_at", null: false
    t.text "explain_plan", comment: "EXPLAIN output from actual SQL execution"
    t.string "hashed_sql", limit: 32, null: false, comment: "MD5 hash of normalized SQL for fast lookups and uniqueness"
    t.text "index_recommendations", comment: "JSON array of database index recommendations"
    t.text "issues", comment: "JSON array of detected performance issues"
    t.text "metadata", comment: "JSON object containing query complexity metrics"
    t.text "n_plus_one_analysis", comment: "JSON object with enhanced N+1 query detection results"
    t.text "normalized_sql", null: false, comment: "Full normalized SQL query string (e.g., SELECT * FROM users WHERE id = ?)"
    t.text "query_stats", comment: "JSON object with query characteristics analysis"
    t.text "suggestions", comment: "JSON array of optimization recommendations"
    t.text "tags", comment: "JSON array of tags for filtering and categorization"
    t.datetime "updated_at", null: false
    t.index ["hashed_sql"], name: "index_rails_pulse_queries_on_hashed_sql", unique: true
  end

  create_table "rails_pulse_requests", force: :cascade do |t|
    t.string "controller_action", comment: "Controller and action handling the request (e.g., PostsController#show)"
    t.datetime "created_at", null: false
    t.decimal "duration", precision: 15, scale: 6, null: false, comment: "Total request duration in milliseconds"
    t.boolean "is_error", default: false, null: false, comment: "True if status >= 500"
    t.datetime "occurred_at", precision: nil, null: false, comment: "When the request started"
    t.string "request_uuid", null: false, comment: "Unique identifier for the request (e.g., UUID)"
    t.integer "response_size_bytes", comment: "HTTP response body size in bytes"
    t.bigint "route_id", null: false, comment: "Link to the route"
    t.integer "status", null: false, comment: "HTTP status code (e.g., 200, 500)"
    t.text "tags", comment: "JSON array of tags for filtering and categorization"
    t.datetime "updated_at", null: false
    t.index ["created_at", "route_id"], name: "idx_requests_for_aggregation"
    t.index ["occurred_at"], name: "index_rails_pulse_requests_on_occurred_at"
    t.index ["request_uuid"], name: "index_rails_pulse_requests_on_request_uuid", unique: true
    t.index ["route_id", "occurred_at"], name: "index_rails_pulse_requests_on_route_id_and_occurred_at"
    t.index ["route_id"], name: "index_rails_pulse_requests_on_route_id"
  end

  create_table "rails_pulse_routes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "method", null: false, comment: "HTTP method (e.g., GET, POST)"
    t.string "path", null: false, comment: "Request path (e.g., /posts/index)"
    t.text "tags", comment: "JSON array of tags for filtering and categorization"
    t.datetime "updated_at", null: false
    t.index ["method", "path"], name: "index_rails_pulse_routes_on_method_and_path", unique: true
    t.index ["path"], name: "index_rails_pulse_routes_on_path"
  end

  create_table "rails_pulse_summaries", force: :cascade do |t|
    t.float "avg_duration", comment: "Average duration in milliseconds"
    t.integer "count", default: 0, null: false, comment: "Total number of requests/operations"
    t.datetime "created_at", null: false
    t.integer "error_count", default: 0, comment: "Number of error responses (5xx)"
    t.float "max_duration", comment: "Maximum duration in milliseconds"
    t.float "min_duration", comment: "Minimum duration in milliseconds"
    t.float "p50_duration", comment: "50th percentile duration"
    t.float "p95_duration", comment: "95th percentile duration"
    t.float "p99_duration", comment: "99th percentile duration"
    t.datetime "period_end", null: false, comment: "End of the aggregation period"
    t.datetime "period_start", null: false, comment: "Start of the aggregation period"
    t.string "period_type", null: false, comment: "Aggregation period type: hour, day, week, month"
    t.integer "status_2xx", default: 0, comment: "Number of 2xx responses"
    t.integer "status_3xx", default: 0, comment: "Number of 3xx responses"
    t.integer "status_4xx", default: 0, comment: "Number of 4xx responses"
    t.integer "status_5xx", default: 0, comment: "Number of 5xx responses"
    t.float "stddev_duration", comment: "Standard deviation of duration"
    t.integer "success_count", default: 0, comment: "Number of successful responses"
    t.bigint "summarizable_id", null: false, comment: "Link to Route or Query"
    t.string "summarizable_type", null: false
    t.float "total_duration", comment: "Total duration in milliseconds"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_rails_pulse_summaries_on_created_at"
    t.index ["period_start"], name: "index_rails_pulse_summaries_on_period_start"
    t.index ["period_type", "period_start"], name: "index_rails_pulse_summaries_on_period"
    t.index ["summarizable_id"], name: "index_rails_pulse_summaries_on_summarizable_id"
    t.index ["summarizable_type", "summarizable_id", "period_type", "period_start"], name: "idx_pulse_summaries_unique", unique: true
    t.index ["summarizable_type", "summarizable_id"], name: "index_rails_pulse_summaries_on_summarizable"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "email", null: false
    t.boolean "is_admin", default: false, null: false
    t.datetime "last_signed_in_at"
    t.text "login_code"
    t.integer "login_code_attempts", default: 0, null: false
    t.datetime "login_code_sent_at"
    t.datetime "remember_created_at"
    t.text "remember_token"
    t.date "trial_started_on"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "weather_syncs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.bigint "location_id", null: false
    t.jsonb "response_data", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id", "fetched_at"], name: "index_weather_syncs_on_location_id_and_fetched_at"
    t.index ["location_id"], name: "index_weather_syncs_on_location_id"
  end

  add_foreign_key "account_users", "accounts"
  add_foreign_key "account_users", "users"
  add_foreign_key "apple_accounts", "accounts"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "calendar_events", "calendars"
  add_foreign_key "calendars", "accounts"
  add_foreign_key "calendars", "apple_accounts"
  add_foreign_key "calendars", "google_accounts"
  add_foreign_key "calendars", "microsoft_accounts"
  add_foreign_key "devices", "locations"
  add_foreign_key "google_accounts", "accounts"
  add_foreign_key "ha_syncs", "locations"
  add_foreign_key "locations", "accounts"
  add_foreign_key "microsoft_accounts", "accounts"
  add_foreign_key "pending_devices", "devices", column: "claimed_device_id"
  add_foreign_key "rails_pulse_job_runs", "rails_pulse_jobs", column: "job_id"
  add_foreign_key "rails_pulse_operations", "rails_pulse_job_runs", column: "job_run_id"
  add_foreign_key "rails_pulse_operations", "rails_pulse_queries", column: "query_id"
  add_foreign_key "rails_pulse_operations", "rails_pulse_requests", column: "request_id"
  add_foreign_key "rails_pulse_requests", "rails_pulse_routes", column: "route_id"
  add_foreign_key "weather_syncs", "locations"
end
