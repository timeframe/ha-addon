# frozen_string_literal: true

require_relative "../system_test_helper" unless defined?(ApplicationSystemTestCase)

class DeviceSettingsDeleteTest < ApplicationSystemTestCase
  def setup
    super
    PendingDevice.destroy_all
    Device.destroy_all
  end

  test "deleting a device from settings does not 404" do
    visit "/test_sign_in"
    assert_text "Add Device"

    device_name = "Delete Me #{SecureRandom.hex(4)}"
    form = first("#add-device-form")
    within(form) do
      fill_in "device_name", with: device_name
      select "Visionect Place & Play 13\"", from: "device_model"
      click_button "Add Device"
    end

    assert_text device_name

    # Adding a device now lands directly on its settings page. Visionect devices
    # render a second name_confirmation field (Regenerate URL), so scope to the
    # danger zone card to disambiguate the delete confirmation.
    within(".card.border-danger") do
      fill_in "name_confirmation", with: device_name
      click_button "Delete Device"
    end

    assert_current_path "/"
    assert_no_text "Routing Error"
    assert_no_selector ".card-header", text: device_name
  end

  test "fresh device cards show concise updated copy" do
    visit "/test_sign_in"
    assert_text "Add Device"

    device_name = "Fresh Device #{SecureRandom.hex(4)}"
    form = first("#add-device-form")
    within(form) do
      fill_in "device_name", with: device_name
      select "Visionect Place & Play 13\"", from: "device_model"
      click_button "Add Device"
    end

    assert_text device_name
    visit "/"
    assert_text "Updated <1m ago"
    assert_no_text "Updated less than a minute ago"
  end
end
