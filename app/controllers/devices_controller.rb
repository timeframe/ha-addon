# frozen_string_literal: true

require_dependency TimeframeCore::Engine.root.join("app", "controllers", "devices_controller")

class DevicesController
  skip_before_action :auto_sign_in_default_user!, raise: false, only: [:confirmation_image]

  # Admin-facing pages use the app (Tailwind) layout; device-facing actions
  # (show/preview_frame) render with the "device" layout at render time.
  layout "application"

  private

  def available_calendar_identifiers_for(_device)
    HomeAssistantApi.new.calendar_entities.map { |c| c[:entity_id].to_s }
  rescue
    []
  end
end
