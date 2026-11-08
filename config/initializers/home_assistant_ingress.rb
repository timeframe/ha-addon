# frozen_string_literal: true

require Rails.root.join("lib/home_assistant_ingress").to_s

# Run first so everything downstream sees the ingress prefix as SCRIPT_NAME.
Rails.application.config.middleware.insert_before 0, HomeAssistantIngress

# Route helpers read SCRIPT_NAME on their own, but asset helpers
# (stylesheet_link_tag, javascript_importmap_tags, asset_path) only look at
# config.relative_url_root. Set it on this request's controller config copy
# (never the class-level config) so asset URLs carry the ingress prefix too.
ActiveSupport.on_load(:action_controller_base) do
  prepend_before_action do
    config.relative_url_root = request.script_name.presence
  end
end
