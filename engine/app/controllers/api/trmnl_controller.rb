# frozen_string_literal: true

module Api
  class TrmnlController < ActionController::API
    include Rails.application.routes.url_helpers

    # Upper bound on device log entries persisted per /api/log request. Devices
    # can batch many locally-stored logs; this caps a single burst.
    MAX_LOG_ENTRIES_PER_REQUEST = 50

    DEFAULT_BATTERY_VOLTAGE_RANGE = (3.0..4.2)
    # The E1003 ADC reports about 4.09 V after a full charge and the hardware
    # shuts down around 3.15 V. Using the wider generic range otherwise leaves
    # the UI showing roughly 12% when the usable battery is already exhausted.
    E1003_BATTERY_VOLTAGE_RANGE = (3.15..4.08)

    before_action :authenticate_device!
    skip_before_action :authenticate_device!, only: [:setup, :display]
    before_action :authenticate_or_identify_device!, only: [:display]
    after_action :log_response_status

    # GET /api/setup
    def setup
      Rails.logger.info("[API Setup] mac=#{request.headers["ID"]}")

      mac_address = request.headers["ID"]
      return head :bad_request if mac_address.blank?

      device = Device.find_by(mac_address: mac_address)
      # A device only calls /api/setup when it has no stored credentials — it is
      # brand new or has been factory reset. If a device record already exists
      # for this hardware's MAC, the hardware was reset, so detach it (rather
      # than silently handing back its old credentials) and fall through to
      # issue a fresh pairing code the owner must enter to reconnect it.
      device&.detach_hardware!

      pending = PendingDevice.find_or_create_by!(mac_address: mac_address) do |pd|
        pd.api_key = SecureRandom.hex(16)
        pd.friendly_id = SecureRandom.alphanumeric(6).upcase
        pd.model = PendingDevice.model_key_for_firmware(request.headers["Model"])
        # Remember the record we just detached so it can be deleted if this
        # hardware is claimed by a different device (paired to a new account).
        pd.detached_device_id = device&.id
      end

      pending.refresh! if pending.expired?

      # Backfill the model for pending registrations created before we captured
      # it, so pairing can still create the right device model.
      if pending.model.blank? && (model_key = PendingDevice.model_key_for_firmware(request.headers["Model"]))
        pending.update!(model: model_key)
      end

      render json: {
        status: 200,
        api_key: pending.api_key,
        friendly_id: pending.pairing_code,
        message: "Enter this code at timeframe.app"
      }
    end

    # GET /api/display
    def display
      mac_address = request.headers["ID"]
      Rails.logger.info("[API Display] mac=#{mac_address} device_id=#{@device&.id}")

      unless @device
        # Adopt any unrecognized MAC into a pending registration so a device
        # whose server record was removed (deleted/detached, or whose pending
        # was cleaned up) is re-enrolled into pairing instead of dead-ending on
        # a 401. find_or_create keeps this idempotent across the device's poll
        # loop; keep_alive! refreshes the expiry (same code) on each poll so an
        # actively-waiting device's on-screen code stays pairable.
        pending = PendingDevice.find_or_create_by!(mac_address: mac_address) do |pd|
          pd.api_key = SecureRandom.hex(16)
          pd.friendly_id = SecureRandom.alphanumeric(6).upcase
          pd.model = PendingDevice.model_key_for_firmware(request.headers["Model"])
        end
        pending.keep_alive!
        render json: {status: 202}, status: :ok
        return
      end

      if @device.pending_confirmation?
        render json: {
          status: 0,
          filename: "confirmation-#{@device.id}.png",
          image_url: confirmation_image_account_location_device_url(@device.account, @device.location, @device, host: request.base_url),
          image_url_timeout: 0,
          refresh_rate: 30,
          reset_firmware: false,
          special_function: "sleep",
          update_firmware: false,
          firmware_url: nil,
          temperature_profile: "default"
        }
        return
      end

      update_device_from_headers(@device)

      @device.refresh_screenshot!(request.base_url) if @device.cached_image.blank? || params[:force].present?
      # Reconnecting clears any pending "offline for a day" alert so a future
      # outage re-notifies the owner.
      @device.update_columns(last_connection_at: Time.current, device_offline_notified_at: nil)

      RefreshDeviceScreenshotJob.set(wait: (@device.refresh_rate - 60).seconds).perform_later(@device.id)

      render json: {
        status: 0,
        filename: "display-#{@device.cached_image_at}.png",
        image_url: @device.signed_screenshot_url(host: request.base_url),
        image_url_timeout: 0,
        refresh_rate: @device.refresh_rate,
        reset_firmware: false,
        special_function: "sleep",
        update_firmware: false,
        firmware_url: nil,
        temperature_profile: "default"
      }
    end

    # POST /api/log
    def log
      Rails.logger.info("[API Log] mac=#{request.headers["ID"]} body=#{request.raw_post.truncate(1000)}")
      persist_device_logs
      head :no_content
    end

    private

    # Persist device-submitted log entries as audit logs (event_type
    # "device.log") so they're browsable in the existing admin audit logs view.
    # CreateAuditLogJob/AuditLog only exist in the cloud app, so this is a no-op
    # in deployments without them (mirrors the Auditable concern's guard).
    # :nocov: exercised by the cloud app's test suite, not the engine/ha-addon.
    def persist_device_logs
      return unless @device
      return unless defined?(CreateAuditLogJob)

      entries = params[:logs]
      return unless entries.is_a?(Array)

      entries.first(MAX_LOG_ENTRIES_PER_REQUEST).each do |entry|
        next unless entry.respond_to?(:to_unsafe_h) || entry.is_a?(Hash)

        metadata = (entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry).to_h

        CreateAuditLogJob.perform_later(
          subject_type: @device.class.name,
          subject_id: @device.id,
          event_type: "device.log",
          metadata: metadata
        )
      end
    rescue => e
      Rails.logger.error("[API Log] Failed to persist device logs: #{e.message}")
    end
    # :nocov:

    def update_device_from_headers(device)
      attrs = {}
      attrs[:firmware_version] = request.headers["FW-Version"] if request.headers["FW-Version"].present?
      attrs[:firmware_commit] = request.headers["FW-Commit"] if request.headers["FW-Commit"].present?

      level = battery_level_from_headers(device)
      attrs[:battery_level] = level unless level.nil?

      charging = charging_from_headers
      attrs[:charging] = charging unless charging.nil?

      attrs[:rssi] = request.headers["RSSI"].to_i if request.headers["RSSI"].present?

      effective_level = level.nil? ? device.battery_level : level
      effective_charging = charging.nil? ? device.charging? : charging
      attrs[:low_battery_warning] = device.battery_warning_for(level: effective_level, charging: effective_charging)

      device.update_columns(attrs) if attrs.any?
    end

    # Prefers the firmware's fuel-gauge Percent-Charged reading (TRMNL-X) and
    # falls back to a linear voltage-to-percent estimate for simpler hardware.
    def battery_level_from_headers(device)
      if request.headers["Percent-Charged"].present?
        return request.headers["Percent-Charged"].to_f.clamp(0, 100).round
      end
      if request.headers["Battery-Voltage"].present?
        voltage = request.headers["Battery-Voltage"].to_f
        range = device.reterminal_e1003? ? E1003_BATTERY_VOLTAGE_RANGE : DEFAULT_BATTERY_VOLTAGE_RANGE
        return ((voltage - range.begin) / (range.end - range.begin) * 100).clamp(0, 100).round
      end
      nil
    end

    # Charging if the gauge reports it or USB power is connected. Returns nil
    # when the device sent no charging-related headers.
    def charging_from_headers
      values = []
      values << %w[1 true].include?(request.headers["Battery-Charging"].to_s.strip.downcase) if request.headers["Battery-Charging"].present?
      values << (request.headers["USB-Connected"].to_s.strip.downcase == "true") if request.headers["USB-Connected"].present?
      return nil if values.empty?

      values.any?
    end

    def log_response_status
      Rails.logger.info("[API Response] action=#{action_name} status=#{response.status}")
    end

    def authenticate_device!
      mac_address = request.headers["ID"]
      return head :unauthorized if mac_address.blank?

      @device = Device.find_by(mac_address: mac_address)
      return head :unauthorized if @device.nil?

      access_token = request.env["HTTP_ACCESS_TOKEN"].presence || request.env["ACCESS_TOKEN"].presence
      return unless access_token
      head :unauthorized unless @device.authenticate_api_key(access_token)
    end

    def authenticate_or_identify_device!
      mac_address = request.headers["ID"]
      return head :unauthorized if mac_address.blank?

      @device = Device.find_by(mac_address: mac_address)
      # Unknown MAC (no device record): allow through so #display can adopt the
      # hardware into a fresh pending registration and return 202, rather than
      # stranding a previously-paired device on a permanent 401.
      return unless @device

      access_token = request.env["HTTP_ACCESS_TOKEN"].presence || request.env["ACCESS_TOKEN"].presence
      return unless access_token
      head :unauthorized unless @device.authenticate_api_key(access_token)
    end
  end
end
