# frozen_string_literal: true

# Moves billing from the account to the individual device: each device gets its
# own free-trial window and is billed only once purchased. Cloud-only
# behaviour; the columns are harmless for the self-hosted ha-addon.
class AddTrialAndPurchaseToDevices < ActiveRecord::Migration[8.1]
  def change
    add_column :devices, :trial_ends_on, :date
    add_column :devices, :purchased_at, :datetime
  end
end
