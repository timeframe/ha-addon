# frozen_string_literal: true

class Devices::TwoDayComponent < ViewComponent::Base
  include ActionView::Helpers::TextHelper

  def initialize(view_object:, landscape: false)
    @view_object = view_object
    @landscape = landscape
  end
end
