# frozen_string_literal: true

require "test_helper"

class ChargeReminderComponentTest < ActiveSupport::TestCase
  test "renders a full-screen recharge reminder" do
    html = render_reminder(battery: {level: 7, low: true, charging: false})

    assert_includes html, "Battery low. Plug in to recharge."
    assert_includes html, "mdi-battery-alert-variant-outline"
  end

  test "renders the same message when there is no battery reading" do
    html = render_reminder(battery: nil)

    assert_includes html, "Battery low. Plug in to recharge."
    refute_includes html, "charge-reminder-level"
  end

  private

  def render_reminder(battery:)
    ApplicationController.render(
      Devices::ChargeReminderComponent.new(view_object: {battery: battery}),
      layout: false
    )
  end
end
