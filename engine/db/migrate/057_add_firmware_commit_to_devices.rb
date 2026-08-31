# frozen_string_literal: true

class AddFirmwareCommitToDevices < ActiveRecord::Migration[8.1]
  def change
    add_column :devices, :firmware_commit, :string
  end
end
