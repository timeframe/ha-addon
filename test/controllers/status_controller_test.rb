# frozen_string_literal: true

require "test_helper"

class StatusControllerTest < ActionDispatch::IntegrationTest
  test "status page shows api statuses" do
    get "/status"
    assert_response :success
    assert_includes response.body, "API Status"
    assert_includes response.body, "States"
    assert_includes response.body, "Calendars"
    assert_includes response.body, "Config"
    assert_includes response.body, "Weather"
  end

  test "status page summarizes the year view calendars" do
    store = ActiveSupport::Cache::MemoryStore.new
    api = HomeAssistantApi.new(TimeframeConfig.new, store: store)
    api.seed_config(DEFAULT_TEST_CONFIG)
    api.send(:save_domain, HomeAssistantApi::YEAR_CALENDAR_DOMAIN, [
      {id: "trip", starts_at: "2027-06-01", ends_at: "2027-06-04", summary: "Trip", entity_id: "calendar.family"}
    ])

    Rails.stub(:cache, store) do
      get "/status"
    end

    assert_response :success
    assert_includes response.body, "Year View Calendars (1 events)"
    assert_includes response.body, "calendar.family"
    assert_includes response.body, "Jun 1, 2027"
  end

  test "status page shows the uptime section" do
    UptimeCheck.delete_all
    get "/status"
    assert_response :success
    assert_includes response.body, "Uptime"
    assert_includes response.body, "Past 90 days"
  end
end
