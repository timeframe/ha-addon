# frozen_string_literal: true

require "test_helper"

class CalendarEventCustomizationTest < ActiveSupport::TestCase
  def setup
    CalendarEventCustomization.delete_all
    Calendar.delete_all
    @calendar = test_user.accounts.first.calendars.create!(external_id: "calendar.test", name: "Test", source_type: "home_assistant")
  end

  test "token_string builds each timeframe token" do
    customization = @calendar.event_customizations.new(
      customization_key: "e1", icon: "star", title_override: "Party", omit: true,
      only_tokens: ["kitchen"], countdown_days: 3, banner_enabled: true
    )
    tokens = customization.token_string
    assert_includes tokens, "timeframe-icon:mdi-star"
    assert_includes tokens, "timeframe-title:Party"
    assert_includes tokens, "timeframe-only:kitchen"
    assert_includes tokens, "timeframe-countdown:3"
    assert_includes tokens, "timeframe-banner"
    assert_includes tokens, "timeframe-omit"
  end

  test "token_string is empty when nothing is set" do
    assert_equal "", @calendar.event_customizations.new(customization_key: "e1").token_string
  end

  test "merged_description prepends tokens and tolerates a nil description" do
    customization = @calendar.event_customizations.new(customization_key: "e1", icon: "star")
    assert_equal "timeframe-icon:mdi-star\nNotes", customization.merged_description("Notes")
    assert_equal "timeframe-icon:mdi-star", customization.merged_description(nil)
  end

  test "merged_description uses the banner message as the body when a banner is on" do
    customization = @calendar.event_customizations.new(customization_key: "e1", banner_enabled: true, banner_message: "Party time")
    merged = customization.merged_description("original notes")
    assert_includes merged, "timeframe-banner"
    assert_includes merged, "Party time"
    refute_includes merged, "original notes"
  end

  test "merged_description keeps the description when the banner has no message" do
    customization = @calendar.event_customizations.new(customization_key: "e1", banner_enabled: true)
    assert_includes customization.merged_description("original notes"), "original notes"
  end

  test "blank_customization? detects empty and non-empty records" do
    assert @calendar.event_customizations.new(customization_key: "e1").blank_customization?
    refute @calendar.event_customizations.new(customization_key: "e1", icon: "star").blank_customization?
    refute @calendar.event_customizations.new(customization_key: "e1", countdown_days: 3).blank_customization?
    refute @calendar.event_customizations.new(customization_key: "e1", banner_enabled: true).blank_customization?
  end

  test "only_token_list normalizes to strings" do
    customization = @calendar.event_customizations.new(customization_key: "e1", only_tokens: ["a", "b"])
    assert_equal ["a", "b"], customization.only_token_list
  end
end
