# frozen_string_literal: true

require "test_helper"

class DeviceEventTest < Minitest::Test
  def test_assigns_time
    event = DeviceEvent.new(
      starts_at: 1675123200,
      ends_at: 1675126800,
      summary: "foo",
      timezone: "America/Chicago"
    )

    assert_equal("6 - 7p", event.time)
  end

  def test_assigns_time_from_datetime
    event = DeviceEvent.new(
      starts_at: Time.at(1675123200),
      ends_at: Time.at(1675126800),
      summary: "foo",
      timezone: "America/Chicago"
    )

    assert_equal("6 - 7p", event.time)
  end

  def test_assigns_time_from_string
    event = DeviceEvent.new(
      starts_at: "2023-08-16T11:30:00.000-06:00",
      ends_at: "2023-08-16T12:30:00.000-06:00",
      summary: "foo",
      timezone: "America/Chicago"
    )

    assert_equal("12:30 - 1:30p", event.time)
  end

  def test_sets_multi_day
    event = DeviceEvent.new(
      starts_at: 1675123200,
      ends_at: 1675209601,
      summary: "foo"
    )

    assert_equal(true, event.multi_day?)
  end

  def test_multi_day_time_change
    event = DeviceEvent.new(
      starts_at: 1762063200,
      ends_at: 1762153200,
      summary: "foo",
      timezone: "America/Chicago"
    )

    assert_equal(false, event.multi_day?)
  end

  def test_sets_counter
    event = DeviceEvent.new(
      starts_at: 1675123200,
      ends_at: 1675209601,
      summary: "foo",
      description: (Date.today.year - 2).to_s
    )

    assert_equal("foo (2)", event.summary)
  end

  def test_daily_true
    event = DeviceEvent.new(
      starts_at: DateTime.new(2023, 1, 23),
      ends_at: DateTime.new(2023, 1, 25),
      summary: "foo"
    )

    assert(event.daily?)
  end

  def test_daily_false
    event = DeviceEvent.new(
      starts_at: Time.at(1675123200),
      ends_at: Time.at(1675126800),
      summary: "foo"
    )

    refute(event.daily?)
  end

  def test_daily_same_start_end
    event = DeviceEvent.new(
      starts_at: 1675123200,
      ends_at: 1675123200,
      summary: "foo"
    )

    refute(event.daily?)
  end

  def test_daily_24h_non_midnight
    event = DeviceEvent.new(
      starts_at: 1698516000,
      ends_at: 1698602400,
      summary: "foo"
    )

    refute(event.daily?)
  end

  def test_start_only
    start = 1621288800 # 5pm Central
    finish = 1621288800

    event = DeviceEvent.new(starts_at: start, ends_at: finish, summary: "foo", timezone: "America/Chicago")

    assert_equal("5p", event.time)
  end

  def test_start_only_minutes
    start = 1621288860 # 5:01pm Central
    finish = 1621288860

    event = DeviceEvent.new(starts_at: start, ends_at: finish, summary: "foo", timezone: "America/Chicago")

    assert_equal("5:01p", event.time)
  end

  def test_one_hour_event_in_afternoon_at_top_of_hour
    start = 1621288800 # 5pm Central
    finish = 1621292400 # 6pm Central

    event = DeviceEvent.new(starts_at: start, ends_at: finish, summary: "foo", timezone: "America/Chicago")

    assert_equal("5 - 6p", event.time)
  end

  def test_one_hour_event_in_afternoon_at_minute_past_hour
    start = 1621288860 # 5:01pm Central
    finish = 1621292460 # 6:01pm Central

    event = DeviceEvent.new(starts_at: start, ends_at: finish, summary: "foo", timezone: "America/Chicago")

    assert_equal("5:01 - 6:01p", event.time)
  end

  def test_event_with_same_start_and_end_at_top_of_hour
    start = 1621288800 # 5pm Central

    event = DeviceEvent.new(starts_at: start, ends_at: start, summary: "foo", timezone: "America/Chicago")

    assert_equal("5p", event.time)
  end

  def test_event_with_same_start_and_end_at_minute_past
    start = 1621288860 # 5:01pm Central

    event = DeviceEvent.new(starts_at: start, ends_at: start, summary: "foo", timezone: "America/Chicago")

    assert_equal("5:01p", event.time)
  end

  def test_event_morning_to_afternoon
    start = 1621260000 # 9am Central
    finish = 1621288800 # 5pm Central

    event = DeviceEvent.new(starts_at: start, ends_at: finish, summary: "foo", timezone: "America/Chicago")

    assert_equal("9a - 5p", event.time)
  end

  def test_event_morning_to_afternoon_off_minute
    start = 1621260060 # 9:01am Central
    finish = 1621288860 # 5:01pm Central

    event = DeviceEvent.new(starts_at: start, ends_at: finish, summary: "foo", timezone: "America/Chicago")

    assert_equal("9:01a - 5:01p", event.time)
  end

  def test_event_different_days_off_by_minutes
    start = 1621220000 # 9:53pm Central 5/16/21
    finish = 1621288800 # 5pm Central 5/17

    event = DeviceEvent.new(starts_at: start, ends_at: finish, summary: "foo", timezone: "America/Chicago")

    assert_equal("Su 9:53p - M 5p", event.time)
  end

  def test_event_different_days
    start = 1621216820 # 9pm Central 5/16/21
    finish = 1621288800 # 5pm Central 5/17

    event = DeviceEvent.new(starts_at: start, ends_at: finish, summary: "foo", timezone: "America/Chicago")

    assert_equal("Su 9p - M 5p", event.time)
  end

  def test_event_over_time_change
    event = DeviceEvent.new(starts_at: "2023-11-01", ends_at: "2023-11-08", summary: "foo")

    assert(event.daily?)
  end

  def test_strips_emoji
    event = DeviceEvent.new(starts_at: "2023-11-01", ends_at: "2023-11-08", summary: "✨ foo")

    assert_equal("foo", event.summary)
  end

  def test_does_not_strip_things_we_should_keep
    event = DeviceEvent.new(starts_at: "2023-11-01", ends_at: "2023-11-08", summary: "foo bar / \\ ° - _ & : + , ()@ <> '’#")

    assert_equal("foo bar / \\ ° - _ & : + , ()@ <> '’#", event.summary)
  end

  def test_strips_non_ascii
    event = DeviceEvent.new(starts_at: "2023-11-01", ends_at: "2023-11-08", summary: " ‍ meeting")

    assert_equal("meeting", event.summary)
  end

  def test_daily_summary_count
    event = DeviceEvent.new(
      starts_at: DateTime.new(2023, 1, 23),
      ends_at: DateTime.new(2023, 1, 25),
      summary: "foo"
    )

    assert_equal(event.summary(DateTime.new(2023, 1, 24)), "foo (2/2)")
  end

  def test_non_daily_multi_day_summary_count
    event = DeviceEvent.new(
      starts_at: DateTime.new(2023, 1, 23, 10),
      ends_at: DateTime.new(2023, 1, 25, 11),
      summary: "foo"
    )

    assert_equal(event.summary(DateTime.new(2023, 1, 24)), "foo (2/3)")
  end

  def test_omit_if_blank
    event = DeviceEvent.new(
      starts_at: DateTime.new(2023, 1, 23),
      ends_at: DateTime.new(2023, 1, 25),
      summary: ""
    )

    assert(event.omit?)
  end

  def test_weather_hourly_true
    event = DeviceEvent.new(
      id: "_ha_weather_hour_1675123200",
      starts_at: 1675123200,
      ends_at: 1675123200,
      summary: "72°",
      icon: "weather-sunny"
    )

    assert(event.weather_hourly?)
  end

  def test_weather_hourly_true_for_wk
    event = DeviceEvent.new(
      id: "_wk_weather_hour_1675123200",
      starts_at: 1675123200,
      ends_at: 1675123200,
      summary: "72°",
      icon: "cloud"
    )

    assert(event.weather_hourly?)
  end

  def test_weather_hourly_false_for_non_weather
    event = DeviceEvent.new(
      starts_at: 1675123200,
      ends_at: 1675123200,
      summary: "foo",
      icon: "alpha-j"
    )

    refute(event.weather_hourly?)
  end

  def test_weather_hourly_false_for_ranged_event
    event = DeviceEvent.new(
      id: "_ha_weather_hour_1675123200",
      starts_at: 1675123200,
      ends_at: 1675126800,
      summary: "72°",
      icon: "weather-sunny"
    )

    refute(event.weather_hourly?)
  end

  def test_weather_true_for_ha_weather
    event = DeviceEvent.new(
      id: "_ha_weather_day_1675123200",
      starts_at: 1675123200,
      ends_at: 1675209600,
      summary: "72° / 55°",
      icon: "weather-sunny"
    )

    assert(event.weather?)
  end

  def test_weather_false_for_calendar_event
    event = DeviceEvent.new(
      starts_at: 1675123200,
      ends_at: 1675126800,
      summary: "Meeting",
      icon: "alpha-j"
    )

    refute(event.weather?)
  end

  def test_start_time
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      timezone: "America/Chicago"
    )

    assert_equal("5p", event.start_time)
  end

  def test_start_time_with_minutes
    event = DeviceEvent.new(
      starts_at: 1621288860,
      ends_at: 1621292400,
      summary: "foo",
      timezone: "America/Chicago"
    )

    assert_equal("5:01p", event.start_time)
  end

  def test_as_json_includes_start_time
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      timezone: "America/Chicago"
    )

    assert_equal("5p", event.as_json[:start_time])
  end

  def test_hidden_for_returns_false_without_description
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo"
    )

    refute(event.hidden_for?("Kitchen"))
  end

  def test_hidden_for_returns_false_without_timeframe_only_tag
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "just a regular description"
    )

    refute(event.hidden_for?("Kitchen"))
  end

  def test_hidden_for_returns_false_when_device_matches
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "timeframe-only:Kitchen"
    )

    refute(event.hidden_for?("Kitchen"))
  end

  def test_hidden_for_returns_true_when_device_does_not_match
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "timeframe-only:Kitchen"
    )

    assert(event.hidden_for?("Living Room"))
  end

  def test_hidden_for_is_case_insensitive
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "timeframe-only:kitchen"
    )

    refute(event.hidden_for?("Kitchen"))
  end

  def test_hidden_for_supports_multiple_devices
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "timeframe-only:Kitchen, Living Room"
    )

    refute(event.hidden_for?("Kitchen"))
    refute(event.hidden_for?("Living Room"))
    assert(event.hidden_for?("Bedroom"))
  end

  def test_hidden_for_returns_false_with_nil_device_name
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "timeframe-only:Kitchen"
    )

    refute(event.hidden_for?(nil))
  end

  def test_hidden_for_matches_by_device_id
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "timeframe-only:12, 15"
    )

    refute(event.hidden_for?("Kitchen", device_id: 12))
    refute(event.hidden_for?("Kitchen", device_id: 15))
    assert(event.hidden_for?("Kitchen", device_id: 99))
  end

  def test_hidden_for_matches_by_name_or_id
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "timeframe-only:Kitchen, 15"
    )

    refute(event.hidden_for?("Kitchen", device_id: 99))
    refute(event.hidden_for?("Bedroom", device_id: 15))
    assert(event.hidden_for?("Bedroom", device_id: 99))
  end

  def test_hidden_for_returns_false_with_nil_name_and_id
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "foo",
      description: "timeframe-only:Kitchen"
    )

    refute(event.hidden_for?(nil, device_id: nil))
  end

  def test_timeframe_icon_overrides_icon_from_description
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Practice",
      icon: "calendar",
      description: "Bring cleats\n\ntimeframe-icon:soccer"
    )

    assert_equal("soccer", event.icon)
    assert_equal("soccer", event.as_json[:icon_class])
    assert_equal("soccer", event.as_json[:timeframe_icon])
  end

  def test_timeframe_icon_strips_mdi_prefix
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Practice",
      icon: "calendar",
      description: "timeframe-icon:mdi-soccer"
    )

    assert_equal("soccer", event.icon)
  end

  def test_title_override_from_description
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Original Title",
      description: "timeframe-title:Custom Title"
    )

    assert_equal("Custom Title", event.summary)
    assert_equal("Custom Title", event.as_json[:summary])
  end

  def test_auto_icon_titles_include_override_then_underlying
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Original Title",
      description: "timeframe-title:Custom Title"
    )

    assert_equal(["Custom Title", "Original Title"], event.as_json[:auto_icon_titles])
  end

  def test_auto_icon_titles_without_override
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Original Title"
    )

    assert_equal(["Original Title"], event.as_json[:auto_icon_titles])
  end

  def test_year_count_for_a_year_description
    assert_equal Date.today.year - 1990, DeviceEvent.year_count("1990")
  end

  def test_year_count_finds_a_year_anywhere_in_the_description
    assert_equal Date.today.year - 1990, DeviceEvent.year_count("Born 1990")
    assert_equal Date.today.year - 2000, DeviceEvent.year_count("married in 2000, still going")
  end

  def test_year_count_nil_for_non_year_description
    assert_nil DeviceEvent.year_count("just a note")
    assert_nil DeviceEvent.year_count(nil)
    assert_nil DeviceEvent.year_count("1850")
    # A 4-digit run inside a longer number is not a standalone year.
    assert_nil DeviceEvent.year_count("id 1234567")
  end

  def test_summary_renders_a_description_year_as_a_count
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Anniversary",
      description: "Married in 2000"
    )

    assert_equal "Anniversary (#{Date.today.year - 2000})", event.summary
  end

  def test_summary_renders_trailing_year_in_title_as_a_count_for_yearly_events
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Ada (1990)",
      yearly_recurring: true
    )

    assert_equal "Ada (#{Date.today.year - 1990})", event.summary
    assert_equal "Ada (#{Date.today.year - 1990})", event.as_json[:summary]
  end

  def test_summary_leaves_title_year_alone_for_non_yearly_events
    # The title "(YYYY)" -> count only applies to yearly recurring events; a
    # one-off event keeps its parenthetical year as written.
    event = DeviceEvent.new(starts_at: 1621288800, ends_at: 1621292400, summary: "Ada (1990)")
    assert_equal "Ada (1990)", event.summary
  end

  def test_summary_leaves_non_year_parentheticals_alone
    unchanged = DeviceEvent.new(starts_at: 1621288800, ends_at: 1621292400, summary: "Team (12)", yearly_recurring: true)
    assert_equal "Team (12)", unchanged.summary

    out_of_range = DeviceEvent.new(starts_at: 1621288800, ends_at: 1621292400, summary: "Old (1850)", yearly_recurring: true)
    assert_equal "Old (1850)", out_of_range.summary
  end

  def test_title_with_year_count_helper
    assert_equal "Ada (#{Date.today.year - 2000})", DeviceEvent.title_with_year_count("Ada (2000)")
    assert_nil DeviceEvent.title_with_year_count("No year here")
    assert_nil DeviceEvent.title_with_year_count("Old (1850)")
    assert_nil DeviceEvent.title_with_year_count(nil)
  end

  def test_title_override_not_applied_without_tag
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Original Title",
      description: "just a note"
    )

    assert_equal("Original Title", event.summary)
  end

  def test_title_override_with_other_tags
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Original",
      description: "timeframe-icon:church\ntimeframe-title:Sunday Service"
    )

    assert_equal("Sunday Service", event.summary)
    assert_equal("church", event.as_json[:timeframe_icon])
  end

  def test_precip_from_precip_icon_and_label
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "72° / 45°",
      precip_icon: "weather-rainy",
      precip_label: "0.5\""
    )

    assert_equal [{icon: "weather-rainy", label: "0.5\""}], event.precip
  end

  def test_precip_from_precip_array
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "72° / 45°",
      precip: [{icon: "snowflake", label: "3.0\""}, {icon: "weather-rainy", label: "0.5\""}]
    )

    assert_equal 2, event.precip.length
    assert_equal "snowflake", event.precip.first[:icon]
  end

  def test_precip_nil_when_not_provided
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "72° / 45°"
    )

    assert_nil event.precip
  end

  def test_banner_with_timeframe_banner_keyword
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Office Closed",
      description: "timeframe-banner\nBuilding maintenance today"
    )

    assert event.banner?
    assert_equal "Office Closed", event.banner_title
    assert_equal "Building maintenance today", event.banner_description
  end

  def test_banner_with_hash_banner_keyword
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Snow Day",
      description: "#banner\nAll schools closed"
    )

    assert event.banner?
    assert_equal "Snow Day", event.banner_title
    assert_equal "All schools closed", event.banner_description
  end

  def test_banner_false_without_keyword
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Regular Event",
      description: "Just a normal event"
    )

    refute event.banner?
  end

  def test_banner_false_without_description
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "No Description"
    )

    refute event.banner?
  end

  def test_banner_description_nil_without_description
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "No Description"
    )

    assert_nil event.banner_description
  end

  def test_banner_description_sanitizes_html
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Alert",
      description: "timeframe-banner\n<b>Important</b><script>alert('xss')</script><p>Details here</p>"
    )

    assert event.banner?
    desc = event.banner_description
    assert_includes desc, "<b>Important</b>"
    assert_includes desc, "<p>Details here</p>"
    refute_includes desc, "<script>"
    refute_includes desc, "alert('xss')"
  end

  def test_banner_description_with_rich_html
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Update",
      description: "#banner\n<ul><li>Item 1</li><li>Item <em>2</em></li></ul>"
    )

    desc = event.banner_description
    assert_includes desc, "<ul>"
    assert_includes desc, "<li>Item 1</li>"
    assert_includes desc, "<em>2</em>"
  end

  def test_banner_description_plain_text_newlines
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Notice",
      description: "timeframe-banner\nLine one\nLine two"
    )

    desc = event.banner_description
    assert_includes desc, "Line one<br>Line two"
  end

  def test_banner_description_strips_metadata_tags
    event = DeviceEvent.new(
      starts_at: 1621288800,
      ends_at: 1621292400,
      summary: "Alert",
      description: "timeframe-banner\ntimeframe-icon:soccer\ntimeframe-only:kitchen\nActual message"
    )

    desc = event.banner_description
    refute_includes desc, "timeframe-icon"
    refute_includes desc, "timeframe-only"
    assert_includes desc, "Actual message"
  end
end
