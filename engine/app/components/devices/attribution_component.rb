# frozen_string_literal: true

class Devices::AttributionComponent < ViewComponent::Base
  def initialize(view_object:, offset: "1px")
    @view_object = view_object
    @offset = offset
  end
end
