# frozen_string_literal: true

# Records the Stripe Tax transaction created for a paid order (needed to issue a
# tax reversal on refund and to reconcile which orders have been reported) and
# the timestamp a refund was recorded, for period-accurate tax liability exports.
class AddTaxReportingToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :stripe_tax_transaction_id, :string
    add_column :orders, :refunded_at, :datetime
  end
end
