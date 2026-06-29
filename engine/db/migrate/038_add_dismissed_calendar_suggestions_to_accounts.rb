# frozen_string_literal: true

# Per-kind dismissals for the managed-calendar suggestions (birthdays,
# anniversaries, meals), replacing the single yearly_suggestion_dismissed_at.
class AddDismissedCalendarSuggestionsToAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :accounts, :dismissed_calendar_suggestions, :jsonb, default: [], null: false
    execute(<<~SQL.squish)
      UPDATE accounts
      SET dismissed_calendar_suggestions = '["birthdays", "anniversaries"]'
      WHERE yearly_suggestion_dismissed_at IS NOT NULL
    SQL
    remove_column :accounts, :yearly_suggestion_dismissed_at
  end

  def down
    add_column :accounts, :yearly_suggestion_dismissed_at, :datetime
    remove_column :accounts, :dismissed_calendar_suggestions
  end
end
