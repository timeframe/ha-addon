# frozen_string_literal: true

require "test_helper"

class UvWarningTest < ActiveSupport::TestCase
  test "shows the integer UV index above 3" do
    assert_equal({icon: "weather-sunny-alert", label: "6"}, UvWarning.call(uv_index: 6.8))
  end

  test "does not show at or below 3" do
    assert_nil UvWarning.call(uv_index: 3)
    assert_nil UvWarning.call(uv_index: nil)
  end
end
