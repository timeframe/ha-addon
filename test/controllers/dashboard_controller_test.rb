# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  def teardown
    Warden.test_reset!
  end

  test "unauthenticated root auto-signs in and shows dashboard in single tenant mode" do
    User.where(email: "homeassistant@timeframe.local").destroy_all
    User.stub(:first, nil) do
      Account.stub(:first, nil) do
        get "/"
      end
    end
    assert_response :success
    assert_includes response.body, "Timeframe"
    user = User.find_by!(email: "homeassistant@timeframe.local")
    assert_equal user.id, request.env["warden"].user(:user).id
    assert user.accounts.first.locations.exists?
  end

  test "authenticated root shows dashboard" do
    login_as(test_user, scope: :user)
    get "/"
    assert_response :success
    assert_includes response.body, "Timeframe"
  end

  test "claim_device with invalid location shows error" do
    login_as(test_user, scope: :user)
    mac = "CC:DD:#{SecureRandom.hex(4).scan(/../).join(":").upcase}"
    pending = PendingDevice.create!(mac_address: mac, api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase)

    post "/claim_device", params: {
      pairing_code: pending.pairing_code,
      device_name: "Test Device",
      device_model: "trmnl_og",
      location_id: 999999
    }

    assert_response :redirect
    follow_redirect!
    assert_includes response.body, "Location not found"
  end
end
