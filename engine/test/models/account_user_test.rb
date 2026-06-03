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
end
