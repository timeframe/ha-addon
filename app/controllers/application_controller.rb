# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  before_action :auto_sign_in_default_user!
  before_action :authenticate_user!

  private

  def auto_sign_in_default_user!
    return if warden.authenticated?(:user)

    user = User.first
    unless user
      config = begin
        HomeAssistantApi.new.config_data
      rescue
        {}
      end

      account = Account.first || Account.create!(name: "Home", **host_display_units(config))

      unless account.locations.exists?
        account.locations.create!(
          name: config[:location_name] || "Home",
          latitude: config[:latitude] || 0,
          longitude: config[:longitude] || 0,
          time_zone: config[:time_zone] || "America/Chicago"
        )
      end

      user = User.create!(email: "homeassistant@timeframe.local")
      user.accounts << account
    end

    warden.set_user(user, scope: :user)
  end

  # Display units for a new account, derived from the Home Assistant host
  # unit_system (the settings page can override them afterwards).
  def host_display_units(config)
    system = config[:unit_system] || {}
    {
      temperature_unit: (system[:temperature] == "°C") ? "C" : "F",
      speed_unit: {"km/h" => "kph", "mi/h" => "mph"}[system[:wind_speed]] || "mph",
      precipitation_unit: %w[mm cm].include?(system[:accumulated_precipitation]) ? system[:accumulated_precipitation] : "in"
    }
  end

  def authenticate_user!
    head :unauthorized unless current_user
  end

  def current_user
    warden&.user(:user)
  end

  def warden
    request.env["warden"]
  end
end
