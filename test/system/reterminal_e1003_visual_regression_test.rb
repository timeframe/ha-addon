# frozen_string_literal: true

require_relative "../system_test_helper"
require_relative "../support/visual_regression_helper"

class ReterminalE1003VisualRegressionTest < ApplicationSystemTestCase
  include VisualRegressionHelper

  CURRENT_TIME = "2026-03-19T08:00:00"

  def setup
    super
    Rails.cache.clear
    Device.destroy_all
    PendingDevice.destroy_all
  end

  test "renders the demo timeline for the reTerminal E1003 portrait layout" do
    device = create_device("portrait", "reterminal")

    # reTerminal E1003 portrait renders at 1414x1872.
    page.current_window.resize_to(1414, 1872)
    visit_preview(device)

    # Two door-open indicators consolidate into one grouped label, and the
    # descender-bearing labels ("Garage", "Laundry") must render un-clipped.
    assert_text "Front Door, Garage"
    assert_text "Laundry"
    assert_text "Soccer practice"
    assert_visual_match "reterminal_e1003_portrait"
  end

  test "renders the demo timeline for the reTerminal E1003 landscape layout" do
    device = create_device("landscape", "reterminal_landscape")

    # reTerminal E1003 landscape renders at swapped 1872x1414 dimensions.
    page.current_window.resize_to(1872, 1414)
    visit_preview(device)

    # Two door-open indicators consolidate into one grouped label, and the
    # descender-bearing labels ("Garage", "Laundry") must render un-clipped.
    assert_text "Front Door, Garage"
    assert_text "Laundry"
    assert_text "Soccer practice"
    assert_visual_match "reterminal_e1003_landscape"
  end

  private

  def create_device(name, template)
    Device.create!(
      location: test_location,
      name: "reterminal_e1003_visual_#{name}_#{SecureRandom.hex(4)}",
      model: "reterminal_e1003",
      mac_address: "RT:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: template,
      demo_mode_enabled: true,
      confirmed_at: Time.current,
      confirmation_code: nil
    )
  end

  def visit_preview(device)
    visit "/test_sign_in"
    visit "/accounts/#{device.account.id}/locations/#{device.location.id}/devices/#{device.id}/preview_frame?at=#{CURRENT_TIME}"
  end
end
