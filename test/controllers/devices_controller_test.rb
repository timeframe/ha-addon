# frozen_string_literal: true

require "test_helper"

class DevicesControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  def setup
    @account = test_user.accounts.first
    @location = test_location
    login_as(test_user, scope: :user)
  end

  def teardown
    Warden.test_reset!
  end

  test "root shows dashboard with devices" do
    device = Device.find_or_create_by!(name: "test-dashboard-device", model: "visionect_13") do |d|
      d.location = @location
      d.confirmed_at = Time.current
      d.confirmation_code = nil
    end

    get "/"
    assert_response :success
    assert_includes response.body, device.name
    assert_includes response.body, "/pair"
  end

  # --- create ---

  test "create adds a Visionect device directly" do
    name = "My Visionect #{SecureRandom.hex(4)}"
    post account_location_devices_path(@account, @location),
      params: {device_model: "visionect_13", device_name: name}

    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, name
    device = Device.find_by(name: name)
    assert device.present?
    assert device.confirmed?
    assert device.display_key.present?
  end

  test "create pairs a TRMNL device via pairing code" do
    mac = SecureRandom.hex(6).scan(/../).join(":")
    pending = PendingDevice.create!(mac_address: mac, api_key: SecureRandom.hex(16), friendly_id: "T1#{SecureRandom.hex(2)}")

    post account_location_devices_path(@account, @location),
      params: {device_model: "trmnl_og", device_name: "My TRMNL #{SecureRandom.hex(4)}", pairing_code: pending.pairing_code}

    assert_redirected_to root_path
  end

  test "create pairs a Boox device via pairing code" do
    mac = SecureRandom.hex(6).scan(/../).join(":")
    pending = PendingDevice.create!(mac_address: mac, api_key: SecureRandom.hex(16), friendly_id: "B1#{SecureRandom.hex(2)}")

    post account_location_devices_path(@account, @location),
      params: {device_model: "boox_mira_pro", device_name: "My Boox #{SecureRandom.hex(4)}", pairing_code: pending.pairing_code}

    assert_redirected_to root_path
  end

  test "create with invalid pairing code redirects with alert" do
    post account_location_devices_path(@account, @location),
      params: {device_model: "trmnl_og", device_name: "Bad TRMNL", pairing_code: "999999"}

    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "Invalid or expired pairing code"
  end

  test "create with expired pairing code redirects with alert" do
    mac = SecureRandom.hex(6).scan(/../).join(":")
    pending = PendingDevice.create!(mac_address: mac, api_key: SecureRandom.hex(16), friendly_id: "EX#{SecureRandom.hex(2)}")
    pending.update_column(:created_at, 65.minutes.ago)

    post account_location_devices_path(@account, @location),
      params: {device_model: "trmnl_og", device_name: "Expired TRMNL", pairing_code: pending.pairing_code}

    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "Invalid or expired pairing code"
    assert_nil PendingDevice.find_by(id: pending.id), "Expired pending device should be destroyed"
  end

  test "create with invalid data redirects with alert" do
    post account_location_devices_path(@account, @location),
      params: {device_model: "visionect_13", device_name: ""}

    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "Validation failed"
  end

  # --- update (demo mode toggle) ---

  test "update toggles demo mode on" do
    device = Device.find_or_create_by!(name: "test-demo-device", model: "visionect_13") do |d|
      d.location = @location
    end
    device.update!(demo_mode_enabled: false, confirmed_at: Time.current, confirmation_code: nil)

    patch account_location_device_path(@account, @location, device)

    assert_redirected_to root_path
    assert device.reload.demo_mode_enabled?
  end

  test "update toggles demo mode off" do
    device = Device.find_or_create_by!(name: "test-demo-off", model: "visionect_13") do |d|
      d.location = @location
    end
    device.update!(demo_mode_enabled: true, confirmed_at: Time.current, confirmation_code: nil)

    patch account_location_device_path(@account, @location, device)

    assert_redirected_to root_path
    refute device.reload.demo_mode_enabled?
  end

  # --- destroy ---

  test "destroy deletes device with correct name confirmation" do
    device = Device.find_or_create_by!(name: "test-delete-me", model: "visionect_13") do |d|
      d.location = @location
    end
    device.update!(confirmed_at: Time.current, confirmation_code: nil)

    delete account_location_device_path(@account, @location, device),
      params: {name_confirmation: device.name}

    assert_redirected_to root_path
    assert_nil Device.find_by(name: "test-delete-me")
  end

  test "destroy does not delete device with wrong name confirmation" do
    device = Device.find_or_create_by!(name: "test-keep-me", model: "visionect_13") do |d|
      d.location = @location
    end
    device.update!(confirmed_at: Time.current, confirmation_code: nil)

    delete account_location_device_path(@account, @location, device),
      params: {name_confirmation: "wrong"}

    assert_redirected_to root_path
    assert Device.find_by(name: "test-keep-me").present?
  end

  # --- regenerate_tokens ---

  test "regenerate_tokens changes tokens with correct name confirmation" do
    device = Device.find_or_create_by!(name: "test-regen-device", model: "visionect_13") do |d|
      d.location = @location
      d.confirmed_at = Time.current
      d.confirmation_code = nil
    end
    device.update!(display_key: SecureRandom.alphanumeric(24))
    old_key = device.display_key

    post regenerate_tokens_account_location_device_path(@account, @location, device),
      params: {name_confirmation: device.name}

    assert_redirected_to root_path
    device.reload
    refute_equal old_key, device.display_key
  end

  test "regenerate_tokens does not change tokens with wrong name confirmation" do
    device = Device.find_or_create_by!(name: "test-regen-keep", model: "visionect_13") do |d|
      d.location = @location
      d.confirmed_at = Time.current
      d.confirmation_code = nil
    end
    device.update!(display_key: SecureRandom.alphanumeric(24))
    old_key = device.display_key

    post regenerate_tokens_account_location_device_path(@account, @location, device),
      params: {name_confirmation: "wrong name"}

    assert_redirected_to root_path
    device.reload
    assert_equal old_key, device.display_key
  end

  # --- repair ---

  test "repair re-pairs a Boox device with valid pairing code" do
    device = Device.find_or_create_by!(name: "test-repair-boox", model: "boox_mira_pro") do |d|
      d.location = @location
      d.confirmed_at = Time.current
      d.confirmation_code = nil
    end
    pending = PendingDevice.create!

    post repair_account_location_device_path(@account, @location, device),
      params: {pairing_code: pending.pairing_code}

    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "reconnected"
    pending.reload
    assert_equal device.id, pending.claimed_device_id
  end

  test "repair with invalid pairing code shows alert" do
    device = Device.find_or_create_by!(name: "test-repair-bad", model: "boox_mira_pro") do |d|
      d.location = @location
      d.confirmed_at = Time.current
      d.confirmation_code = nil
    end

    post repair_account_location_device_path(@account, @location, device),
      params: {pairing_code: "999999"}

    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "Invalid or expired pairing code"
  end

  # --- confirmation_image ---

  test "confirmation_image returns png for pending device" do
    device = Device.create!(
      name: "test-confirm-img-#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      location: @location,
      mac_address: SecureRandom.hex(6).scan(/../).join(":")
    )

    # Stub MiniMagick to avoid ImageMagick dependency in tests.
    # We need to let the block execute so lines are covered, but prevent actual ImageMagick calls.
    fake_blob = "\x89PNG\r\n\x1a\n"
    null_convert = Object.new
    null_convert.define_singleton_method(:method_missing) { |*| self }
    null_convert.define_singleton_method(:respond_to_missing?) { |*| true }
    null_convert.define_singleton_method(:<<) { |*| self }
    null_convert.define_singleton_method(:call) { nil }

    mock_image = Object.new
    mock_image.define_singleton_method(:to_blob) { fake_blob }

    image_creator = ->(ext, &block) do
      tempfile = Tempfile.new(["test", ext])
      block&.call(tempfile)
      mock_image
    end

    MiniMagick::Image.stub(:create, image_creator) do
      MiniMagick.stub(:convert, ->(&blk) { blk&.call(null_convert) }) do
        get confirmation_image_account_location_device_path(@account, @location, device)
      end
    end

    assert_response :success
  end

  test "confirmation_image returns 404 for confirmed device" do
    device = Device.find_or_create_by!(name: "test-confirm-done", model: "visionect_13") do |d|
      d.location = @location
    end

    get confirmation_image_account_location_device_path(@account, @location, device)

    assert_response :not_found
  end

  # --- Display (show/screenshot) tests ---

  test "should get mira display with no data" do
    mira = Device.find_or_create_by!(name: "test-mira", model: "boox_mira_pro") { |d| d.location = @location }
    mira.update!(demo_mode_enabled: false, confirmed_at: Time.current, confirmation_code: nil)
    Rails.cache.delete(DEPLOY_TIME.to_s + HomeAssistantApi::WEATHER_DOMAIN)

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{mira.id}"

    assert_includes response.body, "Tomorrow"
    assert_response :success
  end

  test "should get thirteen display with no data" do
    thirteen = Device.find_or_create_by!(name: "test-thirteen", model: "visionect_13") { |d| d.location = @location }
    thirteen.update!(demo_mode_enabled: false, confirmed_at: Time.current, confirmation_code: nil)
    Rails.cache.delete(DEPLOY_TIME.to_s + HomeAssistantApi::WEATHER_DOMAIN)

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{thirteen.id}"

    assert_includes response.body, "Tomorrow"
    assert_response :success
  end

  test "should handle errors in thirteen display" do
    thirteen = Device.find_or_create_by!(name: "test-thirteen", model: "visionect_13") { |d| d.location = @location }
    thirteen.update!(demo_mode_enabled: false, confirmed_at: Time.current, confirmation_code: nil)

    DeviceContent.stub :new, -> {
      obj = Object.new
      def obj.call(*)
        raise StandardError.new("Test error message")
      end
      obj
    } do
      get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{thirteen.id}"

      assert_response :success
      assert_includes response.body, "StandardError"
      assert_includes response.body, "Test error message"
    end
  end

  test "should handle errors in mira display" do
    mira = Device.find_or_create_by!(name: "test-mira", model: "boox_mira_pro") { |d| d.location = @location }
    mira.update!(demo_mode_enabled: false, confirmed_at: Time.current, confirmation_code: nil)

    DeviceContent.stub :new, -> {
      obj = Object.new
      def obj.call(*)
        raise StandardError.new("Test error message")
      end
      obj
    } do
      get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{mira.id}"

      assert_response :success
      assert_includes response.body, "StandardError"
      assert_includes response.body, "Test error message"
    end
  end

  test "display returns 404 for unknown device" do
    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/nonexistent"
    assert_response :not_found
  end

  test "should get mira display in demo mode" do
    mira = Device.find_or_create_by!(name: "test-mira", model: "boox_mira_pro") { |d| d.location = @location }
    mira.update!(demo_mode_enabled: true, confirmed_at: Time.current, confirmation_code: nil)

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{mira.id}"

    assert_response :success
    assert_includes response.body, "Spotted Towhee"
    assert_includes response.body, "Tycho"
    assert_includes response.body, "Tomorrow"
  end

  test "should get thirteen display in demo mode" do
    thirteen = Device.find_or_create_by!(name: "test-thirteen", model: "visionect_13") { |d| d.location = @location }
    thirteen.update!(demo_mode_enabled: true, confirmed_at: Time.current, confirmation_code: nil)

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{thirteen.id}"

    assert_response :success
    assert_includes response.body, "Spotted Towhee"
    assert_includes response.body, "Tomorrow"
  end

  test "screenshot returns image for device with cached image" do
    thirteen = Device.find_or_create_by!(name: "test-thirteen", model: "visionect_13") { |d| d.location = @location }
    thirteen.update!(confirmed_at: Time.current, confirmation_code: nil, cached_image: Base64.strict_encode64("fake png data"), cached_image_at: Time.current)

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{thirteen.id}/screenshot"
    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "screenshot refreshes and returns image when no cache" do
    thirteen = Device.find_or_create_by!(name: "test-thirteen", model: "visionect_13") { |d| d.location = @location }
    thirteen.update!(confirmed_at: Time.current, confirmation_code: nil, cached_image: nil, cached_image_at: nil)
    fake_b64 = Base64.strict_encode64("fake png data")

    ScreenshotService.stub :capture, fake_b64 do
      get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{thirteen.id}/screenshot"
      assert_response :success
      assert_equal "image/png", response.media_type
    end
  end

  test "screenshot returns 404 for unknown device" do
    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/nonexistent/screenshot"
    assert_response :not_found
  end

  test "mira display sets refresh parameter" do
    mira = Device.find_or_create_by!(name: "test-mira", model: "boox_mira_pro") { |d| d.location = @location }
    mira.update!(demo_mode_enabled: false, confirmed_at: Time.current, confirmation_code: nil)

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{mira.id}?refresh=false"
    assert_response :success
  end

  test "show renders confirmation for unconfirmed device" do
    device = Device.create!(name: "unconfirmed-#{SecureRandom.hex(4)}", model: "trmnl_og", location: @location, mac_address: "CC:DD:#{SecureRandom.hex(4).scan(/../).join(":").upcase}", api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase)
    assert device.pending_confirmation?

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{device.id}"
    assert_response :success
    assert_includes response.body, device.confirmation_code
  end

  test "show returns not found for invalid account" do
    get "/accounts/999999/locations/#{@location.id}/devices/1"
    assert_response :not_found
  end

  test "show returns not found for invalid location" do
    get "/accounts/#{@account.id}/locations/999999/devices/1"
    assert_response :not_found
  end

  # --- preview_frame ---

  test "preview_frame renders device in demo mode" do
    thirteen = Device.find_or_create_by!(name: "test-thirteen", model: "visionect_13") { |d| d.location = @location }
    thirteen.update!(demo_mode_enabled: true, confirmed_at: Time.current, confirmation_code: nil)

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{thirteen.id}/preview_frame"
    assert_response :success
    assert_includes response.body, "Spotted Towhee"
  end

  test "preview_frame renders device at a specific time" do
    thirteen = Device.find_or_create_by!(name: "test-thirteen", model: "visionect_13") { |d| d.location = @location }
    thirteen.update!(demo_mode_enabled: true, confirmed_at: Time.current, confirmation_code: nil)

    get "/accounts/#{@account.id}/locations/#{@location.id}/devices/#{thirteen.id}/preview_frame?at=2026-05-10T14:00:00"
    assert_response :success
  end
end
