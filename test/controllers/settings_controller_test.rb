# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  def setup
    @account = test_user.accounts.first
    login_as(test_user, scope: :user)
  end

  def teardown
    Warden.test_reset!
  end

  test "show renders the units form" do
    get settings_path
    assert_response :success
    assert_includes response.body, "account[temperature_unit]"
    assert_includes response.body, "account[speed_unit]"
    assert_includes response.body, "account[precipitation_unit]"
  end

  test "update saves valid units to the account" do
    patch settings_path, params: {account: {temperature_unit: "C", speed_unit: "kph", precipitation_unit: "mm"}}
    assert_redirected_to settings_path
    @account.reload
    assert_equal "C", @account.temperature_unit
    assert_equal "kph", @account.speed_unit
    assert_equal "mm", @account.precipitation_unit
  end

  test "update ignores invalid unit values" do
    @account.update!(speed_unit: "mph")
    patch settings_path, params: {account: {temperature_unit: "C", speed_unit: "bogus"}}
    assert_redirected_to settings_path
    @account.reload
    assert_equal "C", @account.temperature_unit
    assert_equal "mph", @account.speed_unit
  end
end
