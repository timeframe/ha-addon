# frozen_string_literal: true

require "test_helper"

class DemoDeviceContentTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def test_returns_all_required_keys
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")

      assert_equal "72°", result[:current_temperature]
      assert result[:timestamp].present?
      assert result[:current_time].present?
      assert result[:top_left].is_a?(Array)
      assert result[:top_right].is_a?(Array)
      assert result[:weather_status].is_a?(Array)
      assert result[:now_playing].is_a?(Hash)
      assert result[:day_groups].is_a?(Array)
      assert result[:minutely_weather_minutes].is_a?(Array)
      assert_equal "water", result[:minutely_weather_minutes_icon]
      assert result[:minutely_precipitation_bars].is_a?(Array)
      assert_equal "Weather", result[:attribution]
    end
  end

  def test_has_five_day_groups
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")

      assert_equal 5, result[:day_groups].count
      assert_equal "Today", result[:day_groups][0][:day_name]
      assert_equal "Tomorrow", result[:day_groups][1][:day_name]
    end
  end

  def test_battery_omitted_when_full_and_not_charging
    result = DemoDeviceContent.new.call(timezone: "America/Chicago", battery_level: 100)
    assert_nil result[:battery]
  end

  def test_battery_low_warning_included
    result = DemoDeviceContent.new.call(timezone: "America/Chicago", battery_level: 15)
    assert result[:battery]
    assert_equal true, result[:battery][:low]
    assert_equal 15, result[:battery][:level]
  end

  def test_battery_charging_included
    result = DemoDeviceContent.new.call(timezone: "America/Chicago", battery_level: 60, charging: true)
    assert result[:battery]
    assert_equal true, result[:battery][:charging]
  end

  def test_day_groups_have_required_structure
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")

      result[:day_groups].each do |day|
        assert day[:day_name].present?
        assert day[:date].is_a?(Date)
        assert day[:daily].is_a?(Array)
        assert day[:periodic].is_a?(Array)
        assert [true, false].include?(day[:show_daily])
      end
    end
  end

  def test_today_has_birthday_with_age
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")
      today_daily = result[:day_groups][0][:daily]

      birthday = today_daily.find { |e| e[:summary].include?("Sarah Johnson") }
      assert birthday, "Expected a birthday event"
      assert_equal "cake-variant", birthday[:icon_class]
      assert birthday[:summary].include?("36"), "Expected age 36 in 2026"
    end
  end

  def test_today_has_multi_day_vacation_with_counter
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")
      today_daily = result[:day_groups][0][:daily]

      vacation = today_daily.find { |e| e[:summary].include?("Vacation") }
      assert vacation, "Expected a Vacation event"
      assert vacation[:summary].include?("/"), "Expected counter in summary"
    end
  end

  def test_today_has_events_with_locations
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")
      today_periodic = result[:day_groups][0][:periodic]

      located = today_periodic.select { |e| e[:location].present? }
      assert located.any?, "Expected events with locations"
    end
  end

  def test_tomorrow_has_wind_event_with_rotation
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")
      tomorrow_periodic = result[:day_groups][1][:periodic]

      wind = tomorrow_periodic.find { |e| e[:icon_style].present? }
      assert wind, "Expected a wind event with rotation style"
      assert_equal "arrow-up", wind[:icon_class]
    end
  end

  def test_uses_alpha_letter_calendar_icons
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")
      today_periodic = result[:day_groups][0][:periodic]

      alpha_j = today_periodic.select { |e| e[:icon_text] == "J" }
      assert alpha_j.any?, "Expected J icon for Joel's calendar events"

      alpha_f = today_periodic.select { |e| e[:icon_text] == "F" }
      assert alpha_f.any?, "Expected F icon for family calendar events"
    end
  end

  def test_top_left_sensors
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")

      assert_equal 1, result[:top_left].count
      assert result[:top_left].any? { |s| s[:icon] == "door-open" }
    end
  end

  def test_top_right_bird
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")

      assert_equal 1, result[:top_right].count
      assert_equal "bird", result[:top_right][0][:icon]
      assert_equal "Spotted Towhee", result[:top_right][0][:label]
    end
  end

  def test_weather_status_rotated_arrow
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")

      assert_equal 1, result[:weather_status].count
      assert_equal "arrow-up", result[:weather_status][0][:icon]
      assert_equal "12", result[:weather_status][0][:label]
      assert_equal 45, result[:weather_status][0][:rotation]
    end
  end

  def test_now_playing
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")

      assert_equal "Tycho", result[:now_playing][:artist]
      assert_equal "A Walk", result[:now_playing][:track]
    end
  end

  def test_minutely_weather_data
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")

      assert_equal 60, result[:minutely_weather_minutes].count
      result[:minutely_weather_minutes].each do |minute|
        assert minute.key?(:precipitationChance)
        assert minute.key?(:precipitationIntensity)
      end
      assert_equal 60, result[:minutely_precipitation_bars].count
    end
  end

  def test_today_has_long_event_name
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")
      today_periodic = result[:day_groups][0][:periodic]

      long = today_periodic.find { |e| e[:summary].length > 30 }
      assert long, "Expected a long event name for truncation demo"
    end
  end

  def test_today_has_past_midnight_event
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")
      today_periodic = result[:day_groups][0][:periodic]

      past_midnight = today_periodic.find { |e| e[:time_html].include?(" - ") }
      assert past_midnight, "Expected an event spanning past midnight"
    end
  end

  def test_day_3_has_overlapping_events
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago")
      day3_periodic = result[:day_groups][2][:periodic]

      lunch = day3_periodic.find { |e| e[:summary].include?("Lunch") }
      call = day3_periodic.find { |e| e[:summary].include?("Call") }
      assert lunch && call, "Expected overlapping Lunch and Call events"
    end
  end

  def test_three_day_mode_limits_days_and_excludes_wind
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago", days: 3, include_precip: false, include_wind: false)
      assert_equal 3, result[:day_groups].length
      day1_periodic = result[:day_groups][1][:periodic]
      wind_event = day1_periodic.find { |e| e[:summary]&.include?("Gusts") }
      assert_nil wind_event, "Wind events should be excluded"
    end
  end

  def test_use_day_names_option
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago", use_day_names: true)

      assert_equal "Thursday", result[:day_groups][0][:day_name]
      assert_equal "Friday", result[:day_groups][1][:day_name]
    end
  end

  def test_weather_row_extracts_weather_events
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago", weather_row: true)

      today = result[:day_groups][0]
      assert today[:weather_row].is_a?(Array)
      assert today[:weather_row].any?, "Expected weather row items"
      assert today[:periodic].none? { |e| e[:icon_class]&.start_with?("weather-") && e[:summary]&.end_with?("°") && e[:time_html] == e[:start_time] }
    end
  end

  def test_temperature_toggle_hides_weather_row_but_keeps_clothing_forecast
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(
        timezone: "America/Chicago",
        weather_row: true,
        clothing_forecast: true,
        include_temperature: false
      )

      today = result[:day_groups][0]
      assert_empty today[:weather_row]
      assert today[:clothing], "Expected clothing forecast to keep using hourly weather data"
      assert today[:periodic].none? { |e| e[:weather] && e[:summary]&.end_with?("°") }
    end
  end

  def test_fill_hourly_weather_interpolates_and_sorts_all_hours
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(
        timezone: "America/Chicago",
        weather_row: true,
        temperature_hours: [7, 9, 12, 16, 20],
        fill_hourly_weather: true
      )

      today = result[:day_groups][0]
      hours = today[:weather_row].map { |w| w[:start_time] }
      assert_equal %w[7a 9a 12p 4p 8p], hours
    end
  end

  def test_fill_hourly_weather_in_full_template_includes_all_selected_hours
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(
        timezone: "America/Chicago",
        temperature_hours: [7, 9, 12, 16, 20],
        fill_hourly_weather: true
      )

      today = result[:day_groups][0]
      weather_hours = today[:periodic]
        .select { |e| e[:weather] && e[:summary]&.end_with?("°") && e[:time_html] == e[:start_time] }
        .map { |e| e[:start_time] }
      assert_equal %w[7a 9a 12p 4p 8p], weather_hours
    end
  end

  def test_start_time_only_flag
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago", start_time_only: true)

      assert result[:start_time_only]
    end
  end

  def test_clothing_forecast
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago", weather_row: true, clothing_forecast: true)

      today = result[:day_groups][0]
      assert today[:clothing], "Expected clothing forecast data"
      assert_equal "shorts", today[:clothing][:icon]
      assert_equal "Shorts", today[:clothing][:summary]
      assert_equal "tshirt", today[:clothing][:shirt_icon]
      assert_equal "T-shirt", today[:clothing][:shirt_summary]
    end
  end

  def test_clothing_forecast_on_timeline_layout_without_weather_row
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      # Timeline layouts (trmnl/reterminal) keep hourly weather in the periodic
      # list rather than a weather row, so clothing must still be computed.
      result = DemoDeviceContent.new.call(timezone: "America/Chicago", weather_row: false, clothing_forecast: true, fill_hourly_weather: true)

      today = result[:day_groups][0]
      assert today[:clothing], "Expected clothing forecast data on the timeline layout"
      assert_equal "shorts", today[:clothing][:icon]
      assert_equal "tshirt", today[:clothing][:shirt_icon]
    end
  end

  def test_clothing_forecast_demo_pants_with_long_sleeves
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = demo_clothing_result(morning_temp: 45, noon_temp: 50)

      today = result[:day_groups][0]
      assert_equal "pants", today[:clothing][:icon]
      assert_equal "Pants", today[:clothing][:summary]
      assert_equal "long-sleeve-shirt", today[:clothing][:shirt_icon]
      assert_equal "Long sleeves", today[:clothing][:shirt_summary]
    end
  end

  def test_clothing_forecast_demo_uses_morning_temperature_when_noon_is_missing
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = demo_clothing_result(morning_temp: 72, noon_temp: nil)

      today = result[:day_groups][0]
      assert_equal "shorts", today[:clothing][:icon]
      assert_equal "Shorts", today[:clothing][:summary]
      assert_equal "tshirt", today[:clothing][:shirt_icon]
      assert_equal "T-shirt", today[:clothing][:shirt_summary]
    end
  end

  def test_clothing_forecast_demo_daily_high_guardrail_allows_short_sleeves_with_pants
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = demo_clothing_result(morning_temp: 66, noon_temp: 68, daily_summary: "62° / 45°")

      today = result[:day_groups][0]
      assert_equal "pants", today[:clothing][:icon]
      assert_equal "Pants", today[:clothing][:summary]
      assert_equal "tshirt", today[:clothing][:shirt_icon]
      assert_equal "T-shirt", today[:clothing][:shirt_summary]
    end
  end

  def test_clothing_forecast_demo_omits_clothing_without_morning_weather
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = demo_clothing_result(morning_temp: nil, noon_temp: 68)

      today = result[:day_groups][0]
      assert_nil today[:clothing]
    end
  end

  def test_auto_icons
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago", auto_icons: true, always_show_today: true)

      all_events = result[:day_groups].flat_map { |d| d[:daily] + d[:periodic] }
      non_weather = all_events.reject { |e| e[:weather_ranged] }
      icons_assigned = non_weather.select { |e| e[:icon_class] }
      assert icons_assigned.any?, "Expected at least one event to have an auto-assigned icon"
    end
  end

  def test_auto_icons_skips_weather_events
    travel_to DateTime.new(2026, 3, 19, 8, 0, 0, "-0500") do
      result = DemoDeviceContent.new.call(timezone: "America/Chicago", auto_icons: true, always_show_today: true)

      weather_event = result[:day_groups][0][:periodic].find { |e| e[:summary] == "58°" }
      assert weather_event, "Expected a demo weather event"
      assert_equal "weather-partly-cloudy", weather_event[:icon_class]
    end
  end

  private

  def demo_clothing_result(morning_temp:, noon_temp:, daily_summary: "72° / 50°")
    content = DemoDeviceContent.new
    content.define_singleton_method(:events_for_day) do |_day_index, date, _current_time, _vacation, timezone, include_wind: true|
      daily = [
        DeviceEvent.new(
          id: "_ha_weather_day_#{date.to_i}",
          starts_at: date.beginning_of_day,
          ends_at: (date + 1.day).beginning_of_day,
          summary: daily_summary,
          icon: "weather-partly-cloudy",
          daily: true,
          timezone: timezone
        )
      ]
      periodic = []
      unless morning_temp.nil?
        periodic << DeviceEvent.new(
          id: "_ha_weather_hour_#{date.change(hour: 8).to_i}",
          starts_at: date.change(hour: 8),
          ends_at: date.change(hour: 8),
          summary: "#{morning_temp}°",
          icon: "weather-cloudy",
          timezone: timezone
        )
      end
      unless noon_temp.nil?
        periodic << DeviceEvent.new(
          id: "_ha_weather_hour_#{date.change(hour: 12).to_i}",
          starts_at: date.change(hour: 12),
          ends_at: date.change(hour: 12),
          summary: "#{noon_temp}°",
          icon: "weather-cloudy",
          timezone: timezone
        )
        periodic << DeviceEvent.new(
          id: "_ha_weather_hour_#{date.change(hour: 16).to_i}",
          starts_at: date.change(hour: 16),
          ends_at: date.change(hour: 16),
          summary: "#{noon_temp}°",
          icon: "weather-cloudy",
          timezone: timezone
        )
      end

      {daily: daily, periodic: periodic}
    end

    content.call(
      timezone: "America/Chicago",
      days: 1,
      weather_row: true,
      clothing_forecast: true,
      always_show_today: true
    )
  end
end
