# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class CheckDocsTest < Minitest::Test
  CHECKER = File.expand_path("check_docs.rb", __dir__)
  REQUIRED_FILES = {
    "README.md" => "# Prompt Smith\n\n[简体中文](README.zh-CN.md)\n\nhttps://ko-fi.com/tinkora\n",
    "README.zh-CN.md" => "# Prompt Smith\n\n[English](README.md)\n\nhttps://ko-fi.com/tinkora\n",
    "docs/PRODUCT_SPEC.md" => "# Specification\n\n[简体中文](PRODUCT_SPEC.zh-CN.md)\n",
    "docs/PRODUCT_SPEC.zh-CN.md" => "# 规格\n\n[English](PRODUCT_SPEC.md)\n",
    "AGENTS.md" => "# Repository guide\n",
    "LICENSE" => "MIT License\n",
    "CHANGELOG.md" => "# Changelog\n",
    "CODE_OF_CONDUCT.md" => "# Code of Conduct\n",
    "CONTRIBUTING.md" => "# Contributing\n",
    "SECURITY.md" => "# Security\n",
    "SUPPORT.md" => "# Support\n",
    ".github/FUNDING.yml" => "ko_fi: tinkora\n"
  }.freeze

  def test_valid_repository_passes
    with_fixture do |root|
      result = run_checker(root)

      assert result[:status].success?, result[:output]
      assert_includes result[:output], "Documentation checks passed"
    end
  end

  def test_missing_required_file_fails
    with_fixture(remove: ["SECURITY.md"]) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "Missing required file: SECURITY.md"
    end
  end

  def test_missing_translation_pair_fails
    with_fixture(remove: ["README.zh-CN.md"]) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "Missing bilingual pair: README.zh-CN.md"
    end
  end

  def test_missing_language_link_fails
    with_fixture(overrides: { "README.md" => "# Prompt Smith\n\nhttps://ko-fi.com/tinkora\n" }) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "README.md must link to README.zh-CN.md"
    end
  end

  def test_missing_funding_link_fails
    with_fixture(overrides: { "README.zh-CN.md" => "# Prompt Smith\n\n[English](README.md)\n" }) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "README.zh-CN.md must include https://ko-fi.com/tinkora"
    end
  end

  def test_invalid_funding_handle_fails
    with_fixture(overrides: { ".github/FUNDING.yml" => "ko_fi: another_account\n" }) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "Funding configuration must contain ko_fi: tinkora"
    end
  end

  def test_utf8_bom_fails
    with_fixture(overrides: { "README.md" => "\xEF\xBB\xBF# Prompt Smith\n".b }) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "UTF-8 BOM is not allowed: README.md"
    end
  end

  def test_invalid_utf8_source_fails
    with_fixture(overrides: { "src/lib.rs" => "pub fn check() {}\n\xFF".b }) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "Invalid UTF-8: src/lib.rs"
    end
  end

  private

  def with_fixture(remove: [], overrides: {})
    Dir.mktmpdir("check-docs-") do |root|
      files = REQUIRED_FILES.merge("Cargo.toml" => "[workspace]\n", "src/lib.rs" => "pub fn check() {}\n")
        .merge(overrides)
      remove.each { |path| files.delete(path) }
      files.each do |path, content|
        absolute_path = File.join(root, path)
        FileUtils.mkdir_p(File.dirname(absolute_path))
        File.binwrite(absolute_path, content)
      end

      run_git(root, "init", "--quiet")
      run_git(root, "add", "--all")
      yield root
    end
  end

  def run_checker(root)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, CHECKER, "--root", root)
    { output: stdout + stderr, status: status }
  end

  def run_git(root, *arguments)
    _stdout, stderr, status = Open3.capture3("git", "-C", root, *arguments)
    raise stderr unless status.success?
  end
end
