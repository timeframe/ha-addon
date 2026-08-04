# frozen_string_literal: true

require_relative "../system_test_helper" unless defined?(ApplicationSystemTestCase)

class VisionectDisplayFlowTest < ApplicationSystemTestCase
  def setup
    super
    PendingDevice.destroy_all
    Device.destroy_all
  end

  test "add Visionect device, enable demo mode, and view display via token URL" do
    # Step 1: Sign in and visit dashboard
    visit "/test_sign_in"
    assert_text "Add Device"

    # Step 2: Add a Visionect device
    device_name = "System Test Visionect #{SecureRandom.hex(4)}"
    form = first("#add-device-form")
    within(form) do
      fill_in "device_name", with: device_name
      select "Visionect Place & Play 13\"", from: "device_model"
      click_button "Add Device"
    end

    # Should redirect to the device settings page
    assert_text device_name

    # Step 3: Enable demo mode via the dropdown menu
    device = Device.find_by(name: device_name)
    assert device.present?, "Device should have been created"
    assert device.confirmed?, "Visionect device should be auto-confirmed"
    assert device.display_key.present?, "Visionect device should have a display key"

    # Already on the settings page; enable demo mode
    find("label", text: "Demo mode").find("input[type='checkbox']").check

    # Should redirect back, device now in demo mode
    device.reload
    assert device.demo_mode_enabled?, "Device should be in demo mode"

    # Step 4: Visit the token URL directly — should see demo content
    token_url = device.token_device_url(host: Capybara.current_session.server.base_url)
    visit token_url

    # Demo content includes "Spotted Towhee" (bird species) and "Tomorrow"
    assert_text "Spotted Towhee"
    assert_text "Tomorrow"
  end
end
