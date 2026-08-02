# frozen_string_literal: true

# Records when a calendar provider account's OAuth grant was revoked/expired
# (invalid_grant) so the cloud can stop syncing it, exclude it from the status
# health check, and email the owner to reconnect at most once per incident.
# Cleared when the account is reconnected. Harmless for the self-hosted ha-addon.
class AddSyncDisabledToProviderAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :google_accounts, :sync_disabled_at, :datetime
    add_column :google_accounts, :sync_disabled_reason, :string
    add_column :google_accounts, :sync_disabled_notified_at, :datetime

    add_column :microsoft_accounts, :sync_disabled_at, :datetime
    add_column :microsoft_accounts, :sync_disabled_reason, :string
    add_column :microsoft_accounts, :sync_disabled_notified_at, :datetime
  end
end
