# frozen_string_literal: true

# Settings page for the single-tenant add-on. Only exposes unit preferences,# which are stored on the Account (seeded from the Home Assistant host config).
class SettingsController < ApplicationController
  ALLOWED_UNITS = {
    temperature_unit: %w[F C],
    speed_unit: %w[mph kph],
    precipitation_unit: %w[in mm cm]
  }.freeze

  def show
    @account = current_user.accounts.first
  end

  def update
    @account = current_user.accounts.first
    @account.update(unit_params)
    redirect_to settings_path, notice: "Settings updated."
  end

  private

  def unit_params
    params.require(:account).permit(:temperature_unit, :speed_unit, :precipitation_unit).to_h.select do |key, value|
      ALLOWED_UNITS[key.to_sym]&.include?(value)
    end
  end
end
