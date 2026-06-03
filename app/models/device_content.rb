class DeviceContent
  def call(
    device: nil,
    home_assistant_api: nil,
    calendar_feed: CalendarFeed.new,
    timezone: nil,
    current_time: nil,
    days: 5,
    include_precip: true,
    include_wind: true,
    include_weather_alerts: true,
    include_temperature: true,
    temperature_hours: nil,
    use_day_names: false,
    include_daily_weather: true,
    weather_row: false,
    start_time_only: false,
    always_show_today: false,
    start_offset: 0,
    clothing_forecast: false,
    auto_icons: false,
    event_filter: nil,
    wind_gust_threshold_mph: 20.0
  )
    home_assistant_api ||= HomeAssistantApi.new(wind_gust_threshold_mph: wind_gust_threshold_mph)
    current_time ||= Time.now.utc.in_time_zone(home_assistant_api.time_zone)

    out = {}
    out[:top_left] = []
    out[:top_right] = []
    out[:weather_status] = []
    out[:current_time] = current_time
    out[:timestamp] = current_time.strftime("%-l:%M %p")

    if home_assistant_api.states_healthy?
      out[:current_temperature] = home_assistant_api.feels_like_temperature

      out[:now_playing] = home_assistant_api.now_playing
      out[:top_right] = home_assistant_api.top_right
      out[:top_left] = home_assistant_api.top_left
      out[:weather_status] = home_assistant_api.weather_status
    else
      out[:top_left] << {icon: "alert", label: "Home Assistant"}
    end

    raw_events = []

    clothing_threshold = if clothing_forecast
      (home_assistant_api.temperature_unit == "C") ? 18 : 55
    end

    clothing_noon_threshold = if clothing_forecast
      (home_assistant_api.temperature_unit == "C") ? 18 : 65
    end

    clothing_shirt_threshold = if clothing_forecast
      (home_assistant_api.temperature_unit == "C") ? 10 : 50
    end

    if home_assistant_api.weather_healthy?
      raw_events << home_assistant_api.hourly_calendar_events if include_temperature || (weather_row && clothing_forecast)
      raw_events << home_assistant_api.daily_calendar_events if include_daily_weather
      raw_events << home_assistant_api.precip_calendar_events if include_precip
      raw_events << home_assistant_api.wind_calendar_events if include_wind
      out[:attribution] = home_assistant_api.attribution
    end

    if home_assistant_api.states_healthy?
      raw_events << home_assistant_api.daily_events(current_time: current_time)
    end

    private_mode = home_assistant_api.calendars_healthy? && home_assistant_api.private_mode?

    if private_mode
      out[:top_left] << {icon: "eye-off", label: "Private mode"}
    end

    out[:private_mode] = private_mode

    cal_events = home_assistant_api.calendar_events
    if device&.excluded_calendar_identifiers&.any?
      cal_events = cal_events.reject { |e| device.calendar_excluded?(e.entity_id) }
    end
    if event_filter.present?
      keywords = event_filter.split(",").map(&:strip).reject(&:empty?)
      cal_events = cal_events.select { |e| keywords.any? { |kw| e.summary.to_s.include?(kw) } } unless keywords.empty?
    end
    raw_events << cal_events

    out[:day_groups] =
      (start_offset...(start_offset + days)).to_a.map do |day_index|
        date = current_time + day_index.day

        day_name =
          if use_day_names
            date.strftime("%A")
          else
            case day_index
            when 0
              "Today"
            when 1
              "Tomorrow"
            else
              date.strftime("%A")
            end
          end

        device_name = device&.name

        events = calendar_feed.events_for(
          ((day_index.zero? && !always_show_today) ? current_time : date.beginning_of_day).utc,
          date.end_of_day.utc,
          raw_events.flatten,
          private_mode,
          device_name: device_name
        )

        # Attempt to hide Today if it's after 8pm and there are no events
        if day_index.zero? && current_time.hour >= 20 && !always_show_today
          next if events[:periodic].empty? ||
            events[:periodic].all? { it.ends_at > date.end_of_day.utc }
        end

        show_daily = (day_index.zero? && (current_time.hour < 20 || always_show_today)) || !day_index.zero?

        periodic_events = events[:periodic]
        weather_row_data = nil
        clothing_data = nil

        if weather_row
          if day_index <= 0
            all_day_events = calendar_feed.events_for(
              date.beginning_of_day.utc,
              date.end_of_day.utc,
              raw_events.flatten,
              false,
              device_name: device_name
            )
            weather_events = all_day_events[:periodic].select(&:weather?)
          else
            weather_events, _ = periodic_events.partition(&:weather?)
          end
          periodic_events = periodic_events.reject(&:weather?)
          weather_row_hours = temperature_hours || [8, 12, 16]
          weather_events = weather_events.select { |e| e.weather_hourly? && weather_row_hours.include?(e.starts_at.hour) }
          weather_row_data = include_temperature ? weather_events.map { |e| e.as_json(date: date.to_date) } : []

          if clothing_forecast && clothing_threshold
            morning = weather_events.find { |e| e.starts_at.hour == 8 }
            noon = weather_events.find { |e| e.starts_at.hour == 12 }
            if morning
              morning_temp = morning.summary.to_i
              noon_temp = noon ? noon.summary.to_i : morning_temp
              daily_weather = events[:daily].find(&:weather?)
              daily_high = daily_weather ? daily_weather.summary.to_i : nil
              is_shorts = morning_temp >= clothing_threshold && noon_temp >= clothing_noon_threshold
              is_shorts = false if daily_high && daily_high < clothing_noon_threshold
              short_sleeves = is_shorts || noon_temp > clothing_shirt_threshold
              clothing_data = {
                icon: is_shorts ? "shorts" : "pants",
                summary: is_shorts ? "Shorts" : "Pants",
                shirt_icon: short_sleeves ? "tshirt" : "long-sleeve-shirt",
                shirt_summary: short_sleeves ? "T-shirt" : "Long sleeves"
              }
            end
          end
        end

        if temperature_hours && !weather_row
          periodic_events = periodic_events.reject { |e| e.weather_hourly? && !temperature_hours.include?(e.starts_at.hour) }
        end

        {
          day_name: day_name,
          date: date.to_date,
          show_daily: show_daily,
          daily: events[:daily].reject(&:banner?).map { |e| e.as_json(date: date.to_date) },
          periodic: periodic_events.reject(&:banner?).map { |e| e.as_json(date: date.to_date) },
          weather_row: weather_row_data,
          clothing: clothing_data
        }
      end.compact

    if auto_icons
      out[:day_groups].each do |day|
        (day[:daily] + day[:periodic]).each do |event|
          next if event[:timeframe_icon] || event[:weather] || event[:weather_ranged]
          matched = MdiIconMatcher.match(event[:summary])
          if matched
            event[:icon_class] = matched
            event[:icon_text] = nil
          end
        end
      end
    end

    out[:start_time_only] = start_time_only

    # Check for active banner events
    all_events = raw_events.flatten
    banner_event = all_events.find { |e| e.banner? && e.start_i <= current_time.to_i && e.end_i > current_time.to_i }
    if banner_event
      out[:banner] = {title: banner_event.banner_title, description: banner_event.banner_description}
    end

    out
  end
end
