# frozen_string_literal: true

require "test_helper"

class OneDayComponentTest < ActiveSupport::TestCase
  test "renders daily weather icon in header" do
    html = render_one_day(
      weather_row: [
        {start_time: "12p", icon_class: "weather-partly-cloudy", summary: "72°"}
      ]
    )

    assert_includes html, "mdi-weather-partly-cloudy"
  end

  test "renders Today label when day matches current time" do
    html = render_one_day(date: Date.new(2026, 5, 23), current_time: Time.zone.local(2026, 5, 23, 8))
    assert_includes html, "Today"
    refute_includes html, "Tomorrow"
  end

  test "renders Tomorrow label when day is after current time" do
    html = render_one_day(date: Date.new(2026, 5, 24), current_time: Time.zone.local(2026, 5, 23, 20))
    assert_includes html, "Tomorrow"
  end

  test "only_show_events_with_icons filters events without icons" do
    html = render_one_day(
      periodic: [
        {summary: "Tagged Event", timeframe_icon: "soccer", icon_class: "soccer"},
        {summary: "Plain Event", timeframe_icon: nil}
      ],
      configuration: {"only_show_events_with_icons" => "true"}
    )
    assert_includes html, "Tagged Event"
    refute_includes html, "Plain Event"
  end

  test "without only_show_events_with_icons shows all periodic events" do
    html = render_one_day(
      periodic: [
        {summary: "Tagged Event", timeframe_icon: "soccer", icon_class: "soccer"},
        {summary: "Plain Event", timeframe_icon: nil}
      ],
      configuration: {"only_show_events_with_icons" => "false"}
    )
    assert_includes html, "Tagged Event"
    assert_includes html, "Plain Event"
  end

  private

  def render_one_day(date: Date.new(2026, 5, 23), current_time: Time.zone.local(2026, 5, 23, 8, 0, 0), weather_row: [], periodic: [], configuration: {})
    ApplicationController.render(
      Devices::OneDayComponent.new(
        view_object: {
          current_time: current_time,
          configuration: configuration,
          day_groups: [
            {
              date: date,
              day_name: "Saturday",
              weather_row: weather_row,
              show_daily: false,
              daily: [],
              periodic: periodic
            }
          ],
          timestamp: "8:00 AM",
          attribution: ""
        }
      ),
      layout: false
    )
  end
end
