# frozen_string_literal: true

require "test_helper"

class DeviceMetricBucketTest < ActiveSupport::TestCase
  def setup
    DeviceMetricBucket.delete_all
    @device = Device.create!(
      location: test_location,
      name: "Metrics device #{SecureRandom.hex(4)}",
      model: "trmnl_og",
      mac_address: SecureRandom.hex(6),
      confirmed_at: Time.current
    )
  end

  def teardown
    @device&.destroy!
  end

  test "aggregates battery readings and poll outcomes by hour" do
    travel_to Time.zone.local(2026, 9, 4, 10, 15) do
      DeviceMetricBucket.record_poll!(device: @device, battery_percent: 72, battery_voltage: 3.91, charging: false, no_update: false)
      DeviceMetricBucket.record_poll!(device: @device, battery_percent: 68, battery_voltage: 3.82, charging: true, no_update: true)
      DeviceMetricBucket.record_update!(device: @device)

      bucket = @device.device_metric_buckets.first!
      assert_equal Time.current.beginning_of_hour, bucket.bucket_at
      assert_equal 68, bucket.battery_percent_last
      assert_equal 68, bucket.battery_percent_min
      assert_equal 72, bucket.battery_percent_max
      assert_equal 3.82, bucket.battery_voltage_last
      assert_equal 3.82, bucket.battery_voltage_min
      assert_equal 3.91, bucket.battery_voltage_max
      assert_equal 2, bucket.battery_sample_count
      assert bucket.charging?
      assert_equal 1, bucket.poll_update_count
      assert_equal 1, bucket.poll_no_update_count
    end
  end

  test "records counters without inventing battery samples" do
    DeviceMetricBucket.record_poll!(device: @device, battery_percent: nil, battery_voltage: nil, charging: nil, no_update: true)
    DeviceMetricBucket.record_update!(device: @device)

    bucket = @device.device_metric_buckets.first!
    assert_nil bucket.battery_percent_last
    assert_nil bucket.battery_voltage_last
    assert_nil bucket.charging
    assert_equal 0, bucket.battery_sample_count
    assert_equal 1, bucket.poll_update_count
    assert_equal 1, bucket.poll_no_update_count
  end

  test "is deleted with its device" do
    device = Device.create!(name: "Metrics cascade #{SecureRandom.hex(4)}", model: "boox_mira")
    DeviceMetricBucket.record_update!(device:)

    device.destroy!

    assert_empty DeviceMetricBucket.where(device_id: device.id)
  end
end
