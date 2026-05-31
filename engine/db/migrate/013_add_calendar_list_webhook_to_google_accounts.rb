# frozen_string_literal: true

class AddCalendarListWebhookToGoogleAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :google_accounts, :calendar_list_webhook_channel_id, :string
    add_column :google_accounts, :calendar_list_webhook_resource_id, :string
    add_column :google_accounts, :calendar_list_webhook_expires_at, :datetime
    add_index :google_accounts, :calendar_list_webhook_channel_id, unique: true
  end
end
