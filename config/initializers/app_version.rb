# frozen_string_literal: true

# Identifies the running release. It MUST be identical across every process of a
# single deploy (web, worker, etc.) and change when new code ships — it's what
# tells long-lived realtime display pages to reload after a deploy.
#
# It must NOT be derived from per-process boot time: the web and worker
# processes boot at different seconds, so a `Time.now` value would differ
# between the process that renders the display page and the worker process that
# runs DeviceBroadcaster. Every cross-process refresh broadcast would then look
# like a brand-new deploy and force a full-page reload (an e-ink flash) every
# minute.
#
# Prefer an explicit/platform-provided release id; otherwise fall back to a
# digest of the compiled assets (built once per deploy, identical across all
# dynos), and finally to boot time for local single-process runs.
DEPLOY_TIME =
  ENV["DEPLOY_VERSION"].presence ||
  ENV["HEROKU_RELEASE_VERSION"].presence ||
  ENV["HEROKU_SLUG_COMMIT"].presence ||
  begin
    builds = Dir[Rails.root.join("app/assets/builds/*")].sort
    builds.any? ? Digest::MD5.hexdigest(builds.map { |f| File.read(f) }.join) : Time.now.to_i
  rescue
    Time.now.to_i
  end
