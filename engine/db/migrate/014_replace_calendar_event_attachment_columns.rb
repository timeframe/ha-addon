# frozen_string_literal: true

class ReplaceCalendarEventAttachmentColumns < ActiveRecord::Migration[8.1]
  def change
    remove_column :calendar_events, :attachment_data, :text
    remove_column :calendar_events, :attachment_content_type, :string
    add_column :calendar_events, :has_attachment, :boolean, null: false, default: false
  end
end
