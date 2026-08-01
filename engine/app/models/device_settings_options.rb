# frozen_string_literal: true

# Single source of truth for the device settings option controls. Shared by the
# device settings form (devices/_options_fields) and the admin templates preview
# page so the two never drift. Returns an ordered list of option definitions for
# a device based on its active template (plus, for account-specific options, its
# account/location). Each entry is a hash:
#
#   {key:, label:, default_on:, type: :switch|:time, default:, description:, depends_on:}
#
# The temperature-hour picker and wind-gust threshold are rendered by each view
# as sub-controls of the "show_temperature_events" / "show_wind_events" options.
class DeviceSettingsOptions
  WEATHER_ALERTS_DESCRIPTION =
    "Shows official government alerts such as severe thunderstorm, tornado, " \
    "flood, winter storm, extreme heat, and high wind warnings."

  AIR_QUALITY_ALERTS_DESCRIPTION =
    "Shows air quality warnings when the US AQI forecast reaches " \
    "\"Unhealthy for Sensitive Groups\" or worse over the next 4 days."

  MINUTELY_PRECIP_DESCRIPTION =
    "Shows a minute-by-minute chart of rain or snow expected over the next " \
    "hour at the bottom of the display."

  DAILY_EMAIL_DESCRIPTION =
    "Each day at the time you choose we'll email a preview of how this " \
    "device will look tomorrow morning, as a reminder to update your calendar."

  CURRENT_DAY_DESCRIPTION =
    "Shows today's date and the current temperature at the top of the display."

  ONLY_ICON_EVENTS_DESCRIPTION =
    "Hides any event that doesn't have a manually set icon, for a cleaner, " \
    "more glanceable display."

  HOURLY_CONDITIONS_DESCRIPTION =
    "Adds hour-by-hour temperature and conditions to the timeline."

  PRECIP_EVENTS_DESCRIPTION =
    "Shows periods when rain or snow is expected."

  WIND_EVENTS_DESCRIPTION =
    "Shows periods when strong wind gusts are expected."

  HA_STATUS_DESCRIPTION =
    "Shows Home Assistant sensor states and now-playing media at the top of " \
    "the display."

  AUTO_ICONS_DESCRIPTION =
    "Automatically picks an icon for each event based on its title."

  DATES_DESCRIPTION =
    "Shows the calendar date beneath each day."

  CLOTHING_FORECAST_DESCRIPTION =
    "Suggests what to wear based on the morning's forecast."

  ICONS_DESCRIPTION =
    "Shows an icon next to each event."

  EVENT_TIMES_DESCRIPTION =
    "Shows the start time next to each event."

  TRUNCATE_EVENT_TEXT_DESCRIPTION =
    "Shortens long event names with an ellipsis so each event stays on one " \
    "line. Turn off to wrap and show the full event name."

  LARGER_TEXT_DESCRIPTION =
    "Increases the size of all text on the display for easier reading from a " \
    "distance."

  HIDE_CURRENT_DAY_DESCRIPTION =
    "After the given time, hides the current day if there are no remaining events, making more room to show future days."

  DAILY_EMAIL_DEFAULT_TIME = "19:00"

  def self.call(device)
    new(device).call
  end

  def initialize(device)
    @device = device
    @template = device.active_template
  end

  def call
    return [] if @template.blank?

    @options = []
    header_options
    weather_options
    account_options
    template_options
    hide_current_day_option
    time_inputs
    @options
  end

  private

  attr_reader :device, :template

  def switch(key, label, default_on:, description: nil, depends_on: nil)
    entry = {key: key, label: label, default_on: default_on, type: :switch}
    entry[:description] = description if description
    entry[:depends_on] = depends_on if depends_on
    @options << entry
  end

  def time_input(key, label, default:, depends_on:)
    @options << {key: key, label: label, type: :time, default: default, depends_on: depends_on}
  end

  def one_day? = template == "one_day"

  def two_day? = template == "two_day"

  def trmnl? = template == "trmnl"

  def compact? = %w[two_day three_day one_day].include?(template)

  def reterminal? = %w[reterminal reterminal_landscape].include?(template)

  def header_options
    if %w[trmnl reterminal thirteen boox_mira mira].include?(template)
      switch("show_current_day", "Current date & temperature", default_on: true, description: CURRENT_DAY_DESCRIPTION)
    end
    if compact? || reterminal?
      switch("only_show_events_with_icons", "Only show events with manually set icons", default_on: false, description: ONLY_ICON_EVENTS_DESCRIPTION)
    end
  end

  def weather_options
    if !one_day? && !two_day?
      switch("show_temperature_events", "Hourly conditions", default_on: true, description: HOURLY_CONDITIONS_DESCRIPTION)
    end
    unless one_day?
      switch("show_precip_events", "Precipitation events", default_on: true, description: PRECIP_EVENTS_DESCRIPTION)
      switch("show_wind_events", "Wind events", default_on: true, description: WIND_EVENTS_DESCRIPTION)
    end
    switch(
      "show_weather_alerts", "Weather alerts",
      default_on: !%w[one_day two_day].include?(template),
      description: WEATHER_ALERTS_DESCRIPTION
    )
    switch(
      "show_air_quality_events", "Air quality alerts",
      default_on: !%w[one_day two_day].include?(template),
      description: AIR_QUALITY_ALERTS_DESCRIPTION
    )
    if %w[mira boox_mira].include?(template)
      switch(
        "show_minutely_precip", "Next-hour precipitation",
        default_on: true,
        description: MINUTELY_PRECIP_DESCRIPTION
      )
    end
  end

  # :nocov: Account/HA-specific options depend on cloud/ha-addon associations
  # (ha_sync, account owner email) that the engine suite can't set up; they are
  # exercised through the host apps' device settings pages instead.
  def account_options
    ha_sync = device.location.respond_to?(:ha_sync) && device.location.ha_sync&.synced_at.present?
    switch("show_ha_status", "Home Assistant status", default_on: true, description: HA_STATUS_DESCRIPTION) if ha_sync

    if device.screenshotted? && device.account.respond_to?(:owner_email)
      switch("daily_screenshot_email", "Email me a daily reminder at", default_on: false, description: DAILY_EMAIL_DESCRIPTION)
      time_input("daily_screenshot_email_time", "Daily reminder time", default: DAILY_EMAIL_DEFAULT_TIME, depends_on: "daily_screenshot_email")
    end
  end
  # :nocov:

  def template_options
    if trmnl?
      switch("auto_assign_icons", "Auto-assign icons based on event title", default_on: false, description: AUTO_ICONS_DESCRIPTION)
      switch("show_dates", "Dates", default_on: false, description: DATES_DESCRIPTION)
      switch("clothing_forecast", "Clothing forecast", default_on: false, description: CLOTHING_FORECAST_DESCRIPTION)
      switch("truncate_event_text", "Truncate long event names", default_on: true, description: TRUNCATE_EVENT_TEXT_DESCRIPTION)
      switch("larger_text", "Larger text", default_on: false, description: LARGER_TEXT_DESCRIPTION)
    end
    if template == "reterminal_landscape"
      switch("clothing_forecast", "Clothing forecast", default_on: false, description: CLOTHING_FORECAST_DESCRIPTION)
    end
    if reterminal? || %w[thirteen mira boox_mira].include?(template)
      switch("auto_assign_icons", "Auto-assign icons based on event title", default_on: false, description: AUTO_ICONS_DESCRIPTION)
    end
    return unless compact?

    switch("clothing_forecast", "Clothing forecast", default_on: false, description: CLOTHING_FORECAST_DESCRIPTION) unless one_day?
    switch("show_icons", "Icons", default_on: true, description: ICONS_DESCRIPTION)
    switch("auto_assign_icons", "Auto-assign icons based on event title", default_on: true, depends_on: "show_icons", description: AUTO_ICONS_DESCRIPTION)
    if template == "three_day"
      switch("show_dates", "Dates", default_on: true, description: DATES_DESCRIPTION)
    end
    if two_day?
      switch("show_dates", "Dates", default_on: true, description: DATES_DESCRIPTION)
      switch("show_event_times", "Event times", default_on: true, description: EVENT_TIMES_DESCRIPTION)
      switch("two_day_rollover_enabled", "Hide current day if no events after", default_on: true, description: HIDE_CURRENT_DAY_DESCRIPTION)
    end
    if one_day?
      switch("show_event_times", "Event times", default_on: false, description: EVENT_TIMES_DESCRIPTION)
      switch("one_day_rollover_enabled", "Hide current day if no events after", default_on: true, description: HIDE_CURRENT_DAY_DESCRIPTION)
    end
  end

  def hide_current_day_option
    return unless Device::HIDE_CURRENT_DAY_TEMPLATES.include?(template)

    switch("hide_current_day_enabled", "Hide current day if no events after", default_on: device.hide_current_day_default_on?, description: HIDE_CURRENT_DAY_DESCRIPTION)
  end

  def time_inputs
    if two_day?
      time_input("two_day_rollover_time", "Hide current day after", default: Device::TWO_DAY_DEFAULT_ROLLOVER_TIME, depends_on: "two_day_rollover_enabled")
    end
    if one_day?
      time_input("one_day_rollover_time", "Hide current day after", default: Device::TWO_DAY_DEFAULT_ROLLOVER_TIME, depends_on: "one_day_rollover_enabled")
    end
    if Device::HIDE_CURRENT_DAY_TEMPLATES.include?(template)
      time_input("hide_current_day_time", "Hide current day after", default: Device::HIDE_CURRENT_DAY_DEFAULT_TIME, depends_on: "hide_current_day_enabled")
    end
  end
end
