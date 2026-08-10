# frozen_string_literal: true

require "test_helper"

class RefreshDeviceScreenshotJobTest < ActiveJob::TestCase
  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def setup
    GoodJob::Job.delete_all
    PendingDevice.delete_all
    Device.delete_all
    @device = Device.create!(
      location: test_location,
      name: "screenshot-job-device",
      model: "trmnl_og",
      mac_address: random_mac,
      confirmed_at: Time.current
    )
  end

  def teardown
    GoodJob::Job.delete_all
    PendingDevice.delete_all
    Device.delete_all
  end

  # --- perform ---

  def test_perform_refreshes_the_device_screenshot
    refreshed = false
    @device.stub(:refresh_screenshot!, -> { refreshed = true }) do
      Device.stub(:find_by, @device) do
        RefreshDeviceScreenshotJob.new.perform(@device.id)
      end
    end
    assert refreshed
  end

  def test_perform_no_ops_for_a_missing_device
    Device.stub(:find_by, nil) do
      assert_nil RefreshDeviceScreenshotJob.new.perform(-1)
    end
  end

  def test_perform_propagates_capture_errors
    @device.stub(:refresh_screenshot!, -> { raise "capture boom" }) do
      Device.stub(:find_by, @device) do
        error = assert_raises(RuntimeError) { RefreshDeviceScreenshotJob.new.perform(@device.id) }
        assert_equal "capture boom", error.message
      end
    end
  end

  # --- before_enqueue dedupe (ignores future-scheduled jobs) ---

  def test_skips_enqueue_when_a_due_job_already_exists
    insert_job(@device.id, scheduled_at: 1.minute.ago)

    assert_no_enqueued_jobs only: RefreshDeviceScreenshotJob do
      RefreshDeviceScreenshotJob.perform_later(@device.id)
    end
  end

  def test_enqueues_when_only_a_future_job_exists
    insert_job(@device.id, scheduled_at: 10.minutes.from_now)

    assert_enqueued_jobs 1, only: RefreshDeviceScreenshotJob do
      RefreshDeviceScreenshotJob.perform_later(@device.id)
    end
  end

  # --- ready_job_pending? ---

  def test_ready_job_pending_true_for_a_due_job
    insert_job(@device.id, scheduled_at: nil)
    assert RefreshDeviceScreenshotJob.ready_job_pending?(@device.id)
  end

  def test_ready_job_pending_ignores_future_finished_and_other_devices
    insert_job(@device.id, scheduled_at: 5.minutes.from_now)
    insert_job(@device.id, scheduled_at: 1.minute.ago, finished_at: Time.current)
    insert_job(999_999, scheduled_at: 1.minute.ago)

    refute RefreshDeviceScreenshotJob.ready_job_pending?(@device.id)
  end

  def test_ready_job_pending_is_false_when_the_lookup_raises
    GoodJob::Job.stub(:where, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      refute RefreshDeviceScreenshotJob.ready_job_pending?(@device.id)
    end
  end

  # --- pending_device_ids ---

  def test_pending_device_ids_includes_due_and_future_but_not_finished
    insert_job(@device.id, scheduled_at: 5.minutes.from_now)
    insert_job(777, scheduled_at: nil)
    insert_job(888, scheduled_at: 1.minute.ago, finished_at: Time.current)

    assert_equal [@device.id, 777].sort, RefreshDeviceScreenshotJob.pending_device_ids.sort
  end

  def test_pending_device_ids_is_empty_when_the_lookup_raises
    GoodJob::Job.stub(:where, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      assert_equal [], RefreshDeviceScreenshotJob.pending_device_ids
    end
  end

  private

  def insert_job(device_id, scheduled_at:, finished_at: nil)
    GoodJob::Job.create!(
      queue_name: "screenshots",
      job_class: "RefreshDeviceScreenshotJob",
      scheduled_at: scheduled_at,
      finished_at: finished_at,
      serialized_params: {"job_class" => "RefreshDeviceScreenshotJob", "arguments" => [device_id]}
    )
  end

  def random_mac
    format("02:00:00:%02x:%02x:%02x", rand(256), rand(256), rand(256)).upcase
  end
end
