# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)

module HaAddon
  class Application < Rails::Application
    config.autoloader = :zeitwerk

    config.anyway_config.future.use :unwrap_known_environments

    config.cache_store = :file_store, Rails.root.join("tmp/cache/").to_s
    config.action_controller.perform_caching = false

    config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "foo")

    config.hosts.clear

    config.active_job.queue_adapter = :good_job
    config.good_job.execution_mode = :async
    # Isolate screenshot jobs onto their own single-threaded pool so a wedged
    # Chromium capture can never starve other background jobs. Bounded explicitly
    # (1 + 2 = 3 threads) so the async pool stays within the DB connection pool.
    config.good_job.queues = ENV.fetch("GOOD_JOB_QUEUES", "screenshots:1;-screenshots:2")
    config.good_job.enable_cron = true
    config.good_job.cron = {
      refresh_disconnected_screenshots: {
        cron: "0 * * * *",
        class: "RefreshDisconnectedDeviceScreenshotsJob"
      },
      record_uptime: {
        cron: "* * * * *",
        class: "RecordUptimeJob"
      },
      cleanup_uptime_checks: {
        cron: "0 2 * * *",
        class: "CleanupUptimeChecksJob"
      }
    }

    config.after_initialize do
      if defined?(GoodJob)
        Device.enqueue_screenshot_refresh_jobs!
      end
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
      # DB not available (e.g. during asset precompilation) or tables not yet created
    end

    # Warden middleware for session-based auth (auto-sign-in)
    config.middleware.use Warden::Manager do |manager|
      manager.default_strategies :none
      manager.failure_app = ->(env) { [401, {"Content-Type" => "text/plain"}, ["Unauthorized"]] }

      manager.serialize_into_session(:user) { |user| user.id }
      manager.serialize_from_session(:user) { |id| User.find_by(id: id) }
    end
  end
end
