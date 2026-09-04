# frozen_string_literal: true

require "test_helper"

class MiraComponentTest < ActiveSupport::TestCase
  test "merges top-left indicators that share an icon into one group" do
    html = render_mira(
      top_left: [
        {icon: "lock", rotation: nil, label: "Front"},
        {icon: "lock", rotation: nil, label: "Back"}
      ]
    )

    assert_includes html, "Front, Back"
    assert_equal 1, html.scan("mdi-lock").size
  end

  test "merges weather-status indicators that share an icon into one group" do
    html = render_mira(
      weather_status: [
        {icon: "water", rotation: nil, label: "Rain"},
        {icon: "water", rotation: nil, label: "Showers"}
      ]
    )

    assert_includes html, "Rain, Showers"
    assert_equal 1, html.scan("mdi-water").size
  end

  test "uses the server time zone for the live clock" do
    html = render_mira(
      current_time: ActiveSupport::TimeZone["America/Chicago"].local(2026, 5, 25, 8, 0, 0)
    )

    assert_includes html, 'var timeZone = "America/Chicago";'
    assert_includes html, "timeZone: timeZone"
  end

  test "formats the live date like the Visionect 13 template" do
    html = render_mira

    assert_includes html, "month: 'short'"
    assert_includes html, "parts.weekday + ', ' + parts.month + '. ' + parts.day"
  end

  private

  def render_mira(top_left: [], top_right: [], weather_status: [], current_time: Time.zone.local(2026, 5, 25, 8, 0, 0))
    ApplicationController.render(
      Devices::MiraComponent.new(
        view_object: {
          current_time: current_time,
          current_temperature: "70°",
          configuration: {},
          top_left: top_left,
          top_right: top_right,
          weather_status: weather_status,
          day_groups: [
            {
              date: Date.new(2026, 5, 25),
              day_name: "Monday",
              show_daily: false,
              daily: [],
              periodic: []
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
