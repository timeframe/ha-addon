# frozen_string_literal: true

# Lets Timeframe customize events that can't be written back to their provider
# (Gmail-generated or locked Google events, meeting invites you don't organize,
# and fully read-only ICS/subscribed calendars). Such customizations are stored
# locally in calendar_event_customizations instead of being patched into the
# provider's event description.
#
# The row is keyed by (calendar_id, customization_key) rather than by a
# CalendarEvent id so it survives the local occurrence rows being deleted and
# recreated when an event scrolls out of and back into the sync window. The key
# is the event's series identity (Google master id / Apple base UID / otherwise
# the external id), so every occurrence of a recurring series shares one
# customization.
#
# provider_read_only records, per event, that the source refused edits even
# though the calendar itself is writable (currently set only for Google
# fromGmail/locked events); other read-only cases are covered by the calendar's
# writable? flag or by falling back locally when a provider write is forbidden.
class AddLocalEventCustomizations < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_event_customizations do |t|
      t.references :calendar, null: false, foreign_key: true
      t.string :customization_key, null: false
      t.string :icon
      t.text :title_override
      t.boolean :omit, default: false, null: false
      t.jsonb :only_tokens, default: [], null: false
      t.boolean :banner_enabled, default: false, null: false
      t.text :banner_message
      t.timestamps
    end

    add_index :calendar_event_customizations,
      [:calendar_id, :customization_key],
      unique: true,
      name: "index_event_customizations_on_calendar_and_key"

    add_column :calendar_events, :provider_read_only, :boolean, default: false, null: false
  end
end
