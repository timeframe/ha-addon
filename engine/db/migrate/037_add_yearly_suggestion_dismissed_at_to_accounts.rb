# frozen_string_literal: true

# Records when an account dismissed the dashboard suggestion to create
# Birthdays/Anniversaries calendars, so it isn't shown again.
class AddYearlySuggestionDismissedAtToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :yearly_suggestion_dismissed_at, :datetime
  end
end
