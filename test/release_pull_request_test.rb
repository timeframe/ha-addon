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
  NOTES = "### Fixed\n- Import calendar events with additional Home Assistant fields.\n"
  PR_URL = "https://github.com/timeframe/ha-addon/pull/42"

  def setup
    @temporary = Dir.mktmpdir("release-pull-request")
    @checkout = File.join(@temporary, "checkout")
    @origin = File.join(@temporary, "origin.git")
    @artifacts = File.join(@temporary, "artifacts")
    @commands = File.join(@temporary, "commands")
    @state_path = File.join(@temporary, "state.json")
    FileUtils.mkdir_p([@checkout, @commands])
    write_state("open_prs" => [], "created_prs" => [], "calls" => [], "notes" => NOTES)
    install_fake_commands

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
      "GITHUB_TOKEN" => "fixture-token",
      "GH_TOKEN" => "fixture-token",
      "GITHUB_RUN_ID" => "123",
      "GITHUB_RUN_ATTEMPT" => "1",
      "GITHUB_SERVER_URL" => "https://github.com",
      "GITHUB_OUTPUT" => File.join(@temporary, "outputs"),
      "GITHUB_STEP_SUMMARY" => File.join(@temporary, "summary"),
      "RELEASE_TEST_STATE" => @state_path,
      "RELEASE_TEST_CHECKOUT" => @checkout
    }
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def test_creates_only_the_version_and_changelog_pull_request
    generate!
    assert_equal "", git("status", "--porcelain")
    metadata = JSON.parse(File.read(File.join(@artifacts, "metadata.json")))
    assert_equal @source_sha, metadata.fetch("source_sha")
    assert_equal "2.15.1", metadata.fetch("version")
    assert_includes File.read(@environment.fetch("GITHUB_OUTPUT")), "source_sha=#{@source_sha}"

    call = state.fetch("calls").find { |entry| entry.fetch("command") == "copilot" }
    refute_equal @checkout, call.fetch("cwd")
    assert_nil call.fetch("gh_token")
    assert_includes call.fetch("arguments"), "--available-tools"
    assert_includes call.fetch("arguments"), "--deny-tool=*"
    assert_includes call.fetch("arguments"), "--no-custom-instructions"
    assert_includes call.fetch("arguments"), "--disable-builtin-mcps"
    assert_includes call.fetch("prompt"), "v2.15.0..#{@source_sha}"
    assert_includes call.fetch("prompt"), "Fix calendar event imports"
    assert_includes call.fetch("prompt"), "new calendar event fields"

    stdout, stderr, status = invoke("create")
    assert status.success?, stderr
    assert_includes stdout, PR_URL
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
    assert_includes File.read(@environment.fetch("GITHUB_STEP_SUMMARY")), PR_URL
  end

  def test_stops_before_generation_for_any_open_release_pull_request
    [
      {"ref" => "release/v2.16.0-1-1", "title" => "Pending", "body" => ""},
      {"ref" => "custom-release", "title" => "Release v2.16.0", "body" => ""},
      {"ref" => "custom-release", "title" => "Pending", "body" => "<!-- timeframe-release-pr -->"}
    ].each do |candidate|
      update_state("open_prs" => [pull_request(candidate)])
      assert_failure("generate", "already open: #{PR_URL}")
    end
    assert_empty copilot_calls
    refute File.exist?(File.join(@artifacts, "notes.md"))
  end

  def test_unrelated_pull_requests_do_not_block_a_release
    update_state("open_prs" => [pull_request("ref" => "dependabot/bundler/rack", "title" => "Bump rack", "body" => nil)])
    generate!
    assert_equal 1, copilot_calls.length
  end

  def test_minor_and_major_dispatches_use_the_same_deterministic_preparation
    {"minor" => "2.16.0", "major" => "3.0.0"}.each do |bump, version|
      @environment["RELEASE_BUMP"] = bump
      generate!
      _, stderr, status = invoke("create")
      assert status.success?, stderr
      assert_equal version, JSON.parse(File.read(File.join(@checkout, "config.json"))).fetch("version")
      git("checkout", "main")
      update_state("open_prs" => [])
    end
  end

  def test_rechecks_for_an_open_release_before_writing
    generate!
    update_state("open_prs" => [pull_request])
    assert_failure("create", "already open")
    assert_equal "2.15.0", JSON.parse(File.read(File.join(@checkout, "config.json"))).fetch("version")
    assert_equal "", git("status", "--porcelain")
  end

  def test_authentication_or_generation_failure_has_no_fallback
    update_state("copilot_status" => 1, "copilot_error" => "403: organization Copilot policy is disabled")
    assert_failure("generate", "403: organization Copilot policy is disabled")
    refute File.exist?(File.join(@artifacts, "metadata.json"))
    assert_empty state.fetch("created_prs")
    assert_equal "", git("status", "--porcelain")
  end

  def test_rejects_missing_tokens_before_generation
    %w[GITHUB_TOKEN GH_TOKEN].each do |token|
      assert_failure("generate", "Missing #{token}", token => nil)
    end
    assert_empty copilot_calls
  end

  def test_rejects_invalid_generated_notes
    ["", "### Fixed\n", "```markdown\n#{NOTES}```"].each do |notes|
      update_state("notes" => notes)
      assert_failure("generate", "Release notes")
      refute File.exist?(File.join(@artifacts, "metadata.json"))
    end
    assert_equal 3, copilot_calls.length
  end

  def test_rejects_dirty_or_nondefault_dispatches
    assert_failure("generate", "default branch", "GITHUB_REF" => "refs/heads/feature")
    File.write(File.join(@checkout, "unexpected.txt"), "not part of a release")
    assert_failure("generate", "must be clean")
    assert_empty copilot_calls
  end

  def test_rejects_missing_or_already_used_tags
    git("tag", "v2.15.1")
    assert_failure("generate", "Target release tag v2.15.1 already exists")
    git("tag", "-d", "v2.15.1", "v2.15.0")
    assert_failure("generate", "Missing baseline tag v2.15.0")
    assert_empty copilot_calls
  end

  def test_rejects_an_unreachable_baseline
    git("checkout", "-b", "other", "v2.15.0")
    File.write(File.join(@checkout, "other.rb"), "other branch")
    commit("Other changes")
    git("tag", "-f", "v2.15.0")
    git("checkout", "main")
    assert_failure("generate", "not an ancestor")
    assert_empty copilot_calls
  end

  def test_rejects_an_empty_change_range
    git("tag", "-f", "v2.15.0")
    assert_failure("generate", "No commits since v2.15.0")
    assert_empty copilot_calls
  end

  def test_refuses_to_truncate_large_change_context
    File.write(File.join(@checkout, "large.rb"), "x" * 500_001)
    commit("Large source change")
    git("push", "origin", "main")
    assert_failure("generate", "refusing to truncate")
    assert_empty copilot_calls
  end

  def test_generated_assets_are_explicitly_excluded_from_the_textual_context
    directory = File.join(@checkout, "app", "assets", "builds")
    FileUtils.mkdir_p(directory)
    generated = "generated-asset-data" * 30_000
    File.write(File.join(directory, "application.css"), generated)
    commit("Rebuild generated assets")
    git("push", "origin", "main")
    generate!
    prompt = copilot_calls.fetch(0).fetch("prompt")
    assert_includes prompt, "app/assets/builds/application.css"
    refute_includes prompt, generated
  end

  def test_rejects_a_moved_default_branch_before_writing
    generate!
    git("--git-dir=#{@origin}", "update-ref", "refs/heads/main", git("rev-parse", "HEAD~1").strip)
    assert_failure("create", "default branch moved")
    assert_equal "", git("status", "--porcelain")
    assert_empty state.fetch("created_prs")
  end

  def test_rejects_artifact_metadata_or_notes_changes
    generate!
    metadata_path = File.join(@artifacts, "metadata.json")
    original = File.read(metadata_path)
    File.write(metadata_path, original.sub(@source_sha, "0" * 40))
    assert_failure("create", "metadata no longer matches")
    File.write(metadata_path, original)
    File.write(File.join(@artifacts, "notes.md"), "not release notes")
    assert_failure("create", "Release notes")
    assert_equal "", git("status", "--porcelain")
  end

  def test_refuses_to_overwrite_a_release_branch
    generate!
    git("push", "origin", "HEAD:refs/heads/release/v2.15.1-123-1")
    assert_failure("create", "refusing to overwrite")
    assert_empty state.fetch("created_prs")
  end

  def test_rechecks_remote_tags_and_run_identifiers_before_writing
    generate!
    assert_failure("create", "Invalid Actions run ID", "GITHUB_RUN_ID" => "not-a-run")
    git("push", "origin", "HEAD:refs/tags/v2.15.1")
    assert_failure("create", "Target release tag v2.15.1 already exists")
    assert_equal "", git("status", "--porcelain")
  end

  def test_refuses_unexpected_checkout_changes_from_either_phase
    update_state("copilot_mutation" => true)
    assert_failure("generate", "must be clean")
    FileUtils.rm(File.join(@checkout, "unexpected.txt"))
    update_state("copilot_mutation" => false)
    generate!
    update_state("gh_mutation" => true)
    assert_failure("create", "changed files beyond")
    assert_empty state.fetch("created_prs")
  end

  def test_a_failed_creation_can_be_retried_but_an_open_pull_request_cannot
    generate!
    update_state("create_status" => 1)
    assert_failure("create", "may need manual cleanup")
    assert_empty state.fetch("created_prs")
    assert_includes git("ls-remote", "--heads", "origin"), "release/v2.15.1-123-1"

    git("checkout", "main")
    @environment["GITHUB_RUN_ATTEMPT"] = "2"
    update_state("create_status" => 0)
    generate!
    _, stderr, status = invoke("create")
    assert status.success?, stderr
    assert_equal "release/v2.15.1-123-2", state.fetch("created_prs").fetch(0).fetch("head")
    assert_equal 2, copilot_calls.length

    git("checkout", "main")
    assert_failure("generate", "already open")
    assert_equal 2, copilot_calls.length
  end

  def test_rerunning_only_creation_reuses_the_successful_generation_artifact
    generate!
    update_state("create_status" => 1)
    assert_failure("create", "may need manual cleanup")
    git("checkout", "main")
    @environment["GITHUB_RUN_ATTEMPT"] = "2"
    update_state("create_status" => 0)

    _, stderr, status = invoke("create")
    assert status.success?, stderr
    assert_equal 1, copilot_calls.length
    assert_equal "release/v2.15.1-123-2", state.fetch("created_prs").fetch(0).fetch("head")
    assert_includes File.read(File.join(@checkout, "CHANGELOG.md")), NOTES
  end

  def test_github_errors_and_invalid_responses_are_explicit
    update_state("gh_status" => 1)
    assert_failure("generate", "GitHub fixture failure")
    update_state("gh_status" => 0, "pull_response" => {"unexpected" => true})
    assert_failure("generate", "Unexpected pull request API response")
    assert_empty copilot_calls
  end

  def test_invalid_pull_request_creation_response_is_not_success
    generate!
    update_state("created_url" => nil)
    assert_failure("create", "valid pull request URL")
    refute File.exist?(@environment.fetch("GITHUB_STEP_SUMMARY"))
  end

  def test_invalid_arguments_and_artifact_locations_are_explicit
    _, stderr, status = invoke("unknown")
    refute status.success?
    assert_includes stderr, "Usage:"
    _, stderr, status = invoke("generate", {}, directory: @checkout)
    refute status.success?
    assert_includes stderr, "artifacts must be outside"
    assert_failure("generate", "Choose a major, minor, or patch", "RELEASE_BUMP" => "automatic")
  end

  def test_workflow_is_manual_and_separates_agent_and_write_permissions
    workflow = YAML.load_file(WORKFLOW)
    assert_equal ["workflow_dispatch"], workflow.fetch("on").keys
    assert_equal "patch", workflow.dig("on", "workflow_dispatch", "inputs", "bump", "default")
    assert_equal %w[patch minor major], workflow.dig("on", "workflow_dispatch", "inputs", "bump", "options")
    assert_equal false, workflow.dig("concurrency", "cancel-in-progress")
    assert_equal({}, workflow.fetch("permissions"))
    generation = workflow.fetch("jobs").fetch("generate")
    creation = workflow.fetch("jobs").fetch("create")
    assert_equal({"contents" => "read", "pull-requests" => "read", "copilot-requests" => "write"}, generation.fetch("permissions"))
    assert_equal({"contents" => "write", "pull-requests" => "write"}, creation.fetch("permissions"))
    assert_equal "generate", creation.fetch("needs")
    assert generation.fetch("steps").first.dig("with", "fetch-depth").zero?
    assert_equal false, generation.fetch("steps").first.dig("with", "persist-credentials")
    assert_equal "${{ needs.generate.outputs.source_sha }}", creation.fetch("steps").first.dig("with", "ref")
    refute_includes creation.to_s, "copilot"
  end

  private

  def invoke(operation, extra_environment = {}, directory: @artifacts)
    Open3.capture3(@environment.merge(extra_environment), RbConfig.ruby, SCRIPT, operation, directory, chdir: @checkout)
  end

  def generate!
    stdout, stderr, status = invoke("generate")
    assert status.success?, "#{stderr}\n#{stdout}"
  end

  def assert_failure(operation, message, extra_environment = {})
    stdout, stderr, status = invoke(operation, extra_environment)
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

  def copilot_calls
    state.fetch("calls").select { |entry| entry.fetch("command") == "copilot" }
  end

  def pull_request(candidate = {"ref" => "release/v2.15.1-1-1", "title" => "Release v2.15.1", "body" => ""})
    {"head" => {"ref" => candidate.fetch("ref")}, "title" => candidate.fetch("title"),
     "body" => candidate.fetch("body"), "html_url" => PR_URL}
  end

  def install_fake_commands
    program = <<~RUBY
      #!#{RbConfig.ruby}
      require "json"
      state_path = ENV.fetch("RELEASE_TEST_STATE")
      state = JSON.parse(File.read(state_path))
      command = File.basename($PROGRAM_NAME)
      entry = {"command" => command, "arguments" => ARGV, "cwd" => Dir.pwd}
      if command == "copilot"
        entry["prompt"] = $stdin.read
        entry["gh_token"] = ENV["GH_TOKEN"]
        if state["copilot_mutation"]
          File.write(File.join(ENV.fetch("RELEASE_TEST_CHECKOUT"), "unexpected.txt"), "unexpected")
        end
        output = state.fetch("notes")
        status = state.fetch("copilot_status", 0)
        warn state.fetch("copilot_error", "Copilot fixture failure") unless status.zero?
      elsif ARGV.include?("POST")
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
        status = state.fetch("gh_status", 0)
        warn "GitHub fixture failure" unless status.zero?
      end
      state["calls"] << entry
      File.write(state_path, JSON.generate(state))
      print output if output
      exit status
    RUBY
    %w[gh copilot].each do |name|
      path = File.join(@commands, name)
      File.write(path, program)
      File.chmod(0o755, path)
    end
  end
end
