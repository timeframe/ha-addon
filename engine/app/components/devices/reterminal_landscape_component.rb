# frozen_string_literal: true

# Landscape variant of the reTerminal timeline. The content is identical to the
# portrait ReterminalComponent; the display is rendered at swapped (landscape)
# dimensions so the wider canvas gives the timeline its full horizontal width.
class Devices::ReterminalLandscapeComponent < ViewComponent::Base
  def initialize(view_object:)
    @view_object = view_object
  end
end
