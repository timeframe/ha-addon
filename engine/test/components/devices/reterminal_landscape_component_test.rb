# frozen_string_literal: true

require "test_helper"

class ReterminalLandscapeComponentTest < ActiveSupport::TestCase
  test "renders the timeline content for the landscape layout" do
    html = render_landscape(
      periodic: [
        {summary: "Standup", time_html: "9a", icon_class: "calendar"}
      ]
    )

    assert_includes html, "Standup"
    assert_includes html, "Monday"
  end

  test "renders the current day header" do
    html = render_landscape(configuration: {"show_current_day" => "true"})
    assert_includes html, "Monday"
  end

  private

  def render_landscape(current_time: Time.zone.local(2026, 5, 25, 8, 0, 0), periodic: [], configuration: {})
    ApplicationController.render(
      Devices::ReterminalLandscapeComponent.new(
        view_object: {
          current_time: current_time,
          current_temperature: "70°",
          configuration: configuration,
          top_left: [],
          top_right: [],
          weather_status: [],
          day_groups: [
            {
              date: Date.new(2026, 5, 25),
              day_name: "Monday",
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
