# frozen_string_literal: true

class AccountUser < ActiveRecord::Base
  ROLES = %w[owner member].freeze
  OWNER = "owner"
  MEMBER = "member"

  belongs_to :account
  belongs_to :user

  validates :role, inclusion: {in: ROLES}
  validates :role, uniqueness: {scope: :account_id, conditions: -> { where(role: OWNER) }}, if: :owner?

  after_destroy :destroy_account_if_orphaned

  def owner?
    role == OWNER
  end

  private

  def destroy_account_if_orphaned
    return unless account
    return if account.destroyed? || account.marked_for_destruction?
    account.destroy if account.account_users.reload.empty?
  end
end
