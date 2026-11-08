# frozen_string_literal: true

class SignedScreenshotsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def show
    @device = GlobalID::Locator.locate_signed(params[:sgid], for: "screenshot")

    unless @device
      return render plain: "Not authorized", status: :unauthorized
    end

    page = params[:page].to_i
    if page == Device::YEAR_PAGE
      @device.refresh_year_page_screenshot!(request.base_url) if @device.page_image(page).blank?
    else
      @device.refresh_screenshot!(request.base_url) if @device.cached_image.blank? || params[:force] == "true"
      @device.reload
    end
    image_data = Base64.strict_decode64(@device.page_image(page))
    record_image_request

    send_data image_data, type: "image/png", disposition: "inline", filename: "#{@device.id}.png?#{Time.now.to_i}"
  end

  private

  def record_image_request
    DeviceMetricBucket.record_update!(device: @device)
  rescue => e
    Rails.logger.warn("[Metrics] Failed to record image request for device #{@device.id}: #{e.message}")
  end
end
