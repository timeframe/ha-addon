# frozen_string_literal: true

module Api
  class TrmnlController < ActionController::API
    include Rails.application.routes.url_helpers

    # Upper bound on device log entries persisted per /api/log request. Devices
    # can batch many locally-stored logs; this caps a single burst.
    MAX_LOG_ENTRIES_PER_REQUEST = 50

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
      if device
        update_device_from_headers(device)
        render json: {
          status: 200,
          api_key: device.api_key,
          friendly_id: device.friendly_id,
          message: "Welcome to Timeframe"
        }
        return
      end

      pending = PendingDevice.find_or_create_by!(mac_address: mac_address) do |pd|
        pd.api_key = SecureRandom.hex(16)
        pd.friendly_id = SecureRandom.alphanumeric(6).upcase
      end

      pending.refresh! if pending.expired?

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
      @device.update_column(:last_connection_at, Time.current)

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
      if request.headers["Battery-Voltage"].present?
        voltage = request.headers["Battery-Voltage"].to_f
        attrs[:battery_level] = ((voltage - 3.0) / 1.2 * 100).clamp(0, 100).round
      end
      attrs[:rssi] = request.headers["RSSI"].to_i if request.headers["RSSI"].present?
      device.update_columns(attrs) if attrs.any?
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
      if @device
        access_token = request.env["HTTP_ACCESS_TOKEN"].presence || request.env["ACCESS_TOKEN"].presence
        return unless access_token
        head :unauthorized unless @device.authenticate_api_key(access_token)
        return
      end

      # Allow pending devices through so display action can return 202
      return if PendingDevice.find_by(mac_address: mac_address)

      head :unauthorized
    end
  end
end
