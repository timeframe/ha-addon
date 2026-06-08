# frozen_string_literal: true

require "test_helper"

class PendingDeviceTest < Minitest::Test
  def test_claimed_returns_false_when_unclaimed
    pd = PendingDevice.create!
    refute pd.claimed?
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
end
