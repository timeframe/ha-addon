# frozen_string_literal: true

# Storefront: products sold in the shop, customer orders, and their line items.
# Shipping address fields on orders hold customer PII and are encrypted at rest
# by the cloud-only Order model. These tables live in the shared engine schema
# (migrations may only live here) but are exercised solely by the cloud app.
class CreateStorefrontTables < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.integer :price_cents, null: false
      t.string :stripe_tax_code, null: false, default: "txcd_99999999"
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :products, :slug, unique: true
    add_index :products, :active

    create_table :orders do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.text :email, null: false
      t.string :status, null: false, default: "pending"
      t.string :currency, null: false, default: "usd"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :shipping_method
      t.string :stripe_payment_intent_id
      t.string :stripe_tax_calculation_id
      t.string :tracking_number
      t.boolean :payment_method_saved, null: false, default: false
      t.text :ship_name
      t.text :ship_line1
      t.text :ship_line2
      t.text :ship_city
      t.text :ship_state
      t.text :ship_postal_code
      t.text :ship_country
      t.datetime :paid_at
      t.datetime :fulfilled_at

      t.timestamps
    end
    add_index :orders, :account_id
    add_index :orders, :user_id
    add_index :orders, :status
    add_index :orders, :stripe_payment_intent_id, unique: true

    create_table :order_items do |t|
      t.bigint :order_id, null: false
      t.bigint :product_id, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false
      t.string :product_name, null: false

      t.timestamps
    end
    add_index :order_items, :order_id
    add_index :order_items, :product_id

    add_foreign_key :orders, :accounts, on_delete: :cascade
    add_foreign_key :orders, :users, on_delete: :nullify
    add_foreign_key :order_items, :orders, on_delete: :cascade
    add_foreign_key :order_items, :products
  end
end
