# frozen_string_literal: true

class Device < ActiveRecord::Base
  include Rails.application.routes.url_helpers

  REFRESH_RATE_SECONDS = 900
  # Overnight (23:00-05:00 local) devices update roughly once per hour to spare
  # battery. 3540s (59 min) rather than a full 3600 keeps last_connection_at
  # inside the one-hour "disconnected?" window so the device isn't flagged
  # disconnected between hourly wakes.
  NIGHT_REFRESH_RATE_SECONDS = 3540
  NIGHT_START_HOUR = 23
  MORNING_RESUME_HOUR = 5
  TWO_DAY_DEFAULT_ROLLOVER_TIME = "18:00"

  # Battery hysteresis: turn the on-screen recharge warning ON at/below
  # LOW_BATTERY_THRESHOLD and only clear it once charge recovers to/above
  # LOW_BATTERY_CLEAR_THRESHOLD. The gap prevents the warning from flickering
  # for a device hovering around the threshold.
  LOW_BATTERY_THRESHOLD = 25
  LOW_BATTERY_CLEAR_THRESHOLD = 30

  # Below this charge the display is replaced entirely with a recharge reminder
  # (see Device.charge_reminder?).
  CRITICAL_BATTERY_THRESHOLD = 10

  # Templates that render without the top status bar (the compact day layouts).
  # A low battery can't be shown up top on these, so it's surfaced as a bottom
  # banner instead (see Device.low_battery_banner).
  NO_STATUS_BAR_TEMPLATES = %w[one_day sticky_one_day two_day three_day].freeze

  SUPPORTED_MODELS = {
    "visionect_13" => {name: "Visionect Place & Play 13\"", template: "thirteen", width: 1200, height: 1600},
    "boox_mira_pro" => {name: "Boox Mira Pro 25.3\"", template: "mira", width: 1800, height: 3200, realtime: true},
    "boox_mira" => {name: "Boox Mira 13.3\"", template: "boox_mira", width: 1650, height: 2200, realtime: true},
    "trmnl_og" => {name: "TRMNL (OG)", template: "trmnl", width: 800, height: 480, templates: [{name: "trmnl", label: "Timeline"}, {name: "three_day", label: "3-Day"}, {name: "two_day", label: "2-Day"}, {name: "one_day", label: "1-Day"}], screenshotted: true},
    "reterminal_e1001" => {name: "reTerminal E1001 7.5\"", template: "trmnl", width: 800, height: 480, templates: [{name: "trmnl", label: "Timeline"}, {name: "three_day", label: "3-Day"}, {name: "two_day", label: "2-Day"}, {name: "one_day", label: "1-Day"}], screenshotted: true, product_slug: "timeframe-7"},
    "reterminal_sticky" => {name: "reTerminal Sticky 3.97\"", template: "sticky_one_day", width: 800, height: 480, templates: [{name: "sticky_one_day", label: "1-Day Portrait"}], screenshotted: true},
    "reterminal_e1003" => {name: "reTerminal E1003 10.3\"", template: "reterminal", width: 1414, height: 1872, templates: [{name: "reterminal", label: "Portrait"}, {name: "reterminal_landscape", label: "Landscape"}], screenshotted: true, product_slug: "timeframe-10"},
    "trmnl_x" => {name: "TRMNL (X)", template: "reterminal", width: 1404, height: 1872, templates: [{name: "reterminal", label: "Portrait"}, {name: "reterminal_landscape", label: "Landscape"}], screenshotted: true}
  }.freeze

  REALTIME_MODELS = SUPPORTED_MODELS.select { |_, v| v[:realtime] }.keys.freeze
  SCREENSHOTTED_MODELS = SUPPORTED_MODELS.select { |_, v| v[:screenshotted] }.keys.freeze
  # Models Timeframe sells directly, mapped to a storefront product slug. Only
  # these can be purchased from the "Purchase Devices" card; other supported
  # models are bring-your-own hardware.
  PURCHASABLE_MODELS = SUPPORTED_MODELS.select { |_, v| v[:product_slug] }.keys.freeze

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
  validates :display_template, inclusion: {in: ->(device) { device.valid_display_templates }}
  validates :visionect_serial, uniqueness: true, allow_nil: true

  # When the model changes (e.g. during onboarding when a paired browser device
  # picks its real hardware), a display_template that was valid for the old
  # model may no longer be offered by the new one. Fall back to "default" so the
  # model change doesn't raise a validation error.
  before_validation :reset_invalid_display_template

  before_create :generate_api_key, if: :screenshotted?
  before_create :generate_friendly_id, if: :screenshotted?
  before_create :generate_confirmation_code, unless: :visionect?
  before_create :generate_display_key
  before_create :auto_confirm!, if: :visionect?

  def model_name_label
    SUPPORTED_MODELS.dig(model, :name)
  end

  def display_width
    return SUPPORTED_MODELS.dig(model, :height) if landscape_template?
    portrait? ? SUPPORTED_MODELS.dig(model, :height) : SUPPORTED_MODELS.dig(model, :width)
  end

  def display_height
    return SUPPORTED_MODELS.dig(model, :width) if landscape_template?
    portrait? ? SUPPORTED_MODELS.dig(model, :width) : SUPPORTED_MODELS.dig(model, :height)
  end

  # How long (seconds) the firmware should sleep before polling again. Normally
  # 15 minutes, but overnight (23:00-05:00 in the device's local time) devices
  # update roughly once per hour to conserve battery. During the final overnight
  # hour the interval is capped so a device wakes back up around 05:00 rather
  # than sleeping well past it, and floored at the normal rate so that after
  # ~04:45 it simply resumes the regular 15-minute cadence.
  def refresh_rate(at: Time.current)
    tz = location&.time_zone.presence || "UTC"
    now = at.in_time_zone(tz)
    return REFRESH_RATE_SECONDS unless now.hour >= NIGHT_START_HOUR || now.hour < MORNING_RESUME_HOUR

    morning = now.change(hour: MORNING_RESUME_HOUR, min: 0, sec: 0)
    morning += 1.day if now.hour >= MORNING_RESUME_HOUR
    seconds_until_morning = (morning - now).to_i
    seconds_until_morning.clamp(REFRESH_RATE_SECONDS, NIGHT_REFRESH_RATE_SECONDS)
  end

  def trmnl?
    model == "trmnl_og"
  end

  def reterminal_e1001?
    model == "reterminal_e1001"
  end

  def reterminal_sticky?
    model == "reterminal_sticky"
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

  # Resolves the next value of the persisted low-battery warning flag from a new
  # reading, applying hysteresis. Charging always clears the warning; a nil
  # level (no reading) leaves the flag untouched.
  def self.next_low_battery_warning(level:, charging:, current:)
    return false if charging
    return current if level.nil?

    if level <= LOW_BATTERY_THRESHOLD
      true
    elsif level >= LOW_BATTERY_CLEAR_THRESHOLD
      false
    else
      current
    end
  end

  # Builds the battery indicator hash shown on the device screen from a raw
  # level/charging pair (used by the admin layout preview, which has no
  # persisted device). Returns nil when there is no reading.
  def self.battery_descriptor(level:, charging:)
    return nil if level.nil?

    new(battery_level: level, charging: charging).battery_descriptor(
      low: next_low_battery_warning(level: level, charging: charging, current: false)
    )
  end

  # The battery indicator to surface as a bottom banner for templates that have
  # no top status bar (the compact day layouts). Returns the battery descriptor
  # when it is low or plugged in, otherwise nil.
  def self.low_battery_banner(template, view_object)
    battery = view_object[:battery]
    return nil unless battery
    return nil unless battery[:low] || battery[:charging]
    return nil unless NO_STATUS_BAR_TEMPLATES.include?(template.to_s)

    battery
  end

  # Whether the display should be replaced with a full-screen recharge reminder,
  # which happens once the battery falls below CRITICAL_BATTERY_THRESHOLD and the
  # device is not currently charging.
  def self.charge_reminder?(view_object)
    battery = view_object[:battery]
    return false unless battery
    return false if battery[:charging]

    battery[:level] < CRITICAL_BATTERY_THRESHOLD
  end

  # Next value for the persisted low_battery_warning flag given a fresh reading.
  def battery_warning_for(level:, charging:)
    self.class.next_low_battery_warning(level: level, charging: charging, current: low_battery_warning?)
  end

  # Coarse battery state used for color coding and screen logic.
  def battery_status
    return :unknown if battery_level.nil?
    return :charging if charging? && battery_level < 100

    level = battery_level.to_i
    if level <= 10
      :critical
    elsif level <= LOW_BATTERY_THRESHOLD
      :low
    elsif level <= 50
      :medium
    else
      :good
    end
  end

  # Material Design Icons glyph name for the current battery level/charging state.
  def battery_icon
    return "battery-unknown" if battery_level.nil?

    level = battery_level.to_i.clamp(0, 100)
    if charging? && level < 100
      "battery-charging-#{[(level / 10) * 10, 10].max}"
    elsif level < 10
      "battery-outline"
    elsif level >= 100
      "battery"
    else
      "battery-#{(level / 10) * 10}"
    end
  end

  # Bootstrap text color class matching the battery status.
  def battery_color_class
    case battery_status
    when :charging then "text-info"
    when :critical then "text-danger"
    when :low then "text-warning"
    else "text-body-tertiary"
    end
  end

  # Battery indicator hash for the device screen status bar, or nil when there
  # is no reading. `low` defaults to the persisted hysteresis flag.
  def battery_descriptor(low: low_battery_warning?)
    return nil if battery_level.nil?

    {
      level: battery_level.to_i,
      charging: charging?,
      low: low,
      icon: battery_icon
    }
  end

  def rotate_session_token!
    update!(session_token: SecureRandom.urlsafe_base64(32))
    session_token
  end

  # Detaches the physical hardware from this device so it must be explicitly
  # re-paired (e.g. after a factory reset), without discarding the device's
  # settings or account. Swaps in a placeholder MAC (like an unpaired,
  # onboarding-created device), invalidates the old credentials, and clears the
  # prior pairing registration so the device reads as never_paired? again — the
  # reset hardware is neither silently served nor re-paired to its old account.
  def detach_hardware!
    transaction do
      PendingDevice.where(claimed_device_id: id).destroy_all
      update!(
        mac_address: SecureRandom.hex(6),
        api_key: SecureRandom.hex(16),
        session_token: nil,
        last_connection_at: nil
      )
    end
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

  def valid_display_templates
    ["default"] + (SUPPORTED_MODELS.dig(model, :templates)&.map { |t| t[:name] } || [])
  end

  def portrait?
    reterminal_sticky?
  end

  # The reTerminal 10" / TRMNL X panels can be mounted landscape. When the
  # landscape template is active the display is rendered at swapped (landscape)
  # dimensions and the previews skip the portrait -90deg rotation.
  def landscape_template?
    active_template == "reterminal_landscape"
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

  # Weather alerts can be toggled on every template. They default ON, except for
  # the compact one-day / two-day layouts which default OFF.
  def weather_alerts_enabled?
    value = configuration&.dig("show_weather_alerts")
    return value != "false" unless value.nil?

    !%w[one_day two_day].include?(active_template)
  end

  # Air-quality alerts (US AQI "Unhealthy for Sensitive Groups" or worse) can be
  # toggled on every template. They default ON, except for the compact one-day /
  # two-day layouts which default OFF.
  def air_quality_alerts_enabled?
    value = configuration&.dig("show_air_quality_events")
    return value != "false" unless value.nil?

    !%w[one_day two_day].include?(active_template)
  end

  # Minute-resolution "next hour" precipitation bars are only rendered by the
  # realtime (Mira/Boox) displays. Defaults ON for those models; other models
  # have no place to show them.
  def minutely_precip_enabled?
    return false unless realtime_display?

    configuration&.dig("show_minutely_precip") != "false"
  end

  def uv_warning_enabled?
    model == "boox_mira_pro" && configuration&.dig("show_uv_warning") != "false"
  end

  # The Home Assistant status bar (top-left/right, weather status, now playing)
  # can be toggled on every template. It defaults ON.
  def ha_status_enabled?
    configuration&.dig("show_ha_status") != "false"
  end

  # Whether the numeric device ID badge is shown on the device settings page.
  # Admin-only control; defaults OFF so the ID is hidden unless explicitly enabled.
  def show_device_id?
    configuration&.dig("show_device_id") == "true"
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
  HIDE_CURRENT_DAY_TEMPLATES = %w[trmnl three_day thirteen mira boox_mira reterminal reterminal_landscape].freeze

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
    args = content_args(timezone: tz, current_time: current_time)
    if demo_mode_enabled?
      DemoDeviceContent.new.call(timezone: tz, **args)
    else
      DeviceContent.new.call(device: self, timezone: tz, **args)
    end
  end

  # The DeviceContent/DemoDeviceContent arguments derived from this device's
  # active template and configuration. Extracted so the admin templates preview
  # renders through the same per-template rules as real devices instead of a
  # duplicated copy that drifts.
  def content_args(timezone: nil, current_time: nil)
    compact_view = %w[three_day two_day one_day sticky_one_day].include?(active_template)
    two_day = active_template == "two_day"
    one_day = %w[one_day sticky_one_day].include?(active_template)
    three_day = active_template == "three_day"
    include_ranged_weather_events = !one_day
    include_temperature_events = if two_day || one_day
      true
    else
      weather_event_enabled?("show_temperature_events")
    end
    temperature_hours = include_temperature_events ? temperature_event_hours : nil
    include_precip_events = include_ranged_weather_events && weather_event_enabled?("show_precip_events")
    include_wind_events = include_ranged_weather_events && weather_event_enabled?("show_wind_events")
    hide_today_enabled = current_day_rollover_enabled?
    hide_today_minutes = hide_today_enabled ? current_day_rollover_after_minutes : (24 * 60)
    always_show_today_value = !hide_today_enabled
    # Auto-assign icons is available on every template. It defaults ON for the
    # timeline (trmnl) and compact layouts (their historical behavior) and OFF
    # for all other templates.
    auto_icons_default_on = compact_view
    auto_icons_value = configuration&.dig("auto_assign_icons")
    auto_icons_enabled = auto_icons_value.nil? ? auto_icons_default_on : auto_icons_value == "true"
    # Compact templates render a fixed number of day columns. When the current
    # day can be hidden after the rollover cutoff, over-generate one extra future
    # day (below) and cap the rendered groups here so a hidden "today" is
    # backfilled with the next day instead of leaving a short display.
    day_groups_limit =
      if two_day
        2
      elsif one_day
        1
      elsif three_day
        3
      end
    args = {
      days:
        if two_day
          (hide_today_enabled ? 3 : 2)
        elsif one_day
          (hide_today_enabled ? 2 : 1)
        elsif active_template == "trmnl"
          14
        elsif active_template == "reterminal" || active_template == "reterminal_landscape"
          12
        elsif three_day
          (hide_today_enabled ? 4 : 3)
        else
          (compact_view ? 3 : 5)
        end,
      start_offset: 0,
      include_precip: include_precip_events,
      include_wind: include_wind_events,
      include_weather_alerts: weather_alerts_enabled?,
      include_air_quality: air_quality_alerts_enabled?,
      include_minutely: minutely_precip_enabled?,
      include_temperature: include_temperature_events,
      temperature_hours: temperature_hours,
      use_day_names: compact_view, include_daily_weather: !compact_view,
      weather_row: compact_view, start_time_only: compact_view,
      always_show_today: always_show_today_value,
      hide_today_after_minutes: hide_today_minutes,
      clothing_forecast: (compact_view || active_template == "trmnl" || active_template == "reterminal_landscape") && (one_day || configuration&.dig("clothing_forecast") == "true"),
      auto_icons: auto_icons_enabled,
      wind_gust_threshold_mph: wind_gust_threshold_mph,
      event_filters: calendar_event_filters,
      day_groups_limit: day_groups_limit
    }
    args[:current_time] = current_time if current_time
    args
  end

  # Unified "hide current day" rollover for every template. The toggle and time
  # live under template-specific config keys (two_day_rollover_*,
  # one_day_rollover_*, hide_current_day_*) but all mean the same thing, and all
  # now defer the actual hiding to DeviceContent so the current day is only
  # dropped after the cutoff when no events remain.
  def current_day_rollover_enabled?
    case active_template
    when "two_day"
      configuration&.dig("two_day_rollover_enabled") != "false"
    when "one_day", "sticky_one_day"
      configuration&.dig("one_day_rollover_enabled") != "false"
    else
      hide_current_day_enabled?
    end
  end

  def current_day_rollover_after_minutes
    case active_template
    when "two_day"
      self.class.time_string_to_minutes(configuration&.dig("two_day_rollover_time").presence)
    when "one_day", "sticky_one_day"
      self.class.time_string_to_minutes(configuration&.dig("one_day_rollover_time").presence)
    else
      hide_current_day_after_minutes
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

  def token_device_url(host:, generation: false)
    url = "#{host}/d/#{id}?key=#{display_key}"
    generation ? "#{url}&generation=true" : url
  end

  def signed_screenshot_url(host:)
    sgid = to_sgid(expires_in: 1.minute, for: "screenshot").to_s
    "#{host}/signed_screenshot/#{sgid}"
  end

  def refresh_screenshot!(base_url = nil)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stage = "render"
    base_url ||= ENV.fetch("APP_HOST") { "http://localhost:#{ENV.fetch("PORT", 3000)}" }
    url = token_device_url(host: base_url, generation: true)

    # Skip regenerating the screenshot when the rendered page (plus the deploy
    # id) is byte-for-byte the same as last time. Keeping the existing
    # cached_image AND cached_image_at means /api/display serves the same
    # filename, so TRMNL devices recognise it as already-drawn and never
    # re-flash the panel for unchanged content. A new deploy changes DEPLOY_TIME
    # so every device refreshes exactly once after a release.
    crc = display_content_crc
    if crc && crc == display_state_crc && cached_image.present?
      log_screenshot_refresh("skipped", crc: crc, duration_ms: elapsed_milliseconds(started_at))
      return
    end

    previous_crc = display_state_crc
    stage = "capture"
    self.cached_image = capture_screenshot(url)
    stage = "persist"
    self.cached_image_at = Time.current
    self.last_generated_at = cached_image_at
    self.display_state_crc = crc
    save!

    stage = "encode"
    encode_visionect_image! if visionect?
    log_screenshot_refresh("regenerated", crc: crc, previous_crc: previous_crc, duration_ms: elapsed_milliseconds(started_at))
  rescue => e
    log_screenshot_refresh("failed", duration_ms: elapsed_milliseconds(started_at), stage: stage, error: e)
    raise
  end

  # Records the screenshot refresh decision (skipped vs regenerated) as an audit
  # log so the content-hash short-circuit is observable in the admin audit view.
  # CreateAuditLogJob/AuditLog only exist in the cloud app, so this is a no-op
  # in deployments without them.
  def log_screenshot_refresh(result, crc: nil, previous_crc: nil, duration_ms: nil, stage: nil, error: nil)
    return unless defined?(CreateAuditLogJob)

    metadata = {content_crc: crc, previous_content_crc: previous_crc, duration_ms: duration_ms, stage: stage}.compact
    metadata[:error] = {class: error.class.name, message: error.message} if error
    CreateAuditLogJob.perform_later(
      subject_type: self.class.name,
      subject_id: id,
      event_type: "devices.screenshot_refresh",
      result_type: result,
      metadata: metadata
    )
  rescue => e
    Rails.logger.warn("[Screenshot] audit log failed for #{name}: #{e.message}")
  end

  def elapsed_milliseconds(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end

  # CRC of the rendered display HTML combined with the deploy id. Returns nil if
  # rendering fails so the caller falls back to capturing a fresh screenshot.
  def display_content_crc
    Zlib.crc32("#{rendered_display_html}\n#{DEPLOY_TIME}")
  rescue => e
    Rails.logger.warn("[Screenshot] content hash failed for #{name}: #{e.message}")
    nil
  end

  # Renders the device display page HTML in-process (no headless browser),
  # matching what the screenshot browser loads. Only ever used for
  # screenshotted (non-realtime) templates.
  def rendered_display_html(current_time: nil)
    template = active_template
    view_object = device_content(current_time: current_time)
    view_object[:configuration] = configuration || {}
    component = DevicesController::TEMPLATE_COMPONENTS[template].constantize.new(view_object: view_object)
    ApplicationController.render(
      component,
      layout: "device",
      assigns: {
        refresh: false,
        banner: ((template == "mira") ? nil : view_object[:banner]),
        low_battery_banner: Device.low_battery_banner(template, view_object)
      }
    )
  end

  # Captures the display as it will look at a future moment (used by the daily
  # screenshot reminder email) without touching the persisted cached_image.
  def screenshot_at(current_time, base_url = nil)
    base_url ||= ENV.fetch("APP_HOST") { "http://localhost:#{ENV.fetch("PORT", 3000)}" }
    # The daily preview email mentions a low battery in its copy, so the preview
    # image itself skips the full-screen charge reminder.
    url = "#{token_device_url(host: base_url)}&at=#{CGI.escape(current_time.iso8601)}&charge_reminder=false"
    capture_screenshot(url)
  end

  def capture_screenshot(url)
    if visionect?
      ScreenshotService.capture(
        url,
        width: display_width, height: display_height,
        raw: true
      )
    elsif reterminal_e1003? || trmnl_x?
      ScreenshotService.capture(
        url,
        width: display_width, height: display_height,
        grayscale_only: true,
        rotate: !landscape_template?
      )
    elsif trmnl? || reterminal_e1001? || reterminal_sticky?
      ScreenshotService.capture(url, width: display_width, height: display_height, rotate: portrait?)
    else
      ScreenshotService.capture(url, width: display_width, height: display_height)
    end
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
    pending_ids = RefreshDeviceScreenshotJob.pending_device_ids
    where(model: SCREENSHOTTED_MODELS).where.not(id: pending_ids).find_each.with_index do |device, index|
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

  def reset_invalid_display_template
    return if display_template.blank?
    return if valid_display_templates.include?(display_template)

    self.display_template = "default"
  end

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
