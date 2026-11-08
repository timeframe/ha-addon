# frozen_string_literal: true

require "test_helper"

class ScreenshotHostConfigTest < ActiveSupport::TestCase
  test "the add-on captures screenshots from its own Puma address" do
    assert_equal "http://127.0.0.1:#{ENV.fetch("PORT", 3000)}", Device.screenshot_host
  end
end
