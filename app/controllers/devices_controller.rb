# frozen_string_literal: true

require_dependency TimeframeCore::Engine.root.join("app", "controllers", "devices_controller")

class DevicesController
  skip_before_action :auto_sign_in_default_user!, raise: false, only: [:confirmation_image]

  # The admin settings page uses the Tailwind layout; device-facing actions
  # (preview/screenshot/confirmation) keep their existing layouts.
  layout -> { (action_name == "settings") ? "application_tw" : "application" }

  private

  def available_calendar_identifiers_for(_device)
    HomeAssistantApi.new.calendar_entities.map { |c| c[:entity_id].to_s }
  rescue
    []
  end
end
