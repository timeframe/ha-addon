# frozen_string_literal: true

# Caches the recurrence rule (RRULE body) of a recurring event's series on the
# local mirror so the dashboard can show/edit recurrence without fetching it
# from the provider every time.
class AddRecurrenceRuleToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_events, :recurrence_rule, :string
  end
end
