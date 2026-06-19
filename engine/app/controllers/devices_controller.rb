# frozen_string_literal: true

class DevicesController < ApplicationController
  skip_before_action :authenticate_user!, raise: false, only: [:confirmation_image, :show, :screenshot, :client_log]
  before_action :set_account_and_location, except: [:confirmation_image, :show, :screenshot, :client_log]
  before_action :authorize_device_access!, only: [:show, :screenshot, :client_log]
  skip_forgery_protection only: :client_log
  layout "device", only: [:show, :preview_frame]
  after_action(only: [:show, :screenshot]) { response.headers["X-Deploy-Time"] = DEPLOY_TIME.to_s }

  TEMPLATE_COMPONENTS = {
    "trmnl" => "Devices::TrmnlComponent",
    "three_day" => "Devices::ThreeDayComponent",
    "two_day" => "Devices::TwoDayComponent",
    "one_day" => "Devices::OneDayComponent",
    "reterminal" => "Devices::ReterminalComponent",
    "boox_mira" => "Devices::BooxMiraComponent",
    "thirteen" => "Devices::ThirteenComponent",
    "mira" => "Devices::MiraComponent"
  }.freeze

  def show
    if @device.pending_confirmation?
      render "devices/confirmation", locals: {device: @device}, layout: params[:layout] != "false"
      return
    end

    @device.update_column(:last_connection_at, Time.current) if session[:device_session_token].present?

    template = @device.active_template
    refresh = @device.realtime_display? && params[:refresh] != "false"
    @refresh = refresh

    view_object = @device.device_content
    view_object[:configuration] = @device.try(:configuration) || {}
    @banner = view_object[:banner] unless template == "mira"

    component = build_device_component(template, view_object, refresh: refresh, device: @device)
    render component, layout: params[:layout] != "false"
  rescue => e
    render "devices/error", locals: {klass: e.class.to_s, message: e.message, backtrace: e.backtrace}
  end

  def preview_frame
    device = @location.devices.find(params[:id])
    tz = device.location&.time_zone.presence || "America/Denver"

    current_time = if params[:at].present?
      ActiveSupport::TimeZone[tz].parse(params[:at])
    end

    template = device.active_template
    view_object = device.device_content(current_time: current_time)
    view_object[:configuration] = device.try(:configuration) || {}
    @banner = view_object[:banner] unless template == "mira"

    component = build_device_component(template, view_object)
    render component, layout: "device"
  rescue => e
    render "devices/error", locals: {klass: e.class.to_s, message: e.message, backtrace: e.backtrace}
  end

  def settings
    @device = @location.devices.find(params[:id])
    @preview_tz = @device.location&.time_zone.presence || "America/Denver"
    @preview_now = Time.current.in_time_zone(@preview_tz)
  end

  def screenshot
    if @device.cached_image.blank? || params[:force] == "true"
      begin
        @device.refresh_screenshot!(request.base_url)
      rescue Ferrum::BinaryNotFoundError => e
        Rails.logger.error("[Screenshot] Browser not available: #{e.message}")
        return render plain: "Screenshot service unavailable", status: :service_unavailable if @device.cached_image.blank?
      end
    end

    @device.reload
    image_data = Base64.strict_decode64(@device.cached_image)

    send_data image_data, type: "image/png", disposition: "inline", filename: "#{@device.id}.png?#{Time.now.to_i}"
  end

  def create
    model = params[:device_model]
    name = params[:device_name].to_s.strip

    if model == "visionect_13"
      device = @location.devices.create!(name: name, model: model)
      redirect_to settings_account_location_device_path(@account, @location, device), notice: "Device \"#{name}\" added."
    elsif current_user.is_admin? && params[:pairing_code].blank?
      device = @location.devices.create!(name: name, model: model, mac_address: SecureRandom.hex(6), confirmed_at: Time.current)
      redirect_to settings_account_location_device_path(@account, @location, device), notice: "Device \"#{name}\" added."
    else
      pairing_code = params[:pairing_code].to_s.strip
      pending_device = PendingDevice.find_active_by_code(pairing_code)

      unless pending_device
        return redirect_back fallback_location: root_path, alert: "Invalid or expired pairing code."
      end

      device = pending_device.claim!(location: @location, name: name, model: model)
      redirect_to settings_account_location_device_path(@account, @location, device), notice: "Device \"#{name}\" paired successfully."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: root_path, alert: e.message
  end

  def update
    device = @location.devices.find(params[:id])
    device.update!(demo_mode_enabled: !device.demo_mode_enabled?)
    if device.realtime_display?
      DeviceBroadcaster.clear_hash(device.id)
      DeviceBroadcaster.broadcast_if_changed(device)
    end
    redirect_back fallback_location: root_path
  end

  def update_template
    device = @location.devices.find(params[:id])
    device.update!(display_template: params[:display_template])
    RefreshDeviceScreenshotJob.perform_later(device.id) if device.screenshotted?
    redirect_back fallback_location: root_path
  end

  def update_configuration
    device = @location.devices.find(params[:id])
    config = device.configuration || {}
    config[params[:key]] = normalize_configuration_value(params[:key], params[:value], params[:unit])
    device.update!(configuration: config)
    RefreshDeviceScreenshotJob.perform_later(device.id) if device.screenshotted?
    redirect_back fallback_location: root_path
  end

  def update_calendars
    device = @location.devices.find(params[:id])
    all_identifiers = available_calendar_identifiers_for(device)
    included = Array(params[:calendar_identifiers]).map(&:to_s)
    excluded = all_identifiers - included
    config = device.configuration || {}
    config = config.reject { |key, _| key.to_s.start_with?("event_filter_") }
    included.each do |identifier|
      value = params.dig(:event_filters, identifier).to_s.strip
      config["event_filter_#{identifier}"] = value if value.present?
    end
    device.update!(excluded_calendar_identifiers: excluded, configuration: config)
    RefreshDeviceScreenshotJob.perform_later(device.id) if device.screenshotted?
    redirect_back fallback_location: settings_account_location_device_path(@account, @location, device)
  end

  # Consolidated save for the device "Options" pane: name, template,
  # configuration toggles, temperature hours, wind threshold, and the
  # per-calendar selection/filters all in a single request.
  def update_options
    device = @location.devices.find(params[:id])

    attrs = {}
    new_name = params[:name].to_s.strip
    attrs[:name] = new_name if new_name.present?
    attrs[:display_template] = params[:display_template] if params[:display_template].present?

    config = device.configuration || {}

    submitted_config = params[:configuration]
    if submitted_config.respond_to?(:each)
      submitted_config.each do |key, value|
        config[key.to_s] = normalize_configuration_value(key.to_s, value, params.dig(:units, key))
      end
    end

    if params.key?(:temperature_hours_present)
      selected_hours = Array(params[:temperature_hours]).map(&:to_s)
      (0..23).each do |hour|
        config["temperature_hour_#{hour}"] = selected_hours.include?(hour.to_s) ? "true" : "false"
      end
    end

    if params.key?(:calendar_identifiers_present)
      all_identifiers = available_calendar_identifiers_for(device)
      included = Array(params[:calendar_identifiers]).map(&:to_s)
      attrs[:excluded_calendar_identifiers] = all_identifiers - included
      config = config.reject { |key, _| key.to_s.start_with?("event_filter_") }
      included.each do |identifier|
        value = params.dig(:event_filters, identifier).to_s.strip
        config["event_filter_#{identifier}"] = value if value.present?
      end
    end

    attrs[:configuration] = config
    device.update!(**attrs)

    RefreshDeviceScreenshotJob.perform_later(device.id) if device.screenshotted?
    if device.realtime_display?
      DeviceBroadcaster.clear_hash(device.id)
      DeviceBroadcaster.broadcast_if_changed(device)
    end

    redirect_to settings_account_location_device_path(@account, @location, device), notice: "Options saved."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_account_location_device_path(@account, @location, device), alert: e.message
  end

  def rename
    device = @location.devices.find(params[:id])
    new_name = params[:name].to_s.strip
    if new_name.present?
      device.update!(name: new_name)
      redirect_to settings_account_location_device_path(@account, @location, device), notice: "Device renamed to \"#{new_name}\"."
    else
      redirect_to settings_account_location_device_path(@account, @location, device), alert: "Name can't be blank."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_account_location_device_path(@account, @location, device), alert: e.message
  end

  def destroy
    device = @location.devices.find(params[:id])

    if params[:name_confirmation].to_s.downcase.strip == device.name.downcase.strip
      device.destroy
      redirect_to root_path, notice: "Device \"#{device.name}\" deleted.", status: :see_other
      return
    end

    redirect_back fallback_location: root_path, alert: "Device name confirmation did not match.", status: :see_other
  end

  def regenerate_tokens
    device = @location.devices.find(params[:id])

    if params[:name_confirmation].to_s.downcase.strip == device.name.downcase.strip
      device.regenerate_display_key!
    end

    redirect_back fallback_location: root_path
  end

  def repair
    device = @location.devices.find(params[:id])
    pairing_code = params[:pairing_code].to_s.strip
    pending_device = PendingDevice.find_active_by_code(pairing_code)

    unless pending_device
      return redirect_back fallback_location: root_path, alert: "Invalid or expired pairing code."
    end

    if device.never_paired?
      pending_device.link_to!(device)
      notice = "\"#{device.name}\" paired successfully."
    else
      pending_device.update!(claimed_device: device)
      notice = "\"#{device.name}\" reconnected successfully."
    end
    device.rotate_session_token!
    redirect_back fallback_location: root_path, notice: notice
  end

  # Best-effort sink for client-side display diagnostics (tfMorph events, JS
  # errors) posted back from realtime device pages. In the cloud app the
  # Auditable concern persists each request (with its params) as an AuditLog
  # via CreateAuditLogJob; self-hosted deployments simply ack it.
  def client_log
    head :no_content
  end

  def confirmation_image
    device = Device.find(params[:id])

    unless device.pending_confirmation?
      return head :not_found
    end

    width = device.display_width
    height = device.display_height
    title_size = [width, height].min / 15
    code_size = [width, height].min / 6
    sub_size = [width, height].min / 20

    image = MiniMagick::Image.create(".png") do |f|
      MiniMagick.convert do |convert|
        convert.size "#{width}x#{height}"
        convert << "xc:white"
        convert.gravity "Center"
        convert.font "Helvetica"
        convert.pointsize title_size
        convert.annotate("+0-#{height / 6}", "Add this device to your")
        convert.annotate("+0-#{height / 10}", "Timeframe account:")
        convert.pointsize code_size
        convert.annotate("+0+#{height / 12}", device.confirmation_code)
        convert.pointsize sub_size
        convert.annotate("+0+#{height / 4}", "Enter this code at")
        convert.annotate("+0+#{height / 4 + sub_size + 10}", "your Timeframe dashboard")
        convert << f.path
      end
    end

    send_data image.to_blob, type: "image/png", disposition: "inline"
  end

  private

  def normalize_configuration_value(key, value, unit)
    return value unless key == "wind_gust_threshold_mph"
    numeric = value.to_f
    return nil if numeric <= 0
    mph = (unit.to_s == "kph") ? (numeric / 1.609344) : numeric
    mph.round(2).to_s
  end

  # Apps override this to list the calendar identifiers the device can choose
  # from. Cloud returns Calendar IDs (as strings); ha-addon returns HA
  # entity_ids. Default is an empty list (no per-device selection).
  def available_calendar_identifiers_for(_device)
    []
  end

  def set_account_and_location
    @account = if current_user.is_admin?
      Account.find(params[:account_id])
    else
      current_user.accounts.find(params[:account_id])
    end
    @location = @account.locations.find(params[:location_id])
  end

  def authorize_device_access!
    if params[:account_id] && params[:location_id]
      account = Account.find_by(id: params[:account_id])
      return render(plain: "Account not found", status: :not_found) unless account
      location = account.locations.find_by(id: params[:location_id])
      return render(plain: "Location not found", status: :not_found) unless location
      @device = location.devices.find_by(id: params[:id])
    elsif current_user
      @device = current_user.accounts.flat_map(&:devices).find { |d| d.id == params[:id].to_i }
    end

    return render(plain: "Device not found", status: :not_found) unless @device

    return if current_user&.is_admin?
    return if current_user&.accounts&.exists?(id: @device.account&.id)

    if session[:device_session_token].present? && @device.session_token.present? &&
        ActiveSupport::SecurityUtils.secure_compare(@device.session_token, session[:device_session_token])
      return
    end

    render plain: "Not authorized", status: :unauthorized
  end

  def build_device_component(template, view_object, refresh: false, device: nil)
    component_class = TEMPLATE_COMPONENTS[template].constantize
    args = {view_object: view_object}

    if component_class.in?([Devices::BooxMiraComponent, Devices::MiraComponent])
      args[:refresh] = refresh
      args[:device] = device
      args[:device_url] = device ? account_location_device_path(account_id: device.account&.id, location_id: device.location&.id, id: device.id) : nil
    end

    component_class.new(**args)
  end
end
