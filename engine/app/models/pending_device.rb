# frozen_string_literal: true

class PendingDevice < ActiveRecord::Base
  EXPIRY_DURATION = 60.minutes

  # Aliases for firmware "Model" header values that do not already match a
  # Device SUPPORTED_MODELS key. reTerminal / TRMNL-X hardware sends the exact
  # underscore key (e.g. "reterminal_e1003"), which is matched directly in
  # model_key_for_firmware; only the short marketing aliases need mapping here.
  FIRMWARE_MODEL_MAP = {
    "og" => "trmnl_og",
    "x" => "trmnl_x"
  }.freeze

  belongs_to :claimed_device, class_name: "Device", optional: true
  # The device this registration superseded when the hardware was factory reset
  # (set by Device#detach_hardware!). Deleted once a *different* device claims
  # the reset hardware (see delete_superseded_device!).
  belongs_to :detached_device, class_name: "Device", optional: true

  encrypts :mac_address, deterministic: true
  encrypts :pairing_code, deterministic: true
  encrypts :api_key

  validates :pairing_code, uniqueness: true, allow_nil: true

  before_create :generate_pairing_code

  # Resolves a firmware "Model" header to a Device model key, or nil when the
  # value is blank/unrecognized. The firmware sends its DEVICE_MODEL string,
  # which for reTerminal hardware is the underscore form that already matches a
  # SUPPORTED_MODELS key (e.g. "reterminal_e1003"); human/spaced forms
  # ("reTerminal E1003") normalize to the same key. Short marketing aliases
  # ("og", "x") fall back to FIRMWARE_MODEL_MAP.
  def self.model_key_for_firmware(firmware_model)
    value = firmware_model.to_s.strip.downcase.presence
    return nil unless value

    underscored = value.tr(" ", "_")
    return underscored if Device::SUPPORTED_MODELS.key?(underscored)

    FIRMWARE_MODEL_MAP[value]
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

  # Extends the expiry window WITHOUT rotating the pairing code. A device that
  # is waiting to be paired polls /api/display every few seconds while showing
  # its code, so calling this on each poll keeps the on-screen code valid (and
  # keeps find_active_by_code from destroying it) for as long as the device
  # stays online — preventing the 60-minute expiry from stranding the device on
  # a dead code / permanent 401.
  def keep_alive!
    return if claimed?

    update_column(:created_at, Time.current)
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
    delete_superseded_device!(device)
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
    delete_superseded_device!(device)
    device
  end

  private

  # When a factory-reset device is claimed by a *different* device (e.g. paired
  # into a new account via onboarding rather than re-paired to its original
  # device card), delete the superseded record so it doesn't linger as an
  # orphaned "needs pairing" card on the previous account. Re-pairing the same
  # device (repair) keeps it, since claimed device == detached device.
  def delete_superseded_device!(claiming_device)
    return if detached_device_id.nil?
    return if detached_device_id == claiming_device.id

    Device.where(id: detached_device_id).destroy_all
  end

  def generate_pairing_code
    self.pairing_code ||= SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
  end
end
