# frozen_string_literal: true

require "test_helper"

class TwoDayLandscapeComponentTest < ActiveSupport::TestCase
  test "renders two days without a current day and temperature header" do
    html = ApplicationController.render(
      Devices::TwoDayLandscapeComponent.new(view_object: view_object),
      layout: false
    )

    assert_includes html, "two-day-landscape-page"
    refute_includes html, "current-day-header"
    refute_includes html, "70°"
    assert_includes html, "Monday event"
    assert_includes html, "Tuesday event"
  end

  private

  def view_object(configuration: {})
    {
      current_time: Time.zone.local(2026, 5, 25, 8, 0, 0),
      current_temperature: "70°",
      configuration: configuration,
      day_groups: [
        day_group(Date.new(2026, 5, 25), "Monday", "Monday event"),
        day_group(Date.new(2026, 5, 26), "Tuesday", "Tuesday event")
      ]
    }
  end

  def day_group(date, day_name, summary)
    {
      date: date,
      day_name: day_name,
      weather_row: [],
      clothing: nil,
      show_daily: false,
      daily: [],
      periodic: [{summary: summary, time_html: "9a", icon_class: "calendar"}]
    }
  end
end
