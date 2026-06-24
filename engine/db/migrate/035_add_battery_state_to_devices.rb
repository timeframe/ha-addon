# frozen_string_literal: true

# Tracks battery charging state and a hysteresis-backed low-battery warning flag
# so the device screen can show a recharge warning / charging indicator and the
# cloud can alert on low batteries. Harmless for the self-hosted ha-addon.
class AddBatteryStateToDevices < ActiveRecord::Migration[8.1]
  def change
    add_column :devices, :charging, :boolean, default: false, null: false
    add_column :devices, :low_battery_warning, :boolean, default: false, null: false
  end
end
