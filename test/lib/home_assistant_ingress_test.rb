# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/home_assistant_ingress"

class HomeAssistantIngressTest < Minitest::Test
  def setup
    @app = HomeAssistantIngress.new(->(env) { [200, {}, [env["SCRIPT_NAME"].to_s]] })
  end

  def script_name_for(header)
    env = {"SCRIPT_NAME" => "", "PATH_INFO" => "/events"}
    env["HTTP_X_INGRESS_PATH"] = header unless header.nil?
    @app.call(env).last.first
  end

  def test_sets_script_name_from_ingress_header
    assert_equal "/api/hassio_ingress/AbC_12-3", script_name_for("/api/hassio_ingress/AbC_12-3")
  end

  def test_ignores_trailing_slash
    assert_equal "/api/hassio_ingress/abc", script_name_for("/api/hassio_ingress/abc/")
  end

  def test_leaves_direct_requests_alone
    assert_equal "", script_name_for(nil)
  end

  def test_rejects_unexpected_header_values
    assert_equal "", script_name_for("/somewhere/else")
    assert_equal "", script_name_for("/api/hassio_ingress/abc\"><script>")
    assert_equal "", script_name_for("/api/hassio_ingress/abc/extra")
    assert_equal "", script_name_for("")
  end
end
