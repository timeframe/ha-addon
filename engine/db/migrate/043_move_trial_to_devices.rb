# frozen_string_literal: true

# Moves the free trial from the account to the device. Backfills existing data
# so current billing is preserved, then drops the now-unused account column.
# Cloud-only billing reads these; the changes are harmless for the self-hosted
# ha-addon (which never billed at the account level).
class MoveTrialToDevices < ActiveRecord::Migration[8.1]
  def up
    # Accounts with a subscription are billed today for their devices — mark
    # those devices purchased so the subscription quantity is unchanged.
    execute(<<~SQL)
      UPDATE devices SET purchased_at = NOW()
      WHERE purchased_at IS NULL
        AND location_id IN (
          SELECT l.id FROM locations l
          JOIN accounts a ON a.id = l.account_id
          WHERE a.stripe_subscription_id IS NOT NULL
        )
    SQL

    # Carry each account's legacy trial end date onto its devices.
    execute(<<~SQL)
      UPDATE devices d SET trial_ends_on = a.trial_ends_on
      FROM locations l
      JOIN accounts a ON a.id = l.account_id
      WHERE d.location_id = l.id
        AND d.trial_ends_on IS NULL
        AND a.trial_ends_on IS NOT NULL
    SQL

    # Anything still without a trial or purchase gets a fresh 30-day window
    # rather than locking immediately.
    execute(<<~SQL)
      UPDATE devices SET trial_ends_on = CURRENT_DATE + 30
      WHERE trial_ends_on IS NULL AND purchased_at IS NULL
    SQL

    remove_column :accounts, :trial_ends_on
  end

  def down
    add_column :accounts, :trial_ends_on, :date
  end
end
