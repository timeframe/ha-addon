# frozen_string_literal: true

class AddSubscriptionRenewalRemindedForToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :subscription_renewal_reminded_for, :datetime
  end
end
