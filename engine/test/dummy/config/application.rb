# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "global_id/railtie"

Bundler.require(*Rails.groups)
require "timeframe_core"
require "good_job"
require "warden"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.autoloader = :zeitwerk
    config.secret_key_base = "test-secret-key-base-for-dummy-app"
    config.hosts.clear
    config.eager_load = false

    config.middleware.use Warden::Manager do |manager|
      manager.default_strategies :none
      manager.failure_app = ->(env) { [401, {"Content-Type" => "text/plain"}, ["Unauthorized"]] }

      manager.serialize_into_session(:user) { |user| user.id }
      manager.serialize_from_session(:user) { |id| User.find_by(id: id) }
    end
  end
end
