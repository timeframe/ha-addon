# frozen_string_literal: true

require "test_helper"

class HomeAssistantIngressIntegrationTest < ActionDispatch::IntegrationTest
  INGRESS = "/api/hassio_ingress/abc123_-XYZ"

  test "links and assets carry the ingress prefix" do
    get "/status", headers: {"X-Ingress-Path" => INGRESS}
    assert_response :success

    assert_includes response.body, %(href="#{INGRESS}/events")
    assert_includes response.body, %(href="#{INGRESS}/settings")
    assert_includes response.body, %(href="#{INGRESS}/status")
    assert_match %r{href="#{INGRESS}/assets/application_tailwind-[^"]+\.css"}, response.body
    assert_includes response.body, %(href="#{INGRESS}/css/mdi/materialdesignicons.css")
    assert_includes response.body, %(href="#{INGRESS}/favicon.ico")
    assert_includes response.body, %("#{INGRESS}/assets/application-)
  end

  test "direct requests are not prefixed, even right after an ingress request" do
    get "/status", headers: {"X-Ingress-Path" => INGRESS}
    get "/status"
    assert_response :success

    refute_includes response.body, "hassio_ingress"
    assert_includes response.body, %(href="/events")
    assert_match %r{href="/assets/application_tailwind-[^"]+\.css"}, response.body
    assert_includes response.body, %("/assets/application-)
  end

  # importmap-rails caches the importmap JSON and modulepreload paths, so the
  # prefix must not stick from whichever request happened to render first.
  test "ingress requests carry the prefix in the importmap, even right after a direct request" do
    get "/status"
    get "/status", headers: {"X-Ingress-Path" => INGRESS}
    assert_response :success

    assert_includes response.body, %("application": "#{INGRESS}/assets/application-)
    assert_match %r{<link rel="modulepreload" href="#{INGRESS}/assets/application-}, response.body
    refute_match %r{"/assets/}, response.body
  end
end
