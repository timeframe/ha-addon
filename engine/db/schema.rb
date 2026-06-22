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

ActiveRecord::Schema[8.1].define(version: 33) do
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
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "stripe_subscription_item_id"
    t.boolean "subscription_cancel_at_period_end", default: false, null: false
    t.datetime "subscription_current_period_end"
    t.datetime "subscription_grace_until"
    t.string "subscription_status"
    t.datetime "support_access_at"
    t.string "temperature_unit", default: "F", null: false
    t.date "trial_ends_on"
    t.datetime "updated_at", null: false
    t.index ["stripe_customer_id"], name: "index_accounts_on_stripe_customer_id", unique: true
    t.index ["stripe_subscription_id"], name: "index_accounts_on_stripe_subscription_id", unique: true
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
    t.text "city"
    t.string "country_code", limit: 2
    t.datetime "created_at", null: false
    t.text "ha_sync_api_key"
    t.text "latitude", null: false
    t.text "line1"
    t.text "line2"
    t.text "longitude", null: false
    t.text "name", null: false
    t.text "postal_code"
    t.text "state"
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

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.string "product_name", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.text "email", null: false
    t.datetime "fulfilled_at"
    t.datetime "paid_at"
    t.boolean "payment_method_saved", default: false, null: false
    t.text "ship_city"
    t.text "ship_country"
    t.text "ship_line1"
    t.text "ship_line2"
    t.text "ship_name"
    t.text "ship_postal_code"
    t.text "ship_state"
    t.integer "shipping_cents", default: 0, null: false
    t.string "shipping_method"
    t.string "status", default: "pending", null: false
    t.string "stripe_payment_intent_id"
    t.string "stripe_tax_calculation_id"
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.string "tracking_number"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["account_id"], name: "index_orders_on_account_id"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["stripe_payment_intent_id"], name: "index_orders_on_stripe_payment_intent_id", unique: true
    t.index ["user_id"], name: "index_orders_on_user_id"
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

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents", null: false
    t.string "slug", null: false
    t.string "stripe_tax_code", default: "txcd_99999999", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_products_on_active"
    t.index ["slug"], name: "index_products_on_slug", unique: true
  end

  create_table "sent_emails", force: :cascade do |t|
    t.text "bcc"
    t.text "body"
    t.text "cc"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.datetime "delivered_at", null: false
    t.text "from"
    t.string "mail_action"
    t.string "mailer"
    t.string "message_id"
    t.text "subject"
    t.text "to"
    t.datetime "updated_at", null: false
    t.index ["delivered_at"], name: "index_sent_emails_on_delivered_at"
    t.index ["mailer"], name: "index_sent_emails_on_mailer"
  end

  create_table "uptime_checks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "healthy", default: true, null: false
    t.datetime "recorded_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recorded_at"], name: "index_uptime_checks_on_recorded_at", unique: true
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
  add_foreign_key "order_items", "orders", on_delete: :cascade
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "accounts", on_delete: :cascade
  add_foreign_key "orders", "users", on_delete: :nullify
  add_foreign_key "pending_devices", "devices", column: "claimed_device_id"
  add_foreign_key "weather_syncs", "locations"
end
