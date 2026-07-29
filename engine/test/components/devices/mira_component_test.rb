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

  private

  def render_mira(top_left: [], top_right: [], weather_status: [])
    ApplicationController.render(
      Devices::MiraComponent.new(
        view_object: {
          current_time: Time.zone.local(2026, 5, 25, 8, 0, 0),
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
