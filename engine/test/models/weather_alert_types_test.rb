# frozen_string_literal: true

require "test_helper"

class WeatherAlertTypesTest < Minitest::Test
  def test_normalizes_provider_event_labels_ids_and_camel_case
    ["High Wind Warning", "high_wind_warning", "highWindWarning", " High-Wind Warning! "].each do |value|
      assert_equal "high_wind_warning", WeatherAlertTypes.normalize(value)
    end
    assert_nil WeatherAlertTypes.normalize(nil)
    assert_nil WeatherAlertTypes.normalize("A new provider's alert")
  end

  def test_excludes_only_selected_known_types
    excluded = ["high_wind_warning", "unknown_alert"]
    assert WeatherAlertTypes.excluded?("High Wind Warning", excluded_ids: excluded)
    refute WeatherAlertTypes.excluded?("Winter Storm Watch", excluded_ids: excluded)
    refute WeatherAlertTypes.excluded?("unknown_alert", excluded_ids: excluded)
    refute WeatherAlertTypes.excluded?(nil, excluded_ids: excluded)
    refute WeatherAlertTypes.excluded?("High Wind Warning", excluded_ids: nil)
  end
end
