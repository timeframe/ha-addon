# frozen_string_literal: true

require "test_helper"
require "capybara"
require_relative "visual_regression_helper"

class VisualRegressionHelperTest < Minitest::Test
  include VisualRegressionHelper

  def test_missing_baselines_fail_without_generating_a_replacement
    previous_update_visuals = ENV.delete("UPDATE_VISUALS")
    name = "missing-baseline-#{SecureRandom.hex(8)}"
    session = Object.new
    def session.save_screenshot(*, **)
    end

    stub(:wait_for_web_fonts, nil) do
      Capybara.stub(:current_session, session) do
        error = assert_raises(Minitest::Assertion) { assert_visual_match(name) }
        assert_match(/Missing visual baseline/, error.message)
      end
    end

    refute FIXTURE_ROOT.join("#{name}.png").exist?
  ensure
    ENV["UPDATE_VISUALS"] = previous_update_visuals
  end
end
