# frozen_string_literal: true

require_relative "../system_test_helper" unless defined?(ApplicationSystemTestCase)

class BooxMiraProSetupFlowTest < ApplicationSystemTestCase
  def setup
    super
    PendingDevice.destroy_all
    Device.destroy_all
  end

  test "pair a Boox Mira Pro 25 inch from setup through dashboard and verify display content" do
    # Step 1: Visit /pair as an unauthenticated device to get a pairing code
    visit "/pair"
    assert_text "Timeframe"
    assert_text "Enter this pairing code on your Timeframe dashboard"

    pairing_code = find(".display-1").text.strip

    # Step 2: Sign in as a user (creates test user, account, and location)
    visit "/test_sign_in"
    assert_text "Add Device"

    # Step 3: Fill in the add device form to pair the Boox Mira Pro
    device_name = "Living Room Mira #{SecureRandom.hex(4)}"
    form = first("#add-device-form")
    within(form) do
      fill_in "device_name", with: device_name
      select "Boox Mira Pro 25.3\"", from: "device_model"

      # Pairing code field appears after selecting a model that needs pairing
      fill_in "pairing_code", with: pairing_code

      click_button "Add Device"
    end

    assert_text device_name
    assert_text "paired successfully"

    # Step 4: Verify the device was created correctly
    device = Device.find_by(name: device_name)
    assert device.present?, "Device should have been created"
    assert_equal "boox_mira_pro", device.model
    assert device.confirmed?, "Device should be confirmed after pairing"

    # Step 5: Enable demo mode so the display has content (already on settings page)
    within(first(".form-check", text: "Demo Mode")) do
      find("input[type='checkbox'][role='switch']").check
    end

    device.reload
    assert device.demo_mode_enabled?, "Device should be in demo mode"

    # Step 6: Visit the device display page and verify it renders the mira template with content
    visit account_location_device_path(device.account, device.location, device)
    assert_text "Spotted Towhee"
    assert_text "Tycho"
  end
end
