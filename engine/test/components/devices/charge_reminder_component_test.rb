# frozen_string_literal: true

require "test_helper"

class ChargeReminderComponentTest < ActiveSupport::TestCase
  test "renders a full-screen recharge reminder with the battery level" do
    html = render_reminder(battery: {level: 7, low: true, charging: false})

    assert_includes html, "Plug in your Timeframe device to recharge"
    assert_includes html, "7%"
    assert_includes html, "mdi-battery-alert-variant-outline"
  end

  test "renders without a level when there is no battery reading" do
    html = render_reminder(battery: nil)

    assert_includes html, "Plug in your Timeframe device to recharge"
    refute_includes html, "<div class=\"charge-reminder-level\">"
  end

  private

  def render_reminder(battery:)
    ApplicationController.render(
      Devices::ChargeReminderComponent.new(view_object: {battery: battery}),
      layout: false
    )
  end
end
