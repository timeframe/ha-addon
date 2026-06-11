# frozen_string_literal: true

class CreateInnerPerformanceEvents < ActiveRecord::Migration[8.1]
  def change
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
end
