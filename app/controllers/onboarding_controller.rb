# frozen_string_literal: true

# Guided device-setup wizard for the add-on. Each step redirects to the next
# via OnboardingFlow, which derives the current step from the created device.
class OnboardingController < ApplicationController
  before_action :clear_step_override, only: %i[create_device pair set_layout]
  before_action :require_onboarding_device, only: %i[pair set_layout]

  def show
    if flow.complete?
      device = flow.onboarding_device
      clear_onboarding_session
      return redirect_to settings_account_location_device_path(device.location.account, device.location, device),
        notice: "You're all set up!"
    end

    @flow = flow
    @step = flow.current_step
    @account = flow.account
  end

  def create_device
    model = params[:device_model].to_s
    return redirect_to onboarding_path, alert: "Pick a device model." unless Device::SUPPORTED_MODELS.key?(model)

    name = params[:device_name].to_s.strip.presence || "Timeframe"
    if (device = flow.onboarding_device)
      device.update!(name: name, model: model)
    else
      device = flow.location.devices.create!(name: name, model: model, mac_address: SecureRandom.hex(6), confirmed_at: Time.current)
      session[:onboarding_device_id] = device.id
    end
    redirect_to onboarding_path, notice: "Device \"#{device.name}\" created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to onboarding_path, alert: e.message
  end

  def pair
    device = flow.onboarding_device
    pending = PendingDevice.find_active_by_code(params[:pairing_code].to_s.strip)
    return redirect_to onboarding_path, alert: "Invalid or expired pairing code." unless pending

    pending.link_to!(device)
    device.rotate_session_token!
    refresh_screenshot(device)
    redirect_to onboarding_path, notice: "\"#{device.name}\" paired successfully."
  end

  def set_layout
    device = flow.onboarding_device
    template = params[:display_template].to_s
    return redirect_to onboarding_path, alert: "Pick a valid layout." unless valid_template?(device, template)

    device.update!(display_template: template)
    session[:onboarding_layout_chosen] = template
    refresh_screenshot(device)
    redirect_to onboarding_path
  end

  def back
    if (step = flow.previous_step)
      session[:onboarding_step_override] = step.to_s
    end
    redirect_to onboarding_path
  end

  private

  def flow
    @flow ||= OnboardingFlow.new(current_user, session)
  end

  def require_onboarding_device
    redirect_to onboarding_path unless flow.onboarding_device
  end

  def valid_template?(device, template)
    Array(device.template_options).any? { |option| option[:name] == template }
  end

  def refresh_screenshot(device)
    RefreshDeviceScreenshotJob.perform_later(device.id) if device.screenshotted?
  end

  def clear_onboarding_session
    session.delete(:onboarding_device_id)
    session.delete(:onboarding_layout_chosen)
    session.delete(:onboarding_step_override)
  end

  def clear_step_override
    session.delete(:onboarding_step_override)
  end
end
