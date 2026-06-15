# frozen_string_literal: true

# Tracks whether an account's Stripe subscription is scheduled to cancel at the
# end of the current billing period. Lets us auto-resume a pending cancellation
# when a device is added back.
class AddSubscriptionCancelAtPeriodEndToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :subscription_cancel_at_period_end, :boolean, default: false, null: false
  end
end
