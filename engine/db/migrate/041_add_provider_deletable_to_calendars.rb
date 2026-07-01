# frozen_string_literal: true

# Records whether a provider (Google/Microsoft) calendar can be deleted at its
# source. The account-calendar sync jobs set this from provider metadata
# (Google accessRole/primary, Microsoft canEdit/isDefaultCalendar) so the
# dashboard only offers "Delete calendar" for calendars that can actually be
# removed at the provider. Defaults to true so calendars already synced before
# this column existed remain deletable until the next list sync refines them;
# ICS/Apple/managed calendars ignore this flag (they are always deletable).
class AddProviderDeletableToCalendars < ActiveRecord::Migration[8.1]
  def change
    add_column :calendars, :provider_deletable, :boolean, default: true, null: false
  end
end
