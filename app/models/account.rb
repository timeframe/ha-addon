# frozen_string_literal: true

require_dependency TimeframeCore::Engine.root.join("app", "models", "account").to_s

# ha-addon extends the shared engine Account with the read-only calendars
# imported from Home Assistant (used only by the add-on's Events page).
class Account
  has_many :calendars, dependent: :destroy
end
