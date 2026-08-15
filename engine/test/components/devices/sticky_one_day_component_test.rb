# frozen_string_literal: true

require "test_helper"

class StickyOneDayComponentTest < ActiveSupport::TestCase
  test "hides times for all-day events while showing timed event times" do
    html = ApplicationController.render(
      Devices::StickyOneDayComponent.new(
        view_object: {
          current_time: Time.zone.local(2026, 5, 23, 8),
          configuration: {"show_event_times" => "true"},
          day_groups: [{
            date: Date.new(2026, 5, 23),
            weather_row: [],
            show_daily: true,
            daily: [{summary: "School closed", time_html: "ALL-DAY-TIME"}],
            periodic: [{summary: "Lunch", time_html: "12p"}]
          }],
          timestamp: "Updated 8:00 AM",
          attribution: ""
        }
      ),
      layout: false
    )

    assert_includes html, "School closed"
    refute_includes html, "ALL-DAY-TIME"
    assert_includes html, "12p"
  end

  test "renders a portrait one-day view without environmental sensors" do
    html = ApplicationController.render(
      Devices::StickyOneDayComponent.new(
        view_object: {
          current_time: Time.zone.local(2026, 5, 23, 8),
          configuration: {"show_event_times" => "true"},
          day_groups: [{
            date: Date.new(2026, 5, 23),
            weather_row: [{start_time: "12p", icon_class: "weather-partly-cloudy", summary: "72°"}],
            show_daily: false,
            daily: [],
            periodic: [{summary: "Lunch", time_html: "12p", icon_class: "silverware-fork-knife"}]
          }],
          timestamp: "Updated 8:00 AM",
          attribution: "Forecast service",
          battery: {icon: "battery-70", level: 70},
          sensors: {temperature: "91°", humidity: "99%"}
        }
      ),
      layout: false
    )

    assert_includes html, "width: 480px"
    assert_includes html, "height: 800px"
    assert_includes html, "Today"
    assert_includes html, "72°"
    assert_includes html, "Lunch"
    assert_includes html, "70%"
    refute_includes html, "Forecast service"
    refute_includes html, "91°"
    refute_includes html, "99%"
  end
end
