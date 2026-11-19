# frozen_string_literal: true

require_relative "../system_test_helper"

class WeatherAlertTypesSystemTest < ApplicationSystemTestCase
  test "search bulk selection and master toggle preserve saved alert choices" do
    device = test_location.devices.create!(name: "Weather picker", model: "visionect_13", display_template: "three_day", demo_mode_enabled: true)
    visit "/test_sign_in"
    visit settings_account_location_device_path(device.account, device.location, device)
    find("summary", text: "Alert types").click

    within("[data-weather-alert-types]") do
      find("[data-alert-search]").set("High Wind")
      assert_selector "[data-alert-type]", count: 2
      assert_no_selector "#weather-alert-winter_storm_watch"
      click_button "Clear all"
    end
    assert_selector "[data-save-status]", text: "Saved"
    assert_equal WeatherAlertTypes::IDS, device.reload.excluded_weather_alert_types

    within("[data-weather-alert-types]") do
      click_button "Select all"
    end
    assert_selector "[data-save-status]", text: "Saved"
    assert_empty device.reload.excluded_weather_alert_types

    uncheck "weather-alert-high_wind_warning"
    assert_selector "[data-save-status]", text: "Saved"
    assert_equal ["high_wind_warning"], device.reload.excluded_weather_alert_types

    uncheck "configuration_show_weather_alerts"
    assert_no_selector "[data-weather-alert-types]"
    assert_selector "[data-save-status]", text: "Saved"
    assert_equal ["high_wind_warning"], device.reload.excluded_weather_alert_types
    check "configuration_show_weather_alerts"
    assert_selector "[data-weather-alert-types]"
    assert_selector "#weather-alert-high_wind_warning:not(:checked)"
    assert_selector "[data-save-status]", text: "Saved"

    visit current_url
    find("summary", text: "Alert types").click
    assert_selector "#weather-alert-high_wind_warning:not(:checked)"
    assert_selector "#weather-alert-winter_storm_watch:checked"
  end
end
