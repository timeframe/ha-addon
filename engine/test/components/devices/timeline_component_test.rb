# frozen_string_literal: true

require "test_helper"

class TimelineComponentTest < ActiveSupport::TestCase
  test "compact header renders the weather icon next to the day name with the weather summary right-aligned" do
    html = render_timeline(
      compact_header: true,
      daily: [
        weather_event(icon_class: "weather-sunny", summary: "72° / 50°", precip: [{icon: "weather-rainy", label: "20%"}], wind_gust: "15mph"),
        event(icon_class: "cake-variant", summary: "Sarah (36)"),
        event(icon_text: "A", summary: "All-hands"),
        event(icon_class: "vacation", summary: "Vacation (3/7)", icon_style: "color: red;")
      ]
    )

    assert_includes html, "timeline-day-header--compact"
    assert_includes html, "timeline-day-weather-icon"
    assert_includes html, "mdi-weather-sunny"
    assert_includes html, "72° / 50°"
    assert_includes html, "mdi-weather-rainy"
    assert_includes html, "20%"
    assert_includes html, "mdi-weather-windy"
    assert_includes html, "15mph"
    assert_includes html, "timeline-day-daily"
    assert_includes html, "mdi-cake-variant"
    assert_includes html, "Sarah (36)"
    assert_includes html, "<span>A</span>"
    assert_includes html, "All-hands"
    assert_includes html, "Vacation (3/7)"
    assert_includes html, "color: red"
  end

  test "compact header without a weather event omits the inline weather row but keeps the daily table" do
    html = render_timeline(
      compact_header: true,
      daily: [event(icon_class: "cake-variant", summary: "Sarah (36)")]
    )

    refute_includes html, "timeline-day-weather-icon"
    assert_includes html, "timeline-day-daily"
    assert_includes html, "Sarah (36)"
  end

  test "compact header with no daily events renders neither the inline weather row nor the daily table" do
    html = render_timeline(compact_header: true, daily: [], show_daily: false)

    assert_includes html, "Today"
    refute_includes html, "timeline-day-weather-icon"
    refute_includes html, "timeline-day-daily"
  end

  test "compact header with only the weather event omits the daily table" do
    html = render_timeline(
      compact_header: true,
      daily: [weather_event(icon_class: "weather-sunny", summary: "72° / 50°")]
    )

    assert_includes html, "timeline-day-weather-icon"
    refute_includes html, "timeline-day-daily"
  end

  test "event_icon renders an icon_text span when provided" do
    component = Devices::TimelineComponent.new(view_object: {day_groups: []})

    assert_equal "<span>X</span>", component.event_icon({icon_text: "X", icon_class: "ignored"})
  end

  test "event_icon renders a styled mdi icon when icon_style is provided" do
    component = Devices::TimelineComponent.new(view_object: {day_groups: []})

    assert_equal %(<i class="mdi mdi-vacation" style="color: red;"></i>),
      component.event_icon({icon_class: "vacation", icon_style: "color: red;"})
  end

  test "event_summary_html renders precip entries without icons" do
    component = Devices::TimelineComponent.new(view_object: {day_groups: []})

    html = component.event_summary_html({summary: "70°", precip: [{label: "10%"}]})

    assert_includes html, "70°"
    assert_includes html, "/ 10%"
  end

  test "default header keeps the existing table layout" do
    html = render_timeline(
      daily: [weather_event(icon_class: "weather-sunny", summary: "72° / 50°")]
    )

    assert_includes html, "timeline-day-daily"
    refute_includes html, "timeline-day-header--compact"
  end

  private

  def render_timeline(daily: [], show_daily: true, compact_header: false)
    ApplicationController.render(
      Devices::TimelineComponent.new(
        view_object: {
          day_groups: [
            {
              date: Date.new(2026, 5, 23),
              day_name: "Today",
              show_daily: show_daily,
              daily: daily,
              periodic: []
            }
          ]
        },
        compact_header: compact_header
      ),
      layout: false
    )
  end

  def event(overrides = {})
    {
      icon_text: nil,
      icon_class: "calendar",
      icon_style: nil,
      summary: "Event",
      location: nil,
      weather: false,
      precip: nil,
      wind_gust: nil
    }.merge(overrides)
  end

  def weather_event(overrides = {})
    event(weather: true).merge(overrides)
  end
end
