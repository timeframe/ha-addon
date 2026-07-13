# frozen_string_literal: true

class StatusController < ApplicationController
  layout "application_tw"

  def index
    @state = UptimeCheck.current_state
    @uptime_windows = UptimeCheck::WINDOWS.map { |label, duration| [label, UptimeCheck.uptime_percentage(duration)] }
    @daily_summary = UptimeCheck.daily_summary(days: 90)

    @api = HomeAssistantApi.new
    @statuses = DashboardController::HA_DOMAIN_CHECKS.map do |check|
      {
        name: check[:name],
        icon: check[:icon],
        healthy: @api.send(check[:healthy]),
        last_fetched_at: @api.send(check[:last_fetched_at])&.iso8601
      }
    end
  end
end
