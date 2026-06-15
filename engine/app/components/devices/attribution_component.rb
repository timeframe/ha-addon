# frozen_string_literal: true

class Devices::AttributionComponent < ViewComponent::Base
  def initialize(view_object:, offset: "1px", font_size: "8px")
    @view_object = view_object
    @offset = offset
    @font_size = font_size
  end
end
