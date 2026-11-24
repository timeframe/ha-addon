# frozen_string_literal: true

require_relative "system_test_helper"

class SystemBrowserTest < Minitest::Test
  def test_rails_registers_the_shared_browser_options
    previous_driver = Capybara.current_driver
    ApplicationSystemTestCase.driver.use
    driver = Capybara.drivers[:cuprite].call(Rails.application)

    assert_equal [1280, 800], driver.options[:window_size]
    assert_equal true, driver.options[:headless]
    assert_equal false, driver.options[:pending_connection_errors]
    assert_equal 30, driver.options[:process_timeout]
    assert_equal 30, driver.options[:timeout]
  ensure
    Capybara.current_driver = previous_driver
  end

  def test_failed_browser_reset_does_not_reuse_the_stale_page
    browser = Capybara::Cuprite::Browser.allocate
    browser.instance_variable_set(:@page, Object.new)
    options = Minitest::Mock.new
    options.expect(:reset_window_size, nil)
    browser.instance_variable_set(:@options, options)
    contexts = Object.new
    def contexts.reset
      raise Ferrum::DeadBrowserError
    end

    browser.stub(:contexts, contexts) do
      assert_raises(Ferrum::DeadBrowserError) { browser.reset }
    end

    replacement_page = Object.new
    browser.stub(:attach_page, replacement_page) do
      assert_same replacement_page, browser.page
    end
    options.verify
  end
end
