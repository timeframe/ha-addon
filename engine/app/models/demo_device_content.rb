# frozen_string_literal: true

class DemoDeviceContent
  def call(timezone: "UTC", current_time: nil, days: 5, include_precip: true, include_wind: true,
    include_weather_alerts: true, include_temperature: true, temperature_hours: nil,
    use_day_names: false, include_daily_weather: true, weather_row: false, start_time_only: false,
    always_show_today: false, start_offset: 0, clothing_forecast: false, auto_icons: false, event_filter: nil,
    fill_hourly_weather: false, wind_gust_threshold_mph: 20.0)
    current_time ||= Time.now.utc.in_time_zone(timezone)

    out = {}
    out[:current_temperature] = "72°"
    out[:timestamp] = current_time.strftime("%-l:%M %p")
    out[:current_time] = current_time

    out[:top_left] = [
      {icon: "door-open", label: "Front Door"}
    ]

    out[:top_right] = [
      {icon: "bird", label: "Spotted Towhee"}
    ]

    out[:weather_status] = [
      {icon: "arrow-up", label: "12", rotation: 45}
    ]

    out[:now_playing] = {artist: "Tycho", track: "A Walk"}

    out[:minutely_weather_minutes] = (0...60).map do |i|
      chance = if i < 10
        0.1
      elsif i < 30
        0.3 + (i - 10) * 0.035
      elsif i < 45
        1.0 - (i - 30) * 0.05
      else
        0.2
      end

      intensity = if i < 10
        0.0
      elsif i < 30
        0.5 + (i - 10) * 0.1
      elsif i < 45
        2.5 - (i - 30) * 0.15
      else
        0.2
      end

      {precipitationChance: chance.clamp(0.0, 1.0), precipitationIntensity: intensity.clamp(0.0, 3.0)}
    end
    out[:minutely_weather_minutes_icon] = "weather-rainy"

    out[:minutely_precipitation_bars] = out[:minutely_weather_minutes].map do |minute|
      (minute[:precipitationChance] * minute[:precipitationIntensity] * 50).clamp(3, 100).round
    end

    out[:attribution] = "Weather"
    out[:private_mode] = false

    out[:day_groups] = build_day_groups(current_time, timezone, days: days, include_wind: include_wind,
      include_temperature: include_temperature, temperature_hours: temperature_hours, use_day_names: use_day_names, weather_row: weather_row,
      start_offset: start_offset, clothing_forecast: clothing_forecast, fill_hourly_weather: fill_hourly_weather)

    if event_filter.present?
      keywords = event_filter.split(",").map(&:strip).reject(&:empty?).map(&:downcase)
      unless keywords.empty?
        keep = ->(event) {
          icon = event[:icon_class].to_s
          next true if icon.start_with?("weather-", "arrow-")
          keywords.any? { |kw| event[:summary].to_s.downcase.include?(kw) }
        }
        out[:day_groups].each do |day|
          day[:daily] = day[:daily].select(&keep)
          day[:periodic] = day[:periodic].select(&keep)
        end
      end
    end

    if auto_icons
      out[:day_groups].each do |day|
        (day[:daily] + day[:periodic]).each do |event|
          next if event[:weather]
          matched = MdiIconMatcher.match(event[:summary])
          if matched
            event[:icon_class] = matched
            event[:icon_text] = nil
          end
        end
      end
    end

    out[:start_time_only] = start_time_only

    out
  end

  private

  def build_day_groups(current_time, timezone, days: 5, include_wind: true, include_temperature: true, temperature_hours: nil, use_day_names: false, weather_row: false, start_offset: 0, clothing_forecast: false, fill_hourly_weather: false)
    today = current_time.to_date
    tz = ActiveSupport::TimeZone[timezone]
    vacation = DeviceEvent.new(
      starts_at: tz.local(today.year, today.month, today.day) - 2.days,
      ends_at: tz.local(today.year, today.month, today.day) + 5.days,
      summary: "Vacation",
      icon: "plus",
      daily: true,
      timezone: timezone
    )

    (start_offset...(start_offset + days)).map do |day_index|
      date = current_time + day_index.days

      day_name = if use_day_names
        date.strftime("%A")
      else
        case day_index
        when 0 then "Today"
        when 1 then "Tomorrow"
        else date.strftime("%A")
        end
      end

      show_daily = (day_index.zero? && current_time.hour < 20) || !day_index.zero?
      events = events_for_day(day_index, date, current_time, vacation, timezone, include_wind: include_wind)

      periodic_events = fill_hourly_weather ? fill_hourly_weather_events(events[:periodic], date, timezone) : events[:periodic]
      weather_row_data = nil
      clothing_data = nil

      if weather_row
        weather_events, periodic_events = periodic_events.partition(&:weather?)
        weather_row_hours = temperature_hours || [8, 12, 16]
        weather_events = weather_events
          .select { |e| e.weather_hourly? && weather_row_hours.include?(e.starts_at.hour) }
          .sort_by { |e| e.starts_at.hour }
        weather_row_data = include_temperature ? weather_events.map { |e| e.as_json(date: date.to_date) } : []

        if clothing_forecast
          morning = weather_events.find { |e| e.starts_at.hour == 8 }
          noon = weather_events.find { |e| e.starts_at.hour == 12 }
          if morning
            morning_temp = morning.summary.to_i
            noon_temp = noon ? noon.summary.to_i : morning_temp
            # :nocov:
            daily_weather = events[:daily].find(&:weather?)
            daily_high = daily_weather ? daily_weather.summary.to_i : nil
            # :nocov:
            is_shorts = morning_temp >= 55 && noon_temp >= 65
            is_shorts = false if daily_high && daily_high < 65
            short_sleeves = is_shorts || noon_temp > 50
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
        daily: events[:daily].map { |e| e.as_json(date: date.to_date) },
        periodic: periodic_events.reject { |e| e.weather? && !include_temperature }.map { |e| e.as_json(date: date.to_date) },
        weather_row: weather_row_data,
        clothing: clothing_data
      }
    end
  end

  def fill_hourly_weather_events(periodic_events, date, timezone)
    by_hour = periodic_events
      .select { |e| e.weather_hourly? }
      .index_by { |e| e.starts_at.hour }
    anchors = by_hour.keys.sort
    return periodic_events if anchors.empty?

    filled = periodic_events.dup
    (0..23).each do |hour|
      next if by_hour.key?(hour)
      temp = if hour <= anchors.first
        by_hour[anchors.first].summary.to_i
      elsif hour >= anchors.last
        by_hour[anchors.last].summary.to_i
      else
        lower = anchors.select { |h| h <= hour }.max
        upper = anchors.select { |h| h >= hour }.min
        t1 = by_hour[lower].summary.to_i
        t2 = by_hour[upper].summary.to_i
        (t1 + ((t2 - t1).to_f * (hour - lower) / (upper - lower))).round
      end
      nearest = anchors.min_by { |h| (h - hour).abs }
      filled << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: hour).to_i}",
        starts_at: date.change(hour: hour),
        ends_at: date.change(hour: hour),
        summary: "#{temp}°",
        icon: by_hour[nearest].icon,
        timezone: timezone
      )
    end
    filled.each_with_index.sort_by { |e, i| [e.start_i, i] }.map(&:first)
  end

  def events_for_day(day_index, date, current_time, vacation, timezone, include_wind: true)
    daily = []
    periodic = []

    case day_index
    when 0
      daily << DeviceEvent.new(
        starts_at: date.beginning_of_day,
        ends_at: (date + 1.day).beginning_of_day,
        summary: "Sarah Johnson",
        description: "1990",
        icon: "cake-variant",
        daily: true,
        timezone: timezone
      )

      daily << vacation

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 8).to_i}",
        starts_at: date.change(hour: 8),
        ends_at: date.change(hour: 8),
        summary: "58°",
        icon: "weather-partly-cloudy",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 8),
        ends_at: date.change(hour: 9),
        summary: "Morning standup with the entire engineering team and product managers",
        icon: "alpha-j",
        location: "Conference Room A",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 9),
        ends_at: date.change(hour: 9, min: 30),
        summary: "1:1 with Alex",
        icon: "alpha-j",
        location: "Zoom",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 12).to_i}",
        starts_at: date.change(hour: 12),
        ends_at: date.change(hour: 12),
        summary: "68°",
        icon: "weather-partly-cloudy",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 16).to_i}",
        starts_at: date.change(hour: 16),
        ends_at: date.change(hour: 16),
        summary: "74°",
        icon: "weather-sunny",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 17),
        ends_at: date.change(hour: 18),
        summary: "Soccer practice",
        icon: "alpha-f",
        location: "Greenfield Park",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 20).to_i}",
        starts_at: date.change(hour: 20),
        ends_at: date.change(hour: 20),
        summary: "64°",
        icon: "weather-night",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 21),
        ends_at: (date + 1.day).change(hour: 1),
        summary: "Movie night",
        icon: "alpha-f",
        timezone: timezone
      )

    when 1
      daily << vacation

      daily << DeviceEvent.new(
        starts_at: date.beginning_of_day,
        ends_at: (date + 1.day).beginning_of_day,
        summary: "Recycling",
        icon: "home",
        location: "Put out by 7am",
        daily: true,
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 8).to_i}",
        starts_at: date.change(hour: 8),
        ends_at: date.change(hour: 8),
        summary: "55°",
        icon: "weather-sunny",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 10),
        ends_at: date.change(hour: 11),
        summary: "Dentist",
        icon: "alpha-s",
        location: "123 Main St",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 12).to_i}",
        starts_at: date.change(hour: 12),
        ends_at: date.change(hour: 12),
        summary: "70°",
        icon: "weather-partly-cloudy",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 14),
        ends_at: date.change(hour: 15, min: 30),
        summary: "Piano lesson",
        icon: "alpha-s",
        location: "Music Academy",
        timezone: timezone
      )

      if include_wind
        periodic << DeviceEvent.new(
          starts_at: date.change(hour: 15),
          ends_at: date.change(hour: 19),
          summary: "Gusts up to 25mph",
          icon: "arrow-up",
          icon_rotation: 225,
          timezone: timezone
        )
      end

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 20).to_i}",
        starts_at: date.change(hour: 20),
        ends_at: date.change(hour: 20),
        summary: "48°",
        icon: "weather-night",
        timezone: timezone
      )

    when 2
      daily << vacation

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 8).to_i}",
        starts_at: date.change(hour: 8),
        ends_at: date.change(hour: 8),
        summary: "62°",
        icon: "weather-cloudy",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 9),
        ends_at: date.change(hour: 10, min: 30),
        summary: "Team retro",
        icon: "alpha-j",
        location: "Conference Room B",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 12).to_i}",
        starts_at: date.change(hour: 12),
        ends_at: date.change(hour: 12),
        summary: "67°",
        icon: "weather-rainy",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 13),
        ends_at: date.change(hour: 14),
        summary: "Lunch with Maria",
        icon: "alpha-j",
        location: "Cafe Luna",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 13, min: 30),
        ends_at: date.change(hour: 14, min: 30),
        summary: "Call with client",
        icon: "alpha-j",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 20).to_i}",
        starts_at: date.change(hour: 20),
        ends_at: date.change(hour: 20),
        summary: "55°",
        icon: "weather-night",
        timezone: timezone
      )

    when 3
      daily << vacation

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 8).to_i}",
        starts_at: date.change(hour: 8),
        ends_at: date.change(hour: 8),
        summary: "58°",
        icon: "weather-sunny",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 12).to_i}",
        starts_at: date.change(hour: 12),
        ends_at: date.change(hour: 12),
        summary: "75°",
        icon: "weather-sunny",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        starts_at: date.change(hour: 16),
        ends_at: date.change(hour: 17, min: 30),
        summary: "Swimming",
        icon: "alpha-f",
        location: "Community Pool",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 20).to_i}",
        starts_at: date.change(hour: 20),
        ends_at: date.change(hour: 20),
        summary: "62°",
        icon: "weather-night-partly-cloudy",
        timezone: timezone
      )

    when 4
      daily << vacation

      daily << DeviceEvent.new(
        starts_at: date.beginning_of_day,
        ends_at: (date + 1.day).beginning_of_day,
        summary: "Trash day",
        icon: "home",
        daily: true,
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 8).to_i}",
        starts_at: date.change(hour: 8),
        ends_at: date.change(hour: 8),
        summary: "60°",
        icon: "weather-partly-cloudy",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 12).to_i}",
        starts_at: date.change(hour: 12),
        ends_at: date.change(hour: 12),
        summary: "72°",
        icon: "weather-sunny",
        timezone: timezone
      )

      periodic << DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: 20).to_i}",
        starts_at: date.change(hour: 20),
        ends_at: date.change(hour: 20),
        summary: "58°",
        icon: "weather-night",
        timezone: timezone
      )
    end

    # Add a demo daily weather forecast for every day
    daily << DeviceEvent.new(
      id: "_ha_weather_day_#{date.to_i}",
      starts_at: date.beginning_of_day,
      ends_at: (date + 1.day).beginning_of_day,
      summary: "72° / 50°",
      icon: "weather-partly-cloudy",
      timezone: timezone
    )

    # Add a demo attachment image event for every day
    daily << DeviceEvent.new(
      starts_at: date.beginning_of_day,
      ends_at: (date + 1.day).beginning_of_day,
      summary: "Photo of the day",
      icon: "image",
      daily: true,
      timezone: timezone,
      attachment_image: demo_attachment_image(day_index)
    )

    # Ensure weather events exist for every day (fill in any missing hours)
    existing_weather_hours = periodic.select(&:weather?).map { |e| e.starts_at.hour }
    demo_weather_for_day(date, timezone).each do |w|
      periodic << w unless existing_weather_hours.include?(w.starts_at.hour)
    end

    CalendarFeed.new.events_for(
      date.beginning_of_day.utc,
      date.end_of_day.utc,
      daily + periodic,
      false
    )
  end

  DEMO_IMAGE_COLORS = [
    [70, 130, 180],   # steel blue
    [60, 179, 113],   # medium sea green
    [218, 165, 32],   # goldenrod
    [205, 92, 92],    # indian red
    [147, 112, 219],  # medium purple
    [95, 158, 160],   # cadet blue
    [210, 105, 30],   # chocolate
    [100, 149, 237]   # cornflower blue
  ].freeze

  DEMO_WEATHER = [
    {hour: 8, temp: "58°", icon: "weather-sunny"},
    {hour: 12, temp: "72°", icon: "weather-partly-cloudy"},
    {hour: 16, temp: "70°", icon: "weather-sunny"},
    {hour: 20, temp: "60°", icon: "weather-night"}
  ].freeze

  def demo_weather_for_day(date, timezone)
    DEMO_WEATHER.map do |w|
      DeviceEvent.new(
        id: "_ha_weather_hour_#{date.change(hour: w[:hour]).to_i}",
        starts_at: date.change(hour: w[:hour]),
        ends_at: date.change(hour: w[:hour]),
        summary: w[:temp],
        icon: w[:icon],
        timezone: timezone
      )
    end
  end

  def demo_attachment_image(day_index)
    r, g, b = DEMO_IMAGE_COLORS[day_index % DEMO_IMAGE_COLORS.length]
    "data:image/png;base64,#{demo_png_base64(r, g, b)}"
  end

  def demo_png_base64(r, g, b)
    require "base64"
    require "zlib"
    w, h = 200, 120
    ihdr = [w, h, 8, 2, 0, 0, 0].pack("NNCCCCC")
    raw = "".b
    h.times { raw << "\0".b << ([r, g, b].pack("CCC") * w) }
    idat = Zlib::Deflate.deflate(raw)
    png = "\x89PNG\r\n\x1a\n".b
    [["IHDR", ihdr], ["IDAT", idat], ["IEND", "".b]].each do |type, data|
      png << [data.length].pack("N") << type.b << data << [Zlib.crc32(type.b + data)].pack("N")
    end
    Base64.strict_encode64(png)
  end
end
