# frozen_string_literal: true

# Remembers the device record a pending registration superseded when the
# physical hardware was factory reset (Device#detach_hardware! frees the real
# MAC onto a placeholder and issues a fresh pairing code). If the reset hardware
# is then claimed by a DIFFERENT device (i.e. paired into a new account rather
# than re-paired to its original device card), the superseded device is deleted
# so it doesn't linger as an orphaned "needs pairing" card on the old account.
class AddDetachedDeviceToPendingDevices < ActiveRecord::Migration[8.1]
  def change
    add_reference :pending_devices, :detached_device,
      foreign_key: {to_table: :devices, on_delete: :nullify}
  end
end
