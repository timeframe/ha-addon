# frozen_string_literal: true

class Rack::Attack
  unless Rails.env.test?
    # Bypass throttles for /d/:id requests that present the device's valid
    # display key. These are trusted (the controller authorizes on this key),
    # and crucially include the server's own headless-browser screenshot
    # renders. Without this, a burst of RefreshDeviceScreenshotJobs (e.g. after a
    # queue backup) trips the throttle below and Rack::Attack's "Retry later"
    # 429 page gets captured into the screenshot. Requests without a valid key
    # still get throttled so /d/:id can't be enumerated.
    safelist("token_devices/valid_key") do |req|
      next false unless req.path.start_with?("/d/")
      id = req.path.split("/")[2].to_s
      next false if id.empty?
      key = req.params["key"].to_s
      next false if key.empty?
      device = ::Device.find_by(id: id)
      device&.display_key.present? &&
        ActiveSupport::SecurityUtils.secure_compare(device.display_key, key)
    rescue
      false
    end

    throttle("token_devices/device", limit: 5, period: 60) do |req|
      if req.path.start_with?("/d/")
        req.path.split("/")[2]
      end
    end

    throttle("token_devices/ip", limit: 30, period: 60) do |req|
      req.ip if req.path.start_with?("/d/")
    end

    throttle("pairing/ip", limit: 5, period: 60) do |req|
      if req.post? && req.path.include?("/devices") && req.path.end_with?("/devices", "/repair")
        req.ip
      end
    end
  end
end
