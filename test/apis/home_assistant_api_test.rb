# frozen_string_literal: true

require "test_helper"

class HomeAssistantApiTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  # --- Infrastructure ---

  def test_headers
    api = HomeAssistantApi.new(TimeframeConfig.new(home_assistant_token: "test_token"))
    headers = api.headers
    assert_equal "Bearer test_token", headers[:Authorization]
    assert_equal "application/json", headers[:"content-type"]
  end

  def test_home_assistant_base_url_without_config
    api = HomeAssistantApi.new(TimeframeConfig.new)
    assert_equal "http://homeassistant.local:8123", api.home_assistant_base_url
  end

  def test_home_assistant_base_url_default
    api = HomeAssistantApi.new
    assert_equal "http://homeassistant.local:8123", api.home_assistant_base_url
  end

  def test_fetch_states_non_200
    api = HomeAssistantApi.new
    response = Struct.new(:code).new(500)
    HTTParty.stub :get, response do
      result = api.fetch_states
      assert_nil result
    end
  end

  def test_watched_entity_ids
    states = [
      {"entity_id" => "sensor.timeframe_top_left_door"},
      {"entity_id" => "media_player.living_room"},
      {"entity_id" => "weather.home"},
      {"entity_id" => "light.kitchen"},
      {"entity_id" => "switch.garage"}
    ]
    response = Struct.new(:code, :body).new(200, states.to_json)
    api = HomeAssistantApi.new
    HTTParty.stub :get, response do
      ids = api.watched_entity_ids
      assert_equal 3, ids.length
      assert_includes ids, "sensor.timeframe_top_left_door"
      assert_includes ids, "media_player.living_room"
      assert_includes ids, "weather.home"
      refute_includes ids, "light.kitchen"
    end
  end

  def test_watched_entity_ids_non_200
    response = Struct.new(:code).new(500)
    api = HomeAssistantApi.new
    HTTParty.stub :get, response do
      assert_equal [], api.watched_entity_ids
    end
  end

  def test_save_states
    api = new_test_api
    states = [{"entity_id" => "sensor.test", "state" => "42"}]
    api.save_states(states)
    assert_equal 1, api.data.length
  end

  def test_fetch_config_non_200
    api = HomeAssistantApi.new
    response = Struct.new(:code).new(500)
    HTTParty.stub :get, response do
      result = api.fetch_config
      assert_nil result
    end
  end

  def test_config_data_fetches_when_cache_is_empty
    api = HomeAssistantApi.new(TimeframeConfig.new, store: ActiveSupport::Cache::MemoryStore.new)

    api.stub :fetch_config, -> { api.seed_config(DEFAULT_TEST_CONFIG) } do
      assert_equal "America/Chicago", api.config_data[:time_zone]
    end
  end

  # --- States ---

  def test_feels_like_temperature_no_data
    api = HomeAssistantApi.new
    api.stub :data, [] do
      assert_nil(api.feels_like_temperature)
    end
  end

  def test_feels_like_temperature
    api = HomeAssistantApi.new
    api.stub :data, [
      {entity_id: "sensor.timeframe_weather_feels_like_entity_id", state: "sensor.feels_like"},
      {entity_id: "sensor.feels_like", state: "49.712"}
    ] do
      assert_equal("50°", api.feels_like_temperature)
    end
  end

  def test_feels_like_temperature_falls_back_to_weather_entity
    api = HomeAssistantApi.new
    api.stub :data, [
      {entity_id: "weather.my_weather", state: "sunny", attributes: {apparent_temperature: 72.3}}
    ] do
      assert_equal("72°", api.feels_like_temperature)
    end
  end

  def test_feels_like_temperature_converts_c_to_f
    config = TimeframeConfig.new(temperature_unit: "F")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "mm"})
    api.stub :data, [
      {entity_id: "weather.my_weather", state: "sunny", attributes: {apparent_temperature: 20.0}}
    ] do
      assert_equal("68°", api.feels_like_temperature)
    end
  end

  def test_feels_like_temperature_converts_f_to_c
    config = TimeframeConfig.new(temperature_unit: "C")
    api = HomeAssistantApi.new(config)
    api.stub :data, [
      {entity_id: "sensor.timeframe_weather_feels_like_entity_id", state: "sensor.feels_like"},
      {entity_id: "sensor.feels_like", state: "68"}
    ] do
      assert_equal("20°", api.feels_like_temperature)
    end
  end

  def test_units_prefer_account_over_config
    account = Struct.new(:temperature_unit, :speed_unit, :precipitation_unit).new("C", "kph", "mm")
    api = HomeAssistantApi.new(TimeframeConfig.new, account: account)
    assert_equal "C", api.temperature_unit
    assert_equal "kph", api.speed_unit
    assert_equal "mm", api.precipitation_unit
  end

  def test_units_fall_back_to_config_without_account
    api = HomeAssistantApi.new(TimeframeConfig.new(temperature_unit: "C", speed_unit: "kph", precipitation_unit: "mm"))
    assert_equal "C", api.temperature_unit
    assert_equal "kph", api.speed_unit
    assert_equal "mm", api.precipitation_unit
  end

  def test_feels_like_override_entity_missing
    api = HomeAssistantApi.new
    api.stub :data, [
      {entity_id: "sensor.timeframe_weather_feels_like_entity_id", state: "sensor.nonexistent"}
    ] do
      assert_nil(api.feels_like_temperature)
    end
  end

  def test_weather_entity_id_from_timeframe_sensor
    api = HomeAssistantApi.new
    api.stub :data, [
      {entity_id: "sensor.timeframe_weather_entity_id", state: "weather.custom"},
      {entity_id: "weather.default", state: "sunny"}
    ] do
      assert_equal("weather.custom", api.weather_entity_id)
    end
  end

  def test_weather_entity_id_falls_back_to_first_weather_entity
    api = HomeAssistantApi.new
    api.stub :data, [
      {entity_id: "weather.my_weather", state: "sunny"}
    ] do
      assert_equal("weather.my_weather", api.weather_entity_id)
    end
  end

  def test_weather_entity_id_returns_nil_when_no_weather
    api = HomeAssistantApi.new
    api.stub :data, [] do
      assert_nil(api.weather_entity_id)
    end
  end

  def test_fetch_states
    VCR.use_cassette(:home_assistant_states) do
      api = new_test_api
      api.fetch_states

      assert api.states_healthy?
      assert api.data.length > 0
    end
  end

  def test_fetch_states_empty_watched_ids
    response = Struct.new(:code, :body).new(200, "[]")
    api = new_test_api
    HTTParty.stub :get, response do
      assert_nil api.fetch_states
    end
  end

  def test_states_health_no_fetched_at
    api = HomeAssistantApi.new
    api.stub :states_last_fetched_at, nil do
      assert(!api.states_healthy?)
    end
  end

  def test_states_health_current_fetched_at
    api = HomeAssistantApi.new
    api.stub :states_last_fetched_at, "2023-08-27 15:14:59 -0600" do
      travel_to DateTime.new(2023, 8, 27, 15, 15, 0, "-0600") do
        assert(api.states_healthy?)
      end
    end
  end

  def test_states_health_stale_fetched_at
    api = HomeAssistantApi.new
    api.stub :states_last_fetched_at, "2023-08-27 15:14:59 -0600" do
      travel_to DateTime.new(2023, 8, 27, 15, 17, 0, "-0600") do
        refute(api.states_healthy?)
      end
    end
  end

  def test_now_playing_no_data
    api = HomeAssistantApi.new({})
    api.stub :data, [] do
      assert_equal({}, api.now_playing)
    end
  end

  def test_now_playing_no_media_player_entity
    data = [
      {entity_id: "sensor.timeframe_media_player_entity_id", state: "media_player.living_room"}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal({}, api.now_playing)
    end
  end

  def test_now_playing_paused
    data = [
      {entity_id: "sensor.timeframe_media_player_entity_id", state: "media_player.living_room"},
      {entity_id: "media_player.living_room", state: "paused", attributes: {media_artist: "COSMOGLOW", media_title: "Snoozy Stardust"}}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal({}, api.now_playing)
    end
  end

  def test_now_playing_idle
    data = [
      {entity_id: "sensor.timeframe_media_player_entity_id", state: "media_player.living_room"},
      {entity_id: "media_player.living_room", state: "idle", attributes: {media_artist: "COSMOGLOW", media_title: "Snoozy Stardust"}}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal({}, api.now_playing)
    end
  end

  def test_now_playing_playing
    data = [
      {entity_id: "sensor.timeframe_media_player_entity_id", state: "media_player.living_room"},
      {entity_id: "media_player.living_room", state: "playing", attributes: {media_artist: "COSMOGLOW", media_title: "Snoozy Stardust"}}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal({artist: "COSMOGLOW", track: "Snoozy Stardust"}, api.now_playing)
    end
  end

  def test_now_playing_artist_only
    data = [
      {entity_id: "sensor.timeframe_media_player_entity_id", state: "media_player.living_room"},
      {entity_id: "media_player.living_room", state: "playing", attributes: {media_artist: "COSMOGLOW"}}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal({artist: "COSMOGLOW", track: nil}, api.now_playing)
    end
  end

  def test_now_playing_falls_back_to_first_media_player
    data = [
      {entity_id: "media_player.living_room", state: "playing", attributes: {media_artist: "COSMOGLOW", media_title: "Snoozy Stardust"}}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal({artist: "COSMOGLOW", track: "Snoozy Stardust"}, api.now_playing)
    end
  end

  def test_now_playing_no_artist_or_track
    data = [
      {entity_id: "media_player.living_room", state: "playing", attributes: {}}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal({}, api.now_playing)
    end
  end

  def test_top_left_csv_dedupe
    data = [{entity_id: "sensor.timeframe_top_left_front_door", state: "door-open,Front\n\n  \n      door-open,Front"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "door-open", label: "Front"}], api.top_left)
    end
  end

  def test_top_left
    data = [{entity_id: "sensor.timeframe_top_left_front_door", state: "door-open,Front"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "door-open", label: "Front"}], api.top_left)
    end
  end

  def test_top_left_with_underscore
    data = [{entity_id: "sensor.timeframe_top_left_front_door", state: "door-open,front_door_open"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "door-open", label: "Front door open"}], api.top_left)
    end
  end

  def test_top_left_capitalization
    data = [{entity_id: "sensor.timeframe_top_left_front_door", state: "crow,Great Horned"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "crow", label: "Great Horned"}], api.top_left)
    end
  end

  def test_top_left_empty
    data = [{entity_id: "sensor.timeframe_top_left_front_door", state: ""}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([], api.top_left)
    end
  end

  def test_top_left_no_data
    api = HomeAssistantApi.new({})
    api.stub :data, [] do
      assert_equal([], api.top_left)
    end
  end

  def test_top_left_multiple_sensors
    data = [
      {entity_id: "sensor.timeframe_top_left_front_door", state: "door-open,Front"},
      {entity_id: "sensor.timeframe_top_left_patio", state: "lock-open,Patio"}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([
        {icon: "door-open", label: "Front"},
        {icon: "lock-open", label: "Patio"}
      ], api.top_left)
    end
  end

  def test_top_left_short_parts
    data = [{entity_id: "sensor.timeframe_top_left_x", state: "onlyicon"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "onlyicon"}], api.top_left)
    end
  end

  def test_top_right_no_data
    api = HomeAssistantApi.new({})
    api.stub :data, [] do
      assert_equal([], api.top_right)
    end
  end

  def test_top_right_empty_state
    data = [{entity_id: "sensor.timeframe_top_right", state: ""}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([], api.top_right)
    end
  end

  def test_top_right
    data = [{entity_id: "sensor.timeframe_top_right", state: "thermometer,72°"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "thermometer", label: "72°"}], api.top_right)
    end
  end

  def test_top_right_with_underscore
    data = [{entity_id: "sensor.timeframe_top_right", state: "thermometer,feels_like"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "thermometer", label: "Feels like"}], api.top_right)
    end
  end

  def test_top_right_multiple_sensors
    data = [
      {entity_id: "sensor.timeframe_top_right_temperature", state: "thermometer,72°"},
      {entity_id: "sensor.timeframe_top_right_humidity", state: "water-percent,45%"}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([
        {icon: "thermometer", label: "72°"},
        {icon: "water-percent", label: "45%"}
      ], api.top_right)
    end
  end

  def test_top_right_short_parts
    data = [{entity_id: "sensor.timeframe_top_right_x", state: "onlyicon"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "onlyicon"}], api.top_right)
    end
  end

  def test_weather_status_no_data
    api = HomeAssistantApi.new({})
    api.stub :data, [] do
      assert_equal([], api.weather_status)
    end
  end

  def test_weather_status_empty_state
    data = [{entity_id: "sensor.timeframe_weather_status_aqi", state: ""}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([], api.weather_status)
    end
  end

  def test_weather_status
    data = [{entity_id: "sensor.timeframe_weather_status_aqi", state: "air-filter,AQI 42"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "air-filter", label: "AQI 42"}], api.weather_status)
    end
  end

  def test_weather_status_with_rotation
    data = [{entity_id: "sensor.timeframe_weather_status_wind", state: "arrow-up,15,225"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "arrow-up", label: "15", rotation: 225}], api.weather_status)
    end
  end

  def test_weather_status_multiple_sensors
    data = [
      {entity_id: "sensor.timeframe_weather_status_aqi", state: "air-filter,AQI 42"},
      {entity_id: "sensor.timeframe_weather_status_uv", state: "white-balance-sunny,UV 6"}
    ]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([
        {icon: "air-filter", label: "AQI 42"},
        {icon: "white-balance-sunny", label: "UV 6"}
      ], api.weather_status)
    end
  end

  def test_weather_status_short_parts
    data = [{entity_id: "sensor.timeframe_weather_status_x", state: "onlyicon"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "onlyicon"}], api.weather_status)
    end
  end

  def test_weather_status_without_rotation
    data = [{entity_id: "sensor.timeframe_weather_status_aqi", state: "air-filter,AQI 42"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      result = api.weather_status
      assert_equal 1, result.length
      refute result.first.key?(:rotation)
    end
  end

  def test_weather_status_with_underscore_label
    data = [{entity_id: "sensor.timeframe_weather_status_aqi", state: "air-filter,air_quality"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([{icon: "air-filter", label: "Air quality"}], api.weather_status)
    end
  end

  def test_weather_status_multiline_single_sensor
    data = [{entity_id: "sensor.timeframe_weather_status_info", state: "air-filter,AQI 42\nwhite-balance-sunny,UV 6"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([
        {icon: "air-filter", label: "AQI 42"},
        {icon: "white-balance-sunny", label: "UV 6"}
      ], api.weather_status)
    end
  end

  def test_top_right_multiline_single_sensor
    data = [{entity_id: "sensor.timeframe_top_right_info", state: "home,At home\ncar,Driving"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([
        {icon: "home", label: "At home"},
        {icon: "car", label: "Driving"}
      ], api.top_right)
    end
  end

  def test_multiline_with_blank_lines_ignored
    data = [{entity_id: "sensor.timeframe_weather_status_info", state: "air-filter,AQI 42\n\nwhite-balance-sunny,UV 6"}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([
        {icon: "air-filter", label: "AQI 42"},
        {icon: "white-balance-sunny", label: "UV 6"}
      ], api.weather_status)
    end
  end

  def test_daily_events_no_data
    api = HomeAssistantApi.new({})
    api.stub :data, [] do
      assert_equal([], api.daily_events)
    end
  end

  def test_daily_events_empty_state
    data = [{entity_id: "sensor.timeframe_daily_event_test", state: ""}]

    api = HomeAssistantApi.new({})
    api.stub :data, data do
      assert_equal([], api.daily_events)
    end
  end

  def test_daily_events
    data = [{entity_id: "sensor.timeframe_daily_event_trash", state: "trash-can,Trash day"}]

    api = HomeAssistantApi.new({})
    travel_to DateTime.new(2023, 8, 27, 12, 0, 0, "-0600") do
      api.stub :data, data do
        events = api.daily_events
        assert_equal(1, events.length)
        assert_equal("trash-can", events.first.icon)
        assert_equal("Trash day", events.first.summary)
        assert(events.first.daily?)
      end
    end
  end

  def test_daily_events_with_underscore
    data = [{entity_id: "sensor.timeframe_daily_event_recycle", state: "recycle,recycling_day"}]

    api = HomeAssistantApi.new({})
    travel_to DateTime.new(2023, 8, 27, 12, 0, 0, "-0600") do
      api.stub :data, data do
        events = api.daily_events
        assert_equal(1, events.length)
        assert_equal("Recycling day", events.first.summary)
      end
    end
  end

  def test_daily_events_multiple_sensors
    data = [
      {entity_id: "sensor.timeframe_daily_event_trash", state: "trash-can,Trash day"},
      {entity_id: "sensor.timeframe_daily_event_recycle", state: "recycle,Recycling"}
    ]

    api = HomeAssistantApi.new({})
    travel_to DateTime.new(2023, 8, 27, 12, 0, 0, "-0600") do
      api.stub :data, data do
        events = api.daily_events
        assert_equal(2, events.length)
        assert_equal("trash-can", events[0].icon)
        assert_equal("Trash day", events[0].summary)
        assert_equal("recycle", events[1].icon)
        assert_equal("Recycling", events[1].summary)
      end
    end
  end

  def test_daily_events_multiple_values_from_one_sensor
    data = [{entity_id: "sensor.timeframe_daily_event_ages", state: "alpha-j,3y\nalpha-c,1y"}]

    api = HomeAssistantApi.new({})
    travel_to DateTime.new(2023, 8, 27, 12, 0, 0, "-0600") do
      api.stub :data, data do
        events = api.daily_events
        feed = CalendarFeed.new.events_for(Time.current.beginning_of_day, Time.current.end_of_day, events)

        assert_equal(2, events.map(&:id).uniq.length)
        assert_equal(["3y", "1y"], feed[:daily].map(&:summary))
      end
    end
  end

  def test_daily_events_invalid_format
    data = [{entity_id: "sensor.timeframe_daily_event_test", state: "just-an-icon"}]

    api = HomeAssistantApi.new({})
    travel_to DateTime.new(2023, 8, 27, 12, 0, 0, "-0600") do
      api.stub :data, data do
        events = api.daily_events
        assert_equal(1, events.length)
        assert_equal("just-an-icon", events.first.icon)
        assert_equal("", events.first.summary)
      end
    end
  end

  # --- Config ---

  def test_latitude
    api = HomeAssistantApi.new
    api.stub :config_data, {latitude: 38.4937, longitude: -98.7675} do
      assert_equal("38.4937", api.latitude)
    end
  end

  def test_longitude
    api = HomeAssistantApi.new
    api.stub :config_data, {latitude: 38.4937, longitude: -98.7675} do
      assert_equal("-98.7675", api.longitude)
    end
  end

  def test_latitude_no_data
    api = HomeAssistantApi.new
    api.stub :config_data, {} do
      assert_nil(api.latitude)
    end
  end

  def test_longitude_no_data
    api = HomeAssistantApi.new
    api.stub :config_data, {} do
      assert_nil(api.longitude)
    end
  end

  def test_fetch_config
    VCR.use_cassette(:home_assistant_config) do
      api = new_test_api
      api.fetch_config

      assert_equal("39.4937", api.latitude)
      assert_equal("-99.7675", api.longitude)
      assert_equal("America/Chicago", api.time_zone)
    end
  end

  def test_time_zone
    api = HomeAssistantApi.new
    api.stub :config_data, {time_zone: "America/Chicago"} do
      assert_equal("America/Chicago", api.time_zone)
    end
  end

  def test_time_zone_no_data
    api = HomeAssistantApi.new
    api.stub :config_data, {} do
      assert_nil(api.time_zone)
    end
  end

  def test_config_health_no_fetched_at
    api = HomeAssistantApi.new
    api.stub :config_last_fetched_at, nil do
      refute(api.config_healthy?)
    end
  end

  def test_config_health_current_fetched_at
    api = HomeAssistantApi.new
    api.stub :config_last_fetched_at, "2023-08-27 15:14:59 -0600" do
      travel_to DateTime.new(2023, 8, 27, 15, 15, 0, "-0600") do
        assert(api.config_healthy?)
      end
    end
  end

  def test_config_health_stale_fetched_at
    api = HomeAssistantApi.new
    api.stub :config_last_fetched_at, "2023-08-27 15:14:59 -0600" do
      travel_to DateTime.new(2023, 8, 27, 16, 20, 0, "-0600") do
        refute(api.config_healthy?)
      end
    end
  end

  def test_unit_system_defaults
    api = HomeAssistantApi.new
    api.stub :config_data, {} do
      assert_equal({}, api.unit_system)
      assert_equal "mph", api.ha_speed_unit
      assert_equal "F", api.ha_temperature_unit
      assert_equal "in", api.ha_precipitation_unit
    end
  end

  def test_unit_system_imperial
    api = HomeAssistantApi.new
    api.stub :config_data, {unit_system: {temperature: "°F", wind_speed: "mph", accumulated_precipitation: "in"}} do
      assert_equal "mph", api.ha_speed_unit
      assert_equal "F", api.ha_temperature_unit
      assert_equal "in", api.ha_precipitation_unit
    end
  end

  def test_unit_system_metric
    api = HomeAssistantApi.new
    api.stub :config_data, {unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "mm"}} do
      assert_equal "kph", api.ha_speed_unit
      assert_equal "C", api.ha_temperature_unit
      assert_equal "mm", api.ha_precipitation_unit
    end
  end

  def test_unit_system_cm_precipitation
    api = HomeAssistantApi.new
    api.stub :config_data, {unit_system: {accumulated_precipitation: "cm"}} do
      assert_equal "cm", api.ha_precipitation_unit
    end
  end

  # Reproducer for #91: HA unit_system.wind_speed is a frontend display
  # preference (e.g. "m/s") that does not reflect the unit a weather
  # integration actually returns. The entity's own wind_speed_unit attribute
  # is authoritative and must take precedence.
  def test_ha_speed_unit_prefers_entity_wind_speed_unit_over_unit_system
    api = HomeAssistantApi.new
    weather_entity = {entity_id: "weather.forecast_home_weather", state: "cloudy",
                      attributes: {wind_speed_unit: "km/h"}}
    api.stub :config_data, {unit_system: {wind_speed: "m/s"}} do
      api.stub :data, [weather_entity] do
        assert_equal "kph", api.ha_speed_unit
      end
    end
  end

  def test_ha_speed_unit_falls_back_to_unit_system_when_entity_missing_attribute
    api = HomeAssistantApi.new
    weather_entity = {entity_id: "weather.foo", state: "cloudy", attributes: {}}
    api.stub :config_data, {unit_system: {wind_speed: "km/h"}} do
      api.stub :data, [weather_entity] do
        assert_equal "kph", api.ha_speed_unit
      end
    end
  end

  # --- Calendars ---

  def test_fetch_calendars
    VCR.use_cassette(:home_assistant_calendar_states) do
      travel_to DateTime.new(2024, 9, 5, 15, 15, 0, "-0600") do
        api = new_test_api
        api.fetch_calendars

        assert(api.calendar_events.length > 1)
      end
    end
  end

  def test_fetch_calendars_builds_stable_id_when_uid_is_missing
    api = new_test_api
    calendar = {"entity_id" => "calendar.family"}
    event = {
      "summary" => "Dentist",
      "start" => {"dateTime" => "2024-09-05T10:00:00-06:00"},
      "end" => {"dateTime" => "2024-09-05T11:00:00-06:00"}
    }

    api.stub :fetch_calendar_list, [calendar] do
      api.stub :fetch_calendar_icons, {} do
        HTTParty.stub :get, [event] do
          api.fetch_calendars
        end
      end
    end

    fetched = api.calendar_events.first
    assert fetched.id.start_with?("calendar.family_2024-09-05T10:00:00-06:00_")
    assert_equal "calendar", fetched.icon
  end

  def test_fetch_calendars_tags_events_with_entity_id
    api = new_test_api
    calendar = {"entity_id" => "calendar.family"}
    event = {
      "summary" => "Dentist",
      "start" => {"dateTime" => "2024-09-05T10:00:00-06:00"},
      "end" => {"dateTime" => "2024-09-05T11:00:00-06:00"}
    }

    api.stub :fetch_calendar_list, [calendar] do
      api.stub :fetch_calendar_icons, {} do
        HTTParty.stub :get, [event] do
          api.fetch_calendars
        end
      end
    end

    assert_equal "calendar.family", api.calendar_events.first.entity_id
  end

  def test_calendar_events_apply_local_customizations
    account = test_user.accounts.first
    CalendarEventCustomization.delete_all
    Calendar.delete_all
    calendar = account.calendars.create!(external_id: "calendar.family", name: "Family", source_type: "home_assistant")
    calendar.event_customizations.create!(customization_key: "evt-1", icon: "cake-variant", title_override: "Birthday")

    store = ActiveSupport::Cache::MemoryStore.new
    api = HomeAssistantApi.new(TimeframeConfig.new, store: store, account: account)
    api.seed_config(DEFAULT_TEST_CONFIG)

    cal = {"entity_id" => "calendar.family"}
    customized = {"summary" => "Party", "uid" => "evt-1", "start" => {"dateTime" => "2024-09-05T10:00:00-06:00"}, "end" => {"dateTime" => "2024-09-05T11:00:00-06:00"}}
    plain = {"summary" => "Meeting", "uid" => "evt-2", "start" => {"dateTime" => "2024-09-06T10:00:00-06:00"}, "end" => {"dateTime" => "2024-09-06T11:00:00-06:00"}}

    api.stub :fetch_calendar_list, [cal] do
      api.stub :fetch_calendar_icons, {} do
        HTTParty.stub :get, [customized, plain] do
          api.fetch_calendars
        end
      end
    end

    events = api.calendar_events
    assert_equal "cake-variant", events[0].icon
    assert_equal "Birthday", events[0].summary
    assert_equal "Meeting", events[1].summary
  end

  def test_calendar_entities
    api = new_test_api

    api.stub :fetch_calendar_list, [{"entity_id" => "calendar.family", "name" => "Family"}, {"entity_id" => "calendar.work"}] do
      api.stub :fetch_calendar_icons, {"calendar.family" => "home"} do
        entities = api.calendar_entities
        assert_equal 2, entities.length
        assert_equal({entity_id: "calendar.family", name: "Family", icon: "home"}, entities.first)
        assert_equal({entity_id: "calendar.work", name: "calendar.work", icon: "calendar"}, entities.last)
      end
    end
  end

  def test_fetch_calendar_icons
    VCR.use_cassette(:home_assistant_calendar_icons) do
      api = HomeAssistantApi.new
      icons = api.fetch_calendar_icons([{"entity_id" => "calendar.birthdays"}])

      assert_equal("calendar", icons["calendar.birthdays"])
    end
  end

  def test_fetch_calendar_icons_non_200
    api = HomeAssistantApi.new
    response = Struct.new(:code).new(500)
    HTTParty.stub :get, response do
      icons = api.fetch_calendar_icons([{"entity_id" => "calendar.test"}])
      assert_equal({}, icons)
    end
  end

  def test_fetch_calendar_icons_no_icon
    api = HomeAssistantApi.new
    response = Struct.new(:code, :parsed_response).new(200, {"attributes" => {}})
    response.define_singleton_method(:dig) { |*keys| {"attributes" => {}}.dig(*keys) }
    HTTParty.stub :get, response do
      icons = api.fetch_calendar_icons([{"entity_id" => "calendar.test"}])
      assert_equal({}, icons)
    end
  end

  def test_fetch_calendar_icons_invalid_icon
    api = HomeAssistantApi.new
    response = Struct.new(:code, :parsed_response).new(200, {"attributes" => {"icon" => "mdi:nonexistent-icon-xyz"}})
    response.define_singleton_method(:dig) { |*keys| {"attributes" => {"icon" => "mdi:nonexistent-icon-xyz"}}.dig(*keys) }
    HTTParty.stub :get, response do
      icons = api.fetch_calendar_icons([{"entity_id" => "calendar.test"}])
      assert_equal({}, icons)
    end
  end

  def test_fetch_calendar_list_non_200
    api = HomeAssistantApi.new
    response = Struct.new(:code, :parsed_response).new(500, nil)
    HTTParty.stub :get, response do
      assert_equal([], api.fetch_calendar_list)
    end
  end

  def test_calendars_healthy_no_fetched_at
    api = HomeAssistantApi.new
    api.stub :calendars_last_fetched_at, nil do
      refute(api.calendars_healthy?)
    end
  end

  def test_calendars_healthy_current_fetched_at
    api = HomeAssistantApi.new
    api.stub :calendars_last_fetched_at, DateTime.now do
      assert(api.calendars_healthy?)
    end
  end

  # --- Weather ---

  def test_fetch_weather
    VCR.use_cassette(:home_assistant_weather) do
      api = new_test_api
      api.seed_states([{entity_id: "weather.forecast_home", state: "sunny", attributes: {attribution: "Powered by WeatherFlow https://weatherflow.com"}}])
      api.fetch_weather

      assert api.weather_healthy?
      assert api.hourly_forecast.length > 0
      assert api.daily_forecast.length > 0
      assert_equal "Powered by WeatherFlow", api.attribution
    end
  end

  def test_hourly_forecast_returns_empty_when_no_data
    api = new_test_api
    assert_equal [], api.hourly_forecast
  end

  def test_daily_forecast_returns_empty_when_no_data
    api = new_test_api
    assert_equal [], api.daily_forecast
  end

  def test_hourly_calendar_events_returns_empty_when_no_data
    api = new_test_api
    assert_equal [], api.hourly_calendar_events
  end

  def test_hourly_calendar_events
    VCR.use_cassette(:home_assistant_weather) do
      api = new_test_api
      api.seed_states([{entity_id: "weather.honeysuckle_weather", state: "sunny", attributes: {}}])
      api.fetch_weather

      events = api.hourly_calendar_events
      assert events.is_a?(Array)
    end
  end

  def test_icon_for
    api = HomeAssistantApi.new
    assert_equal "cloud", api.icon_for("cloudy")
    assert_equal "weather-sunny", api.icon_for("sunny")
    assert_equal "water", api.icon_for("rainy")
    assert_equal "snowflake", api.icon_for("snowy")
    assert_equal "help-circle", api.icon_for("unknown-condition")
  end

  def test_hourly_calendar_events_with_data
    travel_to DateTime.new(2023, 8, 27, 12, 0, 0, "-0600") do
      today = Date.new(2023, 8, 27)
      noon_utc = today.in_time_zone("America/Chicago").noon.utc.iso8601

      api = HomeAssistantApi.new
      api.stub :hourly_forecast, [{datetime: noon_utc, condition: "sunny", temperature: 85}] do
        events = api.hourly_calendar_events
        assert events.length > 0
        assert_equal "85°", events.first.summary
        assert_equal "weather-sunny", events.first.icon
      end
    end
  end

  def test_hourly_calendar_events_with_offset_format
    travel_to DateTime.new(2023, 8, 27, 12, 0, 0, "-0600") do
      today = Date.new(2023, 8, 27)
      noon_utc = today.in_time_zone("America/Chicago").noon.utc
      offset_str = noon_utc.strftime("%Y-%m-%dT%H:%M:%S+00:00")

      api = HomeAssistantApi.new
      api.stub :hourly_forecast, [{datetime: offset_str, condition: "partlycloudy", temperature: 72}] do
        events = api.hourly_calendar_events
        assert events.length > 0
        assert_equal "72°", events.first.summary
        assert_equal "weather-partly-cloudy", events.first.icon
      end
    end
  end

  def test_daily_calendar_events_returns_empty_when_no_data
    api = new_test_api
    assert_equal [], api.daily_calendar_events
  end

  def test_daily_calendar_events_with_data
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "sunny", temperature: 90, templow: 65}
    ] do
      events = api.daily_calendar_events
      assert_equal 1, events.length
      assert_equal "90° / 65°", events.first.summary
      assert_equal "weather-sunny", events.first.icon
    end
  end

  def test_daily_calendar_events_with_rain_precip
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "rainy", temperature: 65, templow: 50, precipitation: 5.0}
    ] do
      events = api.daily_calendar_events
      assert_equal 1, events.length
      assert_equal 1, events.first.precip.length
      # rainy maps to water which matches the precip icon, so it should be suppressed
      assert_nil events.first.precip.first[:icon]
      assert_includes events.first.precip.first[:label], "\""
    end
  end

  def test_daily_calendar_events_with_snow_precip
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "snowy", temperature: 30, templow: 20, precipitation: 10.0}
    ] do
      events = api.daily_calendar_events
      assert_equal 1, events.length
      assert_equal 1, events.first.precip.length
      assert_includes events.first.precip.first[:label], "\""
    end
  end

  def test_daily_calendar_events_with_snow_precip_metric
    config = TimeframeConfig.new(precipitation_unit: "mm")
    api = HomeAssistantApi.new(config)
    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "snowy", temperature: -1, templow: -5, precipitation: 10.0}
    ] do
      events = api.daily_calendar_events
      assert_equal 1, events.length
      assert_equal 1, events.first.precip.length
      assert_includes events.first.precip.first[:label], "cm"
    end
  end

  def test_daily_calendar_events_with_rain_precip_metric
    config = TimeframeConfig.new(precipitation_unit: "mm")
    api = HomeAssistantApi.new(config)
    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "cloudy", temperature: 10, templow: 5, precipitation: 10.0}
    ] do
      events = api.daily_calendar_events
      assert_equal 1, events.first.precip.length
      assert_equal "water", events.first.precip.first[:icon]
      assert_includes events.first.precip.first[:label], "mm"
    end
  end

  def test_daily_calendar_events_no_precip_when_zero
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "sunny", temperature: 90, templow: 65, precipitation: 0.0}
    ] do
      events = api.daily_calendar_events
      assert_equal 1, events.length
      assert_nil events.first.precip
    end
  end

  def test_daily_calendar_events_no_precip_when_rounds_to_zero
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "rainy", temperature: 65, templow: 50, precipitation: 0.01}
    ] do
      events = api.daily_calendar_events
      assert_equal 1, events.length
      assert_nil events.first.precip
    end
  end

  def test_daily_calendar_events_with_wind_gust_above_threshold
    tomorrow = 1.day.from_now.utc.beginning_of_day
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: tomorrow.iso8601, condition: "sunny", temperature: 75, templow: 55}
    ] do
      api.stub :hourly_forecast, [
        {datetime: tomorrow.iso8601, wind_gust_speed: 25},
        {datetime: (tomorrow + 6.hours).iso8601, wind_gust_speed: 35}
      ] do
        events = api.daily_calendar_events
        assert_equal 1, events.length
        assert_equal "35mph", events.first.wind_gust
      end
    end
  end

  def test_daily_calendar_events_keeps_highest_wind_gust
    tomorrow = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 20)
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: tomorrow.iso8601, condition: "sunny", temperature: 75, templow: 55}
    ] do
      api.stub :hourly_forecast, [
        {datetime: (tomorrow + 10.hours).iso8601, wind_gust_speed: 35},
        {datetime: (tomorrow + 12.hours).iso8601, wind_gust_speed: 25}
      ] do
        events = api.daily_calendar_events
        assert_equal "35mph", events.first.wind_gust
      end
    end
  end

  def test_daily_calendar_events_no_wind_gust_below_threshold
    tomorrow = 1.day.from_now.utc.beginning_of_day
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: tomorrow.iso8601, condition: "sunny", temperature: 75, templow: 55}
    ] do
      api.stub :hourly_forecast, [
        {datetime: tomorrow.iso8601, wind_gust_speed: 15}
      ] do
        events = api.daily_calendar_events
        assert_equal 1, events.length
        assert_nil events.first.wind_gust
      end
    end
  end

  def test_precip_calendar_events_returns_empty_when_no_data
    api = HomeAssistantApi.new
    assert_equal [], api.precip_calendar_events
  end

  def test_precip_calendar_events_with_rain
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 80, precipitation: 2.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Rain 2.0\" 80%", events.first.summary
      assert_equal "weather-rainy", events.first.icon
    end
  end

  def test_precip_calendar_events_with_snow
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "snowy", precipitation_probability: 80, precipitation: 2.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Snow 2.0\" 80%", events.first.summary
      assert_equal "snowflake", events.first.icon
    end
  end

  def test_precip_calendar_events_merges_consecutive_hours
    hour1 = (Time.now + 1.hour).utc.beginning_of_hour
    hour2 = hour1 + 1.hour

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: hour1.iso8601, condition: "rainy", precipitation_probability: 80, precipitation: 2.0},
      {datetime: hour2.iso8601, condition: "rainy", precipitation_probability: 70, precipitation: 1.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
    end
  end

  def test_precip_skips_low_probability
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 9, precipitation: 1.0}
    ] do
      assert_equal [], api.precip_calendar_events
    end
  end

  def test_precip_skips_zero_precip_moderate_probability
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 30, precipitation: 0.0}
    ] do
      assert_equal [], api.precip_calendar_events
    end
  end

  def test_precip_skips_past_hours
    past_time = (Time.now - 2.hours).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: past_time, condition: "rainy", precipitation_probability: 80, precipitation: 2.0}
    ] do
      assert_equal [], api.precip_calendar_events
    end
  end

  def test_precip_calendar_events_zero_amount_high_probability
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 80, precipitation: 0.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 0, events.length
    end
  end

  def test_precip_calendar_events_without_probability
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation: 2.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Rain 2.0\"", events.first.summary
    end
  end

  def test_precip_calendar_events_without_probability_skips_zero_precip
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "sunny", precipitation: 0.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 0, events.length
    end
  end

  def test_precip_small_amount
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 80, precipitation: 0.05}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Rain 0.1\" 80%", events.first.summary
    end
  end

  def test_precip_rain_converts_in_to_mm
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(precipitation_unit: "mm")
    api = HomeAssistantApi.new(config)
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 80, precipitation: 1.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Rain 25.4mm 80%", events.first.summary
    end
  end

  def test_precip_snow_converts_in_to_cm
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(precipitation_unit: "mm")
    api = HomeAssistantApi.new(config)
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "snowy", precipitation_probability: 80, precipitation: 1.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Snow 2.5cm 80%", events.first.summary
    end
  end

  def test_precip_rain_from_mm_ha
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(precipitation_unit: "mm")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 80, precipitation: 25.4}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Rain 25.4mm 80%", events.first.summary
    end
  end

  def test_precip_snow_from_mm_ha
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(precipitation_unit: "mm")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "snowy", precipitation_probability: 80, precipitation: 50.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Snow 5.0cm 80%", events.first.summary
    end
  end

  def test_precip_snow_from_cm_ha
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(precipitation_unit: "mm")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "cm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "snowy", precipitation_probability: 80, precipitation: 5.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Snow 5.0cm 80%", events.first.summary
    end
  end

  def test_precip_rain_from_cm_ha
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(precipitation_unit: "mm")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "cm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 80, precipitation: 5.0}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Rain 50.0mm 80%", events.first.summary
    end
  end

  def test_precip_in_mode_with_mm_ha
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = new_test_api
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "rainy", precipitation_probability: 80, precipitation: 25.4}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Rain 1.0\" 80%", events.first.summary
    end
  end

  def test_precip_in_mode_snow_with_cm_ha
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = new_test_api
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "cm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, condition: "snowy", precipitation_probability: 80, precipitation: 2.54}
    ] do
      events = api.precip_calendar_events
      assert_equal 1, events.length
      assert_equal "Snow 1.0\" 80%", events.first.summary
    end
  end

  def test_convert_precipitation_unknown_unit_passthrough
    api = HomeAssistantApi.new
    api.stub :ha_precipitation_unit, "liters" do
      assert_equal 5.0, api.convert_precipitation(5.0, "gallons")
    end
  end

  def test_wind_calendar_events_returns_empty_when_no_data
    api = HomeAssistantApi.new
    assert_equal [], api.wind_calendar_events
  end

  def test_wind_calendar_events_with_high_wind
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 40.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      assert_includes events.first.summary, "mph"
      assert_equal "arrow-up", events.first.icon
    end
  end

  def test_wind_calendar_events_skips_low_wind
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 10.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 0, events.length
    end
  end

  def test_wind_calendar_events_skips_past_hours
    past_time = (Time.now - 2.hours).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: past_time, wind_gust_speed: 40.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 0, events.length
    end
  end

  def test_wind_calendar_events_merges_consecutive_hours
    hour1 = (Time.now + 1.hour).utc.beginning_of_hour
    hour2 = hour1 + 1.hour

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: hour1.iso8601, wind_gust_speed: 40.0, wind_bearing: 180},
      {datetime: hour2.iso8601, wind_gust_speed: 50.0, wind_bearing: 90}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      assert_includes events.first.summary, "50"
    end
  end

  def test_wind_calendar_events_with_kph_unit
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "kph")
    api = HomeAssistantApi.new(config)
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 40.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      assert_includes events.first.summary, "kph"
    end
  end

  def test_wind_calendar_events_kph_threshold
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "kph")
    api = HomeAssistantApi.new(config)
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 15.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 0, events.length
    end
  end

  def test_wind_calendar_events_respects_configured_threshold_mph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "mph")
    # 30 mph gust, threshold 35 mph -> no event
    api = HomeAssistantApi.new(config, wind_gust_threshold_mph: 35.0)
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 30.0, wind_bearing: 180}
    ] do
      assert_empty api.wind_calendar_events
    end

    # Same gust, threshold 25 mph -> one event
    api_low = HomeAssistantApi.new(config, wind_gust_threshold_mph: 25.0)
    api_low.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 30.0, wind_bearing: 180}
    ] do
      assert_equal 1, api_low.wind_calendar_events.length
    end
  end

  def test_wind_threshold_in_kph_converts_from_mph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "kph")
    # 20 mph threshold -> ~32.19 kph. 35 kph gust crosses it.
    api = HomeAssistantApi.new(config, wind_gust_threshold_mph: 20.0)
    api.stub :ha_speed_unit, "kph" do
      api.stub :hourly_forecast, [
        {datetime: future_time, wind_gust_speed: 35.0, wind_bearing: 180}
      ] do
        assert_equal 1, api.wind_calendar_events.length
      end
    end

    api_high = HomeAssistantApi.new(config, wind_gust_threshold_mph: 25.0)
    api_high.stub :ha_speed_unit, "kph" do
      api_high.stub :hourly_forecast, [
        {datetime: future_time, wind_gust_speed: 35.0, wind_bearing: 180}
      ] do
        assert_empty api_high.wind_calendar_events
      end
    end
  end

  def test_wind_skips_past_hours
    past_time = (Time.now - 2.hours).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: past_time, wind_speed: 50.0, wind_bearing: 180}
    ] do
      assert_equal [], api.wind_calendar_events
    end
  end

  def test_wind_calendar_events_with_wind_speed_fallback
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_speed: 40.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      assert_includes events.first.summary, "40mph"
      assert_equal "arrow-up", events.first.icon
    end
  end

  def test_wind_calendar_events_wind_speed_fallback_below_threshold
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    api = HomeAssistantApi.new
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_speed: 10.0, wind_bearing: 180}
    ] do
      assert_equal [], api.wind_calendar_events
    end
  end

  def test_convert_speed_mph_to_kph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "kph")
    api = HomeAssistantApi.new(config)
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 25.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      assert_includes events.first.summary, "40kph"
    end
  end

  def test_convert_speed_kph_to_mph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "mph")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 50.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      assert_includes events.first.summary, "31mph"
    end
  end

  def test_convert_speed_ms_to_kph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "kph")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "m/s", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 15.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      assert_includes events.first.summary, "54kph"
    end
  end

  def test_convert_speed_ms_to_mph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "mph")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "m/s", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 15.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      assert_includes events.first.summary, "34mph"
    end
  end

  def test_ha_speed_unit_ms
    api = HomeAssistantApi.new
    api.stub :config_data, {unit_system: {wind_speed: "m/s"}} do
      assert_equal "m/s", api.ha_speed_unit
    end
  end

  def test_convert_speed_no_double_conversion_kph_to_kph
    config = TimeframeConfig.new(speed_unit: "kph")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "mm"})
    assert_equal 25.0, api.convert_speed(25.0)
  end

  def test_ha_speed_unit_knots
    api = HomeAssistantApi.new
    api.stub :config_data, {unit_system: {wind_speed: "kn"}} do
      assert_equal "kn", api.ha_speed_unit
    end
  end

  def test_ha_speed_unit_ft_s
    api = HomeAssistantApi.new
    api.stub :config_data, {unit_system: {wind_speed: "ft/s"}} do
      assert_equal "ft/s", api.ha_speed_unit
    end
  end

  def test_ha_speed_unit_mi_h
    api = HomeAssistantApi.new
    api.stub :config_data, {unit_system: {wind_speed: "mi/h"}} do
      assert_equal "mph", api.ha_speed_unit
    end
  end

  def test_ha_speed_unit_beaufort
    api = HomeAssistantApi.new
    api.stub :config_data, {unit_system: {wind_speed: "Beaufort"}} do
      assert_equal "Beaufort", api.ha_speed_unit
    end
  end

  def test_convert_speed_knots_to_mph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "mph")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "kn", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 25.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      # 25 kn * 1.15078 = 28.77 mph
      assert_includes events.first.summary, "29mph"
    end
  end

  def test_convert_speed_ft_s_to_kph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "kph")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "ft/s", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 50.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      # 50 ft/s * 0.681818 = 34.09 mph / 0.621371 = 54.87 kph
      assert_includes events.first.summary, "55kph"
    end
  end

  def test_convert_speed_beaufort_to_mph
    future_time = (Time.now + 1.hour).utc.beginning_of_hour.iso8601

    config = TimeframeConfig.new(speed_unit: "mph")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "Beaufort", accumulated_precipitation: "mm"})
    api.stub :hourly_forecast, [
      {datetime: future_time, wind_gust_speed: 7.0, wind_bearing: 180}
    ] do
      events = api.wind_calendar_events
      assert_equal 1, events.length
      # Beaufort 7: 0.836 * 7^1.5 = 15.48 m/s * 2.23694 = 34.63 mph
      assert_includes events.first.summary, "35mph"
    end
  end

  def test_convert_temperature_same_unit
    api = HomeAssistantApi.new
    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "sunny", temperature: 90, templow: 65}
    ] do
      events = api.daily_calendar_events
      assert_equal "90° / 65°", events.first.summary
    end
  end

  def test_convert_temperature_f_to_c
    config = TimeframeConfig.new(temperature_unit: "C")
    api = HomeAssistantApi.new(config)

    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "sunny", temperature: 90, templow: 68}
    ] do
      events = api.daily_calendar_events
      assert_equal "32° / 20°", events.first.summary
    end
  end

  def test_convert_temperature_c_to_f
    config = TimeframeConfig.new(temperature_unit: "F")
    api = new_test_api(config)
    api.seed_config(time_zone: "America/Chicago", unit_system: {temperature: "°C", wind_speed: "km/h", accumulated_precipitation: "mm"})

    api.stub :daily_forecast, [
      {datetime: "2023-08-27T06:00:00Z", condition: "sunny", temperature: 32, templow: 20}
    ] do
      events = api.daily_calendar_events
      assert_equal "90° / 68°", events.first.summary
    end
  end

  def test_fetch_forecast_handles_network_error
    VCR.use_cassette(:home_assistant_weather) do
      api = HomeAssistantApi.new
      HTTParty.stub :post, ->(*) { raise Errno::ECONNREFUSED } do
        result = api.send(:fetch_forecast, "weather.test", "hourly")
        assert_nil result
      end
    end
  end

  def test_fetch_forecast_non_200
    api = HomeAssistantApi.new
    response = Struct.new(:code).new(500)
    HTTParty.stub :post, response do
      result = api.send(:fetch_forecast, "weather.test", "hourly")
      assert_nil result
    end
  end

  def test_fetch_weather_no_entity
    api = HomeAssistantApi.new
    api.stub :weather_entity_id, nil do
      assert_nil api.fetch_weather
    end
  end

  def test_fetch_weather_no_forecast_data
    api = HomeAssistantApi.new
    api.stub :weather_entity_id, "weather.test" do
      api.stub :data, [] do
        api.stub :fetch_forecast, nil do
          assert_nil api.fetch_weather
        end
      end
    end
  end

  def test_fetch_weather_entity_not_found_in_data
    api = new_test_api
    api.seed_weather({entity_id: "weather.nonexistent", hourly: [{}], daily: [{}], attribution: nil})
    assert api.weather_data.present?
    assert_nil api.weather_data[:attribution]
  end

  def test_fetch_weather_entity_not_in_states
    api = new_test_api
    api.stub :weather_entity_id, "weather.nonexistent" do
      api.stub :data, [] do
        api.stub :fetch_forecast, [{}] do
          api.fetch_weather
          assert api.weather_data.present?
          assert_nil api.weather_data[:attribution]
        end
      end
    end
  end

  def test_attribution_nil
    api = HomeAssistantApi.new
    api.stub :weather_data, {} do
      assert_nil api.attribution
    end
  end
end
