# frozen_string_literal: true

require "test_helper"

class AttributionComponentTest < ActiveSupport::TestCase
  test "renders the noun project credit and attribution" do
    html = render_attribution(attribution: "Apple Weather")

    assert_includes html, "Noun Project icons."
    assert_includes html, "Apple Weather"
  end

  test "omits attribution when not present" do
    html = render_attribution(attribution: nil)

    assert_includes html, "Noun Project icons."
  end

  test "renders the text in solid black for legibility" do
    html = render_attribution(attribution: "Apple Weather")

    assert_includes html, "color: #000"
    refute_includes html, "#777"
    refute_includes html, "#999"
  end

  test "applies the provided corner offset" do
    html = render_attribution(attribution: nil, offset: ".25rem")

    assert_includes html, "bottom: .25rem"
    assert_includes html, "right: .25rem"
  end

  private

  def render_attribution(attribution:, offset: "1px")
    ApplicationController.render(
      Devices::AttributionComponent.new(
        view_object: {attribution: attribution},
        offset: offset
      ),
      layout: false
    )
  end
end
