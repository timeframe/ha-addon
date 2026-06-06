# frozen_string_literal: true

require_relative "../system_test_helper"
require_relative "../support/visual_regression_helper"

class OneDayVisualRegressionTest < ApplicationSystemTestCase
  include VisualRegressionHelper

  CURRENT_TIME = "2026-03-19T08:00:00"
  LONG_TITLE = "Morning standup with the entire engineering team and product managers"

  def setup
    super
    Rails.cache.clear
    Device.destroy_all
    PendingDevice.destroy_all
    page.current_window.resize_to(800, 480)
  end

  test "renders events at full size when the list fits" do
    device = create_one_day_device("fits")
    seed_home_assistant_calendar([
      calendar_event(
        summary: "Lunch with Maria",
        starts_at: "2026-03-19T12:00:00-05:00",
        ends_at: "2026-03-19T13:00:00-05:00",
        icon: "alpha-j"
      ),
      calendar_event(
        summary: "Dentist",
        starts_at: "2026-03-19T15:00:00-05:00",
        ends_at: "2026-03-19T16:00:00-05:00",
        icon: "alpha-s"
      )
    ])

    visit_preview(device)

    assert_text "Lunch with Maria"
    assert events_fit_container?, "Event list should fit inside its visible container"
    assert_visual_match "one_day_fits"
  end

  test "auto-sizes a long event list so it does not overflow" do
    device = create_one_day_device("autosize")
    seed_home_assistant_calendar(
      Array.new(9) do |index|
        calendar_event(
          summary: "Planning session #{index + 1}",
          starts_at: "2026-03-19T#{format("%02d", 9 + index)}:00:00-05:00",
          ends_at: "2026-03-19T#{format("%02d", 9 + index)}:30:00-05:00",
          icon: "alpha-j"
        )
      end
    )

    visit_preview(device)

    assert events_fit_container?, "Auto-sized event list should fit inside its visible container"
    assert_operator rendered_events_font_size, :<, base_events_font_size,
      "Event font size should shrink to fit the long list"
    assert_visual_match "one_day_autosize"
  end

  private

  def create_one_day_device(name)
    Device.create!(
      location: test_location,
      name: "one_day_visual_#{name}_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "OD:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "one_day",
      configuration: {
        "only_show_events_with_icons" => "true",
        "show_weather_events" => "false"
      }
    )
  end

  def seed_home_assistant_calendar(events)
    api = HomeAssistantApi.new
    api.seed_config(DEFAULT_TEST_CONFIG)
    api.seed_calendars(events)
  end

  def calendar_event(summary:, starts_at:, ends_at:, icon:, description: nil)
    description ||= "timeframe-icon:#{icon}"

    {
      starts_at: starts_at,
      ends_at: ends_at,
      summary: summary,
      icon: icon,
      description: description
    }
  end

  def visit_preview(device)
    visit "/test_sign_in"
    visit "/accounts/#{device.account.id}/locations/#{device.location.id}/devices/#{device.id}/preview_frame?at=#{CURRENT_TIME}"
    assert_selector ".one-day-wrap"
  end

  def events_fit_container?
    page.evaluate_script(<<~JS)
      (function() {
        var container = document.querySelector('.one-day-events');
        if (!container) { return true; }
        return container.scrollHeight <= container.clientHeight + 1;
      })()
    JS
  end

  def rendered_events_font_size
    page.evaluate_script(<<~JS)
      (function() {
        var container = document.querySelector('.one-day-events');
        return parseFloat(window.getComputedStyle(container).fontSize);
      })()
    JS
  end

  def base_events_font_size
    # 5.625rem at the 16px root font size used by the template.
    5.625 * 16
  end
end
