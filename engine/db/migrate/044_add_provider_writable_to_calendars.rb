# frozen_string_literal: true

# Records whether a provider (Google/Microsoft) calendar can have events written
# to it at its source. The account-calendar sync jobs set this from provider
# metadata (Google accessRole owner/writer, Microsoft canEdit) so the dashboard
# only offers "Add event" for calendars that can actually be edited at the
# provider. Read-only calendars (e.g. Google holiday calendars, shared reader
# calendars) sync with this false. Defaults to true so calendars already synced
# before this column existed remain editable until the next list sync refines
# them; ICS calendars ignore this flag (they are always read-only).
class AddProviderWritableToCalendars < ActiveRecord::Migration[8.1]
  def change
    add_column :calendars, :provider_writable, :boolean, default: true, null: false
  end
end
