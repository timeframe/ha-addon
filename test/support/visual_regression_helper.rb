# frozen_string_literal: true

require "fileutils"
require "mini_magick"

module VisualRegressionHelper
  FIXTURE_ROOT = Pathname.new(__dir__).join("..", "fixtures", "visual").expand_path
  ARTIFACT_ROOT = Pathname.new(__dir__).join("..", "..", "tmp", "visual_regression").expand_path

  def assert_visual_match(name, max_changed_ratio: 0.006, channel_tolerance: 18)
    FileUtils.mkdir_p(FIXTURE_ROOT)
    FileUtils.mkdir_p(ARTIFACT_ROOT)

    baseline_path = FIXTURE_ROOT.join("#{name}.png")
    actual_path = ARTIFACT_ROOT.join("#{name}.actual.png")
    diff_path = ARTIFACT_ROOT.join("#{name}.diff.png")

    Capybara.current_session.save_screenshot(actual_path.to_s, full: false)

    if ENV["UPDATE_VISUALS"] == "1" || !baseline_path.exist?
      FileUtils.cp(actual_path, baseline_path)
      return
    end

    changed_ratio = changed_pixel_ratio(
      baseline_path,
      actual_path,
      channel_tolerance: channel_tolerance
    )

    if changed_ratio > max_changed_ratio
      write_visual_diff(baseline_path, actual_path, diff_path)
    end

    assert changed_ratio <= max_changed_ratio,
      "Expected #{name} visual diff to be <= #{max_changed_ratio}, got #{changed_ratio.round(5)}. " \
      "Actual: #{actual_path} Diff: #{diff_path}"
  end

  private

  def changed_pixel_ratio(expected_path, actual_path, channel_tolerance:)
    expected = MiniMagick::Image.open(expected_path.to_s)
    actual = MiniMagick::Image.open(actual_path.to_s)

    assert_equal expected.dimensions, actual.dimensions, "Screenshot dimensions changed"

    expected_pixels = expected.get_pixels
    actual_pixels = actual.get_pixels
    changed = 0
    total = expected.width * expected.height

    expected_pixels.each_with_index do |row, y|
      row.each_with_index do |expected_pixel, x|
        actual_pixel = actual_pixels[y][x]
        changed += 1 if expected_pixel.zip(actual_pixel).any? { |a, b| (a - b).abs > channel_tolerance }
      end
    end

    changed.to_f / total
  end

  def write_visual_diff(expected_path, actual_path, diff_path)
    MiniMagick.compare(errors: false) do |compare|
      compare.metric("AE")
      compare.fuzz("8%")
      compare << expected_path.to_s
      compare << actual_path.to_s
      compare << diff_path.to_s
    end
  rescue MiniMagick::Error
    FileUtils.rm_f(diff_path)
  end
end
