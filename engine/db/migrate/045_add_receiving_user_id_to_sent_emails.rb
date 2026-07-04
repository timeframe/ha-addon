# frozen_string_literal: true

# Records which user an outbound email was addressed to (matched by recipient
# address at send time) so the user's profile can list the emails they've
# received. Nullable: some messages (e.g. admin notifications) have no matching
# user, and the reference is cleared if the user is deleted.
class AddReceivingUserIdToSentEmails < ActiveRecord::Migration[8.1]
  def change
    add_reference :sent_emails, :receiving_user, null: true, foreign_key: {to_table: :users, on_delete: :nullify}
  end
end
