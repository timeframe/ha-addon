# frozen_string_literal: true

require "test_helper"

class MdiIconMatcherTest < Minitest::Test
  def setup
    MdiIconMatcher.reload!
  end

  # Custom mappings take priority

  def test_match_custom_mapping_church
    assert_equal "church", MdiIconMatcher.match("Church")
  end

  def test_match_curated_phrase_independence_day
    assert_equal "firework", MdiIconMatcher.match("Independence Day")
    assert_equal "firework", MdiIconMatcher.match("4th of July BBQ")
    assert_equal "firework", MdiIconMatcher.match("Fourth of July")
  end

  def test_match_curated_phrase_waterpark
    assert_equal "waves", MdiIconMatcher.match("Waterpark")
    assert_equal "waves", MdiIconMatcher.match("Water park")
  end

  def test_match_custom_mapping_nap
    assert_equal "bed", MdiIconMatcher.match("Nap")
  end

  def test_match_custom_mapping_playground
    assert_equal "slide", MdiIconMatcher.match("Playground")
  end

  def test_match_custom_mapping_school
    assert_equal "bag-personal", MdiIconMatcher.match("School")
  end

  def test_match_custom_mapping_grocery
    assert_equal "cart", MdiIconMatcher.match("Grocery pickup")
  end

  def test_match_custom_mapping_dog_uses_dog_side
    assert_equal "dog-side", MdiIconMatcher.match("Dog")
    assert_equal "dog-side", MdiIconMatcher.match("Dog park")
  end

  def test_match_custom_mapping_farmers_market
    assert_equal "tractor", MdiIconMatcher.match("Farmer's market")
  end

  def test_match_custom_mapping_facetime
    assert_equal "video-account", MdiIconMatcher.match("Facetime with Grandma")
  end

  def test_match_custom_mapping_doctor_and_pediatrician
    assert_equal "stethoscope", MdiIconMatcher.match("Doctor")
    assert_equal "stethoscope", MdiIconMatcher.match("Pediatrician")
  end

  def test_match_custom_mapping_birthday_party
    assert_equal "cake-variant", MdiIconMatcher.match("Jack's birthday party")
  end

  def test_match_custom_mapping_swim_lessons
    assert_equal "swim", MdiIconMatcher.match("Swim lessons")
  end

  def test_match_custom_mapping_pool
    assert_equal "swim", MdiIconMatcher.match("Pool")
    assert_equal "swim", MdiIconMatcher.match("Pool party")
  end

  def test_match_climbing_and_mountain_custom_mapping
    assert_equal "image-filter-hdr", MdiIconMatcher.match("Rock climbing")
    assert_equal "image-filter-hdr", MdiIconMatcher.match("Mountain summit")
  end

  # Exact icon name match (not via custom mapping)

  def test_match_exact_icon_name
    assert_equal "church", MdiIconMatcher.match("Church service")
  end

  def test_match_exact_icon_name_not_in_custom_mappings
    # "camera" is a real MDI icon but not in custom_mappings.yml
    assert_equal "camera", MdiIconMatcher.match("camera setup")
  end

  # Case insensitive

  def test_match_case_insensitive
    assert_equal "church", MdiIconMatcher.match("CHURCH")
  end

  # No match returns nil

  def test_match_no_match
    assert_nil MdiIconMatcher.match("xyzzy gibberish")
  end

  def test_match_nil_input
    assert_nil MdiIconMatcher.match(nil)
  end

  def test_match_empty_string
    assert_nil MdiIconMatcher.match("")
  end

  # Search method

  def test_search_returns_results_for_rain
    results = MdiIconMatcher.search("rain")
    assert results.any?, "Expected search results for 'rain'"
    # weather-pouring has alias "weather-heavy-rain"
    assert results.include?("weather-pouring"), "Expected weather-pouring in results for 'rain'"
  end

  def test_search_exact_match_first
    results = MdiIconMatcher.search("church")
    assert results.first == "church", "Expected exact match 'church' first"
  end

  def test_search_empty_query
    assert_equal [], MdiIconMatcher.search("")
    assert_equal [], MdiIconMatcher.search(nil)
  end

  # Multi-word matching

  def test_match_multi_word_event
    result = MdiIconMatcher.match("Soccer practice")
    assert_equal "soccer", result
  end

  def test_match_birthday_party
    result = MdiIconMatcher.match("Birthday party")
    assert_equal "cake-variant", result
  end

  # Alias-based matching

  def test_search_alias_hotel_finds_bed
    results = MdiIconMatcher.search("hotel")
    assert results.include?("bed"), "Expected 'bed' in results for 'hotel' (alias)"
  end

  def test_match_alias_returns_icon
    # "hotel" is an alias for "bed" but not a custom mapping or icon name
    result = MdiIconMatcher.match("Hotel reservation")
    assert_equal "bed", result
  end

  # Tag-based search

  def test_search_by_tag
    results = MdiIconMatcher.search("weather")
    assert results.any?, "Expected search results for tag 'weather'"
  end

  # Defensive: icon not in CSS

  def test_match_skips_custom_mapping_not_in_css
    matcher = MdiIconMatcher.instance
    original = matcher.instance_variable_get(:@custom_mappings).dup
    matcher.instance_variable_get(:@custom_mappings)["zztest"] = "nonexistent-icon"
    assert_nil matcher.match("zztest only")
  ensure
    matcher.instance_variable_set(:@custom_mappings, original)
  end

  def test_match_skips_alias_not_in_css
    matcher = MdiIconMatcher.instance
    original = matcher.instance_variable_get(:@alias_index).dup
    matcher.instance_variable_get(:@alias_index)["zzfake"] = "nonexistent-icon"
    assert_nil matcher.match("zzfake only")
  ensure
    matcher.instance_variable_set(:@alias_index, original)
  end

  # Compound match

  def test_match_compound_icon_name
    result = MdiIconMatcher.match("hair dryer broke")
    assert_equal "hair-dryer", result
  end
end
