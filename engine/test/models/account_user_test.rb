# frozen_string_literal: true

require "test_helper"

class AccountUserTest < ActiveSupport::TestCase
  def setup
    suffix = SecureRandom.hex(4)
    @account = Account.create!(name: "Test-#{suffix}")
    @user_a = User.create!(email: "a-#{suffix}@example.com")
    @user_b = User.create!(email: "b-#{suffix}@example.com")
  end

  def test_default_role_is_owner
    au = AccountUser.create!(account: @account, user: @user_a)
    assert_equal "owner", au.role
    assert au.owner?
  end

  def test_only_one_owner_per_account
    AccountUser.create!(account: @account, user: @user_a)
    duplicate = AccountUser.new(account: @account, user: @user_b, role: "owner")
    refute duplicate.valid?
    assert_includes duplicate.errors[:role], "has already been taken"
  end

  def test_member_role_allowed_alongside_owner
    AccountUser.create!(account: @account, user: @user_a)
    member = AccountUser.new(account: @account, user: @user_b, role: "member")
    assert member.valid?
  end

  def test_role_must_be_in_allowed_list
    au = AccountUser.new(account: @account, user: @user_a, role: "stranger")
    refute au.valid?
    assert_includes au.errors[:role], "is not included in the list"
  end

  def test_destroying_last_membership_destroys_account
    AccountUser.create!(account: @account, user: @user_a)
    account_id = @account.id

    @account.account_users.first.destroy!

    refute Account.exists?(account_id), "Account should be destroyed when its last user leaves"
  end

  def test_destroying_one_of_many_memberships_keeps_account
    AccountUser.create!(account: @account, user: @user_a)
    AccountUser.create!(account: @account, user: @user_b, role: "member")
    account_id = @account.id

    @account.account_users.find_by(user: @user_b).destroy!

    assert Account.exists?(account_id), "Account should remain while other users belong to it"
  end

  def test_destroying_user_destroys_orphaned_account
    AccountUser.create!(account: @account, user: @user_a)
    account_id = @account.id

    @user_a.destroy!

    refute Account.exists?(account_id), "Account should be destroyed when its sole user is destroyed"
  end
end
