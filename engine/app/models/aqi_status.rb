# frozen_string_literal: true

class AqiStatus
  HEALTHY_ICON = "air-filter"
  UNHEALTHY_ICON = "face-mask-outline"
  UNHEALTHY_MIN = 101

  def self.call(aqi:)
    value = Float(aqi, exception: false)
    return unless value

    {
      icon: (value >= UNHEALTHY_MIN) ? UNHEALTHY_ICON : HEALTHY_ICON,
      label: value.to_i.to_s
    }
  end
end
