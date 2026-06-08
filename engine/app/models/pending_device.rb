# frozen_string_literal: true

class PendingDevice < ActiveRecord::Base
  EXPIRY_DURATION = 60.minutes

  belongs_to :claimed_device, class_name: "Device", optional: true

  encrypts :mac_address, deterministic: true
  encrypts :pairing_code, deterministic: true
  encrypts :api_key

  validates :pairing_code, uniqueness: true, allow_nil: true

  before_create :generate_pairing_code

  def claimed?
    claimed_device_id.present?
  end

  def expired?
    created_at < EXPIRY_DURATION.ago
  end

  def refresh!
    update!(
      pairing_code: SecureRandom.random_number(1_000_000).to_s.rjust(6, "0"),
      created_at: Time.current
    )
  end

  def self.find_active_by_code(code)
    device = find_by(pairing_code: code)
    return nil unless device

    if device.expired?
      device.destroy
      return nil
    end

    device
  end

  def claim!(location:, name:, model:)
    device = Device.create!(
      name: name,
      model: model,
      location: location,
      mac_address: mac_address,
      api_key: api_key,
      friendly_id: friendly_id,
      confirmed_at: Time.current
    )
    update!(claimed_device: device)
    device
  end

  private

  def generate_pairing_code
    self.pairing_code ||= SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
  end
end
