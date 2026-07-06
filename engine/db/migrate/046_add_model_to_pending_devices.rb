# frozen_string_literal: true

# Records the device model reported by the firmware when it first contacts the
# server to get a pairing code (the /api/setup "Model" header, e.g. TRMNL OG vs
# X). Storing it on the pending registration lets the pairing flow create the
# device as the right model and suggest the matching templates, instead of
# asking the user to pick.
class AddModelToPendingDevices < ActiveRecord::Migration[8.1]
  def change
    add_column :pending_devices, :model, :string
  end
end
