# frozen_string_literal: true

# Home Assistant ingress serves the add-on UI from
# /api/hassio_ingress/<token>/..., strips that prefix before proxying the
# request to the add-on, and passes it along in the X-Ingress-Path header.
#
# Rails doesn't know about the prefix on its own, so every generated URL
# (/events, /settings, /assets/...) would point at Home Assistant's root and
# 404. Exposing the prefix as SCRIPT_NAME makes Rails treat it as the app's
# mount point: route helpers and redirects pick it up automatically, and the
# controller hook in config/initializers/home_assistant_ingress.rb applies it
# to asset tags as well.
#
# Requests that don't come through ingress (TRMNL and other devices talking
# to port 8099 directly) have no header and are left untouched.
class HomeAssistantIngress
  HEADER = "HTTP_X_INGRESS_PATH"
  # Supervisor tokens are URL-safe base64. Anything else is ignored so a
  # forged header can't inject arbitrary text into generated links.
  VALID_PATH = %r{\A/api/hassio_ingress/[A-Za-z0-9_-]+\z}

  def initialize(app)
    @app = app
  end

  def call(env)
    ingress_path = env[HEADER].to_s.chomp("/")
    env["SCRIPT_NAME"] = ingress_path if VALID_PATH.match?(ingress_path)
    @app.call(env)
  end
end
