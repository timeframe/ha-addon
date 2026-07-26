# frozen_string_literal: true

class RefreshDisconnectedDeviceScreenshotsJob < ActiveJob::Base
  def perform
    pending_ids = RefreshDeviceScreenshotJob.pending_device_ids
    Device.where(model: Device::SCREENSHOTTED_MODELS)
      .where("last_connection_at IS NULL OR last_connection_at < ?", 1.hour.ago)
      .where.not(id: pending_ids)
      .find_each.with_index do |device, index|
        RefreshDeviceScreenshotJob.set(wait: (index * 30).seconds).perform_later(device.id)
      end
  end
end
