class AddTrialStartedOnToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :trial_started_on, :date
  end
end
