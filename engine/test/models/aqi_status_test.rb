# frozen_string_literal: true

require "test_helper"

class AqiStatusTest < ActiveSupport::TestCase
  test "uses air filter icon below unhealthy AQI" do
    assert_equal({icon: "air-filter", label: "42"}, AqiStatus.call(aqi: 42))
    assert_equal({icon: "air-filter", label: "100"}, AqiStatus.call(aqi: 100))
  end

  test "uses mask icon for unhealthy AQI" do
    assert_equal({icon: "face-mask-outline", label: "101"}, AqiStatus.call(aqi: 101))
  end

  test "ignores missing and nonnumeric AQI" do
    assert_nil AqiStatus.call(aqi: nil)
    assert_nil AqiStatus.call(aqi: "unavailable")
  end
end
