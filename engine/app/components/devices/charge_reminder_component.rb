# frozen_string_literal: true

class Devices::ChargeReminderComponent < ViewComponent::Base
  def initialize(view_object:)
    @view_object = view_object
    @battery = view_object[:battery]
  end
end
