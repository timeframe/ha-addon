# frozen_string_literal: true

require "test_helper"

class CompactEventTimesComponentTest < ActiveSupport::TestCase
  test "two day periodic events show shorthand start and end time" do
    html = render_component(
      Devices::TwoDayComponent,
      events: [
        event(time_html: "6-6:30p", start_time: "6p", full_start_time: "6:00pm", full_time: "6:00pm - 6:30pm")
      ],
      configuration: {
        "only_show_events_with_icons" => "true",
        "show_event_times" => "true",
        "show_icons" => "false"
      }
    )

    assert_includes html, "6-6:30p"
    refute_includes html, "6:00pm"
  end

  test "three day periodic events show shorthand start and end time" do
    html = render_component(
      Devices::ThreeDayComponent,
      events: [
        event(time_html: "6-6:30p", start_time: "6p", full_start_time: "6:00pm", full_time: "6:00pm - 6:30pm")
      ]
    )

    assert_includes html, "6-6:30p"
    refute_includes html, "6:00pm"
  end

  test "three day ranged periodic events do not use longhand time" do
    html = render_component(
      Devices::ThreeDayComponent,
      events: [
        event(time_html: "2-4p", full_time: "2:00pm - 4:00pm", weather_ranged: true)
      ]
    )

    assert_includes html, "2-4p"
    refute_includes html, "2:00pm"
  end

  test "two day only show calendar events with icons filters to tagged events" do
    html = render_component(
      Devices::TwoDayComponent,
      events: [
        event(summary: "Plain Event", timeframe_icon: nil),
        event(summary: "Tagged Event", timeframe_icon: "soccer")
      ],
      configuration: {
        "only_show_events_with_icons" => "true",
        "show_event_times" => "false",
        "show_icons" => "false"
      }
    )

    assert_includes html, "Tagged Event"
    refute_includes html, "Plain Event"
  end

  test "two day without only show calendar events with icons includes all events" do
    html = render_component(
      Devices::TwoDayComponent,
      events: [
        event(summary: "Plain Event", timeframe_icon: nil),
        event(summary: "Tagged Event", timeframe_icon: "soccer")
      ],
      configuration: {
        "only_show_events_with_icons" => "false",
        "show_event_times" => "false",
        "show_icons" => "false"
      }
    )

    assert_includes html, "Tagged Event"
    assert_includes html, "Plain Event"
  end

  test "three day only show calendar events with icons filters to tagged events" do
    html = render_component(
      Devices::ThreeDayComponent,
      events: [
        event(summary: "Plain Event", timeframe_icon: nil),
        event(summary: "Tagged Event", timeframe_icon: "church")
      ],
      configuration: {
        "only_show_events_with_icons" => "true",
        "show_icons" => "false"
      }
    )

    assert_includes html, "Tagged Event"
    refute_includes html, "Plain Event"
  end

  private

  def render_component(component_class, events:, configuration: {})
    ApplicationController.render(
      component_class.new(
        view_object: {
          private_mode: false,
          current_time: Time.zone.local(2026, 5, 23, 8, 0, 0),
          configuration: {
            "only_show_events_with_icons" => "true",
            "show_icons" => "false"
          }.merge(configuration),
          day_groups: [
            {
              date: Date.new(2026, 5, 23),
              day_name: "Today",
              weather_row: [],
              show_daily: false,
              daily: [],
              periodic: events
            }
          ],
          timestamp: "8:00 AM",
          attribution: ""
        }
      ),
      layout: false
    )
  end

  def event(overrides = {})
    {
      summary: "Dinner",
      time_html: "6-6:30p",
      start_time: "6p",
      full_start_time: "6:00pm",
      full_time: "6:00pm - 6:30pm",
      weather_ranged: false,
      timeframe_icon: "soccer"
    }.merge(overrides)
  end
end
