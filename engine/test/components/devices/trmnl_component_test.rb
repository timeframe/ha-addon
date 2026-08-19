# frozen_string_literal: true

require "test_helper"

class TrmnlComponentTest < ActiveSupport::TestCase
  test "uses the default root font size" do
    html = render_trmnl(configuration: {})
    assert_includes html, "font-size: 16px;"
  end

  test "enlarges the root font size when larger_text is true" do
    html = render_trmnl(configuration: {"larger_text" => "true"})
    assert_includes html, "font-size: 19.2px;"
  end

  test "shows the current day header by default when unset" do
    html = render_trmnl(configuration: {})
    assert_includes html, "Wednesday, Aug. 19"
  end

  test "hides the current day header when show_current_day is false" do
    html = render_trmnl(configuration: {"show_current_day" => "false"})
    refute_includes html, "Wednesday, Aug. 19"
  end

  private

  def render_trmnl(configuration:)
    view_object = {
      top_left: [],
      top_right: [],
      weather_status: [],
      battery: nil,
      day_groups: [],
      current_time: Time.zone.local(2026, 8, 19, 8, 0, 0),
      current_temperature: "72°".html_safe,
      configuration: configuration
    }
    ApplicationController.render(
      Devices::TrmnlComponent.new(view_object: view_object),
      layout: false
    )
  end
end
