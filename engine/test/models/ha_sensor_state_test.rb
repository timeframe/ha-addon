# frozen_string_literal: true

require "test_helper"

class HaSensorStateTest < Minitest::Test
  def test_ignores_blank_and_unavailable_states
    [nil, "", " \n ", "unavailable", " unknown "].each do |state|
      assert_empty HaSensorState.parts(state)
    end
  end

  def test_preserves_original_line_indexes_and_trims_fields
    assert_equal [
      [["lock", "Front", "90"], 1],
      [["snowflake"], 3]
    ], HaSensorState.parts("\n lock , Front , 90 \n \n snowflake ")
  end

  def test_ignores_lines_without_fields
    assert_empty HaSensorState.parts(",")
  end
end
