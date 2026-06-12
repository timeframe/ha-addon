# frozen_string_literal: true

# This migration comes from active_analytics (originally 20210303094108)
class CreateActiveAnalyticsViewsPerDays < ActiveRecord::Migration[8.1]
  def up
    create_table :active_analytics_views_per_days do |t|
      t.string :site, null: false
      t.string :page, null: false
      t.date :date, null: false
      t.bigint :total, null: false, default: 1
      t.string :referrer_host
      t.string :referrer_path
      t.timestamps
    end
    add_index :active_analytics_views_per_days, [:date, :site, :page]
    add_index :active_analytics_views_per_days, [:date, :site, :referrer_host, :referrer_path],
      name: "index_views_per_days_on_date_site_referrer_host_referrer_path"
  end

  def down
    drop_table :active_analytics_views_per_days
  end
end
