# frozen_string_literal: true

# Stores the per-event countdown length (number of days before the event to
# start showing a "(in Xd)" all-day reminder) on the local customization, so a
# countdown configured on a read-only calendar survives re-sync just like the
# icon/title/omit/banner customizations. Writable calendars keep the same value
# in the event description via the `timeframe-countdown:N` token.
class AddCountdownDaysToEventCustomizations < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_event_customizations, :countdown_days, :integer
  end
end
