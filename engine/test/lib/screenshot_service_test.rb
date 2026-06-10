# frozen_string_literal: true

require "test_helper"

class ScreenshotServiceTest < Minitest::Test
  def teardown
    ScreenshotService.instance_variable_set(:@browser, nil)
    ScreenshotService.instance_variable_set(:@last_screenshot_at, nil)
  end

  def test_capture_with_deadline_returns_worker_result
    result = ScreenshotService.stub(:capture_screenshot_with_retry, "png-data") do
      ScreenshotService.send(:capture_with_deadline, "http://example.test", width: 100, height: 100, deadline: 5)
    end

    assert_equal "png-data", result
  end

  def test_capture_with_deadline_force_kills_browser_when_exceeded
    reset_called = false
    slow_capture = ->(*, **) { sleep 2 }

    ScreenshotService.stub(:capture_screenshot_with_retry, slow_capture) do
      ScreenshotService.stub(:reset!, -> { reset_called = true }) do
        error = assert_raises(Timeout::Error) do
          ScreenshotService.send(:capture_with_deadline, "http://example.test", width: 100, height: 100, deadline: 0.2)
        end
        assert_match(/exceeded/, error.message)
      end
    end

    assert reset_called, "expected the browser to be force-killed via reset! on deadline"
  end

  def test_capture_with_deadline_propagates_worker_errors
    boom = ->(*, **) { raise "capture failed" }

    ScreenshotService.stub(:capture_screenshot_with_retry, boom) do
      error = assert_raises(RuntimeError) do
        ScreenshotService.send(:capture_with_deadline, "http://example.test", width: 100, height: 100, deadline: 5)
      end
      assert_equal "capture failed", error.message
    end
  end

  def test_capture_serializes_concurrent_calls
    counter_mutex = Mutex.new
    active = 0
    max_active = 0

    serialized_capture = lambda do |*, **|
      counter_mutex.synchronize do
        active += 1
        max_active = [max_active, active].max
      end
      sleep 0.05
      counter_mutex.synchronize { active -= 1 }
      "AAAA"
    end

    ScreenshotService.stub(:capture_screenshot_with_retry, serialized_capture) do
      threads = 4.times.map do
        Thread.new do
          ScreenshotService.capture("http://example.test", width: 100, height: 100, raw: true)
        end
      end
      threads.each(&:join)
    end

    assert_equal 1, max_active, "MUTEX should prevent concurrent browser access"
  end
end
