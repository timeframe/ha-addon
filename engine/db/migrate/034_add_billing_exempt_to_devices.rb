# frozen_string_literal: true

# Lets admins exempt an individual device from billing: exempt devices are not
# counted toward the account's billed subscription quantity and are never locked
# by the billing gate. Cloud-only behaviour; the column is harmless for the
# self-hosted ha-addon.
class AddBillingExemptToDevices < ActiveRecord::Migration[8.1]
  def change
    add_column :devices, :billing_exempt, :boolean, default: false, null: false
  end
end
