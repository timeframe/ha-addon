# frozen_string_literal: true

# :nocov:
class RefreshDeviceScreenshotJob < ActiveJob::Base
  queue_as :screenshots

  def perform(device_id)
    device = Device.find_by(id: device_id)
    return unless device

    device.refresh_screenshot!
  rescue => e
    Rails.logger.error "[RefreshDeviceScreenshotJob] Failed for device #{device_id}: #{e.message}"
  end
end
# :nocov:
