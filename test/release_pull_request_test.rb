# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

class ReleasePullRequestTest < Minitest::Test
  SCRIPT = File.expand_path("../script/release-pr", __dir__)
  WORKFLOW = File.expand_path("../.github/workflows/release-pr.yml", __dir__)
  PR_URL = "https://github.com/timeframe/ha-addon/pull/42"

  def setup
    @temporary = Dir.mktmpdir("release-pull-request")
    @checkout = File.join(@temporary, "checkout")
    @origin = File.join(@temporary, "origin.git")
    @commands = File.join(@temporary, "commands")
    @request = File.join(@temporary, "pull.json")
    FileUtils.mkdir_p([File.join(@checkout, "script"), @commands])
    FileUtils.cp(File.expand_path("../script/release", __dir__), File.join(@checkout, "script", "release"))
    install_fake_gh

    git("init", "--initial-branch=main")
    git("config", "user.name", "Release tests")
    git("config", "user.email", "release-tests@example.invalid")
    @config = {"name" => "Timeframe", "version" => "2.15.0", "arch" => ["aarch64", "amd64"]}
    @changelog = "# Changelog\n\n## [2.15.0] - 2026-08-06\n\n### Added\n- Previous release.\n"
    File.write(File.join(@checkout, "config.json"), JSON.pretty_generate(@config) + "\n")
    File.write(File.join(@checkout, "CHANGELOG.md"), @changelog)
    File.write(File.join(@checkout, "display.rb"), "puts 'old'\n")
    commit("Previous release")
    git("tag", "v2.15.0")
    File.write(File.join(@checkout, "display.rb"), "puts 'new calendar event fields'\n")
    commit("Fix calendar event imports")
    git("init", "--bare", "--initial-branch=main", @origin)
    git("remote", "add", "origin", @origin)
    git("push", "origin", "main", "--tags")
    @source_sha = git("rev-parse", "HEAD").strip
    @environment = {
      "PATH" => "#{@commands}:#{ENV.fetch("PATH")}",
      "GITHUB_REPOSITORY" => "timeframe/ha-addon",
      "RELEASE_DEFAULT_BRANCH" => "main",
      "RELEASE_BUMP" => "patch",
      "GITHUB_REF" => "refs/heads/main",
      "GH_TOKEN" => "fixture-token",
      "GITHUB_RUN_ID" => "123",
      "GITHUB_RUN_ATTEMPT" => "1",
      "GITHUB_STEP_SUMMARY" => File.join(@temporary, "summary"),
      "RELEASE_TEST_REQUEST" => @request
    }
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def test_all_bumps_change_only_release_files_and_preserve_existing_content
    {"patch" => "2.15.1", "minor" => "2.16.0", "major" => "3.0.0"}.each do |bump, version|
      stdout, stderr, status = invoke("RELEASE_BUMP" => bump)
      assert status.success?, stderr
      assert_includes stdout, PR_URL
      assert_equal @config.merge("version" => version), JSON.parse(File.read(File.join(@checkout, "config.json")))
      changelog = File.read(File.join(@checkout, "CHANGELOG.md"))
      assert changelog.start_with?("# Changelog\n\n## [#{version}] - ")
      assert changelog.end_with?(@changelog.delete_prefix("# Changelog\n\n"))
      assert_includes release_entry, "### Changed\n- Fix calendar event imports (#{@source_sha[0, 7]})\n"
      assert_equal %w[CHANGELOG.md config.json], git("diff", "--name-only", "#{@source_sha}..HEAD").lines.map(&:strip).sort
      assert_equal ["v2.15.0"], git("tag").lines.map(&:strip)
      assert_equal @source_sha, git("ls-remote", "origin", "refs/heads/main").split.first
      fields = JSON.parse(File.read(@request))
      assert_equal "main", fields.fetch("base")
      assert_equal "Release v#{version}", fields.fetch("title")
      assert_includes fields.fetch("body"), "Review and edit"
      assert_includes File.read(@environment.fetch("GITHUB_STEP_SUMMARY")), PR_URL
      git("checkout", "main")
    end
  end

  def test_drafts_subjects_without_bodies_diffs_or_merge_messages
    File.write(File.join(@checkout, "display.rb"), "private implementation detail" * 30_000)
    commit("Add schedule settings\n\nThis body is not a release note.")
    git("checkout", "-b", "feature")
    git("commit", "--allow-empty", "-m", "Document [settings] and literal \\1")
    git("checkout", "main")
    git("commit", "--allow-empty", "-m", "Update display defaults")
    git("merge", "--no-ff", "feature", "-m", "Merge feature branch")
    git("push", "origin", "main")
    _, stderr, status = invoke
    assert status.success?, stderr
    assert_includes release_entry, "- Add schedule settings ("
    assert_includes release_entry, "- Document [settings] and literal \\1 ("
    assert_includes release_entry, "- Update display defaults ("
    refute_includes release_entry, "This body is not a release note."
    refute_includes release_entry, "private implementation detail"
    refute_includes release_entry, "Merge feature branch"
  end

  def test_blocks_existing_release_pull_requests_even_on_a_later_api_page
    [
      {"head" => {"ref" => "release/v2.16.0-1-1"}, "title" => "Pending"},
      {"head" => {"ref" => "custom-release"}, "title" => "Release v2.16.0"}
    ].each do |candidate|
      pages = [[], [candidate.merge("html_url" => PR_URL)]]
      assert_failure("already open: #{PR_URL}", "RELEASE_TEST_PULLS" => JSON.generate(pages))
    end
    assert_equal "", git("status", "--porcelain")
    refute File.exist?(@request)
  end

  def test_rejects_dirty_or_nondefault_dispatches
    assert_failure("default branch", "GITHUB_REF" => "refs/heads/feature")
    File.write(File.join(@checkout, "unexpected.txt"), "not part of a release")
    assert_failure("must be clean")
    refute File.exist?(@request)
  end

  def test_rejects_missing_or_unreachable_baselines
    git("checkout", "-b", "other", "v2.15.0")
    File.write(File.join(@checkout, "other.rb"), "other branch")
    commit("Other changes")
    git("tag", "-f", "v2.15.0")
    git("checkout", "main")
    assert_failure("merge-base")
    git("tag", "-d", "v2.15.0")
    assert_failure("merge-base")
    refute File.exist?(@request)
  end

  def test_rejects_an_empty_change_range
    git("tag", "-f", "v2.15.0")
    assert_failure("No non-merge commits since v2.15.0")
    assert_equal "", git("status", "--porcelain")
  end

  def test_rejects_a_moved_default_branch_before_pushing
    git("--git-dir=#{@origin}", "update-ref", "refs/heads/main", git("rev-parse", "HEAD~1").strip)
    assert_failure("default branch moved")
    assert_equal "", git("ls-remote", "--heads", "origin", "refs/heads/release/*")
    refute File.exist?(@request)
  end

  def test_rejects_an_existing_target_tag
    git("tag", "v2.15.1")
    assert_failure("Release tag v2.15.1 already exists")
    refute File.exist?(@request)
  end

  def test_api_errors_are_explicit_and_a_failed_creation_can_be_retried
    assert_failure("GitHub fixture failure", "RELEASE_TEST_FAIL" => "list")
    assert_equal "", git("status", "--porcelain")
    assert_failure("GitHub fixture failure", "RELEASE_TEST_FAIL" => "create")
    original_changelog = File.read(File.join(@checkout, "CHANGELOG.md"))
    refute File.exist?(@request)
    assert_includes git("ls-remote", "--heads", "origin"), "release/v2.15.1-123-1"

    git("checkout", "main")
    @environment["GITHUB_RUN_ATTEMPT"] = "2"
    _, stderr, status = invoke
    assert status.success?, stderr
    assert_equal "release/v2.15.1-123-2", JSON.parse(File.read(@request)).fetch("head")
    assert_equal original_changelog, File.read(File.join(@checkout, "CHANGELOG.md"))
  end

  def test_workflow_is_manual_and_uses_one_job_with_the_builtin_actions_token
    workflow = YAML.load_file(WORKFLOW)
    assert_equal ["workflow_dispatch"], workflow.fetch("on").keys
    assert_equal "patch", workflow.dig("on", "workflow_dispatch", "inputs", "bump", "default")
    assert_equal %w[patch minor major], workflow.dig("on", "workflow_dispatch", "inputs", "bump", "options")
    assert_equal false, workflow.dig("concurrency", "cancel-in-progress")
    assert_equal({"contents" => "write", "pull-requests" => "write"}, workflow.fetch("permissions"))
    preparation = workflow.fetch("jobs").fetch("prepare")
    steps = preparation.fetch("steps")
    assert_equal 3, steps.length
    assert steps.fetch(0).dig("with", "fetch-depth").zero?
    assert_equal "${{ github.event.repository.default_branch }}", steps.fetch(0).dig("with", "ref")
    assert_equal "ruby script/release-pr", steps.fetch(2).fetch("run")
    assert_equal "${{ github.token }}", steps.fetch(2).fetch("env").fetch("GH_TOKEN")
    assert_equal "${{ inputs.bump }}", steps.fetch(2).fetch("env").fetch("RELEASE_BUMP")
  end

  private

  def invoke(extra_environment = {})
    Open3.capture3(@environment.merge(extra_environment), RbConfig.ruby, SCRIPT, chdir: @checkout)
  end

  def assert_failure(message, extra_environment = {})
    stdout, stderr, status = invoke(extra_environment)
    refute status.success?, stdout
    assert_includes stderr, message
  end

  def git(*arguments)
    stdout, stderr, status = Open3.capture3("git", *arguments, chdir: @checkout)
    raise "git #{arguments.join(" ")} failed: #{stderr}" unless status.success?
    stdout
  end

  def commit(message)
    git("add", ".")
    git("commit", "-m", message)
  end

  def release_entry
    File.read(File.join(@checkout, "CHANGELOG.md")).split("## [2.15.0]", 2).first
  end

  def install_fake_gh
    program = <<~RUBY
      #!#{RbConfig.ruby}
      require "json"
      operation = ARGV.include?("POST") ? "create" : "list"
      abort "GitHub fixture failure" if ENV["RELEASE_TEST_FAIL"] == operation
      if operation == "create"
        fields = ARGV.each_cons(2).filter_map { |flag, value| value.split("=", 2) if flag == "-f" }.to_h
        File.write(ENV.fetch("RELEASE_TEST_REQUEST"), JSON.generate(fields))
        puts JSON.generate("html_url" => "#{PR_URL}")
      else
        puts ENV.fetch("RELEASE_TEST_PULLS", "[[]]")
      end
    RUBY
    path = File.join(@commands, "gh")
    File.write(path, program)
    File.chmod(0o755, path)
  end
end
