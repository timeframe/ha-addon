# frozen_string_literal: true

require_relative "../system_test_helper"
require_relative "../support/visual_regression_helper"

class ReterminalStickyVisualRegressionTest < ApplicationSystemTestCase
  include VisualRegressionHelper

  CURRENT_TIME = "2026-03-19T08:00:00"

  def setup
    super
    Rails.cache.clear
    Device.destroy_all
    PendingDevice.destroy_all
    page.current_window.resize_to(480, 800)
  end

  test "renders the demo one-day layout for reTerminal Sticky" do
    device = Device.create!(
      location: test_location,
      name: "reterminal_sticky_visual_#{SecureRandom.hex(4)}",
      model: "reterminal_sticky",
      mac_address: "RS:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "sticky_one_day",
      demo_mode_enabled: true,
      confirmed_at: Time.current,
      confirmation_code: nil
    )

    visit "/test_sign_in"
    visit "/accounts/#{device.account.id}/locations/#{device.location.id}/devices/#{device.id}/preview_frame?at=#{CURRENT_TIME}"

    assert_selector ".sticky-day"
    assert_text "Today"
    footer_bounds = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('.sticky-day-footer, .sticky-day-footer > *')).map(function(element) {
        var rect = element.getBoundingClientRect();
        return { element: element.className || element.tagName, top: rect.top, bottom: rect.bottom };
      })
    JS
    grid_bounds = page.evaluate_script(<<~JS)
      ['.sticky-day', '.sticky-day-header', '.sticky-day-events'].map(function(selector) {
        var element = document.querySelector(selector);
        var rect = element.getBoundingClientRect();
        return {
          element: selector,
          top: rect.top,
          bottom: rect.bottom,
          height: rect.height,
          gridRows: getComputedStyle(element).gridTemplateRows
        };
      })
    JS
    assert footer_bounds.all? { |bounds| bounds["top"] >= 0 && bounds["bottom"] <= 800 },
      "Sticky footer content must fit inside the 480x800 viewport: #{footer_bounds.inspect}; " \
      "grid: #{grid_bounds.inspect}"
    assert_visual_match "reterminal_sticky_one_day"
  end

  test "sizes event times to the widest visible time" do
    device = Device.create!(
      location: test_location,
      name: "reterminal_sticky_visual_times_#{SecureRandom.hex(4)}",
      model: "reterminal_sticky",
      mac_address: "RS:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "sticky_one_day",
      configuration: {
        "show_event_times" => "true",
        "show_weather_events" => "false"
      }
    )
    events = (9..21).map do |hour|
      calendar_event("Event #{hour}", "2026-03-19T#{hour}:00:00-05:00", "2026-03-19T#{hour}:30:00-05:00")
    end
    events << calendar_event("Late event", "2026-03-19T23:30:00-05:00", "2026-03-19T23:45:00-05:00")
    seed_home_assistant_calendar(events)

    visit_preview(device)
    page.evaluate_async_script(<<~JS)
      var done = arguments[0];
      document.fonts.ready.then(function() { requestAnimationFrame(function() { done(true); }); });
    JS

    sizing = page.evaluate_script(<<~JS)
      (function() {
        var bottom = document.querySelector('.sticky-day-events').getBoundingClientRect().bottom;
        var cells = Array.from(document.querySelectorAll('.sticky-day-event-time'));
        var visible = cells.filter(function(cell) { return cell.getBoundingClientRect().top < bottom; });
        var hidden = cells.filter(function(cell) { return cell.getBoundingClientRect().top >= bottom; });
        var visibleWidths = visible.map(function(cell) {
          return cell.querySelector('.sticky-day-event-time-inner').getBoundingClientRect().width;
        });
        var hiddenWidths = hidden.map(function(cell) {
          return cell.querySelector('.sticky-day-event-time-inner').getBoundingClientRect().width;
        });
        return {
          appliedWidths: Array.from(new Set(cells.map(function(cell) { return cell.style.width; }))),
          widestVisible: Math.ceil(Math.max.apply(null, visibleWidths)),
          widestHidden: Math.ceil(Math.max.apply(null, hiddenWidths)),
          hiddenCount: hidden.length
        };
      })()
    JS

    assert_operator sizing["hiddenCount"], :>, 0
    assert_operator sizing["widestHidden"], :>, sizing["widestVisible"]
    assert_equal ["#{sizing["widestVisible"]}px"], sizing["appliedWidths"]
  end

  private

  def seed_home_assistant_calendar(events)
    api = HomeAssistantApi.new
    api.seed_config(DEFAULT_TEST_CONFIG)
    api.seed_calendars(events)
  end

  def calendar_event(summary, starts_at, ends_at)
    {
      starts_at: starts_at,
      ends_at: ends_at,
      summary: summary,
      icon: "calendar",
      description: "timeframe-icon:calendar"
    }
  end

  def visit_preview(device)
    visit "/test_sign_in"
    visit "/accounts/#{device.account.id}/locations/#{device.location.id}/devices/#{device.id}/preview_frame?at=#{CURRENT_TIME}"
    assert_selector ".sticky-day"
  end
end
