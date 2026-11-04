# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "open3"
require_relative "../lib/release_preparation"

class ReleasePreparationTest < Minitest::Test
  NOTES = "### Fixed\n- Preserve calendar event fields.\n"
  RELEASE_SCRIPT = File.expand_path("../script/release", __dir__)

  def setup
    @root = Dir.mktmpdir("release-preparation")
    @config = {"name" => "Timeframe", "version" => "2.15.3", "arch" => ["aarch64", "amd64"]}
    @changelog = "# Changelog\n\n## [2.15.3] - 2026-01-01\n\n### Fixed\n- Previous fix.\n"
    File.write(File.join(@root, "config.json"), JSON.pretty_generate(@config) + "\n")
    File.write(File.join(@root, "CHANGELOG.md"), @changelog)
    @release = ReleasePreparation.new(root: @root)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_bump_types
    assert_equal "3.0.0", @release.next_version("major")
    assert_equal "2.16.0", @release.next_version("minor")
    assert_equal "2.15.4", @release.next_version("patch")
    assert_raises(ReleasePreparation::Error) { @release.next_version("automatic") }
  end

  def test_validates_manifest_versions
    [{}, [], {"version" => 2}, {"version" => "02.15.0"}, {"version" => "2.15.0-rc1"}].each do |config|
      File.write(File.join(@root, "config.json"), JSON.generate(config))
      assert_raises(ReleasePreparation::Error) { ReleasePreparation.new(root: @root) }
    end
  end

  def test_prepares_only_version_and_new_notes
    assert_equal "2.16.0", @release.prepare("minor", notes: NOTES, date: Date.new(2026, 11, 4))
    assert_equal @config.merge("version" => "2.16.0"), JSON.parse(File.read(File.join(@root, "config.json")))
    assert_equal "# Changelog\n\n## [2.16.0] - 2026-11-04\n\n#{NOTES}\n#{@changelog.delete_prefix("# Changelog\n\n")}",
      File.read(File.join(@root, "CHANGELOG.md"))
  end

  def test_preserves_literal_backslashes_in_notes
    notes = "### Changed\n- Preserve the literal \\\\1 sequence.\n"
    @release.prepare("patch", notes: notes)
    assert_includes File.read(File.join(@root, "CHANGELOG.md")), notes
  end

  def test_preserves_the_manual_skeleton_without_an_existing_header
    File.write(File.join(@root, "CHANGELOG.md"), "# Changelog\n")
    @release.prepare("patch")
    assert_includes File.read(File.join(@root, "CHANGELOG.md")), "### Added\n\n### Changed\n\n### Fixed\n"
    assert File.read(File.join(@root, "CHANGELOG.md")).start_with?("# Changelog\n")
  end

  def test_rejects_an_existing_target_entry_without_writing
    File.write(File.join(@root, "CHANGELOG.md"), "## [2.15.4] - 2026-01-02\n")
    assert_raises(ReleasePreparation::Error) { @release.prepare("patch", notes: NOTES) }
    assert_equal @config, JSON.parse(File.read(File.join(@root, "config.json")))
  end

  def test_rejects_invalid_notes_without_writing
    [
      "", " \n", "### Fixed\n", "- No section.\n", "```markdown\n#{NOTES}```",
      "## [9.0.0]\n#{NOTES}", "### Unknown\n- A change.\n",
      "#{NOTES}#{NOTES}", "### Added\n\n#{NOTES}", "### Fixed\n- TODO\n"
    ].each do |notes|
      assert_raises(ReleasePreparation::Error) { @release.prepare("patch", notes: notes) }
      assert_equal @config, JSON.parse(File.read(File.join(@root, "config.json")))
      assert_equal @changelog, File.read(File.join(@root, "CHANGELOG.md"))
    end
  end

  def test_accepts_nonempty_existing_changelog_sections
    notes = "\n### Added\n- A display.\n\n### Removed\n- An obsolete template.\n\n### Security\n- A safety fix.\n\n"
    assert_equal "#{notes.strip}\n", ReleasePreparation.validate_notes(notes)
  end

  def test_interactive_script_still_prepares_a_skeleton
    stdout, stderr, status = Open3.capture3("ruby", RELEASE_SCRIPT, stdin_data: "2\n", chdir: @root)
    assert status.success?, stderr
    assert_includes stdout, "2) minor (2.16.0)"
    assert_equal "2.16.0", JSON.parse(File.read(File.join(@root, "config.json")))["version"]
  end

  def test_noninteractive_script_uses_generated_notes
    notes_path = File.join(@root, "notes.md")
    File.write(notes_path, NOTES)
    stdout, stderr, status = Open3.capture3("ruby", RELEASE_SCRIPT, "patch", "--notes", notes_path, chdir: @root)
    assert status.success?, stderr
    assert_includes stdout, "v2.15.4"
    assert_includes File.read(File.join(@root, "CHANGELOG.md")), NOTES
  end

  def test_script_errors_are_explicit
    [%w[patch unexpected], %w[--unknown], %w[--notes missing.md], []].each do |arguments|
      _, stderr, status = Open3.capture3("ruby", RELEASE_SCRIPT, *arguments, stdin_data: "", chdir: @root)
      refute status.success?
      assert_includes stderr, "Release preparation failed:"
    end
    _, stderr, status = Open3.capture3("ruby", RELEASE_SCRIPT, "patch", "--notes", "missing.md", chdir: @root)
    refute status.success?
    assert_includes stderr, "missing.md"
  end
end
