# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class CheckCommitPolicyTest < Minitest::Test
  CHECKER = File.expand_path("check_commit_policy.rb", __dir__)
  AUTHOR_ENV = {
    "GIT_AUTHOR_NAME" => "tinkeragora",
    "GIT_AUTHOR_EMAIL" => "314183062+tinkeragora@users.noreply.github.com",
    "GIT_COMMITTER_NAME" => "tinkeragora",
    "GIT_COMMITTER_EMAIL" => "314183062+tinkeragora@users.noreply.github.com"
  }.freeze

  def test_clean_history_passes
    with_repository do |root|
      commit(root, "docs: add repository guidance")
      result = run_checker(root)

      assert result[:status].success?, result[:output]
      assert_includes result[:output], "Commit policy checks passed"
    end
  end

  def test_unapproved_identity_fails
    with_repository do |root|
      commit(root, "docs: add repository guidance", {
        "GIT_AUTHOR_NAME" => "former_user",
        "GIT_AUTHOR_EMAIL" => "former_user@example.invalid",
        "GIT_COMMITTER_NAME" => "former_user",
        "GIT_COMMITTER_EMAIL" => "former_user@example.invalid"
      })
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "author identity is not allowed"
      assert_includes result[:output], "committer identity is not allowed"
    end
  end

  def test_public_email_fails
    with_repository do |root|
      commit(root, "docs: add repository guidance", {
        "GIT_AUTHOR_EMAIL" => "public@example.com",
        "GIT_COMMITTER_EMAIL" => "public@example.com"
      })
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "author identity is not allowed"
    end
  end

  def test_han_text_in_subject_fails
    with_repository do |root|
      commit(root, "README 增加支持入口")
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "commit message must not contain Han characters"
    end
  end

  def test_han_text_in_body_fails
    with_repository do |root|
      commit(root, "docs: add repository guidance\n\n补充项目说明")
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "commit message must not contain Han characters"
    end
  end

  private

  def with_repository
    Dir.mktmpdir("check-commit-policy-") do |root|
      run_git(root, "init", "--quiet")
      run_git(root, "config", "user.name", "tinkeragora")
      run_git(root, "config", "user.email", AUTHOR_ENV.fetch("GIT_AUTHOR_EMAIL"))
      File.write(File.join(root, "README.md"), "# Repository\n", encoding: "UTF-8")
      run_git(root, "add", "README.md")
      commit(root, "chore: initialize repository")
      yield root
    end
  end

  def commit(root, message, env = {})
    run_git(root, "commit", "--allow-empty", "-m", message, env: AUTHOR_ENV.merge(env))
  end

  def run_checker(root)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, CHECKER, "--root", root)
    { output: stdout + stderr, status: status }
  end

  def run_git(root, *arguments, env: {})
    _stdout, stderr, status = Open3.capture3(env, "git", "-C", root, *arguments)
    raise stderr unless status.success?
  end
end
