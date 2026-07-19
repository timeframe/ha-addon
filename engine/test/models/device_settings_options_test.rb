# frozen_string_literal: true

require "test_helper"

class DeviceSettingsOptionsTest < ActiveSupport::TestCase
  def keys_for(template)
    DeviceSettingsOptions.call(Device.new(display_template: template)).map { |o| o[:key] }
  end

  def test_blank_template_returns_no_options
    assert_empty DeviceSettingsOptions.call(Device.new(display_template: "default"))
  end

  def test_trmnl_options
    assert_equal(
      %w[show_current_day show_temperature_events show_precip_events show_wind_events
        show_weather_alerts auto_assign_icons show_dates clothing_forecast
        hide_current_day_enabled hide_current_day_time],
      keys_for("trmnl")
    )
    show_current_day = DeviceSettingsOptions.call(Device.new(display_template: "trmnl")).find { |o| o[:key] == "show_current_day" }
    refute show_current_day[:default_on]
  end

  def test_three_day_options
    assert_equal(
      %w[only_show_events_with_icons show_temperature_events show_precip_events show_wind_events
        show_weather_alerts clothing_forecast show_icons auto_assign_icons show_dates
        hide_current_day_enabled hide_current_day_time],
      keys_for("three_day")
    )
  end

  def test_two_day_options
    assert_equal(
      %w[only_show_events_with_icons show_precip_events show_wind_events show_weather_alerts
        clothing_forecast show_icons auto_assign_icons show_dates show_event_times
        two_day_rollover_enabled two_day_rollover_time],
      keys_for("two_day")
    )
    # two_day drops hourly conditions and defaults weather alerts off.
    refute_includes keys_for("two_day"), "show_temperature_events"
    alerts = DeviceSettingsOptions.call(Device.new(display_template: "two_day")).find { |o| o[:key] == "show_weather_alerts" }
    refute alerts[:default_on]
  end

  def test_one_day_options
    assert_equal(
      %w[only_show_events_with_icons show_weather_alerts show_icons auto_assign_icons
        show_event_times one_day_rollover_enabled one_day_rollover_time],
      keys_for("one_day")
    )
    # one_day drops the ranged weather events and clothing forecast.
    %w[show_temperature_events show_precip_events show_wind_events clothing_forecast].each do |key|
      refute_includes keys_for("one_day"), key
    end
  end

  def test_reterminal_options
    assert_equal(
      %w[show_current_day only_show_events_with_icons show_temperature_events show_precip_events
        show_wind_events show_weather_alerts hide_current_day_enabled hide_current_day_time],
      keys_for("reterminal")
    )
    show_current_day = DeviceSettingsOptions.call(Device.new(display_template: "reterminal")).find { |o| o[:key] == "show_current_day" }
    assert show_current_day[:default_on]
  end

  def test_reterminal_landscape_has_clothing_forecast_like_trmnl
    keys = keys_for("reterminal_landscape")
    assert_includes keys, "clothing_forecast"
    assert_includes keys, "only_show_events_with_icons"
    refute_includes keys, "show_current_day"
  end

  def test_thirteen_options
    assert_equal(
      %w[show_current_day show_temperature_events show_precip_events show_wind_events
        show_weather_alerts hide_current_day_enabled hide_current_day_time],
      keys_for("thirteen")
    )
  end

  def test_time_inputs_carry_defaults_and_dependencies
    hide_time = DeviceSettingsOptions.call(Device.new(display_template: "trmnl")).find { |o| o[:key] == "hide_current_day_time" }
    assert_equal :time, hide_time[:type]
    assert_equal Device::HIDE_CURRENT_DAY_DEFAULT_TIME, hide_time[:default]
    assert_equal "hide_current_day_enabled", hide_time[:depends_on]
  end
end
