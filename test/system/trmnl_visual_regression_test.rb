# frozen_string_literal: true

require_relative "../system_test_helper"
require_relative "../support/visual_regression_helper"

class TrmnlVisualRegressionTest < ApplicationSystemTestCase
  include VisualRegressionHelper

  CURRENT_TIME = "2026-03-19T08:00:00"

  def setup
    super
    Rails.cache.clear
    Device.destroy_all
    PendingDevice.destroy_all
    page.current_window.resize_to(800, 480)
  end

  test "renders demo timeline for trmnl" do
    device = Device.create!(
      location: test_location,
      name: "trmnl_visual_demo_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "TV:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "trmnl",
      demo_mode_enabled: true,
      confirmed_at: Time.current,
      confirmation_code: nil
    )

    visit "/test_sign_in"
    visit "/accounts/#{device.account.id}/locations/#{device.location.id}/devices/#{device.id}/preview_frame?at=#{CURRENT_TIME}"

    assert_text "Thursday, Mar. 19"
    assert_text "72°"
    assert_text "Front Door"
    assert_text "Morning standup"
    assert_visual_match "trmnl_demo"
  end
end
