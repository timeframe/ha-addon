# frozen_string_literal: true

require "test_helper"

class UptimeCheckTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def setup
    UptimeCheck.delete_all
  end

  # --- record! ---

  def test_record_creates_row_for_current_minute_healthy_by_default
    travel_to Time.utc(2026, 6, 12, 10, 30, 45) do
      check = UptimeCheck.record!
      assert_equal Time.utc(2026, 6, 12, 10, 30, 0), check.recorded_at
      assert check.healthy?
      assert_equal 1, UptimeCheck.count
    end
  end

  def test_record_stores_unhealthy_flag
    travel_to Time.utc(2026, 6, 12, 10, 30, 45) do
      check = UptimeCheck.record!(healthy: false)
      refute check.healthy?
    end
  end

  def test_record_stores_status_snapshot
    travel_to Time.utc(2026, 6, 12, 10, 30, 45) do
      check = UptimeCheck.record!(healthy: false, status: {"status" => "error", "checks" => {"job_queue" => {"status" => "error"}}})
      assert_equal "error", check.status_data["status"]
      assert_equal "error", check.reload.status_data.dig("checks", "job_queue", "status")
    end
  end

  def test_record_is_idempotent_within_a_minute
    travel_to Time.utc(2026, 6, 12, 10, 30, 10) do
      UptimeCheck.record!(healthy: true)
    end
    travel_to Time.utc(2026, 6, 12, 10, 30, 50) do
      UptimeCheck.record!(healthy: false)
    end
    assert_equal 1, UptimeCheck.count
    refute UptimeCheck.first.healthy?
  end

  def test_record_handles_concurrent_insert_race
    travel_to Time.utc(2026, 6, 12, 10, 30, 30) do
      minute = Time.utc(2026, 6, 12, 10, 30, 0)
      existing = UptimeCheck.create!(recorded_at: minute, healthy: true)

      # Simulate a race: find_or_initialize_by hands back a brand-new record for
      # the same minute, so save! hits the unique index and the rescue runs.
      fresh = UptimeCheck.new(recorded_at: minute)
      UptimeCheck.stub(:find_or_initialize_by, fresh) do
        result = UptimeCheck.record!(healthy: false)
        assert_equal existing.id, result.id
      end
    end
  end

  # --- uptime_percentage ---

  def test_uptime_percentage_is_100_with_no_records
    travel_to Time.utc(2026, 6, 12, 10, 30, 0) do
      assert_in_delta 100.0, UptimeCheck.uptime_percentage(24.hours), 0.001
    end
  end

  def test_uptime_percentage_is_100_when_only_current_minute_recorded
    travel_to Time.utc(2026, 6, 12, 0, 5, 30) do
      UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 0, 5, 0), healthy: true)
      # No completed minute is covered yet, so there is nothing to measure.
      assert_in_delta 100.0, UptimeCheck.uptime_percentage(24.hours), 0.001
    end
  end

  def test_uptime_percentage_full
    travel_to Time.utc(2026, 6, 12, 0, 5, 30) do
      (0..4).each { |m| UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 0, m, 0), healthy: true) }
      # Expected completed minutes 00:00..00:04 = 5, all present.
      assert_in_delta 100.0, UptimeCheck.uptime_percentage(24.hours), 0.001
    end
  end

  def test_uptime_percentage_partial
    travel_to Time.utc(2026, 6, 12, 0, 5, 30) do
      [0, 1, 3, 4].each { |m| UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 0, m, 0), healthy: true) }
      # 4 of 5 expected minutes present (00:02 missing).
      assert_in_delta 80.0, UptimeCheck.uptime_percentage(24.hours), 0.001
    end
  end

  # --- current_state ---

  def test_current_state_down_with_no_records
    assert_equal :down, UptimeCheck.current_state
  end

  def test_current_state_down_when_stale
    travel_to Time.utc(2026, 6, 12, 10, 30, 0) do
      UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 10, 25, 0), healthy: true)
      assert_equal :down, UptimeCheck.current_state
    end
  end

  def test_current_state_operational_when_recent_and_healthy
    travel_to Time.utc(2026, 6, 12, 10, 30, 30) do
      UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 10, 29, 0), healthy: true)
      assert_equal :operational, UptimeCheck.current_state
    end
  end

  def test_current_state_degraded_when_recent_and_unhealthy
    travel_to Time.utc(2026, 6, 12, 10, 30, 30) do
      UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 10, 29, 0), healthy: false)
      assert_equal :degraded, UptimeCheck.current_state
    end
  end

  # --- daily_summary ---

  def test_daily_summary_all_no_data_with_no_records
    travel_to Time.utc(2026, 6, 12, 0, 5, 0) do
      summary = UptimeCheck.daily_summary(days: 3)
      assert_equal 3, summary.size
      assert(summary.all? { |d| d[:status] == :no_data })
      assert_equal [Date.new(2026, 6, 10), Date.new(2026, 6, 11), Date.new(2026, 6, 12)], summary.map { |d| d[:date] }
    end
  end

  def test_daily_summary_marks_up_degraded_down_and_no_data
    travel_to Time.utc(2026, 6, 12, 0, 5, 30) do
      # Today (06-12): expected completed minutes 00:00..00:04 = 5.
      (0..4).each { |m| UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 0, m, 0), healthy: true) }

      summary = UptimeCheck.daily_summary(days: 2)
      yesterday, today = summary

      # Yesterday is before the first record → no data.
      assert_equal Date.new(2026, 6, 11), yesterday[:date]
      assert_equal :no_data, yesterday[:status]

      assert_equal Date.new(2026, 6, 12), today[:date]
      assert_equal :up, today[:status]
      assert_in_delta 100.0, today[:uptime_pct], 0.001
    end
  end

  def test_daily_summary_degraded_when_unhealthy_minute
    travel_to Time.utc(2026, 6, 12, 0, 5, 30) do
      (0..3).each { |m| UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 0, m, 0), healthy: true) }
      UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 0, 4, 0), healthy: false)

      today = UptimeCheck.daily_summary(days: 1).last
      assert_equal :degraded, today[:status]
    end
  end

  def test_daily_summary_down_when_minutes_missing
    travel_to Time.utc(2026, 6, 12, 0, 5, 30) do
      # Only 3 of the 5 expected minutes recorded.
      [0, 1, 2].each { |m| UptimeCheck.create!(recorded_at: Time.utc(2026, 6, 12, 0, m, 0), healthy: true) }

      today = UptimeCheck.daily_summary(days: 1).last
      assert_equal :down, today[:status]
      assert_in_delta 60.0, today[:uptime_pct], 0.001
    end
  end
end
