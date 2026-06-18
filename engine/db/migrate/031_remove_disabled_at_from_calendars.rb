# frozen_string_literal: true

class RemoveDisabledAtFromCalendars < ActiveRecord::Migration[8.1]
  def up
    # Preserve current behaviour before dropping the enable/disable concept:
    # any calendar that was disabled should now be explicitly excluded from
    # every device in that calendar's account, so those calendars stop showing.
    execute(<<~SQL)
      UPDATE devices d
      SET excluded_calendar_identifiers = ARRAY(
        SELECT DISTINCT unnest(d.excluded_calendar_identifiers::text[] || disabled.ids)
      )::varchar[]
      FROM locations l
      JOIN (
        SELECT account_id, array_agg(id::text) AS ids
        FROM calendars
        WHERE disabled_at IS NOT NULL
        GROUP BY account_id
      ) disabled ON disabled.account_id = l.account_id
      WHERE d.location_id = l.id;
    SQL

    remove_column :calendars, :disabled_at
  end

  def down
    add_column :calendars, :disabled_at, :datetime
  end
end
