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
    include_air_quality: true,
    include_temperature: true,
    temperature_hours: nil,
    use_day_names: false,
    include_daily_weather: true,
    weather_row: false,
    start_time_only: false,
    always_show_today: false,
    hide_today_after_minutes: 1200,
    start_offset: 0,
    clothing_forecast: false,
    auto_icons: false,
    event_filters: {},
    wind_gust_threshold_mph: 20.0,
    day_groups_limit: nil,
    include_minutely: true
  )
    home_assistant_api ||= HomeAssistantApi.new(wind_gust_threshold_mph: wind_gust_threshold_mph, account: device&.location&.account)
    current_time ||= Time.now.utc.in_time_zone(home_assistant_api.time_zone)

    out = {}
    out[:top_left] = []
    out[:top_right] = []
    out[:weather_status] = []
    out[:current_time] = current_time

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
      raw_events << home_assistant_api.hourly_calendar_events if include_temperature || clothing_forecast
      raw_events << home_assistant_api.daily_calendar_events if include_daily_weather
      raw_events << home_assistant_api.precip_calendar_events if include_precip
      raw_events << home_assistant_api.wind_calendar_events if include_wind
      out[:attribution] = home_assistant_api.attribution
    end

    if home_assistant_api.states_healthy?
      raw_events << home_assistant_api.daily_events(current_time: current_time)
    end

    cal_events = home_assistant_api.calendar_events
    if device&.excluded_calendar_identifiers&.any?
      cal_events = cal_events.reject { |e| device.calendar_excluded?(e.entity_id) }
    end
    if event_filters.present?
      cal_events = cal_events.reject do |e|
        filter = event_filters[e.entity_id.to_s]
        next false if filter.blank?

        keywords = filter.split(",").map(&:strip).reject(&:empty?)
        next false if keywords.empty?

        keywords.none? { |kw| e.summary.to_s.include?(kw) }
      end
    end
    raw_events << cal_events

    # Countdown reminders: a "timeframe-countdown:N" token on a calendar event
    # adds a synthetic all-day "Title (in Xd)" reminder on today for each of the
    # N days leading up to the event.
    today = current_time.to_date
    cal_events.each do |event|
      reminder = event.countdown_reminder(today)
      raw_events << reminder if reminder
    end

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
          device_name: device_name,
          device_id: device&.id
        )

        current_minutes_in_day = (current_time.hour * 60) + current_time.min

        # Attempt to hide Today after the configured cutoff if there are no events.
        # Weather events are ignored here: on their own they don't render a visible
        # timeline row in the evening, so they should not keep an otherwise-empty
        # Today visible. Air quality alerts are visible rows even when they end
        # at midnight, so they keep Today visible.
        if day_index.zero? && current_minutes_in_day >= hide_today_after_minutes && !always_show_today
          remaining_today = events[:periodic].reject(&:weather?)
          next if remaining_today.empty? ||
            remaining_today.all? { it.ends_at > date.end_of_day.utc && !it.air_quality? }
        end

        # The cutoff only hides the entire day (above) when no periodic events
        # remain; it must never hide just the daily events while periodic events
        # are still showing.
        show_daily = true

        periodic_events = events[:periodic]
        weather_row_data = nil
        clothing_data = nil

        if weather_row
          if day_index <= 0
            all_day_events = calendar_feed.events_for(
              date.beginning_of_day.utc,
              date.end_of_day.utc,
              raw_events.flatten,
              device_name: device_name,
              device_id: device&.id
            )
            weather_events = all_day_events[:periodic].select(&:weather?)
          else
            weather_events, _ = periodic_events.partition(&:weather?)
          end
          periodic_events = periodic_events.reject(&:weather?)
          weather_row_hours = temperature_hours || [8, 12, 16]
          # All hourly readings for the day; the clothing forecast needs the 8am
          # "morning" reading regardless of which hours the weather row displays.
          hourly_weather_events = weather_events.select(&:weather_hourly?)
          displayed_weather_events = hourly_weather_events.select { |e| weather_row_hours.include?(e.starts_at.hour) }
          weather_row_data = include_temperature ? displayed_weather_events.map { |e| e.as_json(date: date.to_date) } : []

          if clothing_forecast && clothing_threshold
            daily_weather = events[:daily].find(&:weather?)
            daily_high = daily_weather ? daily_weather.summary.to_i : nil
            clothing_data = clothing_recommendation(
              hourly_weather_events, daily_high,
              threshold: clothing_threshold,
              noon_threshold: clothing_noon_threshold,
              shirt_threshold: clothing_shirt_threshold
            )
          end
        end

        if !weather_row && clothing_forecast && clothing_threshold
          # For "today" the events query is truncated to current_time, so the
          # morning hours are gone. Re-query the full day (like the weather_row
          # path) so clothing reflects the entire day's readings.
          day_weather_events =
            if day_index <= 0
              calendar_feed.events_for(
                date.beginning_of_day.utc,
                date.end_of_day.utc,
                raw_events.flatten,
                device_name: device_name,
                device_id: device&.id
              )[:periodic].select(&:weather_hourly?)
            else
              events[:periodic].select(&:weather_hourly?)
            end
          daily_weather = events[:daily].find(&:weather?)
          daily_high = daily_weather ? daily_weather.summary.to_i : nil
          clothing_data = clothing_recommendation(
            day_weather_events, daily_high,
            threshold: clothing_threshold,
            noon_threshold: clothing_noon_threshold,
            shirt_threshold: clothing_shirt_threshold
          )
        end

        if !weather_row
          periodic_events =
            if include_temperature
              periodic_events.reject { |e| e.weather_hourly? && temperature_hours && !temperature_hours.include?(e.starts_at.hour) }
            else
              periodic_events.reject(&:weather_hourly?)
            end
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

    out[:day_groups] = out[:day_groups].first(day_groups_limit) if day_groups_limit

    if auto_icons
      out[:day_groups].each do |day|
        (day[:daily] + day[:periodic]).each do |event|
          next if event[:timeframe_icon] || event[:weather] || event[:weather_ranged]
          titles = event[:auto_icon_titles].presence || [event[:summary]]
          matched = nil
          titles.each do |title|
            matched = MdiIconMatcher.match(title)
            break if matched
          end
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
    banner_event = all_events.find do |e|
      e.banner? && e.start_i <= current_time.to_i && e.end_i > current_time.to_i &&
        !e.hidden_for?(device&.name, device_id: device&.id)
    end
    if banner_event
      out[:banner] = {title: banner_event.banner_title, description: banner_event.banner_description}
    end

    out
  end

  private

  def clothing_recommendation(weather_events, daily_high, threshold:, noon_threshold:, shirt_threshold:)
    morning = weather_events.find { |e| e.starts_at.hour == 8 }
    return nil unless morning
    noon = weather_events.find { |e| e.starts_at.hour == 12 }
    morning_temp = morning.summary.to_i
    noon_temp = noon ? noon.summary.to_i : morning_temp
    is_shorts = morning_temp >= threshold && noon_temp >= noon_threshold
    is_shorts = false if daily_high && daily_high < noon_threshold
    short_sleeves = is_shorts || noon_temp > shirt_threshold
    {
      icon: is_shorts ? "shorts" : "pants",
      summary: is_shorts ? "Shorts" : "Pants",
      shirt_icon: short_sleeves ? "tshirt" : "long-sleeve-shirt",
      shirt_summary: short_sleeves ? "T-shirt" : "Long sleeves"
    }
  end
end
