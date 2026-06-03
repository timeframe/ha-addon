# frozen_string_literal: true

class Devices::OneDayComponent < ViewComponent::Base
  include ActionView::Helpers::TextHelper

  def initialize(view_object:)
    @view_object = view_object
  end
end
