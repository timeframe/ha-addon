# frozen_string_literal: true

# Creates the legacy inner_performance_traces table (foreign key to
# inner_performance_events). Guarded so it runs cleanly on databases where the
# traces table already exists or the events table is absent — these transient
# telemetry tables are dropped by migrations 023/024 and so never appear in the
# final schema. Mirrors the defensive style of those drop migrations.
class CreateInnerPerformanceTraces < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:inner_performance_traces)
    # Can't add the foreign key if the referenced table was never created (e.g.
    # a database that skipped or never ran migration 019). The table is dropped
    # downstream anyway, so safely no-op.
    return unless table_exists?(:inner_performance_events)

    create_table :inner_performance_traces do |t|
      t.references :event, type: :bigint, null: false, foreign_key: {to_table: :inner_performance_events}
      t.string :name
      t.string :type
      t.json :payload
      t.decimal :duration

      t.timestamps
    end
  end

  def down
    drop_table :inner_performance_traces, if_exists: true
  end
end
