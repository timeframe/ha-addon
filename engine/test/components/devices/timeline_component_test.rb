# frozen_string_literal: true

require "test_helper"

class TimelineComponentTest < ActiveSupport::TestCase
  test "renders day name" do
    html = render_timeline(day_groups: [day_group(day_name: "Monday")])
    assert_includes html, "Monday"
  end

  test "renders periodic event summary and time" do
    html = render_timeline(day_groups: [
      day_group(periodic: [
        {icon_class: "calendar", time_html: "<b>9:00a</b>", summary: "Team Standup"}
      ])
    ])
    assert_includes html, "Team Standup"
    assert_includes html, "9:00a"
  end

  test "renders periodic event icon" do
    html = render_timeline(day_groups: [
      day_group(periodic: [
        {icon_class: "soccer", time_html: "3:00p", summary: "Game"}
      ])
    ])
    assert_includes html, "mdi-soccer"
  end

  test "renders periodic event icon_text instead of icon_class" do
    html = render_timeline(day_groups: [
      day_group(periodic: [
        {icon_text: "🎉", time_html: "5:00p", summary: "Party"}
      ])
    ])
    assert_includes html, "🎉"
  end

  test "renders periodic event icon with style" do
    html = render_timeline(day_groups: [
      day_group(periodic: [
        {icon_class: "star", icon_style: "color: gold;", time_html: "7:00p", summary: "Award"}
      ])
    ])
    assert_includes html, 'style="color: gold;"'
  end

  test "renders daily events when show_daily is true" do
    html = render_timeline(day_groups: [
      day_group(show_daily: true, daily: [
        {icon_class: "weather-sunny", summary: "75°", location: "New York"}
      ])
    ])
    assert_includes html, "75°"
    assert_includes html, "New York"
    assert_includes html, "mdi-weather-sunny"
  end

  test "hides daily events when show_daily is false" do
    html = render_timeline(day_groups: [
      day_group(show_daily: false, daily: [
        {icon_class: "weather-sunny", summary: "75°", location: "New York"}
      ])
    ])
    refute_includes html, "75°"
  end

  test "renders daily event with icon_text" do
    html = render_timeline(day_groups: [
      day_group(show_daily: true, daily: [
        {icon_text: "☀️", summary: "Sunny"}
      ])
    ])
    assert_includes html, "☀️"
  end

  test "renders daily event precipitation" do
    html = render_timeline(day_groups: [
      day_group(show_daily: true, daily: [
        {icon_class: "weather-rainy", summary: "65°", precip: [{icon: "water", label: "80%"}]}
      ])
    ])
    assert_includes html, "mdi-water"
    assert_includes html, "80%"
  end

  test "renders daily event wind gust" do
    html = render_timeline(day_groups: [
      day_group(show_daily: true, daily: [
        {icon_class: "weather-windy", summary: "60°", wind_gust: "25mph"}
      ])
    ])
    assert_includes html, "mdi-weather-windy"
    assert_includes html, "25mph"
  end

  test "renders multiple day groups" do
    html = render_timeline(day_groups: [
      day_group(day_name: "Monday"),
      day_group(day_name: "Tuesday")
    ])
    assert_includes html, "Monday"
    assert_includes html, "Tuesday"
  end

  test "only_show_events_with_icons filters events without manual icons" do
    html = render_timeline(
      day_groups: [
        day_group(
          show_daily: true,
          daily: [{icon_class: "weather-sunny", summary: "75°", weather: true}],
          periodic: [
            {timeframe_icon: "soccer", icon_class: "soccer", time_html: "3:00p", summary: "Game"},
            {icon_class: "calendar", time_html: "9:00a", summary: "Team Standup"}
          ]
        )
      ],
      configuration: {"only_show_events_with_icons" => "true"}
    )
    assert_includes html, "Game"
    refute_includes html, "Team Standup"
    # Weather (daily) events are always kept.
    assert_includes html, "75°"
  end

  test "without only_show_events_with_icons shows all events" do
    html = render_timeline(
      day_groups: [
        day_group(periodic: [
          {icon_class: "calendar", time_html: "9:00a", summary: "Team Standup"}
        ])
      ],
      configuration: {"only_show_events_with_icons" => "false"}
    )
    assert_includes html, "Team Standup"
  end

  private

  def day_group(day_name: "Today", show_daily: false, daily: [], periodic: [])
    {day_name: day_name, show_daily: show_daily, daily: daily, periodic: periodic}
  end

  def render_timeline(day_groups:, configuration: {})
    ApplicationController.render(
      Devices::TimelineComponent.new(view_object: {day_groups: day_groups, configuration: configuration}),
      layout: false
    )
  end
end
