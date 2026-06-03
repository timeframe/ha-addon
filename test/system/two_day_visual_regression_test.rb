# frozen_string_literal: true

require_relative "../system_test_helper"
require_relative "../support/visual_regression_helper"

class TwoDayVisualRegressionTest < ApplicationSystemTestCase
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

  test "wraps long event titles when the event list fits" do
    device = create_two_day_device("wrap")
    seed_home_assistant_calendar([
      calendar_event(
        summary: LONG_TITLE,
        starts_at: "2026-03-19T09:00:00-05:00",
        ends_at: "2026-03-19T10:00:00-05:00",
        icon: "alpha-j"
      ),
      calendar_event(
        summary: "Lunch with Maria",
        starts_at: "2026-03-19T12:00:00-05:00",
        ends_at: "2026-03-19T13:00:00-05:00",
        icon: "alpha-j"
      ),
      calendar_event(
        summary: "Dentist",
        starts_at: "2026-03-20T10:00:00-05:00",
        ends_at: "2026-03-20T11:00:00-05:00",
        icon: "alpha-s"
      )
    ])

    visit_preview(device)

    assert_text LONG_TITLE
    assert_no_selector ".two-day-events-dense"
    assert_operator line_box_count_for_summary(LONG_TITLE), :>, 1
    assert_visual_match "two_day_wrapped"
  end

  test "uses dense ellipsis mode only when wrapped titles overflow" do
    device = create_two_day_device("dense")
    seed_home_assistant_calendar(
      Array.new(7) do |index|
        calendar_event(
          summary: "Planning session #{index + 1} with the entire engineering team and product managers",
          starts_at: "2026-03-19T#{format("%02d", 9 + index)}:00:00-05:00",
          ends_at: "2026-03-19T#{format("%02d", 9 + index)}:30:00-05:00",
          icon: "alpha-j"
        )
      end + [
        calendar_event(
          summary: "Dentist",
          starts_at: "2026-03-20T10:00:00-05:00",
          ends_at: "2026-03-20T11:00:00-05:00",
          icon: "alpha-s"
        )
      ]
    )

    visit_preview(device)

    assert_selector ".two-day-events-dense"
    assert page.evaluate_script(<<~JS), "Dense event list should fit inside its visible container"
      (function() {
        var container = document.querySelector('.two-day-events-dense');
        return container.scrollHeight <= container.clientHeight + 1;
      })()
    JS
    assert_visual_match "two_day_dense"
  end

  private

  def create_two_day_device(name)
    Device.create!(
      location: test_location,
      name: "two_day_visual_#{name}_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "TD:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "two_day",
      configuration: {
        "only_show_events_with_icons" => "true",
        "show_weather_events" => "false",
        "show_event_times" => "true",
        "show_icons" => "true",
        "show_dates" => "true"
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
    assert_selector ".two-day-columns"
  end

  def line_box_count_for_summary(summary)
    page.evaluate_script(<<~JS)
      (function() {
        var summary = #{summary.to_json};
        var element = Array.from(document.querySelectorAll('.two-day-event-summary')).find(function(candidate) {
          return candidate.textContent.indexOf(summary) !== -1;
        });
        var range = document.createRange();
        range.selectNodeContents(element);
        return range.getClientRects().length;
      })()
    JS
  end
end
