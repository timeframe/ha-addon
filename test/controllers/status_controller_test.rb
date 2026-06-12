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

  test "status page shows the uptime section" do
    UptimeCheck.delete_all
    get "/status"
    assert_response :success
    assert_includes response.body, "Uptime"
    assert_includes response.body, "Past 90 days"
  end
end
