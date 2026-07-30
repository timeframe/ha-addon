# frozen_string_literal: true

require "test_helper"

class DeviceTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def setup
    # Clean up all test-created devices to avoid uniqueness conflicts across tests
    PendingDevice.where.not(claimed_device_id: nil).update_all(claimed_device_id: nil)
    Device.where("name LIKE 'test_%' OR name LIKE 'Visionect %' OR name LIKE 'Living Room %'").destroy_all
  end

  def test_model_name_label
    device = Device.new(name: "test", model: "visionect_13")
    assert_equal "Visionect Place & Play 13\"", device.model_name_label
  end

  def test_name_uniqueness_scoped_to_location
    loc1 = test_location
    loc2 = Account.find_or_create_by!(name: "Test2").locations.find_or_create_by!(name: "Other Location") do |l|
      l.latitude = 40.0
      l.longitude = -100.0
      l.time_zone = "America/Chicago"
    end

    Device.create!(location: loc1, name: "test_same_name", model: "visionect_13")
    # Same name, different location — should be valid
    d2 = Device.new(location: loc2, name: "test_same_name", model: "visionect_13")
    assert d2.valid?, "Device with same name in different location should be valid"

    # Same name, same location — should be invalid
    d3 = Device.new(location: loc1, name: "test_same_name", model: "visionect_13")
    refute d3.valid?, "Device with same name in same location should be invalid"
  end

  def test_display_width
    device = Device.new(name: "test", model: "visionect_13")
    assert_equal 1200, device.display_width
  end

  def test_display_height
    device = Device.new(name: "test", model: "visionect_13")
    assert_equal 1600, device.display_height
  end

  def test_refresh_rate_daytime_is_regular
    device = Device.new(location: test_location, name: "test_rr", model: "trmnl_og")
    travel_to ActiveSupport::TimeZone["America/Chicago"].local(2026, 7, 17, 12, 0, 0) do
      assert_equal 900, device.refresh_rate
    end
  end

  def test_refresh_rate_late_evening_is_hourly
    device = Device.new(location: test_location, name: "test_rr", model: "trmnl_og")
    travel_to ActiveSupport::TimeZone["America/Chicago"].local(2026, 7, 17, 23, 30, 0) do
      assert_equal 3540, device.refresh_rate
    end
  end

  def test_refresh_rate_small_hours_is_hourly
    device = Device.new(location: test_location, name: "test_rr", model: "trmnl_og")
    travel_to ActiveSupport::TimeZone["America/Chicago"].local(2026, 7, 17, 2, 0, 0) do
      assert_equal 3540, device.refresh_rate
    end
  end

  def test_refresh_rate_in_four_am_hour_is_capped_to_five_am
    device = Device.new(location: test_location, name: "test_rr", model: "trmnl_og")
    travel_to ActiveSupport::TimeZone["America/Chicago"].local(2026, 7, 17, 4, 30, 0) do
      assert_equal 1800, device.refresh_rate
    end
  end

  def test_refresh_rate_after_four_forty_five_resumes_regular
    device = Device.new(location: test_location, name: "test_rr", model: "trmnl_og")
    travel_to ActiveSupport::TimeZone["America/Chicago"].local(2026, 7, 17, 4, 50, 0) do
      assert_equal 900, device.refresh_rate
    end
  end

  def test_refresh_rate_at_five_am_is_regular
    device = Device.new(location: test_location, name: "test_rr", model: "trmnl_og")
    travel_to ActiveSupport::TimeZone["America/Chicago"].local(2026, 7, 17, 5, 30, 0) do
      assert_equal 900, device.refresh_rate
    end
  end

  def test_refresh_rate_without_location_uses_utc
    device = Device.new(name: "test_rr", model: "trmnl_og")
    travel_to Time.utc(2026, 7, 17, 2, 0, 0) do
      assert_equal 3540, device.refresh_rate
    end
  end

  def test_find_or_create_by_visionect_serial_creates_new_device
    device = Device.find_or_create_by_visionect_serial("ABC123")

    assert_equal "Visionect ABC123", device.name
    assert_equal "visionect_13", device.model
    assert_equal "ABC123", device.visionect_serial
  end

  def test_find_or_create_by_visionect_serial_returns_existing_device
    existing = Device.create!(location: test_location, name: "Visionect ABC123", model: "visionect_13", visionect_serial: "ABC123")

    device = Device.find_or_create_by_visionect_serial("ABC123")

    assert_equal existing.id, device.id
  end

  def test_find_or_create_by_visionect_serial_handles_race_condition
    existing = Device.create!(location: test_location, name: "Visionect RACE1", model: "visionect_13", visionect_serial: "RACE1")

    # Simulate race: find_by returns nil first time, then create! hits unique constraint,
    # then find_by succeeds in the rescue block
    call_count = 0
    original_find_by = Device.method(:find_by)

    Device.stub(:find_by, ->(*args, **kwargs) {
      call_count += 1
      (call_count == 1) ? nil : original_find_by.call(*args, **kwargs)
    }) do
      Device.stub(:create!, ->(*) { raise ActiveRecord::RecordNotUnique }) do
        device = Device.find_or_create_by_visionect_serial("RACE1")
        assert_equal existing.id, device.id
      end
    end
  end

  def test_record_visionect_connection
    device = Device.create!(location: test_location, name: "test_conn", model: "visionect_13", visionect_serial: "CONN1")

    assert_nil device.last_connection_at

    device.record_visionect_connection!
    device.reload

    assert_in_delta Time.current, device.last_connection_at, 2
  end

  def test_never_paired_predicate
    device = Device.create!(location: test_location, name: "test_never_paired", model: "visionect_13", visionect_serial: "NP#{SecureRandom.hex(3)}")
    assert device.never_paired?

    device.update_columns(last_connection_at: Time.current)
    refute device.never_paired?

    device.update_columns(last_connection_at: nil)
    PendingDevice.create!(claimed_device: device)
    device.reload
    refute device.never_paired?
  end

  def test_detach_hardware_frees_the_mac_and_resets_pairing_state
    device = test_location.devices.create!(
      name: "detach_#{SecureRandom.hex(3)}",
      model: "reterminal_e1001",
      mac_address: "DE:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      confirmed_at: Time.current
    )
    device.update_columns(last_connection_at: Time.current)
    original_mac = device.mac_address
    original_api_key = device.api_key
    pending = PendingDevice.create!(claimed_device: device)

    device.detach_hardware!
    device.reload

    refute_equal original_mac, device.mac_address
    refute_equal original_api_key, device.api_key
    assert_nil device.last_connection_at
    assert_nil device.session_token
    assert device.never_paired?
    refute PendingDevice.exists?(pending.id)
  end

  def test_encode_visionect_image_stores_4bpp_data
    device = Device.create!(location: test_location, name: "test_encode", model: "visionect_13", visionect_serial: "ENC1")
    # Create a small white PNG via ImageMagick
    png = generate_test_png
    device.update!(cached_image: Base64.strict_encode64(png))

    device.encode_visionect_image!

    stored = VisionectProtocol::Server.fetch_image(device.id)
    assert_equal 960_000, stored.bytesize
  end

  def test_encode_visionect_image_skips_non_visionect
    device = Device.create!(location: test_location, name: "test_trmnl", model: "trmnl_og", mac_address: "FF:EE:DD:CC:BB:AA")
    device.encode_visionect_image!

    assert_nil VisionectProtocol::Server.fetch_image(device.id)
  end

  def test_encode_visionect_image_skips_without_cached_image
    device = Device.create!(location: test_location, name: "test_nocache", model: "visionect_13", visionect_serial: "NC1")
    device.encode_visionect_image!

    assert_nil VisionectProtocol::Server.fetch_image(device.id)
  end

  def test_refresh_all_screenshots_calls_refresh_on_each_device
    Device.create!(location: test_location, name: "test_refresh_all", model: "trmnl_og", mac_address: "RA:#{SecureRandom.hex(5).scan(/../).join(":").upcase}", api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase)
    refreshed_ids = []

    original_method = Device.instance_method(:refresh_screenshot!)
    Device.define_method(:refresh_screenshot!) { |*| refreshed_ids << id }

    Device.refresh_all_screenshots!
    assert refreshed_ids.any?
  ensure
    Device.define_method(:refresh_screenshot!, original_method)
  end

  def test_refresh_all_screenshots_handles_errors_gracefully
    Device.create!(location: test_location, name: "test_error", model: "trmnl_og", mac_address: "EE:RR:#{SecureRandom.hex(4).scan(/../).join(":").upcase}", api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase)

    original_method = Device.instance_method(:refresh_screenshot!)
    Device.define_method(:refresh_screenshot!) { |*| raise "test error" }

    # Should not raise
    Device.refresh_all_screenshots!
    assert true
  ensure
    Device.define_method(:refresh_screenshot!, original_method)
  end

  def test_refresh_screenshot_skips_capture_when_content_unchanged
    device = Device.create!(location: test_location, name: "test_hash_skip_#{SecureRandom.hex(3)}", model: "trmnl_og", mac_address: "CA:#{SecureRandom.hex(5).scan(/../).join(":").upcase}", api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase, display_key: SecureRandom.alphanumeric(24))
    captures = 0
    capture = ->(_url) {
      captures += 1
      "img-#{captures}"
    }
    device.stub(:rendered_display_html, "<html>stable</html>") do
      device.stub(:capture_screenshot, capture) do
        device.refresh_screenshot!("http://example.test")
        device.refresh_screenshot!("http://example.test")
      end
    end
    assert_equal 1, captures, "unchanged content must not capture a second time"
    assert_equal "img-1", device.reload.cached_image
  end

  def test_refresh_screenshot_recaptures_when_content_changes
    device = Device.create!(location: test_location, name: "test_hash_change_#{SecureRandom.hex(3)}", model: "trmnl_og", mac_address: "CB:#{SecureRandom.hex(5).scan(/../).join(":").upcase}", api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase, display_key: SecureRandom.alphanumeric(24))
    captures = 0
    capture = ->(_url) {
      captures += 1
      "img-#{captures}"
    }
    device.stub(:capture_screenshot, capture) do
      device.stub(:rendered_display_html, "<html>one</html>") { device.refresh_screenshot!("http://example.test") }
      device.stub(:rendered_display_html, "<html>two</html>") { device.refresh_screenshot!("http://example.test") }
    end
    assert_equal 2, captures, "changed content must capture again"
    assert_equal "img-2", device.reload.cached_image
  end

  def test_confirm_sets_location_and_confirmed_at
    device = Device.create!(name: "test_confirm_#{SecureRandom.hex(4)}", model: "trmnl_og", mac_address: "AA:BB:#{SecureRandom.hex(4).scan(/../).join(":").upcase}", api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase)
    assert device.pending_confirmation?

    device.confirm!(test_location)
    device.reload

    assert device.confirmed?
    refute device.pending_confirmation?
    assert_equal test_location, device.location
    assert_nil device.confirmation_code
  end

  def test_confirm_with_name_updates_name
    device = Device.create!(name: "test_confirm_name_#{SecureRandom.hex(4)}", model: "trmnl_og", mac_address: "BB:CC:#{SecureRandom.hex(4).scan(/../).join(":").upcase}", api_key: SecureRandom.hex(16), friendly_id: SecureRandom.alphanumeric(6).upcase)
    new_name = "Renamed #{SecureRandom.hex(4)}"
    device.confirm!(test_location, name: new_name)
    device.reload

    assert_equal new_name, device.name
  end

  def test_authenticate_session_returns_device_for_valid_token
    device = Device.create!(location: test_location, name: "test_auth_session", model: "visionect_13", visionect_serial: "AUTH1")
    token = device.rotate_session_token!

    result = Device.authenticate_session(device.id, token)
    assert_equal device.id, result.id
  end

  def test_authenticate_session_returns_nil_for_wrong_token
    device = Device.create!(location: test_location, name: "test_auth_bad", model: "visionect_13", visionect_serial: "AUTH2")
    device.rotate_session_token!

    assert_nil Device.authenticate_session(device.id, "wrong-token")
  end

  def test_authenticate_session_returns_nil_for_missing_args
    assert_nil Device.authenticate_session(nil, nil)
    assert_nil Device.authenticate_session(nil, "token")
    assert_nil Device.authenticate_session(999_999, nil)
  end

  def test_authenticate_session_returns_nil_for_nonexistent_device
    assert_nil Device.authenticate_session(999_999, "some-token")
  end

  def test_authenticate_session_returns_nil_when_device_has_no_token
    device = Device.create!(location: test_location, name: "test_auth_notoken", model: "visionect_13", visionect_serial: "AUTH3")

    assert_nil Device.authenticate_session(device.id, "some-token")
  end

  def test_accessible_by_user_who_owns_device
    device = Device.create!(location: test_location, name: "test_access_user", model: "visionect_13", visionect_serial: "ACC1")

    assert device.accessible_by?(user: test_user)
  end

  def test_accessible_by_matching_device
    device = Device.create!(location: test_location, name: "test_access_device", model: "visionect_13", visionect_serial: "ACC2")

    assert device.accessible_by?(device: device)
  end

  def test_not_accessible_by_different_device
    device = Device.create!(location: test_location, name: "test_access_diff", model: "visionect_13", visionect_serial: "ACC3")
    other = Device.create!(location: test_location, name: "test_access_other", model: "visionect_13", visionect_serial: "ACC4")

    refute device.accessible_by?(device: other)
  end

  def test_not_accessible_by_nil
    device = Device.create!(location: test_location, name: "test_access_nil", model: "visionect_13", visionect_serial: "ACC5")

    refute device.accessible_by?
  end

  def test_reterminal_e1003_model_name_label
    device = Device.new(name: "test", model: "reterminal_e1003")
    assert_equal "reTerminal E1003 10.3\"", device.model_name_label
  end

  def test_low_battery_banner_only_for_low_battery_on_status_barless_templates
    low = {level: 15, low: true, charging: false}

    # Shown on the compact day layouts that have no top status bar.
    assert_equal low, Device.low_battery_banner("three_day", {battery: low})
    assert_equal low, Device.low_battery_banner("one_day", {battery: low})

    # Not shown on templates that render the status bar (it appears up top).
    assert_nil Device.low_battery_banner("trmnl", {battery: low})
    assert_nil Device.low_battery_banner("reterminal", {battery: low})

    # Not shown when the battery is fine or missing.
    assert_nil Device.low_battery_banner("three_day", {battery: {level: 80, low: false}})
    assert_nil Device.low_battery_banner("three_day", {})
  end

  def test_reterminal_e1003_display_dimensions
    device = Device.new(name: "test", model: "reterminal_e1003")
    assert_equal 1414, device.display_width
    assert_equal 1872, device.display_height
  end

  def test_reterminal_e1003_landscape_template_options
    device = Device.new(name: "test", model: "reterminal_e1003")
    labels = device.template_options.map { |t| t[:label] }
    names = device.template_options.map { |t| t[:name] }
    assert_equal ["Portrait", "Landscape"], labels
    assert_equal ["reterminal", "reterminal_landscape"], names
  end

  def test_trmnl_x_landscape_template_options
    device = Device.new(name: "test", model: "trmnl_x")
    labels = device.template_options.map { |t| t[:label] }
    assert_equal ["Portrait", "Landscape"], labels
  end

  def test_landscape_template_swaps_display_dimensions
    device = Device.new(name: "test", model: "reterminal_e1003", display_template: "reterminal_landscape")
    assert device.landscape_template?
    assert_equal 1872, device.display_width
    assert_equal 1414, device.display_height
  end

  def test_portrait_reterminal_is_not_landscape
    device = Device.new(name: "test", model: "reterminal_e1003", display_template: "reterminal")
    refute device.landscape_template?
    assert_equal 1414, device.display_width
    assert_equal 1872, device.display_height
  end

  def test_reterminal_landscape_supports_hide_current_day
    device = Device.new(name: "test", model: "reterminal_e1003", display_template: "reterminal_landscape")
    assert device.hide_current_day_supported?
  end

  def test_reterminal_e1003_landscape_capture_skips_rotation
    device = Device.new(name: "test", model: "reterminal_e1003", display_template: "reterminal_landscape")
    captured = nil
    ScreenshotService.stub(:capture, ->(_url, **opts) {
      captured = opts
      "img"
    }) do
      device.send(:capture_screenshot, "http://example.test")
    end
    assert_equal false, captured[:rotate]
    assert captured[:grayscale_only]
    assert_equal 1872, captured[:width]
    assert_equal 1414, captured[:height]
  end

  def test_reterminal_e1003_portrait_capture_rotates
    device = Device.new(name: "test", model: "reterminal_e1003", display_template: "reterminal")
    captured = nil
    ScreenshotService.stub(:capture, ->(_url, **opts) {
      captured = opts
      "img"
    }) do
      device.send(:capture_screenshot, "http://example.test")
    end
    assert_equal true, captured[:rotate]
    assert captured[:grayscale_only]
    assert_equal 1414, captured[:width]
    assert_equal 1872, captured[:height]
  end

  def test_boox_mira_model_name_label
    device = Device.new(name: "test", model: "boox_mira")
    assert_equal "Boox Mira 13.3\"", device.model_name_label
  end

  def test_boox_mira_display_dimensions
    device = Device.new(name: "test", model: "boox_mira")
    assert_equal 1650, device.display_width
    assert_equal 2200, device.display_height
  end

  def test_boox_mira_predicate
    assert Device.new(model: "boox_mira").boox_mira?
    refute Device.new(model: "visionect_13").boox_mira?
  end

  def test_trmnl_predicate
    assert Device.new(model: "trmnl_og").trmnl?
    refute Device.new(model: "visionect_13").trmnl?
  end

  def test_reterminal_e1001_predicate
    assert Device.new(model: "reterminal_e1001").reterminal_e1001?
    refute Device.new(model: "visionect_13").reterminal_e1001?
  end

  def test_realtime_display
    assert Device.new(model: "boox_mira_pro").realtime_display?
    assert Device.new(model: "boox_mira").realtime_display?
    refute Device.new(model: "visionect_13").realtime_display?
    refute Device.new(model: "trmnl_og").realtime_display?
  end

  def test_pairing_code_device
    assert Device.new(model: "boox_mira_pro").pairing_code_device?
    assert Device.new(model: "boox_mira").pairing_code_device?
    assert Device.new(model: "trmnl_og").pairing_code_device?
    assert Device.new(model: "reterminal_e1003").pairing_code_device?
    refute Device.new(model: "visionect_13").pairing_code_device?
  end

  def test_screenshotted_models_derived_from_supported_models
    assert_includes Device::SCREENSHOTTED_MODELS, "trmnl_og"
    assert_includes Device::SCREENSHOTTED_MODELS, "reterminal_e1001"
    assert_includes Device::SCREENSHOTTED_MODELS, "reterminal_e1003"
    assert_includes Device::SCREENSHOTTED_MODELS, "trmnl_x"
    refute_includes Device::SCREENSHOTTED_MODELS, "visionect_13"
    refute_includes Device::SCREENSHOTTED_MODELS, "boox_mira_pro"
    refute_includes Device::SCREENSHOTTED_MODELS, "boox_mira"
  end

  def test_realtime_models_derived_from_supported_models
    assert_includes Device::REALTIME_MODELS, "boox_mira_pro"
    assert_includes Device::REALTIME_MODELS, "boox_mira"
    refute_includes Device::REALTIME_MODELS, "visionect_13"
    refute_includes Device::REALTIME_MODELS, "trmnl_og"
  end

  def test_minutely_precip_enabled_defaults_on_for_realtime_models
    device = Device.new(model: "boox_mira")
    device.configuration = nil
    assert device.minutely_precip_enabled?
  end

  def test_minutely_precip_enabled_respects_disabled_configuration
    device = Device.new(model: "boox_mira", configuration: {"show_minutely_precip" => "false"})
    refute device.minutely_precip_enabled?
  end

  def test_minutely_precip_disabled_for_non_realtime_models
    device = Device.new(model: "trmnl_og")
    refute device.minutely_precip_enabled?
  end

  def test_one_day_template_available_for_trmnl_og_and_reterminal_e1001
    %w[trmnl_og reterminal_e1001].each do |model|
      templates = Device::SUPPORTED_MODELS.dig(model, :templates).map { |t| t[:name] }
      assert_includes templates, "one_day", "expected #{model} to include one_day template"
    end
  end

  def test_one_day_start_offset_returns_zero_when_rollover_disabled
    device = Device.new(model: "trmnl_og", display_template: "one_day")
    device.configuration = {"one_day_rollover_enabled" => "false"}
    assert_equal 0, device.one_day_start_offset(Time.utc(2026, 1, 1, 23, 0))
  end

  def test_one_day_start_offset_defaults_to_rollover_enabled
    device = Device.new(model: "trmnl_og", display_template: "one_day")
    device.configuration = nil
    assert_equal 0, device.one_day_start_offset(Time.utc(2026, 1, 1, 17, 59), timezone: "UTC")
    assert_equal 1, device.one_day_start_offset(Time.utc(2026, 1, 1, 18, 0), timezone: "UTC")
  end

  def test_one_day_start_offset_rolls_over_after_configured_time
    device = Device.new(model: "trmnl_og", display_template: "one_day")
    device.configuration = {"one_day_rollover_enabled" => "true", "one_day_rollover_time" => "18:00"}
    assert_equal 0, device.one_day_start_offset(Time.utc(2026, 1, 1, 17, 59), timezone: "UTC")
    assert_equal 1, device.one_day_start_offset(Time.utc(2026, 1, 1, 18, 0), timezone: "UTC")
    assert_equal 1, device.one_day_start_offset(Time.utc(2026, 1, 1, 21, 30), timezone: "UTC")
  end

  def test_one_day_start_offset_only_applies_when_template_is_one_day
    device = Device.new(model: "trmnl_og", display_template: "two_day")
    device.configuration = {"one_day_rollover_enabled" => "true", "one_day_rollover_time" => "18:00"}
    assert_equal 0, device.one_day_start_offset(Time.utc(2026, 1, 1, 20, 0))
  end

  def test_two_day_start_offset_returns_zero_when_rollover_disabled
    device = Device.new(model: "trmnl_og", display_template: "two_day")
    device.configuration = {"two_day_rollover_enabled" => "false"}
    assert_equal 0, device.two_day_start_offset(Time.utc(2026, 1, 1, 23, 0))
  end

  def test_two_day_start_offset_rolls_over_after_configured_time
    device = Device.new(model: "trmnl_og", display_template: "two_day")
    device.configuration = {"two_day_rollover_enabled" => "true", "two_day_rollover_time" => "18:00"}
    assert_equal 0, device.two_day_start_offset(Time.utc(2026, 1, 1, 17, 59), timezone: "UTC")
    assert_equal 1, device.two_day_start_offset(Time.utc(2026, 1, 1, 18, 0), timezone: "UTC")
  end

  def test_two_day_start_offset_only_applies_when_template_is_two_day
    device = Device.new(model: "trmnl_og", display_template: "one_day")
    assert_equal 0, device.two_day_start_offset(Time.utc(2026, 1, 1, 20, 0))
  end

  def test_calendar_excluded_checks_the_excluded_identifiers_list
    device = Device.new(model: "trmnl_og")
    refute device.calendar_excluded?("cal-1")
    device.excluded_calendar_identifiers = ["cal-1"]
    assert device.calendar_excluded?("cal-1")
    refute device.calendar_excluded?("cal-2")
  end

  def test_calendar_event_filters_ignores_blank_and_non_filter_keys
    device = Device.new(model: "trmnl_og")
    device.configuration = {
      "event_filter_cal-1" => "standup",
      "event_filter_cal-2" => "",
      "show_precip_events" => "true"
    }
    assert_equal({"cal-1" => "standup"}, device.calendar_event_filters)
  end

  def test_one_day_device_content_populates_weather_row_for_daily_icon
    device = Device.create!(
      location: test_location,
      name: "test_one_day_icon_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "OD:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "one_day",
      demo_mode_enabled: true
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 8)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    assert_equal 1, result[:day_groups].length
    assert result[:day_groups].first[:weather_row].any?,
      "Expected weather_row to be populated so the header weather icon renders"
  end

  def test_event_filter_configuration_is_applied_to_device_content
    device = Device.create!(
      location: test_location,
      name: "test_event_filter_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "EF:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "three_day",
      demo_mode_enabled: true,
      configuration: {"event_filter_demo" => "Piano"}
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 8)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    summaries = result[:day_groups].flat_map { |day| (day[:daily] + day[:periodic]).map { |e| e[:summary] } }
    calendar_summaries = summaries - ["Vacation"]
    refute_empty calendar_summaries.select { |s| s.to_s.include?("Piano") },
      "expected at least one event matching the filter"
    non_matching = calendar_summaries.reject { |s| s.to_s.include?("Piano") || s.to_s.match?(/\A-?\d+°/) || s.to_s.match?(/Gusts/i) }
    assert_empty non_matching,
      "expected event_filter to remove non-matching calendar events, but found: #{non_matching.inspect}"
  end

  def test_active_template_for_boox_mira
    device = Device.new(model: "boox_mira", display_template: "default")
    assert_equal "boox_mira", device.active_template
  end

  def test_template_options_returns_hashes
    device = Device.new(model: "trmnl_og")
    options = device.template_options
    assert_kind_of Array, options
    assert options.all? { |t| t.key?(:name) && t.key?(:label) }
    assert_equal "trmnl", options.first[:name]
    assert_equal "Timeline", options.first[:label]
  end

  def test_template_options_nil_for_single_template_device
    assert_nil Device.new(model: "boox_mira").template_options
    assert_nil Device.new(model: "visionect_13").template_options
  end

  def test_reterminal_e1003_predicate
    device = Device.new(name: "test", model: "reterminal_e1003")
    assert device.reterminal_e1003?
    refute device.trmnl?
    refute device.trmnl_x?
    refute device.visionect?
  end

  def test_reterminal_template_device_content_spans_12_days
    %w[reterminal_e1003 trmnl_x].each do |model|
      device = Device.create!(
        location: test_location,
        name: "test_reterminal_days_#{SecureRandom.hex(4)}",
        model: model,
        mac_address: "RT:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
        demo_mode_enabled: true
      )
      current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 8)

      result = device.device_content(timezone: "America/Chicago", current_time: current_time)

      assert_equal "reterminal", device.active_template
      assert_equal 12, result[:day_groups].length, "expected #{model} to render 12 days"
    end
  end

  def test_trmnl_x_predicate
    device = Device.new(name: "test", model: "trmnl_x")
    assert device.trmnl_x?
    refute device.reterminal_e1003?
    refute device.trmnl?
    refute device.visionect?
  end

  def test_trmnl_x_model_name_label
    device = Device.new(name: "test", model: "trmnl_x")
    assert_equal "TRMNL (X)", device.model_name_label
  end

  def test_trmnl_x_display_dimensions
    device = Device.new(name: "test", model: "trmnl_x")
    assert_equal 1404, device.display_width
    assert_equal 1872, device.display_height
  end

  def test_trmnl_x_generates_api_key_and_friendly_id
    device = Device.create!(
      name: "test_trmnl_x_#{SecureRandom.hex(4)}",
      model: "trmnl_x",
      mac_address: "TX:#{SecureRandom.hex(4).scan(/../).join(":").upcase}"
    )
    assert device.api_key.present?
    assert device.friendly_id.present?
    assert device.confirmation_code.present?
    refute device.confirmed?
  end

  def test_trmnl_x_requires_mac_address
    device = Device.new(name: "test_tx_no_mac", model: "trmnl_x")
    refute device.valid?
    assert device.errors[:mac_address].any?
  end

  def test_reterminal_e1003_generates_api_key_and_friendly_id
    device = Device.create!(
      name: "test_reterminal_#{SecureRandom.hex(4)}",
      model: "reterminal_e1003",
      mac_address: "RT:#{SecureRandom.hex(4).scan(/../).join(":").upcase}"
    )
    assert device.api_key.present?
    assert device.friendly_id.present?
    assert device.confirmation_code.present?
    refute device.confirmed?
  end

  def test_reterminal_e1003_requires_mac_address
    device = Device.new(name: "test_rt_no_mac", model: "reterminal_e1003")
    refute device.valid?
    assert device.errors[:mac_address].any?
  end

  def test_active_template_returns_custom_when_set
    device = Device.new(name: "test", model: "trmnl_og", display_template: "three_day")
    assert_equal "three_day", device.active_template
  end

  def test_two_day_show_weather_events_false_keeps_clothing_forecast
    device = Device.create!(
      location: test_location,
      name: "test_two_day_weather_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "TW:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "two_day",
      demo_mode_enabled: true,
      configuration: {
        "show_weather_events" => "false",
        "clothing_forecast" => "true"
      }
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 8)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    assert_equal 2, result[:day_groups].length
    assert result[:day_groups].first[:weather_row].any?, "Expected hourly weather to remain available"
    assert result[:day_groups].first[:clothing], "Expected clothing forecast to remain available"
    assert result[:day_groups].flat_map { |day| day[:periodic] }.none? { |event| event[:summary]&.include?("Gusts") }
  end

  def test_temperature_toggle_hides_hourly_weather_but_keeps_daily_weather
    device = Device.create!(
      location: test_location,
      name: "test_hourly_temperature_toggle_#{SecureRandom.hex(4)}",
      model: "visionect_13",
      demo_mode_enabled: true,
      configuration: {
        "show_temperature_events" => "false"
      }
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 8)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    all_daily = result[:day_groups].flat_map { |day| day[:daily] }
    all_periodic = result[:day_groups].flat_map { |day| day[:periodic] }
    assert all_daily.any? { |event| event[:weather] && event[:summary] == "72° / 50°" }
    refute all_periodic.any? { |event| event[:weather] && event[:summary].to_s.end_with?("°") }
  end

  def test_weather_event_enabled_defaults_explicit_settings_and_legacy_setting
    device = Device.new

    assert device.weather_event_enabled?("show_temperature_events")
    assert device.weather_event_enabled?("show_precip_events")

    device.configuration = {"show_weather_events" => "false"}
    assert device.weather_event_enabled?("show_temperature_events")
    refute device.weather_event_enabled?("show_precip_events")
    refute device.weather_event_enabled?("show_wind_events")

    device.configuration = {"show_precip_events" => "false"}
    refute device.weather_event_enabled?("show_precip_events")

    device.configuration = {"show_precip_events" => "true", "show_weather_events" => "false"}
    assert device.weather_event_enabled?("show_precip_events")
  end

  def test_weather_alerts_enabled_defaults_per_template_and_overrides
    # Defaults: on for most templates, off for the compact one/two-day layouts.
    assert Device.new(display_template: "three_day").weather_alerts_enabled?
    assert Device.new(display_template: "trmnl").weather_alerts_enabled?
    refute Device.new(display_template: "one_day").weather_alerts_enabled?
    refute Device.new(display_template: "two_day").weather_alerts_enabled?

    # A nil configuration falls back to the template default.
    nil_config = Device.new(display_template: "trmnl")
    nil_config.configuration = nil
    assert nil_config.weather_alerts_enabled?

    # Explicit setting wins regardless of template.
    assert Device.new(display_template: "two_day", configuration: {"show_weather_alerts" => "true"}).weather_alerts_enabled?
    refute Device.new(display_template: "three_day", configuration: {"show_weather_alerts" => "false"}).weather_alerts_enabled?
  end

  def test_ha_status_enabled_defaults_on_and_respects_setting
    # Defaults on when unset.
    assert Device.new.ha_status_enabled?
    assert Device.new(configuration: {"show_ha_status" => "true"}).ha_status_enabled?
    refute Device.new(configuration: {"show_ha_status" => "false"}).ha_status_enabled?

    # A nil configuration still defaults on.
    nil_config = Device.new
    nil_config.configuration = nil
    assert nil_config.ha_status_enabled?
  end

  def test_show_device_id_defaults_off_and_respects_setting
    # Defaults off when unset.
    refute Device.new.show_device_id?
    assert Device.new(configuration: {"show_device_id" => "true"}).show_device_id?
    refute Device.new(configuration: {"show_device_id" => "false"}).show_device_id?

    # A nil configuration still defaults off.
    nil_config = Device.new
    nil_config.configuration = nil
    refute nil_config.show_device_id?
  end

  def test_wind_gust_threshold_mph_defaults_and_overrides
    device = Device.new
    device.configuration = nil
    assert_equal Device::DEFAULT_WIND_GUST_THRESHOLD_MPH, device.wind_gust_threshold_mph

    device.configuration = {"wind_gust_threshold_mph" => "27.5"}
    assert_in_delta 27.5, device.wind_gust_threshold_mph, 0.001

    device.configuration = {"wind_gust_threshold_mph" => ""}
    assert_equal Device::DEFAULT_WIND_GUST_THRESHOLD_MPH, device.wind_gust_threshold_mph
  end

  def test_two_day_uses_today_and_tomorrow_before_default_rollover_time
    device = Device.create!(
      location: test_location,
      name: "test_two_day_rollover_before_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "RB:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "two_day",
      demo_mode_enabled: true
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 17, 59)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    assert_equal [Date.new(2026, 3, 19), Date.new(2026, 3, 20)], result[:day_groups].map { |day| day[:date] }
  end

  def test_two_day_rollover_is_enabled_by_default
    device = Device.create!(
      location: test_location,
      name: "test_two_day_rollover_disabled_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "RD:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "two_day",
      demo_mode_enabled: true
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 18)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    assert_equal [Date.new(2026, 3, 20), Date.new(2026, 3, 21)], result[:day_groups].map { |day| day[:date] }
  end

  def test_two_day_uses_tomorrow_and_following_day_at_default_rollover_time
    device = Device.create!(
      location: test_location,
      name: "test_two_day_rollover_after_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "RA:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "two_day",
      demo_mode_enabled: true,
      configuration: {"two_day_rollover_enabled" => "true"}
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 18)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    assert_equal [Date.new(2026, 3, 20), Date.new(2026, 3, 21)], result[:day_groups].map { |day| day[:date] }
  end

  def test_two_day_rollover_time_can_be_configured
    device = Device.create!(
      location: test_location,
      name: "test_two_day_rollover_custom_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "RC:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "two_day",
      demo_mode_enabled: true,
      configuration: {
        "two_day_rollover_enabled" => "true",
        "two_day_rollover_time" => "20:30"
      }
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 19)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    assert_equal [Date.new(2026, 3, 19), Date.new(2026, 3, 20)], result[:day_groups].map { |day| day[:date] }
  end

  def test_three_day_show_weather_events_false_keeps_clothing_forecast
    device = Device.create!(
      location: test_location,
      name: "test_three_day_weather_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "TH:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "three_day",
      demo_mode_enabled: true,
      configuration: {
        "show_weather_events" => "false",
        "clothing_forecast" => "true"
      }
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 8)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    assert_equal 3, result[:day_groups].length
    assert result[:day_groups].first[:weather_row].any?, "Expected hourly weather to remain available"
    assert result[:day_groups].first[:clothing], "Expected clothing forecast to remain available"
    assert result[:day_groups].flat_map { |day| day[:periodic] }.none? { |event| event[:summary]&.include?("Gusts") }
  end

  def test_destroying_device_destroys_associated_pending_device
    device = Device.create!(location: test_location, name: "test_destroy_pending", model: "trmnl_og",
      mac_address: "DE:ST:RO:YP:EN:D1", confirmed_at: Time.current)
    pending = PendingDevice.create!(mac_address: "DE:ST:RO:YP:EN:D1", claimed_device: device)

    assert PendingDevice.exists?(pending.id)
    device.destroy!
    refute PendingDevice.exists?(pending.id)
  end

  def test_enqueue_screenshot_refresh_jobs_handles_connection_error
    Device.stub(:where, ->(*) { raise ActiveRecord::ConnectionNotEstablished }) do
      Device.enqueue_screenshot_refresh_jobs!
    end
    pass
  end

  def test_hide_current_day_enabled_defaults_per_template
    %w[trmnl thirteen mira boox_mira reterminal three_day].each do |tmpl|
      device = Device.new(model: "trmnl_og")
      device.stub(:active_template, tmpl) do
        assert device.hide_current_day_enabled?, "expected #{tmpl} to default to on"
      end
    end
  end

  def test_hide_current_day_enabled_not_supported_for_two_day_and_one_day
    %w[two_day one_day].each do |tmpl|
      device = Device.new(model: "trmnl_og", display_template: tmpl)
      device.configuration = {"hide_current_day_enabled" => "true"}
      refute device.hide_current_day_enabled?, "expected #{tmpl} to ignore hide_current_day_enabled"
    end
  end

  def test_hide_current_day_enabled_reads_configuration
    device = Device.new(model: "trmnl_og", display_template: "three_day")
    device.configuration = {"hide_current_day_enabled" => "true"}
    assert device.hide_current_day_enabled?

    device = Device.new(model: "trmnl_og", display_template: "trmnl")
    device.configuration = {"hide_current_day_enabled" => "false"}
    refute device.hide_current_day_enabled?
  end

  def test_hide_current_day_after_minutes_defaults_and_reads_config
    device = Device.new(model: "trmnl_og", display_template: "trmnl")
    assert_equal 18 * 60, device.hide_current_day_after_minutes
    device.configuration = {"hide_current_day_time" => "21:30"}
    assert_equal (21 * 60) + 30, device.hide_current_day_after_minutes
  end

  def test_trmnl_template_requests_fourteen_days_of_data
    device = Device.create!(
      location: test_location,
      name: "test_trmnl_days_#{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: "T8:#{SecureRandom.hex(5).scan(/../).join(":").upcase}",
      display_template: "trmnl",
      demo_mode_enabled: true,
      configuration: {"hide_current_day_enabled" => "false"}
    )
    current_time = ActiveSupport::TimeZone["America/Chicago"].local(2026, 3, 19, 9)

    result = device.device_content(timezone: "America/Chicago", current_time: current_time)

    assert_equal 14, result[:day_groups].size
  end

  def test_battery_status
    device = Device.new(name: "test", model: "trmnl_og")
    assert_nil device.battery_level
    assert_equal :unknown, device.battery_status

    device.battery_level = 80
    device.charging = true
    assert_equal :charging, device.battery_status

    device.charging = false
    device.battery_level = 100
    assert_equal :good, device.battery_status

    device.battery_level = 8
    assert_equal :critical, device.battery_status

    device.battery_level = 20
    assert_equal :low, device.battery_status

    device.battery_level = 40
    assert_equal :medium, device.battery_status

    device.battery_level = 60
    assert_equal :good, device.battery_status
  end

  def test_battery_status_full_while_charging_reports_good
    device = Device.new(name: "test", model: "trmnl_og", battery_level: 100, charging: true)
    assert_equal :good, device.battery_status
  end

  def test_battery_icon
    device = Device.new(name: "test", model: "trmnl_og")
    assert_equal "battery-unknown", device.battery_icon

    device.battery_level = 45
    device.charging = true
    assert_equal "battery-charging-40", device.battery_icon

    device.charging = false
    device.battery_level = 5
    assert_equal "battery-outline", device.battery_icon

    device.battery_level = 100
    assert_equal "battery", device.battery_icon

    device.battery_level = 45
    assert_equal "battery-40", device.battery_icon
  end

  def test_battery_color_class
    device = Device.new(name: "test", model: "trmnl_og", battery_level: 50, charging: true)
    assert_equal "text-info", device.battery_color_class

    device.charging = false
    device.battery_level = 5
    assert_equal "text-danger", device.battery_color_class

    device.battery_level = 20
    assert_equal "text-warning", device.battery_color_class

    device.battery_level = 80
    assert_equal "text-body-tertiary", device.battery_color_class
  end

  def test_next_low_battery_warning_hysteresis
    # Charging always clears the warning.
    refute Device.next_low_battery_warning(level: 10, charging: true, current: true)
    # No reading keeps the previous state.
    assert Device.next_low_battery_warning(level: nil, charging: false, current: true)
    refute Device.next_low_battery_warning(level: nil, charging: false, current: false)
    # At/below the low threshold turns the warning on.
    assert Device.next_low_battery_warning(level: 25, charging: false, current: false)
    # At/above the clear threshold turns it off.
    refute Device.next_low_battery_warning(level: 30, charging: false, current: true)
    # In the hysteresis band the previous state is held.
    assert Device.next_low_battery_warning(level: 27, charging: false, current: true)
    refute Device.next_low_battery_warning(level: 27, charging: false, current: false)
  end

  def test_battery_warning_for_uses_persisted_flag
    device = Device.new(name: "test", model: "trmnl_og", low_battery_warning: true)
    # In the hysteresis band, the current persisted flag is preserved.
    assert device.battery_warning_for(level: 28, charging: false)
  end

  def test_battery_descriptor_instance
    device = Device.new(name: "test", model: "trmnl_og")
    assert_nil device.battery_descriptor

    device.battery_level = 15
    device.low_battery_warning = true
    descriptor = device.battery_descriptor
    assert_equal 15, descriptor[:level]
    assert_equal false, descriptor[:charging]
    assert_equal true, descriptor[:low]
    assert_equal "battery-10", descriptor[:icon]
  end

  def test_battery_descriptor_class_helper
    assert_nil Device.battery_descriptor(level: nil, charging: false)

    low = Device.battery_descriptor(level: 20, charging: false)
    assert_equal true, low[:low]
    refute low[:charging]

    charging = Device.battery_descriptor(level: 50, charging: true)
    assert_equal true, charging[:charging]
    refute charging[:low]
  end

  private

  def generate_test_png
    require "mini_magick"
    img = MiniMagick::Image.create(".png") do |f|
      MiniMagick.convert do |c|
        c.size "1600x1200"
        c << "xc:white"
        c << f.path
      end
    end
    img.to_blob
  end
end
