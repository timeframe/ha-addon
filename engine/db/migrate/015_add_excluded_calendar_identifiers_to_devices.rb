# frozen_string_literal: true

class AddExcludedCalendarIdentifiersToDevices < ActiveRecord::Migration[8.1]
  def change
    add_column :devices, :excluded_calendar_identifiers, :string, array: true, default: [], null: false
  end
end
