# frozen_string_literal: true

class CreateUptimeChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :uptime_checks do |t|
      t.datetime :recorded_at, null: false
      t.boolean :healthy, null: false, default: true
      t.timestamps
    end

    add_index :uptime_checks, :recorded_at, unique: true
  end
end
