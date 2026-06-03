# frozen_string_literal: true

class AccountUser < ActiveRecord::Base
  ROLES = %w[owner member].freeze
  OWNER = "owner"

  belongs_to :account
  belongs_to :user

  validates :role, inclusion: {in: ROLES}
  validates :role, uniqueness: {scope: :account_id, conditions: -> { where(role: OWNER) }}, if: :owner?

  def owner?
    role == OWNER
  end
end
