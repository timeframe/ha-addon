# frozen_string_literal: true

# :nocov:
class ScreenshotService
  VIEWPORT_WIDTH = 480
  VIEWPORT_HEIGHT = 800

  # Ferrum's per-command timeout and browser-launch timeout (seconds).
  COMMAND_TIMEOUT = 15
  PROCESS_TIMEOUT = 20

  # Hard wall-clock ceiling for a single capture. If a capture exceeds this we
  # force-kill the browser process - the only reliable way to unblock a thread
  # parked in a corrupted/deadlocked CDP websocket read - so a job can never
  # wedge indefinitely the way RefreshDeviceScreenshotJob did in production.
  CAPTURE_DEADLINE = 20

  # The shared browser is not thread-safe and is driven over a single CDP
  # websocket. Concurrent GoodJob threads interleaving commands corrupt the
  # protocol stream and deadlock both threads. Serialize all access.
  MUTEX = Mutex.new

  class << self
    def capture(url, width: VIEWPORT_WIDTH, height: VIEWPORT_HEIGHT, grayscale_depth: 2, rotate: true, raw: false, dither: true, grayscale_only: false)
      MUTEX.synchronize do
        png_base64 = capture_with_deadline(url, width: width, height: height)

        if raw
          png_base64
        elsif grayscale_only
          image = MiniMagick::Image.read(Base64.decode64(png_base64), ".png")
          image.rotate "90" if rotate
          image.combine_options do |c|
            c.colorspace "Gray"
            c.dither("None")
            c.colors 16
            c.depth 4
          end
          image.format "png"
          Base64.strict_encode64(image.to_blob)
        else
          process_image(Base64.decode64(png_base64), grayscale_depth: grayscale_depth, rotate: rotate, dither: dither)
        end
      ensure
        # Quit Chromium after every capture so the worker never holds a browser
        # while idle between refresh cycles; a persistent browser kept the dyno
        # over its 512MB quota (R14). Relaunch cost is negligible at this cadence.
        reset!
      end
    end

    def browser
      @browser ||= Ferrum::Browser.new(
        headless: "new",
        browser_path: find_browser_path,
        env: {
          "LD_PRELOAD" => nil,
          "MALLOC_CONF" => nil
        },
        window_size: [VIEWPORT_WIDTH, VIEWPORT_HEIGHT],
        timeout: COMMAND_TIMEOUT,
        process_timeout: PROCESS_TIMEOUT,
        pending_connection_errors: false,
        browser_options: {
          "no-sandbox" => nil,
          "disable-gpu" => nil,
          "disable-dev-shm-usage" => nil,
          "disable-software-rasterizer" => nil,
          "font-render-hinting" => "none",
          "disable-font-subpixel-positioning" => nil
        }
      )
    end

    def reset!
      @browser&.quit
      @browser = nil
    end

    private

    # Runs the capture on a worker thread and enforces a hard wall-clock
    # deadline. If the deadline passes, force-kill the browser (which unblocks
    # the worker's stuck syscall), abandon the worker, and raise so the job
    # fails fast instead of sitting in Running forever.
    def capture_with_deadline(url, width:, height:, deadline: CAPTURE_DEADLINE)
      worker = Thread.new do
        Thread.current.report_on_exception = false
        capture_screenshot_with_retry(url, width: width, height: height)
      end

      if worker.join(deadline).nil?
        Rails.logger.error "[ScreenshotService] Capture exceeded #{deadline}s; killing browser"
        reset!
        worker.kill
        worker.join(5)
        raise Timeout::Error, "screenshot capture exceeded #{deadline}s"
      end

      worker.value
    end

    def capture_screenshot_with_retry(url, width:, height:)
      capture_screenshot(url, width: width, height: height)
    rescue Ferrum::DeadBrowserError, Ferrum::NoSuchPageError => e
      Rails.logger.warn "[ScreenshotService] Browser dead, resetting and retrying: #{e.message}"
      reset!
      capture_screenshot(url, width: width, height: height)
    end

    def capture_screenshot(url, width:, height:)
      page = browser.create_page
      begin
        page.command("Emulation.setDeviceMetricsOverride",
          width: width,
          height: height,
          deviceScaleFactor: 1,
          mobile: false)
        page.go_to(url)
        png_base64 = page.screenshot(format: "png")
      ensure
        begin
          page&.close
        rescue Ferrum::Error
          # Page or browser already gone; nothing to clean up.
        end
      end
      png_base64
    end

    def process_image(png_data, grayscale_depth: 2, rotate: true, dither: true)
      image = MiniMagick::Image.read(png_data, ".png")
      image.rotate "90" if rotate
      image.combine_options do |c|
        c.colorspace "Gray"
        c.dither("None") unless dither
        c.dither("FloydSteinberg") if dither
        c.posterize(2**grayscale_depth)
        c.depth grayscale_depth
      end
      image.format "png"
      Base64.strict_encode64(image.to_blob)
    end

    def find_browser_path
      ENV["BROWSER_PATH"].presence ||
        ENV["GOOGLE_CHROME_BIN"].presence ||
        ENV["CHROME_BIN"].presence ||
        [
          "/usr/bin/chromium",
          "/usr/bin/chromium-browser",
          "/usr/bin/google-chrome",
          "/usr/bin/google-chrome-stable",
          "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        ].find { |path| File.exist?(path) }
    end
  end
end
# :nocov:
