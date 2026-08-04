# frozen_string_literal: true

require "test_helper"

class MdiIconsHelperTest < ActionView::TestCase
  def test_renders_a_letter_for_alpha_icons
    result = calendar_icon_tag("mdi-alpha-a")
    assert_includes result, "cal-letter"
    assert_includes result, "A"
  end

  def test_renders_an_mdi_glyph_for_regular_icons
    assert_includes calendar_icon_tag("mdi-cake"), "mdi mdi-cake"
  end

  def test_exposes_icon_data_as_json
    assert_includes mdi_icons_json, "mdi-cake"
    assert mdi_search_index_json.present?
  end
end
