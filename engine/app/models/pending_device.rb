# frozen_string_literal: true

class PendingDevice < ActiveRecord::Base
  EXPIRY_DURATION = 60.minutes

  # Maps the firmware "Model" header sent to /api/setup to a Device
  # SUPPORTED_MODELS key, so pairing can create the device as the right model and
  # suggest the matching templates. Unknown/omitted models stay nil (the pairing
  # flow falls back to a default or lets the user choose).
  FIRMWARE_MODEL_MAP = {
    "og" => "trmnl_og",
    "x" => "trmnl_x"
  }.freeze

  belongs_to :claimed_device, class_name: "Device", optional: true

  encrypts :mac_address, deterministic: true
  encrypts :pairing_code, deterministic: true
  encrypts :api_key

  validates :pairing_code, uniqueness: true, allow_nil: true

  before_create :generate_pairing_code

  # Resolves a firmware "Model" header to a Device model key, or nil when the
  # value is blank/unrecognized.
  def self.model_key_for_firmware(firmware_model)
    FIRMWARE_MODEL_MAP[firmware_model.to_s.strip.downcase.presence]
  end

  # The Device model key to use when claiming this pending device: the captured
  # firmware model when it maps to a supported model, otherwise nil.
  def resolved_model
    model if model.present? && Device::SUPPORTED_MODELS.key?(model)
  end

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

  def claim!(location:, name:, model: nil)
    device = Device.create!(
      name: name,
      model: model.presence || resolved_model || "reterminal_e1001",
      location: location,
      mac_address: mac_address,
      api_key: api_key,
      friendly_id: friendly_id,
      confirmed_at: Time.current
    )
    update!(claimed_device: device)
    device
  end

  # Bind a pre-created (unpaired) device to this pending registration by copying
  # the physical device's real credentials onto it. /api/display resolves devices
  # strictly by mac_address, so the placeholder mac must be overwritten with the
  # pending device's real mac_address (plus api_key/friendly_id) for the hardware
  # to reach the existing record.
  def link_to!(device)
    attrs = {
      mac_address: mac_address,
      api_key: api_key,
      friendly_id: friendly_id,
      confirmed_at: Time.current
    }
    # Adopt the firmware-reported model so the device is set up as the right type
    # (and gets the matching template suggestions).
    attrs[:model] = resolved_model if resolved_model.present?
    device.update!(attrs)
    update!(claimed_device: device)
    device
  end

  private

  def generate_pairing_code
    self.pairing_code ||= SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
  end
end
