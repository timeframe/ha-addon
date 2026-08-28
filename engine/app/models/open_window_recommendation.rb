# frozen_string_literal: true

class OpenWindowRecommendation
  ICON = "window-open"
  MIN_TEMPERATURE_F = 63
  MAX_TEMPERATURE_F = 72
  MAX_AQI = 70

  def self.call(temperature_f:, aqi:, current_time:)
    return unless temperature_f && aqi

    temperature = temperature_f.to_i
    return unless temperature > MIN_TEMPERATURE_F && temperature <= MAX_TEMPERATURE_F
    return unless aqi.to_i < MAX_AQI

    {icon: ICON}
  end
end
