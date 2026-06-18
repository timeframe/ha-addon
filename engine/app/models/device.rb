# frozen_string_literal: true

class Device < ActiveRecord::Base
  include Rails.application.routes.url_helpers

  REFRESH_RATE_SECONDS = 900
  TWO_DAY_DEFAULT_ROLLOVER_TIME = "18:00"

  SUPPORTED_MODELS = {
    "visionect_13" => {name: "Visionect Place & Play 13\"", template: "thirteen", width: 1200, height: 1600},
    "boox_mira_pro" => {name: "Boox Mira Pro 25.3\"", template: "mira", width: 1800, height: 3200, realtime: true},
    "boox_mira" => {name: "Boox Mira 13.3\"", template: "boox_mira", width: 1650, height: 2200, realtime: true},
    "trmnl_og" => {name: "TRMNL (OG)", template: "trmnl", width: 800, height: 480, templates: [{name: "trmnl", label: "Timeline"}, {name: "three_day", label: "3-Day"}, {name: "two_day", label: "2-Day"}, {name: "one_day", label: "1-Day"}], screenshotted: true},
    "reterminal_e1001" => {name: "reTerminal E1001 7.5\"", template: "trmnl", width: 800, height: 480, templates: [{name: "trmnl", label: "Timeline"}, {name: "three_day", label: "3-Day"}, {name: "two_day", label: "2-Day"}, {name: "one_day", label: "1-Day"}], screenshotted: true},
    "reterminal_e1003" => {name: "reTerminal E1003 10.3\"", template: "reterminal", width: 1404, height: 1872, screenshotted: true},
    "trmnl_x" => {name: "TRMNL (X)", template: "reterminal", width: 1404, height: 1872, screenshotted: true}
  }.freeze

  REALTIME_MODELS = SUPPORTED_MODELS.select { |_, v| v[:realtime] }.keys.freeze
  SCREENSHOTTED_MODELS = SUPPORTED_MODELS.select { |_, v| v[:screenshotted] }.keys.freeze

  belongs_to :location, optional: true

  has_one :account, through: :location
  has_one :pending_device, foreign_key: :claimed_device_id, dependent: :destroy

  encrypts :mac_address, deterministic: true
  encrypts :api_key, deterministic: true
  encrypts :visionect_serial, deterministic: true
  encrypts :display_key, deterministic: true
  encrypts :session_token, deterministic: true
  encrypts :cached_image

  validates :name, presence: true, uniqueness: {scope: :location_id}
  validates :model, presence: true, inclusion: {in: SUPPORTED_MODELS.keys}
  validates :mac_address, uniqueness: true, allow_nil: true
  validates :mac_address, presence: true, if: :screenshotted?
  validates :display_template, inclusion: {in: ->(device) { ["default"] + (SUPPORTED_MODELS.dig(device.model, :templates)&.map { |t| t[:name] } || []) }}
  validates :visionect_serial, uniqueness: true, allow_nil: true

  before_create :generate_api_key, if: :screenshotted?
  before_create :generate_friendly_id, if: :screenshotted?
  before_create :generate_confirmation_code, unless: :visionect?
  before_create :generate_display_key
  before_create :auto_confirm!, if: :visionect?

  def model_name_label
    SUPPORTED_MODELS.dig(model, :name)
  end

  def display_width
    portrait? ? SUPPORTED_MODELS.dig(model, :height) : SUPPORTED_MODELS.dig(model, :width)
  end

  def display_height
    portrait? ? SUPPORTED_MODELS.dig(model, :width) : SUPPORTED_MODELS.dig(model, :height)
  end

  # :nocov:
  def refresh_rate
    REFRESH_RATE_SECONDS
  end
  # :nocov:

  def trmnl?
    model == "trmnl_og"
  end

  def reterminal_e1001?
    model == "reterminal_e1001"
  end

  def reterminal_e1003?
    model == "reterminal_e1003"
  end

  def trmnl_x?
    model == "trmnl_x"
  end

  def screenshotted?
    SCREENSHOTTED_MODELS.include?(model)
  end

  def confirmed?
    confirmed_at.present?
  end

  # :nocov:
  def disconnected?
    last_connection_at.nil? || last_connection_at < 1.hour.ago
  end
  # :nocov:

  # A device that has never connected and has no claimed pending registration
  # has never been paired to physical hardware (e.g. created during onboarding).
  def never_paired?
    last_connection_at.nil? && pending_device.blank?
  end

  def rotate_session_token!
    update!(session_token: SecureRandom.urlsafe_base64(32))
    session_token
  end

  def pending_confirmation?
    confirmation_code.present? && !confirmed?
  end

  def confirm!(location, name: nil)
    attrs = {location: location, confirmed_at: Time.current, confirmation_code: nil}
    attrs[:name] = name if name.present?
    update!(attrs)
  end

  def boox_mira?
    model == "boox_mira"
  end

  def realtime_display?
    REALTIME_MODELS.include?(model)
  end

  def pairing_code_device?
    !visionect?
  end

  def visionect?
    model == "visionect_13"
  end

  def active_template
    (display_template == "default") ? SUPPORTED_MODELS.dig(model, :template) : display_template
  end

  def portrait?
    false
  end

  def template_options
    SUPPORTED_MODELS.dig(model, :templates)
  end

  def calendar_excluded?(identifier)
    excluded_calendar_identifiers.include?(identifier.to_s)
  end

  # Per-calendar event filters, keyed by calendar identifier. Built from
  # configuration keys of the form "event_filter_<identifier>".
  def calendar_event_filters
    (configuration || {}).each_with_object({}) do |(key, value), filters|
      next unless key.to_s.start_with?("event_filter_")

      identifier = key.to_s.delete_prefix("event_filter_")
      filters[identifier] = value if value.present?
    end
  end

  def weather_event_enabled?(key)
    value = configuration&.dig(key)
    return value != "false" unless value.nil?

    # Preserve the legacy setting: it used to hide ranged precip/wind events,
    # while keeping the temperature row available for compact displays.
    return false if key != "show_temperature_events" && configuration&.dig("show_weather_events") == "false"

    true
  end

  DEFAULT_TEMPERATURE_HOURS = [8, 12, 16, 20].freeze
  COMPACT_TEMPERATURE_HOURS = [8, 12, 16].freeze

  def default_temperature_hours
    %w[three_day two_day].include?(active_template) ? COMPACT_TEMPERATURE_HOURS : DEFAULT_TEMPERATURE_HOURS
  end

  def temperature_event_hours
    defaults = default_temperature_hours
    (0..23).select do |hour|
      value = configuration&.dig("temperature_hour_#{hour}")
      value.nil? ? defaults.include?(hour) : value == "true"
    end
  end

  DEFAULT_WIND_GUST_THRESHOLD_MPH = 20.0

  # Stored in mph so the configured value is stable across unit-system changes.
  def wind_gust_threshold_mph
    value = configuration&.dig("wind_gust_threshold_mph").presence
    value ? value.to_f : DEFAULT_WIND_GUST_THRESHOLD_MPH
  end

  HIDE_CURRENT_DAY_DEFAULT_TIME = "18:00"
  HIDE_CURRENT_DAY_TEMPLATES = %w[trmnl three_day thirteen mira boox_mira reterminal].freeze

  def hide_current_day_supported?
    HIDE_CURRENT_DAY_TEMPLATES.include?(active_template)
  end

  def hide_current_day_default_on?
    true
  end

  def hide_current_day_enabled?
    return false unless hide_current_day_supported?
    value = configuration&.dig("hide_current_day_enabled")
    value.nil? ? hide_current_day_default_on? : value == "true"
  end

  def hide_current_day_after_minutes
    self.class.time_string_to_minutes(configuration&.dig("hide_current_day_time").presence || HIDE_CURRENT_DAY_DEFAULT_TIME)
  end

  # :nocov:
  def device_content(timezone: nil, current_time: nil)
    tz = timezone || location&.time_zone || "UTC"
    compact_view = %w[three_day two_day one_day].include?(active_template)
    two_day = active_template == "two_day"
    one_day = active_template == "one_day"
    configuration&.dig("only_show_events_with_icons")
    include_ranged_weather_events = !one_day
    include_temperature_events = if two_day || one_day
      true
    else
      weather_event_enabled?("show_temperature_events")
    end
    temperature_hours = include_temperature_events ? temperature_event_hours : nil
    include_precip_events = include_ranged_weather_events && weather_event_enabled?("show_precip_events")
    include_wind_events = include_ranged_weather_events && weather_event_enabled?("show_wind_events")
    effective_current_time = current_time || Time.now.utc.in_time_zone(tz)
    hide_today_enabled = hide_current_day_enabled?
    hide_today_minutes = hide_today_enabled ? hide_current_day_after_minutes : (24 * 60)
    always_show_today_value = if two_day || one_day
      true
    else
      !hide_today_enabled
    end
    args = {
      days:
        if two_day
          2
        elsif one_day
          1
        elsif active_template == "trmnl"
          14
        elsif active_template == "reterminal"
          12
        else
          (compact_view ? 3 : 5)
        end,
      start_offset:
        if two_day
          two_day_start_offset(effective_current_time, timezone: tz)
        elsif one_day
          one_day_start_offset(effective_current_time, timezone: tz)
        else
          0
        end,
      include_precip: include_precip_events,
      include_wind: include_wind_events,
      include_weather_alerts: include_ranged_weather_events && (include_temperature_events || include_precip_events || include_wind_events),
      include_temperature: include_temperature_events,
      temperature_hours: temperature_hours,
      use_day_names: compact_view, include_daily_weather: !compact_view,
      weather_row: compact_view, start_time_only: compact_view,
      always_show_today: always_show_today_value,
      hide_today_after_minutes: hide_today_minutes,
      clothing_forecast: (compact_view || active_template == "trmnl") && (one_day || configuration&.dig("clothing_forecast") == "true"),
      auto_icons: (compact_view || active_template == "trmnl") && configuration&.dig("auto_assign_icons") != "false",
      wind_gust_threshold_mph: wind_gust_threshold_mph,
      event_filters: calendar_event_filters
    }
    args[:current_time] = current_time if current_time
    if demo_mode_enabled?
      DemoDeviceContent.new.call(timezone: tz, **args)
    else
      DeviceContent.new.call(device: self, timezone: tz, **args)
    end
  end

  def two_day_start_offset(current_time, timezone: nil)
    return 0 unless active_template == "two_day"
    return 0 if configuration&.dig("two_day_rollover_enabled") == "false"

    display_time = current_time.in_time_zone(timezone || location&.time_zone || "UTC")
    current_minutes = (display_time.hour * 60) + display_time.min
    if current_minutes >= self.class.time_string_to_minutes(configuration&.dig("two_day_rollover_time"))
      1
    else
      0
    end
  end

  def one_day_start_offset(current_time, timezone: nil)
    return 0 unless active_template == "one_day"
    return 0 if configuration&.dig("one_day_rollover_enabled") == "false"

    display_time = current_time.in_time_zone(timezone || location&.time_zone || "UTC")
    current_minutes = (display_time.hour * 60) + display_time.min
    if current_minutes >= self.class.time_string_to_minutes(configuration&.dig("one_day_rollover_time"))
      1
    else
      0
    end
  end

  def self.time_string_to_minutes(value)
    match = value.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
    return time_string_to_minutes(TWO_DAY_DEFAULT_ROLLOVER_TIME) unless match

    hour = match[1].to_i
    minute = match[2].to_i
    return time_string_to_minutes(TWO_DAY_DEFAULT_ROLLOVER_TIME) unless hour.between?(0, 23) && minute.between?(0, 59)

    (hour * 60) + minute
  end
  # :nocov:

  # :nocov:
  def regenerate_display_key!
    update!(display_key: SecureRandom.alphanumeric(24))
  end

  def token_device_url(host:)
    "#{host}/d/#{id}?key=#{display_key}"
  end

  def signed_screenshot_url(host:)
    sgid = to_sgid(expires_in: 1.minute, for: "screenshot").to_s
    "#{host}/signed_screenshot/#{sgid}"
  end

  def refresh_screenshot!(base_url = nil)
    base_url ||= ENV.fetch("APP_HOST") { "http://localhost:#{ENV.fetch("PORT", 3000)}" }
    url = token_device_url(host: base_url)

    self.cached_image = if visionect?
      ScreenshotService.capture(
        url,
        width: display_width, height: display_height,
        raw: true
      )
    elsif reterminal_e1003? || trmnl_x?
      ScreenshotService.capture(
        url,
        width: display_width, height: display_height,
        grayscale_only: true
      )
    elsif trmnl? || reterminal_e1001?
      ScreenshotService.capture(url, width: display_width, height: display_height, rotate: portrait?)
    else
      ScreenshotService.capture(url, width: display_width, height: display_height)
    end

    self.cached_image_at = Time.current
    save!

    encode_visionect_image! if visionect?
  end

  def encode_visionect_image!
    return unless visionect? && cached_image.present?

    png_data = Base64.decode64(cached_image)
    raw_4bpp = VisionectProtocol::ImageEncoder.png_to_4bpp(png_data)
    VisionectProtocol::Server.store_image(id, raw_4bpp)
  rescue => e
    Rails.logger.error "[Visionect] Image encoding failed for #{name}: #{e.message}"
  end
  # :nocov:

  # :nocov:
  def self.refresh_all_screenshots!(base_url = nil)
    base_url ||= ENV.fetch("APP_HOST") { "http://localhost:#{ENV.fetch("PORT", 3000)}" }
    where(model: SCREENSHOTTED_MODELS).find_each do |device|
      device.refresh_screenshot!(base_url)
    rescue => e
      Rails.logger.error "[Screenshot] Failed for #{device.name}: #{e.message}"
    end
  end

  def self.enqueue_screenshot_refresh_jobs!(stagger: false)
    where(model: SCREENSHOTTED_MODELS).find_each.with_index do |device, index|
      if stagger
        RefreshDeviceScreenshotJob.set(wait: (index * 30).seconds).perform_later(device.id)
      else
        RefreshDeviceScreenshotJob.perform_later(device.id)
      end
    end
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
    # DB not available (e.g. during asset precompilation) or tables not yet created
  end
  # :nocov:

  def authenticate_api_key(token)
    api_key.present? && ActiveSupport::SecurityUtils.secure_compare(api_key, token.to_s)
  end

  def self.find_or_create_by_visionect_serial(serial)
    device = find_by(visionect_serial: serial)
    return device if device

    create!(
      name: "Visionect #{serial}",
      model: "visionect_13",
      visionect_serial: serial
    )
  rescue ActiveRecord::RecordNotUnique
    find_by(visionect_serial: serial)
  end

  def record_visionect_connection!
    update_column(:last_connection_at, Time.current)
  end

  def self.authenticate_session(device_id, token)
    return unless device_id.present? && token.present?

    device = find_by(id: device_id)
    return unless device&.session_token.present?

    if ActiveSupport::SecurityUtils.secure_compare(device.session_token, token)
      device
    end
  end

  def accessible_by?(user: nil, device: nil)
    return true if user&.accounts&.exists?(id: account&.id)
    return true if device&.id == id

    false
  end

  private

  def generate_api_key
    self.api_key ||= SecureRandom.hex(16)
  end

  def generate_friendly_id
    self.friendly_id ||= SecureRandom.alphanumeric(6).upcase
  end

  def generate_confirmation_code
    self.confirmation_code ||= SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
  end

  def generate_display_key
    self.display_key ||= SecureRandom.alphanumeric(24)
  end

  def auto_confirm!
    self.confirmed_at ||= Time.current
  end
end
