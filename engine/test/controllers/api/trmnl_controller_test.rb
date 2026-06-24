# frozen_string_literal: true

require "test_helper"

class Api::TrmnlControllerTest < ActionDispatch::IntegrationTest
  def setup
    PendingDevice.destroy_all
    Device.where(model: "trmnl_og").destroy_all
  end

  # --- /api/setup ---

  test "setup creates a pending device" do
    get "/api/setup", headers: {"ID" => "AA:BB:CC:DD:EE:FF"}

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 200, json["status"]
    assert json["api_key"].present?
    assert json["friendly_id"].present?
    assert_nil json["image_url"]
    assert_match(/Enter this code/, json["message"])

    pending = PendingDevice.find_by(mac_address: "AA:BB:CC:DD:EE:FF")
    assert pending.present?
  end

  test "setup returns api_key for confirmed device" do
    device = create_trmnl_device!(mac: "AA:BB:CC:DD:EE:FF")

    get "/api/setup", headers: {"ID" => "AA:BB:CC:DD:EE:FF"}

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 200, json["status"]
    assert_equal device.api_key, json["api_key"]
    assert_equal device.friendly_id, json["friendly_id"]
    assert_nil json["image_url"]
    assert_equal "Welcome to Timeframe", json["message"]
  end

  test "setup returns existing pending device for duplicate MAC" do
    get "/api/setup", headers: {"ID" => "AA:BB:CC:DD:EE:FF"}
    first_id = JSON.parse(response.body)["friendly_id"]

    get "/api/setup", headers: {"ID" => "AA:BB:CC:DD:EE:FF"}
    second_id = JSON.parse(response.body)["friendly_id"]

    assert_equal first_id, second_id
    assert_equal 1, PendingDevice.where(mac_address: "AA:BB:CC:DD:EE:FF").count
  end

  test "setup updates firmware_version from headers for confirmed device" do
    device = create_trmnl_device!(mac: "AA:BB:CC:DD:EE:FF")

    get "/api/setup", headers: {"ID" => "AA:BB:CC:DD:EE:FF", "FW-Version" => "1.8.1"}

    assert_response :success
    device.reload
    assert_equal "1.8.1", device.firmware_version
  end

  test "setup returns bad request without MAC address" do
    get "/api/setup"
    assert_response :bad_request
  end

  # --- /api/display ---

  test "display succeeds without access token" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {"ID" => device.mac_address}
      assert_response :success
    end
  end

  test "display succeeds with empty access token" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {"ID" => device.mac_address, "ACCESS_TOKEN" => ""}
      assert_response :success
    end
  end

  test "display returns 401 with wrong access token" do
    device = create_trmnl_device!

    get "/api/display", headers: {"ID" => device.mac_address, "ACCESS_TOKEN" => "wrong"}
    assert_response :unauthorized
  end

  test "display returns 401 without MAC address" do
    get "/api/display", headers: {"ACCESS_TOKEN" => "something"}
    assert_response :unauthorized
  end

  test "display returns 401 for unknown MAC" do
    get "/api/display", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    assert_response :unauthorized
  end

  test "display returns 202 status in body for pending device MAC" do
    get "/api/setup", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    assert_response :success

    get "/api/display", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 202, json["status"]
  end

  test "display returns image data for valid device" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Battery-Voltage" => "4.1",
        "FW-Version" => "1.8.1",
        "RSSI" => "-69"
      }

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal 0, json["status"]
      assert_match(/\Adisplay-.*\.png\z/, json["filename"])
      assert json["image_url"].include?("/signed_screenshot/")
      assert_equal 0, json["image_url_timeout"]
      assert_equal 900, json["refresh_rate"]
      assert_equal "sleep", json["special_function"]
      assert_equal false, json["reset_firmware"]
      assert_equal false, json["update_firmware"]
      assert_nil json["firmware_url"]
      assert_equal "default", json["temperature_profile"]

      device.reload
      assert device.last_connection_at.present?
      assert_equal 92, device.battery_level
      assert_equal "1.8.1", device.firmware_version
      assert_equal(-69, device.rssi)
    end
  end

  test "display skips refresh when cached image exists" do
    device = create_trmnl_device!
    device.update!(cached_image: "existingbase64", cached_image_at: Time.current)

    get "/api/display", headers: {"ID" => device.mac_address, "ACCESS_TOKEN" => device.api_key}

    assert_response :success
  end

  test "display prefers Percent-Charged and records charging state" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Battery-Voltage" => "3.6",
        "Percent-Charged" => "63",
        "Battery-Charging" => "1"
      }
    end

    device.reload
    assert_equal 63, device.battery_level
    assert device.charging?
    refute device.low_battery_warning?
  end

  test "display sets low battery warning when discharging below threshold" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Percent-Charged" => "20",
        "USB-Connected" => "false"
      }
    end

    device.reload
    assert_equal 20, device.battery_level
    refute device.charging?
    assert device.low_battery_warning?
  end

  test "display clears low battery warning once charging" do
    device = create_trmnl_device!
    device.update!(low_battery_warning: true)

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Percent-Charged" => "20",
        "Battery-Charging" => "true"
      }
    end

    device.reload
    assert device.charging?
    refute device.low_battery_warning?
  end

  test "display clears the offline notification flag on reconnect" do
    device = create_trmnl_device!
    device.update!(device_offline_notified_at: 2.days.ago)

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {"ID" => device.mac_address, "ACCESS_TOKEN" => device.api_key}
    end

    device.reload
    assert device.last_connection_at.present?
    assert_nil device.device_offline_notified_at
  end

  # --- /api/log ---

  test "log returns 204 with valid credentials" do
    device = create_trmnl_device!

    post "/api/log",
      params: {logs: [{message: "test"}]}.to_json,
      headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Content-Type" => "application/json"
      }

    assert_response :no_content
  end

  test "log returns 204 with empty access token" do
    device = create_trmnl_device!

    post "/api/log",
      params: {logs: [{message: "test"}]}.to_json,
      headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => "",
        "Content-Type" => "application/json"
      }

    assert_response :no_content
  end

  test "log returns 401 with invalid credentials" do
    device = create_trmnl_device!

    post "/api/log",
      params: {logs: [{message: "test"}]}.to_json,
      headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => "wrong",
        "Content-Type" => "application/json"
      }

    assert_response :unauthorized
  end

  test "display returns confirmation data for unconfirmed device" do
    device = Device.create!(location: test_location,
      name: "Pending TRMNL",
      model: "trmnl_og",
      mac_address: "AA:BB:CC:11:22:33",
      confirmation_code: "ABC123")

    get "/api/display", headers: {"ID" => device.mac_address}

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0, json["status"]
    assert_match(/confirmation/, json["filename"])
    assert_equal 30, json["refresh_rate"]
    assert_equal false, json["reset_firmware"]
    assert_equal false, json["update_firmware"]
    assert_nil json["firmware_url"]
    assert_equal "default", json["temperature_profile"]
  end

  private

  def create_trmnl_device!(mac: "11:22:33:44:55:66")
    Device.create!(location: test_location,
      name: "Test TRMNL #{mac}",
      model: "trmnl_og",
      mac_address: mac,
      confirmed_at: Time.current,
      confirmation_code: nil)
  end
end
