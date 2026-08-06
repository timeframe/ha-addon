# frozen_string_literal: true

require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  def setup
    CalendarEventCustomization.delete_all
    Calendar.delete_all
    @account = test_user.accounts.first
    @calendar = @account.calendars.create!(external_id: "calendar.family", name: "Family", source_type: "home_assistant")
    seed_calendar_events([all_day_today("calendar.family", "evt-1", "Party")])
    login_as(test_user, scope: :user)
  end

  def teardown
    Warden.test_reset!
  end

  def all_day_today(entity_id, id, summary)
    today = Time.current.in_time_zone("America/Chicago").to_date
    {"entity_id" => entity_id, "id" => id, "summary" => summary,
     "starts_at" => today.to_s, "ends_at" => (today + 1).to_s, "icon" => "calendar"}
  end

  def seed_calendar_events(events)
    Rails.cache.write(
      "#{DEPLOY_TIME}#{HomeAssistantApi::CALENDAR_DOMAIN}",
      {last_fetched_at: Time.now.utc, response: events}.to_json
    )
  end

  test "index lists calendars and their events" do
    get events_path
    assert_response :success
    assert_includes response.body, "Family"
    assert_includes response.body, "Party"
    assert_includes response.body, "Home Assistant calendar events are read-only"
    refute_includes response.body, "Saved in Timeframe"
  end

  test "index badges events with local customizations" do
    @calendar.event_customizations.create!(customization_key: "evt-1", icon: "star")

    get events_path

    assert_response :success
    assert_select ".tf-badge", text: "Saved in Timeframe"
  end

  test "index skips events whose calendar is not imported" do
    seed_calendar_events([
      all_day_today("calendar.family", "evt-1", "Party"),
      all_day_today("calendar.ghost", "evt-2", "Ghosted")
    ])
    get events_path
    assert_response :success
    assert_includes response.body, "Party"
    refute_includes response.body, "Ghosted"
  end

  test "update_customization creates a customization" do
    patch event_customization_path, params: {
      calendar_id: @calendar.id, customization_key: "evt-1",
      customization: {icon: "cake-variant", title_override: "Birthday", omit: "0"}
    }
    assert_redirected_to events_path
    customization = @calendar.event_customizations.find_by(customization_key: "evt-1")
    assert_equal "cake-variant", customization.icon
    assert_equal "Birthday", customization.title_override
  end

  test "update_customization removes an emptied customization" do
    @calendar.event_customizations.create!(customization_key: "evt-1", icon: "star")
    patch event_customization_path, params: {
      calendar_id: @calendar.id, customization_key: "evt-1",
      customization: {icon: "", title_override: "", omit: "0"}
    }
    assert_redirected_to events_path
    assert_nil @calendar.event_customizations.find_by(customization_key: "evt-1")
  end

  test "update_customization ignores an empty submission with no existing record" do
    patch event_customization_path, params: {
      calendar_id: @calendar.id, customization_key: "evt-1",
      customization: {icon: "", title_override: "", omit: "0"}
    }
    assert_redirected_to events_path
    assert_equal 0, @calendar.event_customizations.count
  end

  test "update_customization saves the full customization set" do
    patch event_customization_path, params: {
      calendar_id: @calendar.id, customization_key: "evt-1",
      customization: {icon: "mdi-cake-variant", title_override: "Birthday"},
      device_ids: ["99"], banner: "1", message: "Party", countdown: "1", countdown_days: "5"
    }
    assert_redirected_to events_path
    customization = @calendar.event_customizations.find_by(customization_key: "evt-1")
    assert_equal "cake-variant", customization.icon
    assert_equal "Birthday", customization.title_override
    assert_equal ["99"], customization.only_token_list
    assert customization.banner_enabled
    assert_equal "Party", customization.banner_message
    assert_equal 5, customization.countdown_days
  end

  test "update_customization ignores a zero countdown length" do
    patch event_customization_path, params: {
      calendar_id: @calendar.id, customization_key: "evt-1",
      customization: {icon: "mdi-star"}, countdown: "1", countdown_days: "0"
    }
    assert_nil @calendar.event_customizations.find_by(customization_key: "evt-1").countdown_days
  end

  test "toggle_omit hides then clears an event" do
    patch toggle_omit_event_path, params: {calendar_id: @calendar.id, customization_key: "evt-1", omit: "1"}
    assert_redirected_to events_path
    assert @calendar.event_customizations.find_by(customization_key: "evt-1").omit
    patch toggle_omit_event_path, params: {calendar_id: @calendar.id, customization_key: "evt-1", omit: "0"}
    assert_nil @calendar.event_customizations.find_by(customization_key: "evt-1")
  end

  test "bulk_hide hides selected events and skips malformed tokens" do
    patch bulk_hide_events_path, params: {calendar_event_ids: ["#{@calendar.id}::evt-1", "999999::evt-2", "#{@calendar.id}::"]}
    assert_redirected_to events_path
    customization = @calendar.event_customizations.find_by(customization_key: "evt-1")
    assert customization.omit
    assert_equal 1, @calendar.event_customizations.count
  end
end
