# frozen_string_literal: true

class CreateHealthProbes < ActiveRecord::Migration[8.1]
  def change
    create_table :health_probes do |t|
      t.string :key, null: false
      t.boolean :successful, null: false, default: true
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :checked_at, null: false
      t.jsonb :details
      t.timestamps
    end

    add_index :health_probes, :key, unique: true
  end
end
