# frozen_string_literal: true

# Slim onboarding wizard for the single-tenant add-on: name and choose the
# device model, pair it (unless it needs no pairing code, e.g. Visionect), and
# pick a layout (only for models that offer more than one). The account,
# location, and Home Assistant calendars are set up automatically, so those
# steps are omitted.
class OnboardingFlow
  STEP_LABELS = {create_device: "Device", pairing: "Pair", layout: "Layout"}.freeze

  def initialize(user, session = {})
    @user = user
    @session = session || {}
  end

  def account
    @account ||= @user.accounts.first
  end

  def location
    @location ||= account.locations.order(:created_at).first
  end

  def onboarding_device
    return @onboarding_device if defined?(@onboarding_device)

    @onboarding_device = account.devices.find_by(id: @session[:onboarding_device_id])
  end

  def current_step
    natural = natural_step
    override = @session[:onboarding_step_override]&.to_sym
    if override && visible_steps.include?(override)
      natural_index = (natural == :done) ? visible_steps.length : visible_steps.index(natural)
      # Only allow navigating back to an already-reached step, never ahead.
      return override if visible_steps.index(override) < natural_index
    end
    natural
  end

  def natural_step
    return :create_device unless onboarding_device
    return :pairing if needs_pairing? && !paired?
    return :layout if needs_layout? && !layout_chosen?

    :done
  end

  def complete?
    current_step == :done
  end

  def needs_pairing?
    onboarding_device.present? && !onboarding_device.visionect?
  end

  def needs_layout?
    onboarding_device.present? && onboarding_device.template_options.present?
  end

  def paired?
    onboarding_device.pending_device.present?
  end

  def visible_steps
    steps = [:create_device]
    steps << :pairing if needs_pairing?
    steps << :layout if needs_layout?
    steps
  end

  def can_go_back?
    idx = visible_steps.index(current_step)
    idx.present? && idx.positive?
  end

  def previous_step
    idx = visible_steps.index(current_step)
    return nil unless idx&.positive?

    visible_steps[idx - 1]
  end

  def stepper
    steps = visible_steps
    current_index = (current_step == :done) ? steps.length : steps.index(current_step)

    steps.each_with_index.map do |step, index|
      status = if index < current_index
        :complete
      elsif index == current_index
        :current
      else
        :upcoming
      end
      {step: step, label: STEP_LABELS[step], status: status, number: index + 1}
    end
  end

  private

  def layout_chosen?
    @session[:onboarding_layout_chosen].present?
  end
end
