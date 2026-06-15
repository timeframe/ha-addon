# frozen_string_literal: true

class AddSubscriptionGraceToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :subscription_grace_until, :datetime
  end
end
