# frozen_string_literal: true

class Devices::StatusBarComponent < ViewComponent::Base
  def initialize(view_object:)
    @view_object = view_object
  end

  def render?
    @view_object[:top_left].any? || @view_object[:top_right].any? || @view_object[:weather_status].any? || @view_object[:battery].present?
  end
end
