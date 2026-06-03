class DeviceEvent
  DAY_IN_SECONDS = 86_400
  TIMEFRAME_ICON_PATTERN = /timeframe-icon:(?:mdi-)?([a-z0-9][a-z0-9-]*)/i

  attr_reader :id, :starts_at, :ends_at, :multi_day, :location, :icon_rotation, :attachment_image, :precip, :wind_gust, :entity_id
  attr_accessor :icon

  def initialize(
    starts_at:,
    ends_at:,
    summary:,
    timezone: "UTC",
    description: nil,
    icon: nil,
    icon_rotation: nil,
    location: nil,
    daily: false,
    attachment_image: nil,
    precip_icon: nil,
    precip_label: nil,
    precip: nil,
    wind_gust: nil,
    entity_id: nil,
    id: SecureRandom.hex
  )
    @id, @icon, @icon_rotation, @summary, @description, @location, @daily, @timezone, @attachment_image, @wind_gust, @entity_id =
      id, icon, icon_rotation, summary.gsub(/[^a-zA-Z0-9.\-"\  _°\/\\&:+,?()<>'@#%\u2019]/, ""), description, location, daily, timezone, attachment_image, wind_gust, entity_id

    @precip = if precip
      precip
    elsif precip_icon
      [{icon: precip_icon, label: precip_label}]
    end

    @timeframe_icon = @description&.match(TIMEFRAME_ICON_PATTERN)&.captures&.first
    @icon = @timeframe_icon if @timeframe_icon.present?

    title_override = @description&.match(/timeframe-title:(.+?)(?:\n|$)/)&.captures&.first&.strip
    @summary = title_override if title_override.present?

    @starts_at = case starts_at
    when Integer
      Time.at(starts_at).in_time_zone(@timezone)
    when String
      ActiveSupport::TimeZone[@timezone].parse(starts_at)
    else
      starts_at.in_time_zone(@timezone)
    end

    @ends_at = case ends_at
    when Integer
      Time.at(ends_at).in_time_zone(@timezone)
    when String
      ActiveSupport::TimeZone[@timezone].parse(ends_at)
    else
      ends_at.in_time_zone(@timezone)
    end
  end

  def daily?
    length_in_seconds = end_i - start_i

    return false if length_in_seconds == 0

    local_start = @starts_at.in_time_zone(@timezone)
    local_end = @ends_at.in_time_zone(@timezone)
    return false unless local_start.hour == 0 && local_start.min == 0 &&
      local_end.hour == 0 && local_end.min == 0

    true
  end

  def private?
    @summary == "timeframe-private" || @description == "timeframe-private"
  end

  def omit?
    @summary.blank? || @description&.include?("timeframe-omit") || false
  end

  def banner?
    return false unless @description.present?
    @description.include?("timeframe-banner") || @description.include?("#banner")
  end

  def banner_title
    @summary
  end

  def banner_description
    return nil unless @description.present?
    text = @description.dup

    # Strip timeframe metadata tags
    text.gsub!(/timeframe-banner\s*/, "")
    text.gsub!(/#banner\s*/, "")
    text.gsub!(/timeframe-private\s*/, "")
    text.gsub!(/timeframe-omit\s*/, "")
    text.gsub!(/timeframe-title:\S+\s*/, "")
    text.gsub!(/timeframe-icon:(?:mdi-)?[a-z0-9][a-z0-9-]*\s*/i, "")
    text.gsub!(/timeframe-only:[^\n]+\s*/, "")

    # Google Calendar sends HTML; Outlook sends HTML too.
    # If it looks like HTML, sanitize it to safe tags.
    # Otherwise, treat as plain text and convert newlines to <br>.
    if text.match?(/<[a-z][\s\S]*>/i)
      sanitize_html(text)
    else
      ERB::Util.html_escape(text.strip).gsub("\n", "<br>")
    end
  end

  def hidden_for?(device_name)
    return false unless @description.present? && device_name.present?
    match = @description.match(/timeframe-only:(.+?)(?:\n|$)/)
    return false unless match
    allowed = match[1].split(",").map(&:strip).map(&:downcase)
    !allowed.include?(device_name.downcase)
  end

  def start_i
    @starts_at.to_i
  end

  def end_i
    @ends_at.to_i
  end

  def multi_day?
    (end_i - start_i) > if starts_at.to_time.dst? && !ends_at.to_time.dst?
      (DAY_IN_SECONDS + 3600)
    else
      DAY_IN_SECONDS
    end
  end

  def weather?
    id.to_s.match?(/\A_(?:ha|wk)_weather_/)
  end

  def weather_hourly?
    start_i == end_i && weather?
  end

  def weather_ranged?
    id.to_s.match?(/_(precip|wind|alert)/) && start_i != end_i
  end

  def full_start_time
    start = Time.at(start_i).in_time_zone(@timezone)
    start.strftime("%-l:%M%P")
  end

  def full_time
    start = Time.at(start_i).in_time_zone(@timezone)

    if start_i == end_i
      return start.strftime("%-l:%M%P")
    end

    endtime = Time.at(end_i).in_time_zone(@timezone)
    start_date = ""
    end_date = ""

    if start.to_date != endtime.to_date
      start_date = "#{short_weekday_label(start)} "
      end_date = "#{short_weekday_label(endtime)} "
    end

    "#{start_date}#{start.strftime("%-l:%M%P")} - #{end_date}#{endtime.strftime("%-l:%M%P")}"
  end

  def start_time
    start = Time.at(start_i).in_time_zone(@timezone)
    label = start.min.positive? ? start.strftime("%-l:%M") : start.strftime("%-l")
    suffix = start.strftime("%p").gsub("AM", "a").gsub("PM", "p")
    "#{label}#{suffix}"
  end

  def time
    @time ||= begin
      start = Time.at(start_i).in_time_zone(@timezone)

      if start_i == end_i
        label = start.min.positive? ? start.strftime("%-l:%M") : start.strftime("%-l")
        suffix = start.strftime("%p").gsub("AM", "a").gsub("PM", "p")

        return "#{label}#{suffix}"
      end

      endtime = Time.at(end_i).in_time_zone(@timezone)

      start_label = start.min.positive? ? start.strftime("%-l:%M") : start.strftime("%-l")
      end_label = endtime.min.positive? ? endtime.strftime("%-l:%M%p") : endtime.strftime("%-l%p")

      start_suffix =
        if start.strftime("%p") == endtime.strftime("%p") && start.to_date == endtime.to_date
          ""
        else
          start.strftime("%p").gsub("AM", "a").gsub("PM", "p")
        end
      start_date = ""
      end_date = ""

      if start.to_date != endtime.to_date
        start_date = "#{short_weekday_label(start)} "
        end_date = "#{short_weekday_label(endtime)} "
      end

      "#{start_date}#{start_label}#{start_suffix} - #{end_date}#{end_label.gsub("AM", "a").gsub("PM", "p")}"
    end
  end

  def short_weekday_label(value)
    %w[Su M Tu W Th F Sa][value.wday]
  end

  def summary(as_of = nil)
    if (1900..2100).cover?(@description.to_s.to_i)
      counter = Date.today.year - @description.to_s.to_i

      "#{@summary} (#{counter})"
    elsif multi_day? && as_of
      numerator = (as_of.to_date - @starts_at.to_date).to_i + 1
      denominator = (@ends_at.to_date - @starts_at.to_date).to_i
      denominator += 1 unless daily?

      "#{@summary} (#{numerator}/#{denominator})"
    else
      @summary
    end.gsub(/\p{Emoji_Presentation}/, "").strip
  end

  def as_json(date: nil)
    {
      icon_text: icon&.start_with?("alpha-") ? icon.delete_prefix("alpha-").upcase : nil,
      icon_class: icon&.start_with?("alpha-") ? nil : icon,
      icon_style: icon_rotation ? "display: inline-block; transform: rotate(#{icon_rotation + 180}deg); " : nil,
      summary: summary(date),
      location: location,
      time_html: time.to_s,
      start_time: start_time,
      full_time: full_time,
      full_start_time: full_start_time,
      weather_ranged: weather_ranged?,
      weather: weather?,
      attachment_image: attachment_image,
      timeframe_icon: @timeframe_icon,
      precip: precip,
      wind_gust: wind_gust
    }
  end

  private

  BANNER_SAFE_TAGS = %w[b i em strong u s br p ul ol li a span div h1 h2 h3 h4 h5 h6].freeze
  BANNER_SAFE_ATTRS = %w[href style].freeze

  def sanitize_html(html)
    doc = Loofah.fragment(html)
    doc.scrub!(:prune)  # Remove unsafe elements and their children
    scrubber = Rails::HTML::PermitScrubber.new
    scrubber.tags = BANNER_SAFE_TAGS
    scrubber.attributes = BANNER_SAFE_ATTRS
    doc.scrub!(scrubber).to_s.strip
  end
end
