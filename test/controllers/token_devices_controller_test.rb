# frozen_string_literal: true

require "test_helper"

class TokenDevicesControllerTest < ActionDispatch::IntegrationTest
  def setup
    Rails.cache.delete(DEPLOY_TIME.to_s + HomeAssistantApi::WEATHER_DOMAIN)
    @account = test_user.accounts.first
    location = @account.locations.first
    @device = Device.find_or_create_by!(name: "test-token-display", model: "visionect_13") do |d|
      d.location = location
    end
    @device.update!(
      demo_mode_enabled: false,
      confirmed_at: Time.current,
      confirmation_code: nil,
      display_key: SecureRandom.alphanumeric(24)
    )
    Rack::Attack.reset!
  end

  test "show with valid id and key returns 200" do
    get "/d/#{@device.id}?key=#{@device.display_key}"
    assert_response :success
    assert_includes response.body, "Tomorrow"
  end

  test "screenshot generation does not count as a device connection" do
    @device.update_column(:last_connection_at, nil)

    get "/d/#{@device.id}?key=#{@device.display_key}&generation=true"

    assert_response :success
    assert_nil @device.reload.last_connection_at
  end

  test "show with valid id and wrong key returns 401" do
    get "/d/#{@device.id}?key=wrongkey"
    assert_response :unauthorized
  end

  test "show with invalid id returns 401" do
    get "/d/999999?key=somekey"
    assert_response :unauthorized
  end

  test "show with valid id and missing key returns 401" do
    get "/d/#{@device.id}"
    assert_response :unauthorized
  end

  test "invalid id and wrong key return same response as wrong key only" do
    get "/d/999999?key=wrongkey"
    bad_id_body = response.body
    bad_id_status = response.status

    get "/d/#{@device.id}?key=wrongkey"
    wrong_key_body = response.body
    wrong_key_status = response.status

    assert_equal bad_id_status, wrong_key_status
    assert_equal bad_id_body, wrong_key_body
  end

  test "response includes Referrer-Policy no-referrer header" do
    get "/d/#{@device.id}?key=#{@device.display_key}"
    assert_response :success
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "response includes X-Deploy-Time header" do
    get "/d/#{@device.id}?key=#{@device.display_key}"
    assert_response :success
    assert_equal DEPLOY_TIME.to_s, response.headers["X-Deploy-Time"]
  end

  test "screenshot with valid tokens returns PNG" do
    @device.update!(cached_image: Base64.strict_encode64("fake png data"), cached_image_at: Time.current)
    get "/d/#{@device.id}/screenshot?key=#{@device.display_key}"
    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "screenshot with wrong key returns 401" do
    get "/d/#{@device.id}/screenshot?key=wrongkey"
    assert_response :unauthorized
  end

  test "screenshot refreshes and returns image when no cache" do
    @device.update!(cached_image: nil, cached_image_at: nil)
    fake_b64 = Base64.strict_encode64("fake png data")

    ScreenshotService.stub :capture, fake_b64 do
      get "/d/#{@device.id}/screenshot?key=#{@device.display_key}"
      assert_response :success
      assert_equal "image/png", response.media_type
    end
  end
end
