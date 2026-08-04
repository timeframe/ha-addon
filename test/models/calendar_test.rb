# frozen_string_literal: true

require "test_helper"

class CalendarTest < ActiveSupport::TestCase
  def setup
    CalendarEventCustomization.delete_all
    Calendar.delete_all
    @account = test_user.accounts.first
    @calendar = @account.calendars.create!(external_id: "calendar.test", name: "Test", source_type: "home_assistant")
  end

  test "requires a name and external id" do
    refute Calendar.new(account: @account, source_type: "home_assistant").valid?
  end

  test "customization_for finds a customization by key" do
    customization = @calendar.event_customizations.create!(customization_key: "e1", icon: "star")
    assert_equal customization, @calendar.customization_for("e1")
    assert_nil @calendar.customization_for("missing")
  end
end
