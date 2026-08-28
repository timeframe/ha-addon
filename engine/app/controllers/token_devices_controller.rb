# frozen_string_literal: true

class TokenDevicesController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  before_action :authorize_via_tokens!
  layout "device"

  after_action do
    response.headers["X-Deploy-Time"] = DEPLOY_TIME.to_s
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def show
    if @device.pending_confirmation?
      render "devices/confirmation", locals: {device: @device}, layout: params[:layout] != "false"
      return
    end

    @device.update_column(:last_connection_at, Time.current) unless params[:at].present? || params[:generation] == "true"

    template = @device.active_template
    refresh = @device.realtime_display? && params[:refresh] != "false"
    @refresh = refresh

    tz = @device.location&.time_zone.presence || "UTC"
    current_time = params[:at].present? ? ActiveSupport::TimeZone[tz].parse(params[:at]) : nil
    view_object = @device.device_content(current_time: current_time)
    view_object[:configuration] = @device.try(:configuration) || {}

    if Device.charge_reminder?(view_object) && params[:charge_reminder] != "false"
      render Devices::ChargeReminderComponent.new(view_object: view_object), layout: params[:layout] != "false"
      return
    end

    @banner = view_object[:banner] unless template == "mira"
    @low_battery_banner = Device.low_battery_banner(template, view_object)

    component = DevicesController::TEMPLATE_COMPONENTS[template].constantize.new(view_object: view_object)
    render component, layout: params[:layout] != "false"
  rescue => e
    render "devices/error", locals: {klass: e.class.to_s, message: e.message, backtrace: e.backtrace}
  end

  def screenshot
    @device.refresh_screenshot!(request.base_url) if @device.cached_image.blank? || params[:force] == "true"
    @device.reload
    image_data = Base64.strict_decode64(@device.cached_image)

    send_data image_data, type: "image/png", disposition: "inline", filename: "#{@device.id}.png?#{Time.now.to_i}"
  end

  private

  def authorize_via_tokens!
    @device = Device.find_by(id: params[:id])

    unless @device&.display_key.present? && params[:key].present? &&
        ActiveSupport::SecurityUtils.secure_compare(@device.display_key, params[:key].to_s)
      render plain: "Not authorized", status: :unauthorized
    end
  end
end
