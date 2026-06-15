# frozen_string_literal: true

class AddBillingToAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :accounts, :trial_ends_on, :date
    add_column :accounts, :stripe_customer_id, :string
    add_column :accounts, :stripe_subscription_id, :string
    add_column :accounts, :subscription_status, :string
    add_column :accounts, :subscription_current_period_end, :datetime
    add_column :accounts, :stripe_base_item_id, :string
    add_column :accounts, :stripe_additional_item_id, :string

    add_index :accounts, :stripe_customer_id, unique: true
    add_index :accounts, :stripe_subscription_id, unique: true

    # Backfill trial_ends_on from each account's owner user's trial_started_on + 60 days.
    execute(<<~SQL.squish)
      UPDATE accounts
      SET trial_ends_on = users.trial_started_on + INTERVAL '60 days'
      FROM account_users
      JOIN users ON users.id = account_users.user_id
      WHERE account_users.account_id = accounts.id
        AND account_users.role = 'owner'
        AND users.trial_started_on IS NOT NULL
    SQL

    # Any account still without an end date gets a 60-day trial from today.
    execute(<<~SQL.squish)
      UPDATE accounts
      SET trial_ends_on = CURRENT_DATE + INTERVAL '60 days'
      WHERE trial_ends_on IS NULL
    SQL

    remove_column :users, :trial_started_on
  end

  def down
    add_column :users, :trial_started_on, :date

    remove_index :accounts, :stripe_subscription_id
    remove_index :accounts, :stripe_customer_id

    remove_column :accounts, :stripe_additional_item_id
    remove_column :accounts, :stripe_base_item_id
    remove_column :accounts, :subscription_current_period_end
    remove_column :accounts, :subscription_status
    remove_column :accounts, :stripe_subscription_id
    remove_column :accounts, :stripe_customer_id
    remove_column :accounts, :trial_ends_on
  end
end
