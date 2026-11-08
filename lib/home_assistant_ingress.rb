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

  # importmap-rails memoizes the rendered importmap JSON and modulepreload
  # paths on the (process-wide) map, keyed only by a fixed cache key. Those
  # paths include relative_url_root, so whichever request rendered first -
  # ingress or direct - would fix the prefix for every later request: the HA
  # sidebar could get bare /assets/... module URLs (which hit Home
  # Assistant's own server and 404), or direct visitors could get ingress
  # ones. Vary the cache key by the prefix so each gets its own entry.
  module ImportmapTags
    def javascript_importmap_tags(entry_point = "application", importmap: Rails.application.importmap)
      safe_join [
        javascript_inline_importmap_tag(importmap.to_json(resolver: self, cache_key: ingress_importmap_cache_key(:json))),
        javascript_importmap_module_preload_tags(importmap, entry_point:),
        javascript_import_module_tag(entry_point)
      ], "\n"
    end

    def javascript_importmap_module_preload_tags(importmap = Rails.application.importmap, entry_point: "application")
      packages = importmap.preloaded_module_packages(resolver: self, entry_point:, cache_key: ingress_importmap_cache_key(entry_point))

      _generate_preload_tags(packages) { |path, package| [path, {integrity: package.integrity}] }
    end

    private

    def ingress_importmap_cache_key(base)
      "#{base}@#{config.relative_url_root}"
    end
  end
end
