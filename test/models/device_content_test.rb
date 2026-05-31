# frozen_string_literal: true

require "test_helper"

class DeviceContenttTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def test_no_data
    travel_to DateTime.new(2023, 8, 27, 18, 15, 0, "-0600") do
      result = DeviceContent.new.call(home_assistant_api: new_test_api)

      assert_nil(result[:current_temperature])
      assert_equal(result[:day_groups].count, 5)
    end
  end

  def test_hide_events_after_cutoff
    travel_to DateTime.new(2023, 8, 27, 20, 15, 0, "-0600") do
      result = DeviceContent.new.call(home_assistant_api: new_test_api)

      assert_equal(result[:day_groups].count, 4)
    end
  end

  def test_hide_events_after_cutoff_if_periodic_extends_to_tomorrow
    travel_time = DateTime.new(2023, 8, 27, 20, 15, 0, "-0600")
    travel_to travel_time do
      api = new_test_api
      api.stub :calendars_healthy?, false do
        api.stub :calendar_events, [
          DeviceEvent.new(starts_at: travel_time - 1.hour, ends_at: travel_time + 1.day, summary: "test")
        ] do
          api.stub :private_mode?, false do
            result = DeviceContent.new.call(home_assistant_api: api)

            assert_equal(result[:day_groups].count, 4)
          end
        end
      end
    end
  end

  def test_with_healthy_home_assistant
    travel_to DateTime.new(2023, 8, 27, 18, 15, 0, "-0600") do
      ha_api = new_test_api
      ha_api.stub :states_healthy?, true do
        ha_api.stub :feels_like_temperature, "72°" do
          ha_api.stub :now_playing, {} do
            ha_api.stub :top_right, [] do
              ha_api.stub :top_left, [] do
                ha_api.stub :weather_status, [] do
                  ha_api.stub :daily_events, [] do
                    result = DeviceContent.new.call(home_assistant_api: ha_api)

                    assert_equal("72°", result[:current_temperature])
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def test_with_private_mode
    travel_to DateTime.new(2023, 8, 27, 18, 15, 0, "-0600") do
      api = new_test_api
      api.stub :calendars_healthy?, true do
        api.stub :private_mode?, true do
          api.stub :calendar_events, [] do
            result = DeviceContent.new.call(home_assistant_api: api)

            assert result[:top_left].any? { it[:label] == "Private mode" }
          end
        end
      end
    end
  end

  def test_with_healthy_weather_api
    travel_to DateTime.new(2023, 8, 27, 18, 15, 0, "-0600") do
      api = new_test_api
      api.stub :weather_healthy?, true do
        result = DeviceContent.new.call(home_assistant_api: api)

        assert_equal 5, result[:day_groups].count
      end
    end
  end

  def test_today_not_hidden_when_periodic_events_exist
    travel_to DateTime.new(2023, 8, 27, 20, 15, 0, "-0600") do
      api = new_test_api
      events = [
        DeviceEvent.new(
          starts_at: DateTime.new(2023, 8, 27, 19, 0, 0, "-0600"),
          ends_at: DateTime.new(2023, 8, 27, 21, 0, 0, "-0600"),
          summary: "Evening event"
        )
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, events do
            result = DeviceContent.new.call(home_assistant_api: api)

            assert_equal 5, result[:day_groups].count
          end
        end
      end
    end
  end

  def test_serializes_events_with_icons_and_locations
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      events = [
        DeviceEvent.new(
          starts_at: DateTime.new(2023, 8, 27, 0, 0, 0, "-0600"),
          ends_at: DateTime.new(2023, 8, 28, 0, 0, 0, "-0600"),
          summary: "All Day",
          icon: "cake-variant",
          daily: true,
          timezone: tz
        ),
        DeviceEvent.new(
          starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"),
          ends_at: DateTime.new(2023, 8, 27, 13, 0, 0, "-0600"),
          summary: "Lunch",
          icon: "alpha-j",
          location: "Room A",
          timezone: tz
        )
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, events do
            result = DeviceContent.new.call(home_assistant_api: api)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            assert today[:daily].any? { |e| e[:summary] == "All Day" && e[:icon_class] == "cake-variant" }
            assert today[:periodic].any? { |e| e[:summary] == "Lunch" && e[:icon_text] == "J" && e[:location] == "Room A" }
          end
        end
      end
    end
  end

  def test_use_day_names_option
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      result = DeviceContent.new.call(home_assistant_api: new_test_api, use_day_names: true)

      assert_equal "Sunday", result[:day_groups][0][:day_name]
      assert_equal "Monday", result[:day_groups][1][:day_name]
    end
  end

  def test_weather_row_extracts_hourly_weather
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "65°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "72°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "74°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_4", starts_at: DateTime.new(2023, 8, 27, 20, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 20, 0, 0, "-0600"), summary: "60°", icon: "weather-night", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            assert_equal 3, today[:weather_row].length
            assert today[:weather_row].any? { |w| w[:summary] == "65°" }
            assert today[:weather_row].any? { |w| w[:summary] == "72°" }
            assert today[:weather_row].any? { |w| w[:summary] == "74°" }
            assert today[:periodic].none? { |e| e[:summary] == "65°" }
          end
        end
      end
    end
  end

  def test_include_daily_weather_false_skips_daily_weather
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      api.stub :weather_healthy?, true do
        result = DeviceContent.new.call(home_assistant_api: api, include_daily_weather: false)

        assert_equal 5, result[:day_groups].count
      end
    end
  end

  def test_include_temperature_false_excludes_hourly_weather_but_keeps_daily_weather
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      current_time = ActiveSupport::TimeZone[tz].local(2023, 8, 27, 8)
      hourly_event = DeviceEvent.new(
        id: "_ha_weather_hour_#{current_time.change(hour: 12).to_i}",
        starts_at: current_time.change(hour: 12),
        ends_at: current_time.change(hour: 12),
        summary: "72°",
        icon: "weather-sunny",
        timezone: tz
      )
      daily_event = DeviceEvent.new(
        id: "_ha_weather_day_#{current_time.beginning_of_day.to_i}",
        starts_at: current_time.beginning_of_day,
        ends_at: current_time.tomorrow.beginning_of_day,
        summary: "80° / 60°",
        icon: "weather-sunny",
        timezone: tz
      )

      api.stub :weather_healthy?, true do
        api.stub :hourly_calendar_events, [hourly_event] do
          api.stub :daily_calendar_events, [daily_event] do
            result = DeviceContent.new.call(
              home_assistant_api: api,
              current_time: current_time,
              days: 1,
              always_show_today: true,
              include_temperature: false
            )

            today = result[:day_groups].first
            assert today[:daily].any? { |event| event[:summary] == "80° / 60°" }
            assert today[:periodic].none? { |event| event[:summary] == "72°" }
          end
        end
      end
    end
  end

  def test_start_time_only_flag
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      result = DeviceContent.new.call(home_assistant_api: new_test_api, start_time_only: true)

      assert result[:start_time_only]
    end
  end

  def test_include_precip_false_excludes_precip_events
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      tomorrow = DateTime.new(2023, 8, 28, 14, 0, 0, "-0600")
      api.stub :weather_healthy?, true do
        api.stub :precip_calendar_events, [
          DeviceEvent.new(
            id: "#{tomorrow.to_i}_ha_precip",
            starts_at: tomorrow,
            ends_at: tomorrow + 2.hours,
            summary: "Rain 0.5\"",
            icon: "weather-rainy"
          )
        ] do
          result = DeviceContent.new.call(home_assistant_api: api, include_precip: false)
          all_periodic = result[:day_groups].flat_map { |d| d[:periodic] }
          assert all_periodic.none? { |e| e[:summary]&.include?("Rain") }
        end
      end
    end
  end

  def test_include_precip_true_includes_precip_events
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      tomorrow = DateTime.new(2023, 8, 28, 14, 0, 0, "-0600")
      api.stub :weather_healthy?, true do
        api.stub :precip_calendar_events, [
          DeviceEvent.new(
            id: "#{tomorrow.to_i}_ha_precip",
            starts_at: tomorrow,
            ends_at: tomorrow + 2.hours,
            summary: "Rain 0.5\"",
            icon: "weather-rainy"
          )
        ] do
          result = DeviceContent.new.call(home_assistant_api: api, include_precip: true)
          all_periodic = result[:day_groups].flat_map { |d| d[:periodic] }
          assert all_periodic.any? { |e| e[:summary]&.include?("Rain") }
        end
      end
    end
  end

  def test_include_wind_false_excludes_wind_events
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      tomorrow = DateTime.new(2023, 8, 28, 14, 0, 0, "-0600")
      api.stub :weather_healthy?, true do
        api.stub :wind_calendar_events, [
          DeviceEvent.new(
            id: "#{tomorrow.to_i}_ha_wind",
            starts_at: tomorrow,
            ends_at: tomorrow + 2.hours,
            summary: "Gusts up to 35mph",
            icon: "arrow-up"
          )
        ] do
          result = DeviceContent.new.call(home_assistant_api: api, include_wind: false)
          all_periodic = result[:day_groups].flat_map { |d| d[:periodic] }
          assert all_periodic.none? { |e| e[:summary]&.include?("Gusts") }
        end
      end
    end
  end

  def test_include_wind_true_includes_wind_events
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      tomorrow = DateTime.new(2023, 8, 28, 14, 0, 0, "-0600")
      api.stub :weather_healthy?, true do
        api.stub :wind_calendar_events, [
          DeviceEvent.new(
            id: "#{tomorrow.to_i}_ha_wind",
            starts_at: tomorrow,
            ends_at: tomorrow + 2.hours,
            summary: "Gusts up to 35mph",
            icon: "arrow-up"
          )
        ] do
          result = DeviceContent.new.call(home_assistant_api: api, include_wind: true)
          all_periodic = result[:day_groups].flat_map { |d| d[:periodic] }
          assert all_periodic.any? { |e| e[:summary]&.include?("Gusts") }
        end
      end
    end
  end

  def test_clothing_forecast_works_when_periodic_weather_events_are_hidden
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      current_time = ActiveSupport::TimeZone[tz].local(2023, 8, 27, 7)
      hourly_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: current_time.change(hour: 8), ends_at: current_time.change(hour: 8), summary: "72°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: current_time.change(hour: 12), ends_at: current_time.change(hour: 12), summary: "85°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: current_time.change(hour: 16), ends_at: current_time.change(hour: 16), summary: "80°", icon: "weather-sunny", timezone: tz)
      ]
      precip_event = DeviceEvent.new(
        id: "#{current_time.change(hour: 14).to_i}_ha_precip",
        starts_at: current_time.change(hour: 14),
        ends_at: current_time.change(hour: 16),
        summary: "Rain 0.5\"",
        icon: "weather-rainy",
        timezone: tz
      )
      wind_event = DeviceEvent.new(
        id: "#{current_time.change(hour: 15).to_i}_ha_wind",
        starts_at: current_time.change(hour: 15),
        ends_at: current_time.change(hour: 17),
        summary: "Gusts up to 35mph",
        icon: "arrow-up",
        timezone: tz
      )

      api.stub :weather_healthy?, true do
        api.stub :hourly_calendar_events, hourly_events do
          api.stub :daily_calendar_events, [] do
            api.stub :precip_calendar_events, [precip_event] do
              api.stub :wind_calendar_events, [wind_event] do
                result = DeviceContent.new.call(
                  home_assistant_api: api,
                  current_time: current_time,
                  days: 1,
                  weather_row: true,
                  clothing_forecast: true,
                  always_show_today: true,
                  include_precip: false,
                  include_wind: false
                )

                today = result[:day_groups].first
                assert_equal "Shorts", today[:clothing][:summary]
                assert today[:weather_row].any?
                assert today[:periodic].none? { |e| e[:summary]&.include?("Rain") || e[:summary]&.include?("Gusts") }
              end
            end
          end
        end
      end
    end
  end

  def test_clothing_forecast_shorts_when_warm
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "72°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "85°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "80°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_day_1", starts_at: DateTime.new(2023, 8, 27, 0, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 28, 0, 0, 0, "-0600"), summary: "85° / 65°", icon: "weather-sunny", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true, clothing_forecast: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            assert_equal "Shorts", today[:clothing][:summary]
            assert_equal "shorts", today[:clothing][:icon]
            assert_equal "T-shirt", today[:clothing][:shirt_summary]
            assert_equal "tshirt", today[:clothing][:shirt_icon]
          end
        end
      end
    end
  end

  def test_clothing_forecast_pants_with_short_sleeves_when_noon_above_shirt_threshold
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "45°", icon: "weather-cloudy", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "51°", icon: "weather-cloudy", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "50°", icon: "weather-cloudy", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true, clothing_forecast: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            assert_equal "Pants", today[:clothing][:summary]
            assert_equal "pants", today[:clothing][:icon]
            assert_equal "T-shirt", today[:clothing][:shirt_summary]
            assert_equal "tshirt", today[:clothing][:shirt_icon]
          end
        end
      end
    end
  end

  def test_clothing_forecast_pants_with_long_sleeves_at_shirt_threshold
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "45°", icon: "weather-cloudy", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "50°", icon: "weather-cloudy", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "50°", icon: "weather-cloudy", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true, clothing_forecast: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            assert_equal "Pants", today[:clothing][:summary]
            assert_equal "pants", today[:clothing][:icon]
            assert_equal "Long sleeves", today[:clothing][:shirt_summary]
            assert_equal "long-sleeve-shirt", today[:clothing][:shirt_icon]
          end
        end
      end
    end
  end

  def test_clothing_forecast_uses_morning_temp_when_noon_missing
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "72°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "80°", icon: "weather-sunny", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true, clothing_forecast: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            # noon missing, so noon_temp falls back to morning_temp (72), which >= 65, so shorts
            assert_equal "Shorts", today[:clothing][:summary]
          end
        end
      end
    end
  end

  def test_clothing_forecast_pants_when_daily_high_below_threshold
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "66°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "68°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "62°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_day_1", starts_at: DateTime.new(2023, 8, 27, 0, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 28, 0, 0, 0, "-0600"), summary: "62° / 45°", icon: "weather-sunny", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true, clothing_forecast: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            # Hourly temps say shorts, but daily high (62) < 65 threshold, so pants
            assert_equal "Pants", today[:clothing][:summary]
            assert_equal "pants", today[:clothing][:icon]
            assert_equal "T-shirt", today[:clothing][:shirt_summary]
            assert_equal "tshirt", today[:clothing][:shirt_icon]
          end
        end
      end
    end
  end

  def test_clothing_forecast_celsius
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api(TimeframeConfig.new(temperature_unit: "C"))
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "20°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "25°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "22°", icon: "weather-sunny", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true, clothing_forecast: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            assert_equal "Shorts", today[:clothing][:summary]
            assert_equal "tshirt", today[:clothing][:shirt_icon]
          end
        end
      end
    end
  end

  def test_clothing_forecast_celsius_pants_with_short_sleeves_above_threshold
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api(TimeframeConfig.new(temperature_unit: "C"))
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "9°", icon: "weather-cloudy", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "11°", icon: "weather-cloudy", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "12°", icon: "weather-cloudy", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true, clothing_forecast: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            assert_equal "Pants", today[:clothing][:summary]
            assert_equal "pants", today[:clothing][:icon]
            assert_equal "T-shirt", today[:clothing][:shirt_summary]
            assert_equal "tshirt", today[:clothing][:shirt_icon]
          end
        end
      end
    end
  end

  def test_clothing_forecast_nil_when_disabled
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      weather_events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "72°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_2", starts_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "85°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "_ha_weather_hour_3", starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), summary: "80°", icon: "weather-sunny", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, weather_events do
            result = DeviceContent.new.call(home_assistant_api: api, weather_row: true, clothing_forecast: false, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            assert_nil today[:clothing]
          end
        end
      end
    end
  end

  def test_auto_icons_assigns_icon_to_matching_events
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      events = [
        DeviceEvent.new(id: "1", starts_at: DateTime.new(2023, 8, 27, 9, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 10, 0, 0, "-0600"), summary: "Church service", icon: "calendar", timezone: tz),
        DeviceEvent.new(id: "2", starts_at: DateTime.new(2023, 8, 27, 11, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "Xyzzy gibberish", icon: "calendar", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, events do
            result = DeviceContent.new.call(home_assistant_api: api, auto_icons: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            church_event = today[:periodic].find { |e| e[:summary] == "Church service" }
            assert_equal "church", church_event[:icon_class]

            no_match_event = today[:periodic].find { |e| e[:summary] == "Xyzzy gibberish" }
            assert_equal "calendar", no_match_event[:icon_class], "Non-matching event should keep original icon"
          end
        end
      end
    end
  end

  def test_auto_icons_skips_weather_events
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      events = [
        DeviceEvent.new(id: "_ha_weather_hour_1", starts_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 8, 0, 0, "-0600"), summary: "72°", icon: "weather-sunny", timezone: tz),
        DeviceEvent.new(id: "3", starts_at: DateTime.new(2023, 8, 27, 9, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 10, 0, 0, "-0600"), summary: "Church service", icon: "calendar", timezone: tz)
      ]
      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, events do
            result = DeviceContent.new.call(home_assistant_api: api, auto_icons: true, always_show_today: true)

            today = result[:day_groups].find { |d| d[:day_name] == "Today" }
            weather_event = today[:periodic].find { |e| e[:summary] == "72°" }
            church_event = today[:periodic].find { |e| e[:summary] == "Church service" }

            assert_equal "weather-sunny", weather_event[:icon_class]
            assert_equal "church", church_event[:icon_class]
          end
        end
      end
    end
  end

  def test_auto_icons_skips_ranged_weather_events
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      events = [
        DeviceEvent.new(id: "4_ha_precip", starts_at: DateTime.new(2023, 8, 27, 9, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 10, 0, 0, "-0600"), summary: "Church-level rain", icon: "weather-rainy", timezone: tz),
        DeviceEvent.new(id: "5", starts_at: DateTime.new(2023, 8, 27, 11, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 12, 0, 0, "-0600"), summary: "Church service", icon: "calendar", timezone: tz)
      ]
      matcher = ->(summary) { summary.include?("Church") ? "church" : nil }

      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, events do
            MdiIconMatcher.stub :match, matcher do
              result = DeviceContent.new.call(home_assistant_api: api, auto_icons: true, always_show_today: true)

              today = result[:day_groups].find { |d| d[:day_name] == "Today" }
              weather_event = today[:periodic].find { |e| e[:summary] == "Church-level rain" }
              church_event = today[:periodic].find { |e| e[:summary] == "Church service" }

              assert_equal "weather-rainy", weather_event[:icon_class]
              assert_equal "church", church_event[:icon_class]
            end
          end
        end
      end
    end
  end

  def test_auto_icons_preserves_timeframe_icon
    travel_to DateTime.new(2023, 8, 27, 7, 0, 0, "-0600") do
      api = new_test_api
      tz = "America/Denver"
      events = [
        DeviceEvent.new(id: "1", starts_at: DateTime.new(2023, 8, 27, 9, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 10, 0, 0, "-0600"), summary: "Church", icon: "calendar", description: "timeframe-icon:church", timezone: tz)
      ]
      matcher = ->(_) { "soccer" }

      api.stub :calendars_healthy?, false do
        api.stub :private_mode?, false do
          api.stub :calendar_events, events do
            MdiIconMatcher.stub :match, matcher do
              result = DeviceContent.new.call(home_assistant_api: api, auto_icons: true, always_show_today: true)

              today = result[:day_groups].find { |d| d[:day_name] == "Today" }
              event = today[:periodic].find { |e| e[:summary] == "Church" }
              assert_equal "church", event[:timeframe_icon]
              assert_equal "church", event[:icon_class]
            end
          end
        end
      end
    end
  end

  def test_event_filter_includes_matching_events
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      events = [
        DeviceEvent.new(starts_at: DateTime.new(2023, 8, 27, 14, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 15, 0, 0, "-0600"), summary: "Soccer practice"),
        DeviceEvent.new(starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 17, 0, 0, "-0600"), summary: "Piano lesson"),
        DeviceEvent.new(starts_at: DateTime.new(2023, 8, 27, 18, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 19, 0, 0, "-0600"), summary: "Dinner")
      ]
      api.stub :calendar_events, events do
        result = DeviceContent.new.call(home_assistant_api: api, event_filter: "Soccer, Piano", always_show_today: true)

        today = result[:day_groups].find { |d| d[:day_name] == "Today" }
        summaries = today[:periodic].map { |e| e[:summary] }
        assert_includes summaries, "Soccer practice"
        assert_includes summaries, "Piano lesson"
        refute_includes summaries, "Dinner"
      end
    end
  end

  def test_event_filter_blank_shows_all_events
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      events = [
        DeviceEvent.new(starts_at: DateTime.new(2023, 8, 27, 14, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 15, 0, 0, "-0600"), summary: "Soccer practice"),
        DeviceEvent.new(starts_at: DateTime.new(2023, 8, 27, 16, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 17, 0, 0, "-0600"), summary: "Dinner")
      ]
      api.stub :calendar_events, events do
        result = DeviceContent.new.call(home_assistant_api: api, event_filter: "", always_show_today: true)

        today = result[:day_groups].find { |d| d[:day_name] == "Today" }
        summaries = today[:periodic].map { |e| e[:summary] }
        assert_includes summaries, "Soccer practice"
        assert_includes summaries, "Dinner"
      end
    end
  end

  def test_event_filter_only_commas_shows_all_events
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      events = [
        DeviceEvent.new(starts_at: DateTime.new(2023, 8, 27, 14, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 15, 0, 0, "-0600"), summary: "Soccer practice")
      ]
      api.stub :calendar_events, events do
        result = DeviceContent.new.call(home_assistant_api: api, event_filter: ",,", always_show_today: true)

        today = result[:day_groups].find { |d| d[:day_name] == "Today" }
        summaries = today[:periodic].map { |e| e[:summary] }
        assert_includes summaries, "Soccer practice"
      end
    end
  end

  def test_event_filter_is_case_sensitive
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      events = [
        DeviceEvent.new(starts_at: DateTime.new(2023, 8, 27, 14, 0, 0, "-0600"), ends_at: DateTime.new(2023, 8, 27, 15, 0, 0, "-0600"), summary: "Soccer Practice")
      ]
      api.stub :calendar_events, events do
        result = DeviceContent.new.call(home_assistant_api: api, event_filter: "soccer", always_show_today: true)

        today = result[:day_groups].find { |d| d[:day_name] == "Today" }
        summaries = today[:periodic].map { |e| e[:summary] }
        refute_includes summaries, "Soccer Practice"

        result = DeviceContent.new.call(home_assistant_api: api, event_filter: "Soccer", always_show_today: true)
        today = result[:day_groups].find { |d| d[:day_name] == "Today" }
        summaries = today[:periodic].map { |e| e[:summary] }
        assert_includes summaries, "Soccer Practice"
      end
    end
  end

  def test_banner_active_event
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      events = [
        DeviceEvent.new(
          starts_at: DateTime.new(2023, 8, 27, 9, 0, 0, "-0600"),
          ends_at: DateTime.new(2023, 8, 27, 17, 0, 0, "-0600"),
          summary: "Office Closed",
          description: "timeframe-banner\nBuilding maintenance"
        )
      ]
      api.stub :calendar_events, events do
        result = DeviceContent.new.call(home_assistant_api: api, always_show_today: true)

        assert result[:banner].present?
        assert_equal "Office Closed", result[:banner][:title]
        assert_includes result[:banner][:description], "Building maintenance"
      end
    end
  end

  def test_banner_not_active_when_event_in_future
    travel_to DateTime.new(2023, 8, 27, 8, 0, 0, "-0600") do
      api = new_test_api
      events = [
        DeviceEvent.new(
          starts_at: DateTime.new(2023, 8, 27, 14, 0, 0, "-0600"),
          ends_at: DateTime.new(2023, 8, 27, 17, 0, 0, "-0600"),
          summary: "Later Event",
          description: "#banner\nNot yet"
        )
      ]
      api.stub :calendar_events, events do
        result = DeviceContent.new.call(home_assistant_api: api, always_show_today: true)

        assert_nil result[:banner]
      end
    end
  end

  def test_banner_nil_without_banner_events
    travel_to DateTime.new(2023, 8, 27, 10, 0, 0, "-0600") do
      api = new_test_api
      events = [
        DeviceEvent.new(
          starts_at: DateTime.new(2023, 8, 27, 9, 0, 0, "-0600"),
          ends_at: DateTime.new(2023, 8, 27, 17, 0, 0, "-0600"),
          summary: "Normal Event",
          description: "No banner here"
        )
      ]
      api.stub :calendar_events, events do
        result = DeviceContent.new.call(home_assistant_api: api, always_show_today: true)

        assert_nil result[:banner]
      end
    end
  end
end
