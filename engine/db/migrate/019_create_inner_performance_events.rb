# frozen_string_literal: true

# Creates the legacy inner_performance_events table. Guarded with
# `unless table_exists?` so it runs cleanly whether or not the table is already
# present (the engine and its migrations are shared by multiple apps, and these
# transient telemetry tables are later dropped by migrations 023/024 and so are
# absent from the final schema).
class CreateInnerPerformanceEvents < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:inner_performance_events)

    create_table :inner_performance_events, force: :cascade do |t|
      t.string :event
      t.string :name
      t.decimal :duration
      t.decimal :db_runtime
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.text :properties
      t.string :type
    end
  end

  def down
    drop_table :inner_performance_events, if_exists: true
  end
end
