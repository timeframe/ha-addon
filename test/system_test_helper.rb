# frozen_string_literal: true

require_relative "test_helper"
require "capybara/minitest"
require "capybara/cuprite"

VCR.configure do |config|
  config.ignore_localhost = true
end

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1280, 800], headless: true, process_timeout: 30)
end

Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite
end
