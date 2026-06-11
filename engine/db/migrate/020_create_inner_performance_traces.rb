# frozen_string_literal: true

class CreateInnerPerformanceTraces < ActiveRecord::Migration[8.1]
  def change
    create_table :inner_performance_traces do |t|
      t.references :event, type: :bigint, null: false, foreign_key: {to_table: :inner_performance_events}
      t.string :name
      t.string :type
      t.json :payload
      t.decimal :duration

      t.timestamps
    end
  end
end
