# frozen_string_literal: true

class AddRoleToAccountUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :account_users, :role, :string, default: "owner", null: false
    add_index :account_users, [:account_id, :role], unique: true, where: "role = 'owner'", name: "index_account_users_on_account_id_unique_owner"
  end
end
