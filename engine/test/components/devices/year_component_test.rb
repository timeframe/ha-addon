# frozen_string_literal: true

require "test_helper"

class YearComponentTest < ActiveSupport::TestCase
  test "renders the year view with today's date and the events as data" do
    html = render_year(year_events: [
      {title: "Japan", start: "2026-11-12", end: "2026-11-21"},
      {"title" => "Vancouver", "start" => "2026-12-27", "end" => "2027-01-05"}
    ])

    assert_includes html, "year-view-page"
    assert_includes html, %(data-today="2026-11-07")
    events = JSON.parse(Nokogiri::HTML(html).at_css("#year-view")["data-events"])
    assert_equal [
      {"title" => "Japan", "start" => "2026-11-12", "end" => "2026-11-21"},
      {"title" => "Vancouver", "start" => "2026-12-27", "end" => "2027-01-05"}
    ], events
  end

  test "renders with no events" do
    html = render_year(year_events: nil)

    assert_equal [], JSON.parse(Nokogiri::HTML(html).at_css("#year-view")["data-events"])
  end

  private

  def render_year(year_events:)
    ApplicationController.render(
      Devices::YearComponent.new(view_object: {current_time: Time.zone.local(2026, 11, 7, 8, 0, 0), year_events: year_events}),
      layout: false
    )
  end
end
