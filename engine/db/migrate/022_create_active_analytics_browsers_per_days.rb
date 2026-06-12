# frozen_string_literal: true

# This migration comes from active_analytics (originally 20240823150626)
class CreateActiveAnalyticsBrowsersPerDays < ActiveRecord::Migration[8.1]
  def change
    create_table :active_analytics_browsers_per_days do |t|
      t.string :site, null: false
      t.string :name, null: false
      t.string :version, null: false
      t.date :date, null: false
      t.bigint :total, null: false, default: 1
      t.timestamps
    end
    add_index :active_analytics_browsers_per_days, [:date, :site, :name, :version]
  end
end
