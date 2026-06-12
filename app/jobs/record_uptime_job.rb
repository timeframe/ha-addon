# frozen_string_literal: true

# Records a per-minute uptime heartbeat. The mere existence of the row marks the
# app as "up" for that minute; the healthy flag reflects whether every Home
# Assistant domain check is passing. Runs every minute via GoodJob cron.
class RecordUptimeJob < ActiveJob::Base
  def perform
    healthy =
      begin
        api = HomeAssistantApi.new
        DashboardController::HA_DOMAIN_CHECKS.all? { |check| api.send(check[:healthy]) }
      rescue
        false
      end

    UptimeCheck.record!(healthy: healthy)
  end
end
