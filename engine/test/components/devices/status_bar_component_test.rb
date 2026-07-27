# frozen_string_literal: true

require "test_helper"

class StatusBarComponentTest < ActiveSupport::TestCase
  test "merges indicators that share an icon and rotation into one group" do
    html = render_status_bar(
      top_left: [
        {icon: "lock", rotation: nil, label: "Front"},
        {icon: "lock", rotation: nil, label: "Back"}
      ]
    )

    assert_includes html, "Front, Back"
    assert_equal 1, html.scan("mdi-lock").size
  end

  test "keeps indicators with different rotations separate" do
    html = render_status_bar(
      top_left: [
        {icon: "lock", rotation: nil, label: "Front"},
        {icon: "lock", rotation: 90, label: "Back"}
      ]
    )

    assert_includes html, "Front"
    assert_includes html, "Back"
    refute_includes html, "Front, Back"
  end

  private

  def render_status_bar(top_left: [], top_right: [], weather_status: [], battery: nil)
    ApplicationController.render(
      Devices::StatusBarComponent.new(
        view_object: {
          top_left: top_left,
          top_right: top_right,
          weather_status: weather_status,
          battery: battery
        }
      ),
      layout: false
    )
  end
end
