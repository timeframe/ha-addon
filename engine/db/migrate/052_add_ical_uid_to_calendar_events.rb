# frozen_string_literal: true

# The provider's iCalendar UID (RFC 5545), stored alongside the per-copy
# `external_id` so the same underlying event synced into multiple calendars can
# be recognised and de-duplicated on the dashboard. Google exposes it as
# `iCalUID`, Microsoft Graph as `iCalUId`, and CalDAV/Apple carry it directly in
# the ICS `UID`. Unlike `external_id` (a per-calendar-copy sync key) the UID is
# shared across every copy of a shared/invited event within a provider.
class AddIcalUidToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_events, :ical_uid, :string
  end
end
