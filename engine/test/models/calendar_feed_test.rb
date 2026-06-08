# frozen_string_literal: true

require "test_helper"

class CalendarFeedTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  # DeviceEvents coming from the DB look different than those
  # constructed on the fly. DB events have string keys, for example.
  # This is not ideal and we should probably move to a standard value
  # object that has a consistent API.
  def test_events_for_stringified_key_from_db
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "plus"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)
    end
  end

  def test_events_for_duplicate_plus
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "plus"
      ),
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "alpha-j"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      result = CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)
      events = result[:periodic].select { it.id == "foo" }

      assert(events.length == 1)
      assert(events[0].icon == "plus")
    end
  end

  def test_events_for_duplicate_same_icon
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "alpha-j"
      ),
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "alpha-j"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      result = CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)
      events = result[:periodic].select { it.id == "foo" }

      assert(events.length == 1)
      assert(events[0].icon == "alpha-j")
    end
  end

  def test_events_for_duplicate_same_icon_diff_id
    calendar_events = [
      DeviceEvent.new(
        id: "foo2",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "alpha-j"
      ),
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "alpha-j"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      result = CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)
      events = result[:periodic].select { it.id.include? "foo" }

      assert(events.length == 1)
      assert(events[0].icon == "alpha-j")
    end
  end

  def test_events_for_duplicate_different_icon
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "alpha-c"
      ),
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 23, 0, 0, "-0600"),
        summary: "dupe",
        icon: "alpha-j"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      result = CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)
      events = result[:periodic].select { it.id == "foo" }

      assert(events.length == 1)
      assert(events[0].icon == "alpha-c")
    end
  end

  # Ran into this bug upgrading to Rails 7.1. Momentary events were not
  # returned due to a bug in range overlap comparison
  def test_filtering_moments
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        summary: "momentary events should not be filtered out!",
        icon: "alpha-c"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      assert(CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)[:periodic].length == 1)
    end
  end

  def test_filtering_daily
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 0, 0, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 28, 0, 0, 0, "-0600"),
        summary: "daily events should not be filtered out!",
        icon: "alpha-c",
        timezone: "America/Denver"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      assert(CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)[:daily].length == 1)

      start_time_utc = DateTime.new(2023, 8, 28, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 29, 0, 0, 0, "-0600").utc.to_time

      assert(CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)[:daily].length == 0)
    end
  end

  def test_daily_weather_events_sort_before_other_daily_events
    calendar_events = [
      DeviceEvent.new(
        id: "user-cal-1",
        starts_at: DateTime.new(2023, 8, 27, 0, 0, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 28, 0, 0, 0, "-0600"),
        summary: "Birthday",
        timezone: "America/Denver"
      ),
      DeviceEvent.new(
        id: "_wk_weather_daily_2023-08-27",
        starts_at: DateTime.new(2023, 8, 27, 0, 0, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 28, 0, 0, 0, "-0600"),
        summary: "75°/55°",
        timezone: "America/Denver"
      ),
      DeviceEvent.new(
        id: "user-cal-2",
        starts_at: DateTime.new(2023, 8, 27, 0, 0, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 28, 0, 0, 0, "-0600"),
        summary: "Anniversary",
        timezone: "America/Denver"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 20, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      daily = CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)[:daily]
      assert_equal ["_wk_weather_daily_2023-08-27", "user-cal-1", "user-cal-2"], daily.map(&:id)
    end
  end

  def test_filtering_multi_day_periodic_events
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 29, 22, 20, 0, "-0600"),
        summary: "multi-day periodic events should not be filtered out!",
        icon: "alpha-c"
      )
    ]

    travel_to DateTime.new(2023, 8, 28, 22, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 22, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      assert(CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)[:periodic].length == 1)
    end
  end

  def test_periodic_sort_places_moments_before_periods_at_same_start
    start_time = DateTime.new(2023, 8, 27, 15, 0, 0, "-0600")
    calendar_events = [
      DeviceEvent.new(
        id: "period-early",
        starts_at: start_time,
        ends_at: start_time + 2.hours,
        summary: "earlier period"
      ),
      DeviceEvent.new(
        id: "period-same",
        starts_at: start_time + 1.hour,
        ends_at: start_time + 3.hours,
        summary: "period at 4pm"
      ),
      DeviceEvent.new(
        id: "moment-same",
        starts_at: start_time + 1.hour,
        ends_at: start_time + 1.hour,
        summary: "moment at 4pm"
      )
    ]

    travel_to start_time do
      window_start = start_time.utc.to_time
      window_end = (start_time + 6.hours).utc.to_time

      periodic = CalendarFeed.new.events_for(window_start, window_end, calendar_events)[:periodic]

      assert_equal ["earlier period", "moment at 4pm", "period at 4pm"], periodic.map(&:summary)
    end
  end

  def test_filtering_private_events
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 15, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        summary: "timeframe-private"
      ),
      DeviceEvent.new(
        id: "bar",
        starts_at: DateTime.new(2023, 8, 27, 15, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        summary: "doctor",
        description: "timeframe-private"
      ),
      DeviceEvent.new(
        id: "bar",
        starts_at: DateTime.new(2023, 8, 27, 0, 0, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 28, 0, 0, 0, "-0600"),
        summary: "prep",
        description: "timeframe-private"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 17, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 0, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      assert(CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events, true)[:periodic].length == 0)
    end
  end

  def test_excludes_omit
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 15, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        summary: "Hide me!",
        description: "timeframe-omit"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 17, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 0, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      assert(CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)[:periodic].length == 0)
    end
  end

  def test_excludes_omit_with_other_details
    calendar_events = [
      DeviceEvent.new(
        id: "foo",
        starts_at: DateTime.new(2023, 8, 27, 15, 20, 0, "-0600"),
        ends_at: DateTime.new(2023, 8, 27, 20, 20, 0, "-0600"),
        summary: "Hide me!",
        description: "1995\ntimeframe-omit"
      )
    ]

    travel_to DateTime.new(2023, 8, 27, 17, 20, 0, "-0600") do
      start_time_utc = DateTime.new(2023, 8, 27, 0, 20, 0, "-0600").utc.to_time
      end_time_utc = DateTime.new(2023, 8, 28, 0, 0, 0, "-0600").utc.to_time

      assert(CalendarFeed.new.events_for(start_time_utc, end_time_utc, calendar_events)[:periodic].length == 0)
    end
  end
end
