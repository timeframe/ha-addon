# frozen_string_literal: true

require "test_helper"

class HomeAssistantCalendarImportTest < ActiveSupport::TestCase
  class FakeApi
    def initialize(entities)
      @entities = entities
    end

    def calendar_entities
      @entities
    end
  end

  def setup
    CalendarEventCustomization.delete_all
    Calendar.delete_all
    @account = test_user.accounts.first
  end

  test "creates calendars for HA entities and prunes removed ones" do
    stale = @account.calendars.create!(external_id: "calendar.old", name: "Old", source_type: "home_assistant")
    api = FakeApi.new([{entity_id: "calendar.a", name: "Family", icon: "account-group"}])

    HomeAssistantCalendarImport.new(account: @account, api: api).call

    assert_equal ["calendar.a"], @account.calendars.reload.pluck(:external_id)
    refute Calendar.exists?(stale.id)
  end

  test "updates an existing calendar in place" do
    @account.calendars.create!(external_id: "calendar.a", name: "Old", source_type: "home_assistant")
    api = FakeApi.new([{entity_id: "calendar.a", name: "New", icon: "star"}])

    HomeAssistantCalendarImport.new(account: @account, api: api).call

    calendar = @account.calendars.find_by(external_id: "calendar.a")
    assert_equal "New", calendar.name
    assert_equal "star", calendar.icon
  end
end
