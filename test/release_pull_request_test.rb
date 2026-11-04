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
    @state_path = File.join(@temporary, "state.json")
    FileUtils.mkdir_p([@checkout, @commands])
    write_state("open_prs" => [], "created_prs" => [], "calls" => [])
    install_fake_gh

    git("init", "--initial-branch=main")
    git("config", "user.name", "Release tests")
    git("config", "user.email", "release-tests@example.invalid")
    File.write(File.join(@checkout, "config.json"), JSON.pretty_generate("name" => "Timeframe", "version" => "2.15.0") + "\n")
    File.write(File.join(@checkout, "CHANGELOG.md"), "## [2.15.0] - 2026-08-06\n\n### Added\n- Previous release.\n")
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
      "GITHUB_SERVER_URL" => "https://github.com",
      "GITHUB_STEP_SUMMARY" => File.join(@temporary, "summary"),
      "RELEASE_TEST_STATE" => @state_path,
      "RELEASE_TEST_CHECKOUT" => @checkout
    }
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def test_creates_only_the_version_and_changelog_pull_request
    stdout, stderr, status = invoke
    assert status.success?, stderr
    assert_includes stdout, PR_URL
    assert_equal "2.15.1", JSON.parse(File.read(File.join(@checkout, "config.json"))).fetch("version")
    assert_includes release_entry, "### Changed\n- Fix calendar event imports (#{@source_sha[0, 7]})\n"
    refute_includes release_entry, "Previous release"
    assert_equal %w[CHANGELOG.md config.json], git("diff", "--name-only", "#{@source_sha}..HEAD").lines.map(&:strip).sort
    assert_equal "Release v2.15.1", git("log", "-1", "--format=%s").strip
    assert_equal ["v2.15.0"], git("tag").lines.map(&:strip)
    assert_equal @source_sha, git("ls-remote", "origin", "refs/heads/main").split.first
    assert_equal "", git("status", "--porcelain")
    fields = state.fetch("created_prs").fetch(0)
    assert_equal "Release v2.15.1", fields.fetch("title")
    assert_equal "main", fields.fetch("base")
    assert_equal "release/v2.15.1-123-1", fields.fetch("head")
    assert_includes fields.fetch("body"), "<!-- timeframe-release-pr -->"
    assert_includes fields.fetch("body"), "Changelog drafted from commit subjects"
    assert_includes fields.fetch("body"), "Review and edit the draft changelog"
    assert_includes File.read(@environment.fetch("GITHUB_STEP_SUMMARY")), PR_URL
  end

  def test_drafts_only_commit_subjects_in_order_without_bodies_or_source_contents
    File.write(File.join(@checkout, "display.rb"), "private implementation detail" * 30_000)
    commit("Add schedule settings\n\nThis body is not a release note.")
    settings_sha = git("rev-parse", "HEAD").strip
    git("commit", "--allow-empty", "-m", "Document [settings] and literal \\1")
    docs_sha = git("rev-parse", "HEAD").strip
    git("push", "origin", "main")

    create!
    expected = <<~NOTES
      ### Changed
      - Fix calendar event imports (#{@source_sha[0, 7]})
      - Add schedule settings (#{settings_sha[0, 7]})
      - Document [settings] and literal \\1 (#{docs_sha[0, 7]})
    NOTES
    assert_includes release_entry, expected
    refute_includes release_entry, "This body is not a release note."
    refute_includes release_entry, "private implementation detail"
  end

  def test_excludes_merge_messages_without_losing_the_merged_commits
    git("checkout", "-b", "feature")
    File.write(File.join(@checkout, "feature.rb"), "feature")
    commit("Add display feature")
    git("checkout", "main")
    git("commit", "--allow-empty", "-m", "Update display defaults")
    git("merge", "--no-ff", "feature", "-m", "Merge feature branch")
    git("push", "origin", "main")

    create!
    assert_includes release_entry, "Add display feature"
    assert_includes release_entry, "Update display defaults"
    refute_includes release_entry, "Merge feature branch"
  end

  def test_stops_before_writing_for_any_open_release_pull_request
    [
      {"ref" => "release/v2.16.0-1-1", "title" => "Pending", "body" => ""},
      {"ref" => "custom-release", "title" => "Release v2.16.0", "body" => ""},
      {"ref" => "custom-release", "title" => "Pending", "body" => "<!-- timeframe-release-pr -->"}
    ].each do |candidate|
      update_state("open_prs" => [pull_request(candidate)])
      assert_failure("already open: #{PR_URL}")
    end
    assert_equal "2.15.0", JSON.parse(File.read(File.join(@checkout, "config.json"))).fetch("version")
    assert_equal "", git("status", "--porcelain")
    assert_empty state.fetch("created_prs")
  end

  def test_unrelated_pull_requests_do_not_block_a_release
    update_state("open_prs" => [pull_request("ref" => "dependabot/bundler/rack", "title" => "Bump rack", "body" => nil)])
    create!
    assert_equal 1, state.fetch("created_prs").length
  end

  def test_minor_and_major_dispatches_use_the_same_deterministic_preparation
    {"minor" => "2.16.0", "major" => "3.0.0"}.each do |bump, version|
      @environment["RELEASE_BUMP"] = bump
      create!
      assert_equal version, JSON.parse(File.read(File.join(@checkout, "config.json"))).fetch("version")
      git("checkout", "main")
      update_state("open_prs" => [])
    end
  end

  def test_rechecks_for_an_open_release_before_pushing
    update_state("open_after_read" => pull_request)
    assert_failure("already open")
    assert_equal "", git("ls-remote", "--heads", "origin", "refs/heads/release/v2.15.1-123-1")
    assert_empty state.fetch("created_prs")
  end

  def test_rejects_missing_workflow_environment_before_writing
    %w[GH_TOKEN GITHUB_SERVER_URL GITHUB_STEP_SUMMARY].each do |name|
      assert_failure("Missing #{name}", name => nil)
    end
    assert_empty state.fetch("calls")
  end

  def test_rejects_dirty_or_nondefault_dispatches
    assert_failure("default branch", "GITHUB_REF" => "refs/heads/feature")
    File.write(File.join(@checkout, "unexpected.txt"), "not part of a release")
    assert_failure("must be clean")
    assert_empty state.fetch("calls")
  end

  def test_rejects_missing_or_already_used_tags
    git("tag", "v2.15.1")
    assert_failure("Target release tag v2.15.1 already exists")
    git("tag", "-d", "v2.15.1", "v2.15.0")
    assert_failure("Missing baseline tag v2.15.0")
    assert_empty state.fetch("created_prs")
  end

  def test_rejects_an_unreachable_baseline
    git("checkout", "-b", "other", "v2.15.0")
    File.write(File.join(@checkout, "other.rb"), "other branch")
    commit("Other changes")
    git("tag", "-f", "v2.15.0")
    git("checkout", "main")
    assert_failure("not an ancestor")
    assert_empty state.fetch("created_prs")
  end

  def test_rejects_an_empty_change_range
    git("tag", "-f", "v2.15.0")
    assert_failure("No non-merge commits since v2.15.0")
    assert_equal "", git("status", "--porcelain")
  end

  def test_rejects_a_moved_default_branch_before_writing
    git("--git-dir=#{@origin}", "update-ref", "refs/heads/main", git("rev-parse", "HEAD~1").strip)
    assert_failure("default branch moved")
    assert_equal "", git("status", "--porcelain")
    assert_empty state.fetch("created_prs")
  end

  def test_refuses_to_overwrite_a_release_branch
    git("push", "origin", "HEAD:refs/heads/release/v2.15.1-123-1")
    assert_failure("refusing to overwrite")
    assert_empty state.fetch("created_prs")
  end

  def test_rechecks_remote_tags_and_run_identifiers_before_writing
    %w[GITHUB_RUN_ID GITHUB_RUN_ATTEMPT].each do |name|
      assert_failure("Invalid Actions run ID", name => "not-a-run")
    end
    git("push", "origin", "HEAD:refs/tags/v2.15.1")
    assert_failure("Target release tag v2.15.1 already exists")
    assert_equal "", git("status", "--porcelain")
  end

  def test_refuses_unexpected_checkout_changes_during_preparation
    update_state("gh_mutation" => true)
    assert_failure("changed files beyond")
    assert_empty state.fetch("created_prs")
  end

  def test_a_failed_creation_can_be_retried_but_an_open_pull_request_cannot
    update_state("create_status" => 1)
    assert_failure("may need manual cleanup")
    original_changelog = File.read(File.join(@checkout, "CHANGELOG.md"))
    assert_empty state.fetch("created_prs")
    assert_includes git("ls-remote", "--heads", "origin"), "release/v2.15.1-123-1"

    git("checkout", "main")
    @environment["GITHUB_RUN_ATTEMPT"] = "2"
    update_state("create_status" => 0)
    create!
    assert_equal "release/v2.15.1-123-2", state.fetch("created_prs").fetch(0).fetch("head")
    assert_equal original_changelog, File.read(File.join(@checkout, "CHANGELOG.md"))

    git("checkout", "main")
    assert_failure("already open")
  end

  def test_github_errors_and_invalid_responses_are_explicit
    update_state("gh_status" => 1)
    assert_failure("GitHub fixture failure")
    update_state("gh_status" => 0, "pull_response" => {"unexpected" => true})
    assert_failure("Unexpected pull request API response")
    assert_equal "", git("status", "--porcelain")
  end

  def test_invalid_pull_request_creation_response_is_not_success
    update_state("created_url" => nil)
    assert_failure("valid pull request URL")
    refute File.exist?(@environment.fetch("GITHUB_STEP_SUMMARY"))
  end

  def test_invalid_arguments_and_dispatch_inputs_are_explicit
    _, stderr, status = invoke(arguments: ["unexpected"])
    refute status.success?
    assert_includes stderr, "Usage:"
    assert_failure("Choose a major, minor, or patch", "RELEASE_BUMP" => "automatic")
    assert_failure("Invalid repository name", "GITHUB_REPOSITORY" => "invalid")
  end

  def test_workflow_is_manual_and_uses_one_job_with_the_builtin_actions_token
    workflow = YAML.load_file(WORKFLOW)
    assert_equal ["workflow_dispatch"], workflow.fetch("on").keys
    assert_equal "patch", workflow.dig("on", "workflow_dispatch", "inputs", "bump", "default")
    assert_equal %w[patch minor major], workflow.dig("on", "workflow_dispatch", "inputs", "bump", "options")
    assert_equal false, workflow.dig("concurrency", "cancel-in-progress")
    assert_equal({}, workflow.fetch("permissions"))
    assert_equal ["prepare"], workflow.fetch("jobs").keys
    preparation = workflow.fetch("jobs").fetch("prepare")
    assert_equal({"contents" => "write", "pull-requests" => "write"}, preparation.fetch("permissions"))
    steps = preparation.fetch("steps")
    assert_equal 3, steps.length
    assert_match %r{\Aactions/checkout@}, steps.fetch(0).fetch("uses")
    assert steps.fetch(0).dig("with", "fetch-depth").zero?
    assert_equal "${{ github.event.repository.default_branch }}", steps.fetch(0).dig("with", "ref")
    assert_match %r{\Aruby/setup-ruby@}, steps.fetch(1).fetch("uses")
    assert_equal "ruby script/release-pr", steps.fetch(2).fetch("run")
    assert_equal({"GH_TOKEN" => "${{ github.token }}"}, steps.fetch(2).fetch("env"))
  end

  private

  def invoke(extra_environment = {}, arguments: [])
    Open3.capture3(@environment.merge(extra_environment), RbConfig.ruby, SCRIPT, *arguments, chdir: @checkout)
  end

  def create!
    stdout, stderr, status = invoke
    assert status.success?, "#{stderr}\n#{stdout}"
  end

  def assert_failure(message, extra_environment = {})
    stdout, stderr, status = invoke(extra_environment)
    refute status.success?, stdout
    assert_includes stderr, "Release pull request preparation failed:"
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

  def state
    JSON.parse(File.read(@state_path))
  end

  def write_state(value)
    File.write(@state_path, JSON.generate(value))
  end

  def update_state(value)
    write_state(state.merge(value))
  end

  def release_entry
    File.read(File.join(@checkout, "CHANGELOG.md")).split("## [2.15.0]", 2).first
  end

  def pull_request(candidate = {"ref" => "release/v2.15.1-1-1", "title" => "Release v2.15.1", "body" => ""})
    {"head" => {"ref" => candidate.fetch("ref")}, "title" => candidate.fetch("title"),
     "body" => candidate.fetch("body"), "html_url" => PR_URL}
  end

  def install_fake_gh
    program = <<~RUBY
      #!#{RbConfig.ruby}
      require "json"
      state_path = ENV.fetch("RELEASE_TEST_STATE")
      state = JSON.parse(File.read(state_path))
      if ARGV.include?("POST")
        status = state.fetch("create_status", 0)
        if status.zero?
          fields = ARGV.each_index.filter_map { |index| ARGV[index + 1].split("=", 2) if ARGV[index] == "-f" }.to_h
          state["created_prs"] << fields
          url = state.fetch("created_url", "#{PR_URL}")
          state["open_prs"] << {"head" => {"ref" => fields.fetch("head")}, "title" => fields.fetch("title"), "body" => fields.fetch("body"), "html_url" => url}
          output = JSON.generate("html_url" => url)
        else
          warn "GitHub fixture failure: enable Actions pull request creation"
        end
      else
        if state["gh_mutation"]
          File.write(File.join(ENV.fetch("RELEASE_TEST_CHECKOUT"), "unexpected.txt"), "unexpected")
        end
        output = JSON.generate(state.fetch("pull_response", [state.fetch("open_prs")]))
        state["open_prs"] = [state.fetch("open_after_read")] if state["open_after_read"]
        status = state.fetch("gh_status", 0)
        warn "GitHub fixture failure" unless status.zero?
      end
      state["calls"] << ARGV
      File.write(state_path, JSON.generate(state))
      print output if output
      exit status
    RUBY
    path = File.join(@commands, "gh")
    File.write(path, program)
    File.chmod(0o755, path)
  end
end
