# frozen_string_literal: true

require_dependency TimeframeCore::Engine.root.join("app", "controllers", "dashboard_controller")

class DashboardController
  HA_DOMAIN_CHECKS = [
    {name: "States", healthy: :states_healthy?, last_fetched_at: :states_last_fetched_at, icon: "mdi-list-status"},
    {name: "Calendars", healthy: :calendars_healthy?, last_fetched_at: :calendars_last_fetched_at, icon: "mdi-calendar"},
    {name: "Config", healthy: :config_healthy?, last_fetched_at: :config_last_fetched_at, icon: "mdi-cog"},
    {name: "Weather", healthy: :weather_healthy?, last_fetched_at: :weather_last_fetched_at, icon: "mdi-weather-partly-cloudy"}
  ].freeze

  private

  def dashboard_template
    "dashboard/single_tenant"
  end
end
