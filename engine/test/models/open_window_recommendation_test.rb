# frozen_string_literal: true

require "test_helper"

class OpenWindowRecommendationTest < ActiveSupport::TestCase
  test "recommends an open window in the comfort range with good air" do
    time = ActiveSupport::TimeZone["America/Denver"].local(2026, 8, 28, 12)

    assert_equal({icon: "window-open"}, described_class.call(temperature_f: 68, aqi: 42, current_time: time))
  end

  test "uses the configured temperature and AQI boundaries" do
    time = ActiveSupport::TimeZone["America/Denver"].local(2026, 8, 28, 12)

    assert_nil described_class.call(temperature_f: 63, aqi: 42, current_time: time)
    assert_equal({icon: "window-open"}, described_class.call(temperature_f: 72, aqi: 42, current_time: time))
    assert_nil described_class.call(temperature_f: 73, aqi: 42, current_time: time)
    assert_nil described_class.call(temperature_f: 68, aqi: 70, current_time: time)
  end

  test "recommends at any time of day" do
    zone = ActiveSupport::TimeZone["America/Denver"]

    assert_equal({icon: "window-open"}, described_class.call(temperature_f: 68, aqi: 42, current_time: zone.local(2026, 8, 28, 2)))
    assert_equal({icon: "window-open"}, described_class.call(temperature_f: 68, aqi: 42, current_time: zone.local(2026, 8, 28, 22)))
  end

  test "does not recommend without all inputs" do
    time = ActiveSupport::TimeZone["America/Denver"].local(2026, 8, 28, 12)

    assert_nil described_class.call(temperature_f: nil, aqi: 42, current_time: time)
  end

  private

  def described_class
    OpenWindowRecommendation
  end
end
