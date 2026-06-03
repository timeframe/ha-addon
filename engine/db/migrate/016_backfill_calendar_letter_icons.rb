# frozen_string_literal: true

class BackfillCalendarLetterIcons < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:calendars)

    calendar_class = Class.new(ActiveRecord::Base) { self.table_name = "calendars" }
    calendar_class.where(icon: [nil, ""]).find_each do |cal|
      first = cal.name.to_s.strip[0]&.downcase
      icon = first&.match?(/[a-z]/) ? "mdi-alpha-#{first}" : "mdi-calendar"
      cal.update_column(:icon, icon)
    end
  end

  def down
    # Non-reversible data backfill.
  end
end
