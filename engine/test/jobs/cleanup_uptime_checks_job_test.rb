# frozen_string_literal: true

require "test_helper"

class CleanupUptimeChecksJobTest < Minitest::Test
  def setup
    UptimeCheck.delete_all
  end

  def test_deletes_records_older_than_retention_and_keeps_newer
    old = UptimeCheck.create!(recorded_at: 91.days.ago, healthy: true)
    recent = UptimeCheck.create!(recorded_at: 1.day.ago, healthy: true)

    CleanupUptimeChecksJob.new.perform

    refute UptimeCheck.exists?(old.id)
    assert UptimeCheck.exists?(recent.id)
  end
end
