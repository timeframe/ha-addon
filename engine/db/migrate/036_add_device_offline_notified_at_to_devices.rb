# frozen_string_literal: true

# Records when an "offline for a day with a healthy battery" alert was last sent
# so the cloud emails the owner at most once per offline incident. Cleared when
# the device reconnects. Harmless for the self-hosted ha-addon.
class AddDeviceOfflineNotifiedAtToDevices < ActiveRecord::Migration[8.1]
  def change
    add_column :devices, :device_offline_notified_at, :datetime
  end
end
