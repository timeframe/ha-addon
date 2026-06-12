# frozen_string_literal: true

class CleanupUptimeChecksJob < ActiveJob::Base
  def perform
    UptimeCheck.where("recorded_at < ?", UptimeCheck::RETENTION_PERIOD.ago).delete_all
  end
end
