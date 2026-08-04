# frozen_string_literal: true

require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  def setup
    @account = test_user.accounts.first
    @location = @account.locations.first
    login_as(test_user, scope: :user)
  end

  def teardown
    Warden.test_reset!
  end

  def pending_device
    PendingDevice.create!(mac_address: SecureRandom.hex(6), api_key: SecureRandom.hex(16))
  end

  test "show renders the create-device step with a model selector" do
    get onboarding_path
    assert_response :success
    assert_includes response.body, "Set up your device"
    assert_includes response.body, "device_model"
  end

  test "create_device creates a device" do
    assert_difference -> { Device.count }, 1 do
      post onboarding_device_path, params: {device_name: "Kitchen #{SecureRandom.hex(3)}", device_model: "reterminal_e1001"}
    end
    assert_redirected_to onboarding_path
  end

  test "create_device rejects an unknown model" do
    post onboarding_device_path, params: {device_name: "X", device_model: "nope"}
    assert_redirected_to onboarding_path
    follow_redirect!
    assert_includes response.body, "Pick a device model"
  end

  test "create_device renames the wizard device on a second submit" do
    post onboarding_device_path, params: {device_name: "First #{SecureRandom.hex(3)}", device_model: "reterminal_e1001"}
    device = Device.order(:created_at).last
    renamed = "Second #{SecureRandom.hex(3)}"
    assert_no_difference -> { Device.count } do
      post onboarding_device_path, params: {device_name: renamed, device_model: "reterminal_e1001"}
    end
    assert_equal renamed, device.reload.name
  end

  test "create_device reports a validation error" do
    name = "Taken #{SecureRandom.hex(3)}"
    @location.devices.create!(name: name, model: "reterminal_e1001", mac_address: SecureRandom.hex(6), confirmed_at: Time.current)
    post onboarding_device_path, params: {device_name: name, device_model: "reterminal_e1001"}
    assert_redirected_to onboarding_path
    follow_redirect!
    assert_includes response.body, "has already been taken"
  end

  test "pair links a pending device to the wizard device" do
    post onboarding_device_path, params: {device_name: "Pairme #{SecureRandom.hex(3)}", device_model: "reterminal_e1001"}
    device = Device.order(:created_at).last
    pending = pending_device
    post onboarding_pair_path, params: {pairing_code: pending.pairing_code}
    assert_redirected_to onboarding_path
    assert_equal device.id, pending.reload.claimed_device_id
  end

  test "pair works for a non-screenshotted device" do
    post onboarding_device_path, params: {device_name: "Boox #{SecureRandom.hex(3)}", device_model: "boox_mira"}
    device = Device.order(:created_at).last
    pending = pending_device
    post onboarding_pair_path, params: {pairing_code: pending.pairing_code}
    assert_equal device.id, pending.reload.claimed_device_id
  end

  test "pair rejects an invalid code" do
    post onboarding_device_path, params: {device_name: "P #{SecureRandom.hex(3)}", device_model: "reterminal_e1001"}
    post onboarding_pair_path, params: {pairing_code: "000000"}
    assert_redirected_to onboarding_path
    follow_redirect!
    assert_includes response.body, "Invalid or expired"
  end

  test "pair without a wizard device redirects to onboarding" do
    post onboarding_pair_path, params: {pairing_code: "123456"}
    assert_redirected_to onboarding_path
  end

  test "set_layout sets the template and completes the wizard" do
    post onboarding_device_path, params: {device_name: "Layout #{SecureRandom.hex(3)}", device_model: "reterminal_e1001"}
    device = Device.order(:created_at).last
    post onboarding_pair_path, params: {pairing_code: pending_device.pairing_code}
    patch onboarding_layout_path, params: {display_template: "two_day"}
    assert_redirected_to onboarding_path
    assert_equal "two_day", device.reload.display_template

    get onboarding_path
    assert_response :redirect
  end

  test "set_layout rejects an invalid template" do
    post onboarding_device_path, params: {device_name: "L2 #{SecureRandom.hex(3)}", device_model: "reterminal_e1001"}
    post onboarding_pair_path, params: {pairing_code: pending_device.pairing_code}
    patch onboarding_layout_path, params: {display_template: "bogus"}
    assert_redirected_to onboarding_path
    follow_redirect!
    assert_includes response.body, "Pick a valid layout"
  end

  test "back returns to the previous step" do
    post onboarding_device_path, params: {device_name: "Back #{SecureRandom.hex(3)}", device_model: "reterminal_e1001"}
    post onboarding_back_path
    assert_redirected_to onboarding_path
    follow_redirect!
    assert_includes response.body, "device_model"
  end

  test "back at the first step is a no-op" do
    post onboarding_back_path
    assert_redirected_to onboarding_path
  end
end
