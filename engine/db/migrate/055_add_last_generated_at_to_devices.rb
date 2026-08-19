# frozen_string_literal: true

class AddLastGeneratedAtToDevices < ActiveRecord::Migration[8.1]
  def up
    add_column :devices, :last_generated_at, :datetime
    execute "UPDATE devices SET last_generated_at = cached_image_at WHERE cached_image_at IS NOT NULL"
  end

  def down
    remove_column :devices, :last_generated_at
  end
end
