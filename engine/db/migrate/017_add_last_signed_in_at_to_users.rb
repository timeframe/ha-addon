class AddLastSignedInAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_signed_in_at, :datetime
  end
end
