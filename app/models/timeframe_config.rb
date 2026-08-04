# frozen_string_literal: true

class TimeframeConfig < Anyway::Config
  config_name :timeframe
  coerce_types temperature_unit: :string

  attr_config home_assistant_token: nil,
    home_assistant_url: "http://homeassistant.local:8123",
    speed_unit: "mph",
    precipitation_unit: "in",
    temperature_unit: "F"

  # Support Home Assistant add-on SUPERVISOR_TOKEN
  on_load do
    if home_assistant_token.nil?
      self.home_assistant_token = ENV["SUPERVISOR_TOKEN"]
      self.home_assistant_url = "http://supervisor/core"
    end
  end
end
