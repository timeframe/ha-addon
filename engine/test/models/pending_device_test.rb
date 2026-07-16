# frozen_string_literal: true

require "test_helper"

class PendingDeviceTest < Minitest::Test
  def test_claimed_returns_false_when_unclaimed
    pd = PendingDevice.create!
    refute pd.claimed?
  end

  def test_model_key_for_firmware_maps_known_models
    assert_equal "trmnl_og", PendingDevice.model_key_for_firmware("og")
    assert_equal "trmnl_x", PendingDevice.model_key_for_firmware("X")
    assert_equal "reterminal_e1001", PendingDevice.model_key_for_firmware("reTerminal E1001")
    assert_equal "reterminal_e1003", PendingDevice.model_key_for_firmware("reTerminal E1003")
    assert_nil PendingDevice.model_key_for_firmware("waveshare")
    assert_nil PendingDevice.model_key_for_firmware(nil)
    assert_nil PendingDevice.model_key_for_firmware("")
  end

  # The firmware sends its DEVICE_MODEL string verbatim, which for reTerminal
  # hardware is the underscore form. These must resolve to the matching model
  # key so pairing sets the right model (and template suggestions).
  def test_model_key_for_firmware_maps_underscore_firmware_values
    assert_equal "reterminal_e1001", PendingDevice.model_key_for_firmware("reterminal_e1001")
    assert_equal "reterminal_e1003", PendingDevice.model_key_for_firmware("reterminal_e1003")
    assert_equal "trmnl_x", PendingDevice.model_key_for_firmware("trmnl_x")
  end

  def test_resolved_model_only_returns_supported_models
    assert_equal "trmnl_x", PendingDevice.new(model: "trmnl_x").resolved_model
    assert_nil PendingDevice.new(model: "bogus").resolved_model
    assert_nil PendingDevice.new(model: nil).resolved_model
  end

  def test_claim_uses_the_captured_model_when_none_passed
    mac = "AB:#{SecureRandom.hex(5).scan(/../).join(":").upcase}"
    pd = PendingDevice.create!(mac_address: mac, api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase, model: "trmnl_x")
    device = pd.claim!(location: test_location, name: "Claimed #{SecureRandom.hex(4)}")
    assert_equal "trmnl_x", device.model
  end

  def test_link_to_adopts_the_captured_model
    mac = "AC:#{SecureRandom.hex(5).scan(/../).join(":").upcase}"
    pd = PendingDevice.create!(mac_address: mac, api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase, model: "trmnl_x")
    device = test_location.devices.create!(name: "Placeholder #{SecureRandom.hex(4)}", model: "reterminal_e1001", mac_address: SecureRandom.hex(6), confirmed_at: Time.current)

    pd.link_to!(device)

    assert_equal "trmnl_x", device.reload.model
    assert_equal mac, device.mac_address
  end

  def test_claimed_returns_true_when_claimed
    mac = "EE:FF:#{SecureRandom.hex(4).scan(/../).join(":").upcase}"
    pd = PendingDevice.create!(mac_address: mac, api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase)
    pd.claim!(location: test_location, name: "Claimed #{SecureRandom.hex(4)}", model: "trmnl_og")
    assert pd.claimed?
  end

  def test_expired_returns_false_when_fresh
    pd = PendingDevice.create!
    refute pd.expired?
  end

  def test_expired_returns_true_after_expiry
    pd = PendingDevice.create!
    pd.update_column(:created_at, 65.minutes.ago)
    assert pd.expired?
  end

  def test_find_active_by_code_returns_device
    pd = PendingDevice.create!
    found = PendingDevice.find_active_by_code(pd.pairing_code)
    assert_equal pd.id, found.id
  end

  def test_find_active_by_code_returns_nil_for_unknown
    assert_nil PendingDevice.find_active_by_code("000000")
  end

  def test_find_active_by_code_destroys_and_returns_nil_for_expired
    pd = PendingDevice.create!
    pd.update_column(:created_at, 65.minutes.ago)
    assert_nil PendingDevice.find_active_by_code(pd.pairing_code)
    refute PendingDevice.exists?(pd.id)
  end

  def test_refresh_generates_new_code_and_resets_created_at
    pd = PendingDevice.create!
    old_code = pd.pairing_code
    pd.update_column(:created_at, 65.minutes.ago)
    assert pd.expired?

    pd.refresh!
    pd.reload

    refute pd.expired?
    refute_equal old_code, pd.pairing_code
  end

  def test_keep_alive_resets_expiry_without_changing_the_code
    pd = PendingDevice.create!
    old_code = pd.pairing_code
    pd.update_column(:created_at, 65.minutes.ago)
    assert pd.expired?

    pd.keep_alive!
    pd.reload

    refute pd.expired?
    assert_equal old_code, pd.pairing_code
  end

  def test_keep_alive_is_a_noop_for_a_claimed_device
    mac = "AD:#{SecureRandom.hex(5).scan(/../).join(":").upcase}"
    pd = PendingDevice.create!(mac_address: mac, api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase)
    pd.claim!(location: test_location, name: "Claimed #{SecureRandom.hex(4)}", model: "trmnl_og")
    pd.update_column(:created_at, 65.minutes.ago)

    pd.keep_alive!

    assert pd.reload.expired?
  end

  def test_link_to_copies_credentials_onto_existing_device
    device = test_location.devices.create!(
      name: "Pre #{SecureRandom.hex(4)}",
      model: "reterminal_e1001",
      mac_address: SecureRandom.hex(6),
      confirmed_at: Time.current
    )
    mac = "AA:BB:#{SecureRandom.hex(4).scan(/../).join(":").upcase}"
    api_key = SecureRandom.hex(16)
    friendly = SecureRandom.alphanumeric(6).upcase
    pd = PendingDevice.create!(mac_address: mac, api_key: api_key, friendly_id: friendly)

    pd.link_to!(device)
    device.reload

    assert_equal mac, device.mac_address
    assert_equal api_key, device.api_key
    assert_equal friendly, device.friendly_id
    assert device.confirmed_at.present?
  end

  def test_link_to_sets_claimed_device_and_returns_device
    device = test_location.devices.create!(
      name: "Pre #{SecureRandom.hex(4)}",
      model: "reterminal_e1001",
      mac_address: SecureRandom.hex(6),
      confirmed_at: Time.current
    )
    pd = PendingDevice.create!(
      mac_address: "CC:DD:#{SecureRandom.hex(4).scan(/../).join(":").upcase}",
      api_key: SecureRandom.hex(16),
      friendly_id: SecureRandom.alphanumeric(6).upcase
    )

    result = pd.link_to!(device)
    pd.reload

    assert_equal device.id, result.id
    assert_equal device.id, pd.claimed_device_id
    assert pd.claimed?
  end
end
