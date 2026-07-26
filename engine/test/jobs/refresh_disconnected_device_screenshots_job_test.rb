# frozen_string_literal: true

require "test_helper"

class RefreshDisconnectedDeviceScreenshotsJobTest < ActiveJob::TestCase
  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def setup
    GoodJob::Job.delete_all
    PendingDevice.delete_all
    Device.delete_all
  end

  def teardown
    GoodJob::Job.delete_all
    PendingDevice.delete_all
    Device.delete_all
  end

  def test_enqueues_a_staggered_refresh_for_each_disconnected_device
    device = disconnected_device

    assert_enqueued_with(job: RefreshDeviceScreenshotJob, args: [device.id]) do
      RefreshDisconnectedDeviceScreenshotsJob.new.perform
    end
  end

  def test_skips_devices_that_already_have_a_pending_job
    device = disconnected_device
    # A future-scheduled job still makes the device "pending" so the fan-out
    # must not enqueue another one (idempotency), even though before_enqueue
    # would allow a sooner enqueue.
    insert_pending_job(device.id, scheduled_at: 10.minutes.from_now)

    assert_no_enqueued_jobs only: RefreshDeviceScreenshotJob do
      RefreshDisconnectedDeviceScreenshotsJob.new.perform
    end
  end

  private

  def disconnected_device
    Device.create!(
      location: test_location,
      name: "disconnected-device",
      model: "trmnl_og",
      mac_address: random_mac,
      confirmed_at: Time.current,
      last_connection_at: 2.hours.ago
    )
  end

  def insert_pending_job(device_id, scheduled_at:)
    GoodJob::Job.create!(
      queue_name: "screenshots",
      job_class: "RefreshDeviceScreenshotJob",
      scheduled_at: scheduled_at,
      serialized_params: {"job_class" => "RefreshDeviceScreenshotJob", "arguments" => [device_id]}
    )
  end

  def random_mac
    format("02:00:00:%02x:%02x:%02x", rand(256), rand(256), rand(256)).upcase
  end
end
