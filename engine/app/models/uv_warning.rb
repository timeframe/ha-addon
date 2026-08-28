# frozen_string_literal: true

class UvWarning
  ICON = "weather-sunny-alert"
  MIN_INDEX = 3

  def self.call(uv_index:)
    return unless uv_index
    return unless uv_index.to_f > MIN_INDEX

    {icon: ICON, label: uv_index.to_i.to_s}
  end
end
