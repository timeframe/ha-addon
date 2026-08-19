# frozen_string_literal: true

require "test_helper"

class OnboardingFlowTest < ActiveSupport::TestCase
  def setup
    @user = test_user
    @account = @user.accounts.first
    @location = @account.locations.first
  end

  def flow(session = {})
    OnboardingFlow.new(@user, session)
  end

  def create_device(model)
    @location.devices.create!(name: "Dev-#{SecureRandom.hex(4)}", model: model, mac_address: SecureRandom.hex(6), confirmed_at: Time.current)
  end

  test "starts at create_device when there is no device" do
    assert_equal :create_device, flow.natural_step
    assert_equal :create_device, flow.current_step
    refute flow.complete?
  end

  test "a screenshotted device needs pairing and a layout" do
    device = create_device("reterminal_e1001")
    f = flow(onboarding_device_id: device.id)
    assert f.needs_pairing?
    assert f.needs_layout?
    refute f.paired?
    assert_equal %i[create_device pairing layout], f.visible_steps
    assert_equal :pairing, f.natural_step
  end

  test "a Visionect device needs no pairing or layout" do
    device = create_device("visionect_13")
    f = flow(onboarding_device_id: device.id)
    refute f.needs_pairing?
    refute f.needs_layout?
    assert_equal %i[create_device], f.visible_steps
    assert f.complete?
  end

  test "a Boox device needs pairing but no layout" do
    device = create_device("boox_mira")
    f = flow(onboarding_device_id: device.id)
    assert f.needs_pairing?
    refute f.needs_layout?
    assert_equal %i[create_device pairing], f.visible_steps
    assert_equal :pairing, f.natural_step
  end

  test "a sticky device needs pairing but no layout since it has one layout" do
    device = create_device("reterminal_sticky")
    f = flow(onboarding_device_id: device.id)
    assert f.needs_pairing?
    refute f.needs_layout?
    assert_equal %i[create_device pairing], f.visible_steps
    assert_equal :pairing, f.natural_step
  end

  test "advances to layout once paired and completes once a layout is chosen" do
    device = create_device("reterminal_e1001")
    PendingDevice.create!(claimed_device: device, mac_address: SecureRandom.hex(6))
    assert flow(onboarding_device_id: device.id).paired?
    assert_equal :layout, flow(onboarding_device_id: device.id).natural_step
    assert flow(onboarding_device_id: device.id, onboarding_layout_chosen: "trmnl").complete?
  end

  test "a back override returns an earlier step but never skips ahead" do
    device = create_device("reterminal_e1001")
    assert_equal :create_device, flow(onboarding_device_id: device.id, onboarding_step_override: "create_device").current_step
    assert_equal :pairing, flow(onboarding_device_id: device.id, onboarding_step_override: "layout").current_step
  end

  test "back navigation helpers" do
    device = create_device("reterminal_e1001")
    at_create = flow(onboarding_device_id: device.id, onboarding_step_override: "create_device")
    refute at_create.can_go_back?
    assert_nil at_create.previous_step

    at_pairing = flow(onboarding_device_id: device.id)
    assert at_pairing.can_go_back?
    assert_equal :create_device, at_pairing.previous_step
  end

  test "stepper marks complete, current, and upcoming steps" do
    device = create_device("reterminal_e1001")
    statuses = flow(onboarding_device_id: device.id).stepper.map { |step| step[:status] }
    assert_equal %i[complete current upcoming], statuses
  end

  test "with no device only the create step is shown" do
    f = flow
    assert_equal %i[create_device], f.visible_steps
    refute f.needs_pairing?
    refute f.needs_layout?
    refute f.can_go_back?
    assert_equal %i[current], f.stepper.map { |step| step[:status] }
  end

  test "a completed wizard has no current step and every step complete" do
    device = create_device("reterminal_e1001")
    PendingDevice.create!(claimed_device: device, mac_address: SecureRandom.hex(6))
    f = flow(onboarding_device_id: device.id, onboarding_layout_chosen: "trmnl")
    assert f.complete?
    refute f.can_go_back?
    assert_nil f.previous_step
    assert_equal %i[complete complete complete], f.stepper.map { |step| step[:status] }
  end

  test "an override for a step that is not visible is ignored" do
    device = create_device("visionect_13")
    assert_equal :done, flow(onboarding_device_id: device.id, onboarding_step_override: "pairing").current_step
  end

  test "an override navigates back from a completed wizard" do
    device = create_device("reterminal_e1001")
    PendingDevice.create!(claimed_device: device, mac_address: SecureRandom.hex(6))
    f = flow(onboarding_device_id: device.id, onboarding_layout_chosen: "trmnl", onboarding_step_override: "pairing")
    assert_equal :pairing, f.current_step
  end
end
