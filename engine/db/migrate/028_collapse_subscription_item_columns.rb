# frozen_string_literal: true

# Switches billing from two separate prices (base + additional line items) to a
# single tiered price with one subscription line item whose quantity is the
# account's device count. Collapses the two item-id columns into one.
class CollapseSubscriptionItemColumns < ActiveRecord::Migration[8.1]
  def up
    rename_column :accounts, :stripe_base_item_id, :stripe_subscription_item_id
    remove_column :accounts, :stripe_additional_item_id
  end

  def down
    add_column :accounts, :stripe_additional_item_id, :string
    rename_column :accounts, :stripe_subscription_item_id, :stripe_base_item_id
  end
end
