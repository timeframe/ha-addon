# frozen_string_literal: true

# Renders the minute-by-minute "next hour" precipitation bar chart shown at the
# bottom of the realtime (Mira/Boox) displays. Hidden entirely when there is no
# precipitation forecast for the coming hour.
class Devices::MinutelyPrecipitationComponent < ViewComponent::Base
  def initialize(view_object:)
    @view_object = view_object
    @bars = view_object[:minutely_precipitation_bars]
    @icon = view_object[:minutely_weather_minutes_icon]
  end

  def render?
    @bars.present?
  end
end
