# frozen_string_literal: true

# Persists a copy of every outbound email so admins can review what was sent.
# The body is encrypted at rest because some emails (e.g. login codes) contain
# sensitive content.
class CreateSentEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :sent_emails do |t|
      t.text :to
      t.text :from
      t.text :cc
      t.text :bcc
      t.text :subject
      t.text :body
      t.string :content_type
      t.string :message_id
      t.string :mailer
      t.string :mail_action
      t.datetime :delivered_at, null: false

      t.timestamps
    end

    add_index :sent_emails, :delivered_at
    add_index :sent_emails, :mailer
  end
end
