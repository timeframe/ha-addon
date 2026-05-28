class HomeAssistantApi
  MDI_CSS = File.read(Rails.root.join("public/css/mdi/materialdesignicons.css")).freeze

  CONDITION_ICONS = {
    "cloudy" => "cloud",
    "partlycloudy" => "weather-partly-cloudy",
    "sunny" => "weather-sunny",
    "clear-night" => "weather-night",
    "rainy" => "weather-rainy",
    "pouring" => "weather-rainy",
    "snowy" => "snowflake",
    "snowy-rainy" => "snowflake",
    "hail" => "weather-hail",
    "lightning" => "weather-lightning",
    "lightning-rainy" => "weather-lightning-rainy",
    "windy" => "weather-windy",
    "windy-variant" => "weather-windy-variant",
    "fog" => "weather-fog",
    "exceptional" => "alert"
  }.freeze

  STATES_DOMAIN = "home_assistant_api"
  CONFIG_DOMAIN = "home_assistant_config_api"
  CALENDAR_DOMAIN = "home_assistant_calendar_api"
  WEATHER_DOMAIN = "home_assistant_weather_api"

  def initialize(config = TimeframeConfig.new, store: Rails.cache)
    @config = config
    @store = store
  end

  def home_assistant_base_url
    @config.home_assistant_url
  end

  def headers
    {
      Authorization: "Bearer #{@config.home_assistant_token}",
      "content-type": "application/json"
    }
  end

  # --- States ---

  WATCHED_PREFIXES = %w[sensor.timeframe_ media_player. weather.].freeze

  def watched_entity_ids
    response = HTTParty.get("#{home_assistant_base_url}/api/states", headers: headers)
    return [] if response.code != 200

    JSON.parse(response.body)
      .map { it["entity_id"] }
      .select { |eid| WATCHED_PREFIXES.any? { |prefix| eid.start_with?(prefix) } }
  end

  def fetch_states
    response = HTTParty.get("#{home_assistant_base_url}/api/states", headers: headers)
    return unless response.code == 200

    states = JSON.parse(response.body)
      .select { |s| WATCHED_PREFIXES.any? { |prefix| s["entity_id"].start_with?(prefix) } }
    return if states.empty?

    save_domain(STATES_DOMAIN, states)
  end

  def save_states(states)
    save_domain(STATES_DOMAIN, states)
  end

  def states_healthy?
    fetched = states_last_fetched_at
    return false unless fetched
    fetched > DateTime.now - 2.minutes
  end

  def states_last_fetched_at
    domain_last_fetched_at(STATES_DOMAIN)
  end

  def data
    domain_data(STATES_DOMAIN)
  end

  def top_right
    icon_labels("sensor.timeframe_top_right")
  end

  def top_left
    icon_labels("sensor.timeframe_top_left")
  end

  def weather_status
    icon_labels("sensor.timeframe_weather_status")
  end

  def daily_events(current_time: Time.now.in_time_zone(time_zone))
    day_start = current_time.beginning_of_day
    day_end = day_start + 1.day

    sensor_parts("sensor.timeframe_daily_event").filter_map do |entity_id, parts|
      DeviceEvent.new(
        id: "_daily_event_#{entity_id}",
        starts_at: day_start,
        ends_at: day_end,
        icon: parts.first,
        summary: (parts.length >= 2) ? humanize_label(parts.last) : "",
        timezone: time_zone || "UTC"
      )
    end
  end

  def now_playing
    override = data.find { it[:entity_id].end_with?("timeframe_media_player_entity_id") }

    entity = if override.present? && override[:state].present?
      data.find { it[:entity_id] == override[:state] }
    else
      data.find { it[:entity_id].start_with?("media_player.") }
    end

    return {} unless entity.present?
    return {} if %w[paused idle].include?(entity[:state])

    attrs = entity[:attributes] || {}
    artist = attrs[:media_artist]
    track = attrs[:media_title]
    return {} unless artist.present? || track.present?

    {
      artist: artist,
      track: track
    }
  end

  def weather_entity_id
    override = data.find { it[:entity_id].end_with?("timeframe_weather_entity_id") }
    return override[:state] if override.present? && override[:state].present?

    weather = data.find { it[:entity_id].start_with?("weather.") }
    weather&.dig(:entity_id)
  end

  def feels_like_temperature
    ha_unit = ha_temperature_unit
    display_unit = @config.temperature_unit

    override = data.find { it[:entity_id].end_with?("timeframe_weather_feels_like_entity_id") }

    if override.present? && override[:state].present?
      entity = data.find { it[:entity_id] == override[:state] }
      return "#{convert_temp(entity[:state].to_f, ha_unit, display_unit)}°" if entity.present?
    end

    weather = data.find { it[:entity_id] == weather_entity_id }
    apparent = weather&.dig(:attributes, :apparent_temperature)
    return "#{convert_temp(apparent.to_f, ha_unit, display_unit)}°" if apparent.present?

    nil
  end

  # --- Config ---

  def fetch_config
    response = HTTParty.get("#{home_assistant_base_url}/api/config", headers: headers)
    return if response.code != 200
    save_domain(CONFIG_DOMAIN, JSON.parse(response.body))
  end

  def config_healthy?
    fetched = config_last_fetched_at
    return false unless fetched
    fetched > DateTime.now - 10.minutes
  end

  def config_last_fetched_at
    domain_last_fetched_at(CONFIG_DOMAIN)
  end

  def config_data
    fetch_config unless config_last_fetched_at
    domain_data(CONFIG_DOMAIN)
  end

  def latitude
    config_data[:latitude]&.to_s
  end

  def longitude
    config_data[:longitude]&.to_s
  end

  def time_zone
    config_data[:time_zone]
  end

  def unit_system
    config_data[:unit_system] || {}
  end

  HA_SPEED_UNITS = {
    "km/h" => "kph",
    "m/s" => "m/s",
    "mi/h" => "mph",
    "kn" => "kn",
    "ft/s" => "ft/s",
    "Beaufort" => "Beaufort"
  }.freeze

  def ha_speed_unit
    HA_SPEED_UNITS[unit_system[:wind_speed]] || "mph"
  end

  def ha_temperature_unit
    (unit_system[:temperature] == "°C") ? "C" : "F"
  end

  def ha_precipitation_unit
    case unit_system[:accumulated_precipitation]
    when "mm" then "mm"
    when "cm" then "cm"
    else "in"
    end
  end

  # --- Calendars ---

  def fetch_calendars
    start_time = (Time.now - 1.day).utc.iso8601
    end_time = (Time.now + 5.days).utc.iso8601

    calendars_url = "#{home_assistant_base_url}/api/calendars"

    out = []
    calendars = fetch_calendar_list
    icons = fetch_calendar_icons(calendars)

    calendars.each do |calendar|
      entity_id = calendar["entity_id"]

      res = HTTParty.get("#{calendars_url}/#{entity_id}?start=#{start_time}&end=#{end_time}", headers: headers)

      res.map! do |event|
        event["starts_at"] = event["start"]["date"] || event["start"]["dateTime"]
        event["ends_at"] = event["end"]["date"] || event["end"]["dateTime"]
        event["icon"] = icons[entity_id] || "calendar"
        uid = event["uid"]
        event["id"] = uid.present? ? uid : "#{entity_id}_#{event["starts_at"]}_#{Digest::MD5.hexdigest(event["summary"].to_s)[0, 8]}"
        event.delete("uid")
        event.delete("start")
        event.delete("end")
        event.delete("recurrence_id")
        event.delete("rrule")
        event
      end

      out.concat(res)
    end

    save_domain(CALENDAR_DOMAIN, out.compact)
  end

  def calendars_healthy?
    fetched = calendars_last_fetched_at
    return false unless fetched
    fetched > DateTime.now - 20.minutes
  end

  def calendars_last_fetched_at
    domain_last_fetched_at(CALENDAR_DOMAIN)
  end

  def calendar_events
    @calendar_events ||= (domain_value(CALENDAR_DOMAIN)[:response] || []).map { DeviceEvent.new(**it.symbolize_keys!, timezone: time_zone) }
  end

  def fetch_calendar_list
    res = HTTParty.get("#{home_assistant_base_url}/api/calendars", headers: headers)
    return [] unless res.code == 200
    res.parsed_response
  end

  def fetch_calendar_icons(calendars)
    states_url = "#{home_assistant_base_url}/api/states"
    icons = {}

    calendars.each do |calendar|
      entity_id = calendar["entity_id"]

      begin
        res = HTTParty.get("#{states_url}/#{entity_id}", headers: headers)
        if res.code == 200
          icon = res.dig("attributes", "icon")
          if icon.present?
            icon_name = icon.sub("mdi:", "")
            icons[entity_id] = icon_name if MDI_CSS.include?(".mdi-#{icon_name}::before")
          end
        end
      rescue
        # Fall back to default icon if state lookup fails
      end
    end

    icons
  end

  def private_mode?
    current_time = DateTime.now.in_time_zone(time_zone)

    calendar_events.any? { it.summary == "timeframe-private" && it.starts_at <= current_time && it.ends_at >= current_time }
  end

  # --- Weather ---

  def fetch_weather
    entity_id = weather_entity_id
    return unless entity_id.present?

    hourly = fetch_forecast(entity_id, "hourly")
    daily = fetch_forecast(entity_id, "daily")

    return unless hourly.present? || daily.present?

    entity = data.find { it[:entity_id] == entity_id }
    attribution_value = entity&.dig(:attributes, :attribution)

    save_domain(WEATHER_DOMAIN, {
      entity_id: entity_id,
      hourly: hourly,
      daily: daily,
      attribution: attribution_value
    })
  end

  def weather_healthy?
    fetched = weather_last_fetched_at
    return false unless fetched
    fetched > DateTime.now - 20.minutes
  end

  def weather_last_fetched_at
    domain_last_fetched_at(WEATHER_DOMAIN)
  end

  def weather_data
    domain_data(WEATHER_DOMAIN)
  end

  def hourly_forecast
    weather_data[:hourly] || []
  end

  def attribution
    weather_data[:attribution]&.gsub(%r{\s*https?://\S+}, "")&.strip
  end

  def daily_forecast
    weather_data[:daily] || []
  end

  def icon_for(condition)
    CONDITION_ICONS[condition] || "help-circle"
  end

  def speed_unit
    @config.speed_unit
  end

  def precipitation_unit
    @config.precipitation_unit
  end

  def temperature_unit
    @config.temperature_unit
  end

  # Conversion factors to mph (base unit for internal conversion)
  SPEED_TO_MPH = {
    "mph" => 1.0,
    "kph" => 0.621371,
    "m/s" => 2.23694,
    "kn" => 1.15078,
    "ft/s" => 0.681818
  }.freeze

  def convert_speed(value)
    ha_unit = ha_speed_unit
    return value.to_f if ha_unit == speed_unit

    mph_value = if ha_unit == "Beaufort"
      # Beaufort scale is non-linear: v(m/s) = 0.836 * B^1.5
      0.836 * value.to_f**1.5 * SPEED_TO_MPH["m/s"]
    else
      value.to_f * SPEED_TO_MPH.fetch(ha_unit, 1.0)
    end
    mph_value / SPEED_TO_MPH.fetch(speed_unit, 1.0)
  end

  def convert_temperature(value)
    ha_unit = ha_temperature_unit
    return value.to_i if ha_unit == temperature_unit

    if ha_unit == "C" && temperature_unit == "F"
      (value.to_f * 9.0 / 5.0 + 32).round
    else
      ((value.to_f - 32) * 5.0 / 9.0).round
    end
  end

  def convert_precipitation(value, target_unit)
    ha_unit = ha_precipitation_unit
    return value.to_f if ha_unit == target_unit

    case [ha_unit, target_unit]
    when ["mm", "in"] then value.to_f / 25.4
    when ["mm", "cm"] then value.to_f / 10.0
    when ["cm", "in"] then value.to_f / 2.54
    when ["cm", "mm"] then value.to_f * 10.0
    when ["in", "mm"] then value.to_f * 25.4
    when ["in", "cm"] then value.to_f * 2.54
    else value.to_f
    end
  end

  def wind_gust_threshold
    (speed_unit == "kph") ? 32.0 : 20.0
  end

  def daily_max_gust(day_start, day_end)
    hours = hourly_forecast
    return nil unless hours.present?

    max_gust = 0.0
    hours.each do |hour|
      hour_i = DateTime.parse(hour[:datetime]).to_i
      next unless hour_i >= day_start && hour_i < day_end
      gust = convert_speed(hour[:wind_gust_speed] || hour[:wind_speed])
      max_gust = gust if gust > max_gust
    end

    (max_gust >= wind_gust_threshold) ? "#{max_gust.round}#{speed_unit}" : nil
  end

  def hourly_calendar_events
    today = Date.today.in_time_zone(time_zone)
    hours = hourly_forecast

    return [] unless hours.present?

    (-1..7).map { |i| today + i.days }.flat_map do |day|
      (0..23).map { |h| day.beginning_of_day + h.hours }.map do |hour|
        hour_ts = hour.to_i
        weather_hour = hours.find { DateTime.parse(it[:datetime]).to_i == hour_ts }

        next unless weather_hour.present?

        DeviceEvent.new(
          id: "_ha_weather_hour_#{hour.to_i}",
          starts_at: hour,
          ends_at: hour,
          timezone: time_zone,
          icon: icon_for(weather_hour[:condition]),
          summary: "#{convert_temperature(weather_hour[:temperature])}°"
        )
      end.compact
    end
  end

  def daily_calendar_events
    days = daily_forecast
    tz = time_zone

    return [] unless days.present?

    days.map do |day|
      date = Date.parse(day[:datetime])
      starts = ActiveSupport::TimeZone[tz].local(date.year, date.month, date.day)

      precip_parts = nil
      precip_mm = day[:precipitation].to_f
      if precip_mm > 0
        condition = day[:condition]
        is_snow = %w[snowy snowy-rainy].include?(condition)
        target_unit = if precipitation_unit == "in"
          "in"
        else
          is_snow ? "cm" : "mm"
        end
        precip_icon = is_snow ? "snowflake" : "weather-rainy"
        formatted = format_precipitation(convert_precipitation(precip_mm, target_unit), target_unit)
        precip_parts = [{icon: precip_icon, label: formatted}] unless formatted.start_with?("0.0")
      end

      day_icon = icon_for(day[:condition])
      precip_parts&.each { |p| p[:icon] = nil if p[:icon] == day_icon }

      max_gust = daily_max_gust(starts.to_i, (starts + 1.day).to_i)

      DeviceEvent.new(
        id: "_ha_weather_day_#{starts.to_i}",
        starts_at: starts.to_i,
        ends_at: (starts + 1.day).to_i,
        timezone: tz,
        icon: icon_for(day[:condition]),
        summary: "#{convert_temperature(day[:temperature])}° / #{convert_temperature(day[:templow])}°",
        precip: precip_parts,
        wind_gust: max_gust
      )
    end
  end

  def precip_calendar_events
    hours = hourly_forecast
    return [] unless hours.present?

    events = []

    hours.each do |hour|
      prob = hour[:precipitation_probability]
      precip = hour[:precipitation].to_f
      rainy_condition = %w[rainy pouring snowy snowy-rainy hail lightning lightning-rainy].include?(hour[:condition])

      next if precip == 0.0 && !rainy_condition
      next if prob.present? && prob.to_i < 10

      hour_i = DateTime.parse(hour[:datetime]).to_i
      next if hour_i < Time.now.to_i

      condition = hour[:condition]
      precip_type = %w[snowy snowy-rainy].include?(condition) ? "snow" : "rain"

      existing_event = events.find { it[:end_i] == hour_i && it[:precipitation_type] == precip_type }

      target_unit = if precipitation_unit == "in"
        "in"
      else
        (precip_type == "snow") ? "cm" : "mm"
      end

      hour_prob = prob.present? ? prob.to_i : nil

      if existing_event
        existing_event[:end_i] += 3600
        existing_event[:precipitation_total] += convert_precipitation(hour[:precipitation], target_unit)
        existing_event[:max_probability] = [existing_event[:max_probability], hour_prob].compact.max
      else
        events << {
          start_i: hour_i,
          end_i: hour_i + 3600,
          precipitation_type: precip_type,
          precipitation_total: convert_precipitation(hour[:precipitation], target_unit),
          max_probability: hour_prob
        }
      end
    end

    events.filter_map do
      icon = (it[:precipitation_type] == "snow") ? "snowflake" : "weather-rainy"
      display_unit = if precipitation_unit == "in"
        "in"
      else
        (it[:precipitation_type] == "snow") ? "cm" : "mm"
      end
      amount = it[:precipitation_total]
      formatted = format_precipitation(amount, display_unit)
      next if formatted.start_with?("0.0")

      label = "#{it[:precipitation_type].capitalize} #{formatted}"
      label = "#{label} #{it[:max_probability]}%" if it[:max_probability]

      DeviceEvent.new(
        id: "#{it[:start_i]}_ha_precip",
        starts_at: it[:start_i],
        ends_at: it[:end_i],
        timezone: time_zone,
        icon: icon,
        summary: label
      )
    end
  end

  def wind_calendar_events
    hours = hourly_forecast
    return [] unless hours.present?

    events = []

    hours.each do |hour|
      wind_gust = convert_speed(hour[:wind_gust_speed] || hour[:wind_speed])
      next if wind_gust < wind_gust_threshold

      hour_i = DateTime.parse(hour[:datetime]).to_i
      next if hour_i < Time.now.to_i

      existing_event = events.find { it[:end_i] == hour_i }

      if existing_event
        existing_event[:end_i] += 3600
        existing_event[:wind_max] = [existing_event[:wind_max], wind_gust].max
        existing_event[:wind_directions] << hour[:wind_bearing].to_i
      else
        events << {
          start_i: hour_i,
          end_i: hour_i + 3600,
          wind_max: wind_gust,
          wind_directions: [hour[:wind_bearing].to_i]
        }
      end
    end

    events.map do
      radians = it[:wind_directions].map { |d| d * Math::PI / 180 }
      avg_x = radians.sum { |r| Math.cos(r) } / radians.size
      avg_y = radians.sum { |r| Math.sin(r) } / radians.size
      avg_wind_direction = (Math.atan2(avg_y, avg_x) * 180 / Math::PI).round

      DeviceEvent.new(
        id: "#{it[:start_i]}_ha_wind",
        starts_at: it[:start_i],
        ends_at: it[:end_i],
        timezone: time_zone,
        icon: "arrow-up",
        icon_rotation: avg_wind_direction,
        summary: "Gusts up to #{it[:wind_max].round}#{speed_unit}"
      )
    end
  end

  def seed_states(data)
    save_domain(STATES_DOMAIN, data)
  end

  def seed_config(data)
    save_domain(CONFIG_DOMAIN, data)
  end

  def seed_calendars(data)
    save_domain(CALENDAR_DOMAIN, data)
  end

  def seed_weather(data)
    save_domain(WEATHER_DOMAIN, data)
  end

  private

  def humanize_label(value)
    value.include?("_") ? value.humanize : value
  end

  def sensor_parts(prefix)
    data
      .select { it[:entity_id].start_with?(prefix) && it[:state].present? }
      .flat_map do |entity|
        entity[:state].split("\n").filter_map do |line|
          next if line.strip.empty?
          parts = line.split(",").map(&:strip)
          next if parts.empty?
          [entity[:entity_id], parts]
        end
      end
  end

  def icon_labels(prefix)
    sensor_parts(prefix).filter_map do |_, parts|
      result = {icon: parts.first}
      result[:label] = humanize_label(parts[1]) if parts.length >= 2
      result[:rotation] = parts[2].to_i if parts.length >= 3
      result
    end.uniq
  end

  def storage_key(domain)
    "#{DEPLOY_TIME}#{domain}"
  end

  def save_domain(domain, data)
    @store.write(storage_key(domain), {last_fetched_at: Time.now.utc, response: data}.to_json)
  end

  def domain_value(domain)
    JSON.parse(@store.read(storage_key(domain)) || "{}", symbolize_names: true)
  end

  def domain_data(domain)
    domain_value(domain)[:response] || {}
  end

  def domain_last_fetched_at(domain)
    val = domain_value(domain)
    val[:last_fetched_at].present? ? DateTime.parse(val[:last_fetched_at]) : nil
  end

  def convert_temp(value, from, to)
    return value.round if from == to

    if from == "C" && to == "F"
      (value * 9.0 / 5.0 + 32).round
    else
      ((value - 32) * 5.0 / 9.0).round
    end
  end

  def format_precipitation(amount, unit)
    rounded = sprintf("%.1f", amount)
    label = (unit == "in") ? "\"" : unit
    "#{rounded}#{label}"
  end

  def fetch_forecast(entity_id, forecast_type)
    response = HTTParty.post(
      "#{home_assistant_base_url}/api/services/weather/get_forecasts?return_response",
      headers: headers,
      body: {
        entity_id: entity_id,
        type: forecast_type
      }.to_json
    )

    return nil unless response.code == 200

    parsed = response.parsed_response
    parsed.dig("service_response", entity_id, "forecast")
  rescue
    nil
  end
end
