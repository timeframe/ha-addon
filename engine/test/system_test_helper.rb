# frozen_string_literal: true

require "test_helper"
require "capybara/minitest"
require "capybara/cuprite"

VCR.configure do |config|
  config.ignore_localhost = true
end

Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite, screen_size: [1280, 800], options: {
    headless: true,
    pending_connection_errors: false,
    process_timeout: 30,
    timeout: 30
  }
end
