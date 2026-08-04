# frozen_string_literal: true

require "test_helper"

class IconSuggestionsControllerTest < ActionDispatch::IntegrationTest
  test "suggests an event icon from text via MdiIconMatcher" do
    get icon_suggestion_path, params: {text: "Dentist appointment"}

    assert_response :success
    assert_equal "mdi-tooth", JSON.parse(response.body)["icon"]
  end

  test "returns a null icon when nothing matches" do
    get icon_suggestion_path, params: {text: "zzzqqq"}

    assert_response :success
    assert_nil JSON.parse(response.body)["icon"]
  end
end
