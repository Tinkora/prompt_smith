# frozen_string_literal: true

require "optparse"
require "yaml"

REUSABLE_WORKFLOW_COMMIT = "92df6f4d1a1f4d66fe605a0d30a81f3c2994ef99"
WORKFLOW_DIR = ".github/workflows"
REQUIRED_WORKFLOWS = %w[quality.yml docs-quality.yml supply-chain.yml pages.yml release.yml].freeze
BUILD_PROVENANCE_ACTION = "actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8"
ATTEST_ACTION = "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6"
RELEASE_ASSET_LINES = [
  "LICENSES.json",
  "SBOM.spdx.json",
  "SHA256SUMS",
  '"prompt_smith-source-v${VERSION}.tar.gz"',
  '"prompt_smith-web-v${VERSION}.tar.gz"'
].freeze
EXPECTED_CALLS = {
  "quality.yml" => {
    "rust" => "Tinkora/.github/.github/workflows/reusable-rust-quality.yml@#{REUSABLE_WORKFLOW_COMMIT}",
    "wasm" => "Tinkora/.github/.github/workflows/reusable-wasm-quality.yml@#{REUSABLE_WORKFLOW_COMMIT}"
  },
  "supply-chain.yml" => {
    "rust-audit" => "Tinkora/.github/.github/workflows/reusable-supply-chain.yml@#{REUSABLE_WORKFLOW_COMMIT}"
  },
  "pages.yml" => {
    "deploy" => "Tinkora/.github/.github/workflows/reusable-pages.yml@#{REUSABLE_WORKFLOW_COMMIT}"
  },
  "release.yml" => {
    "candidate" => "Tinkora/.github/.github/workflows/reusable-release.yml@#{REUSABLE_WORKFLOW_COMMIT}"
  }
}.freeze
FULL_SHA_USE = /\A[^@\s]+@[0-9a-f]{40}\z/

options = { root: Dir.pwd }
OptionParser.new do |parser|
  parser.on("--root PATH") { |path| options[:root] = path }
end.parse!

root = File.expand_path(options[:root])
errors = []
workflows = {}

REQUIRED_WORKFLOWS.each do |name|
  path = File.join(root, WORKFLOW_DIR, name)
  unless File.file?(path)
    errors << "Missing workflow: #{name}"
    next
  end

  begin
    workflows[name] = YAML.safe_load_file(path, aliases: false)
  rescue Psych::Exception => error
    errors << "Invalid workflow #{name}: #{error.message}"
  end
end

workflows.each do |name, workflow|
  unless workflow["permissions"] == { "contents" => "read" }
    errors << "#{name} top-level permissions must be contents: read"
  end

  triggers = workflow.fetch("on", {}) || {}
  errors << "#{name} must not use pull_request_target" if triggers.key?("pull_request_target")

  jobs = workflow.fetch("jobs", {})
  jobs.each do |job_name, job|
    uses = [job["uses"]] + job.fetch("steps", []).filter_map { |step| step["uses"] }
    uses.compact.each do |use|
      next if use.start_with?("./")
      next if use.match?(FULL_SHA_USE)

      errors << "#{name}/#{job_name} external use must be pinned to a full commit SHA: #{use}"
    end
  end

  text = File.read(File.join(root, WORKFLOW_DIR, name), encoding: "UTF-8")
  errors << "#{name} must not use write-all" if text.match?(/\bwrite-all\b/)
  errors << "#{name} must not inherit secrets" if text.include?("secrets: inherit")
end

EXPECTED_CALLS.each do |workflow_name, expected_jobs|
  workflow = workflows[workflow_name]
  next unless workflow

  expected_jobs.each do |job_name, expected_reference|
    actual_reference = workflow.dig("jobs", job_name, "uses")
    next if actual_reference == expected_reference

    errors << "#{workflow_name} job #{job_name} must use #{expected_reference}"
  end
end

quality = workflows["quality.yml"]
if quality
  triggers = quality.fetch("on", {}) || {}
  errors << "quality.yml must support workflow_call" unless triggers.key?("workflow_call")
end

docs_text = File.read(File.join(root, WORKFLOW_DIR, "docs-quality.yml"), encoding: "UTF-8") if workflows["docs-quality.yml"]
if docs_text
  %w[
    scripts/test_check_commit_policy.rb
    scripts/test_check_docs.rb
    scripts/test_check_workflow_contracts.rb
    scripts/check_commit_policy.rb
    scripts/check_docs.rb
    scripts/check_workflow_contracts.rb
  ].each do |command|
    errors << "docs-quality.yml must run #{command}" unless docs_text.include?(command)
  end
end

supply_text = File.read(File.join(root, WORKFLOW_DIR, "supply-chain.yml"), encoding: "UTF-8") if workflows["supply-chain.yml"]
if supply_text && !supply_text.include?("npm audit --audit-level=high --registry=https://registry.npmjs.org")
  errors << "supply-chain.yml must run npm audit against the official registry"
end

pages = workflows["pages.yml"]
if pages
  errors << "pages.yml quality job must call the local quality workflow" unless pages.dig("jobs", "quality", "uses") == "./.github/workflows/quality.yml"
  errors << "pages.yml build job must depend on quality" unless pages.dig("jobs", "build", "needs") == "quality"
  build_steps = pages.dig("jobs", "build", "steps") || []
  errors << "pages.yml must build with scripts/build_pages.sh" unless build_steps.any? { |step| step["run"]&.include?("bash scripts/build_pages.sh") }
  upload = build_steps.find { |step| step["uses"]&.start_with?("actions/upload-artifact@") }
  unless upload&.dig("with", "name") == "prompt_smith_pages_${{ github.run_id }}" && upload&.dig("with", "path") == "dist"
    errors << "pages.yml artifact contract is invalid"
  end
  errors << "pages.yml artifact must support full-run retries" unless upload&.dig("with", "overwrite") == true
end

release = workflows["release.yml"]
if release
  release_triggers = release.fetch("on", {}) || {}
  release_tags = release_triggers.dig("push", "tags")
  errors << "release.yml must run only for v* tags" unless release_tags == ["v*"] && release_triggers.keys == ["push"]

  jobs = release.fetch("jobs", {})
  metadata = jobs["metadata"] || {}
  quality_job = jobs["quality"] || {}
  build = jobs["build"] || {}
  candidate = jobs["candidate"] || {}
  attest = jobs["attest"] || {}
  publish = jobs["publish"] || {}

  errors << "release.yml quality job must call the local quality workflow" unless quality_job["uses"] == "./.github/workflows/quality.yml"
  errors << "release.yml build job dependencies are invalid" unless Array(build["needs"]).sort == %w[metadata quality]
  errors << "release.yml candidate job dependencies are invalid" unless Array(candidate["needs"]).sort == %w[build metadata]
  errors << "release.yml candidate must remain dry-run" unless candidate.dig("with", "publish") == false
  unless candidate["permissions"] == { "contents" => "read" }
    errors << "release.yml candidate permissions must be contents: read"
  end

  expected_attest_permissions = {
    "contents" => "read",
    "attestations" => "write",
    "id-token" => "write"
  }
  unless attest["permissions"] == expected_attest_permissions
    errors << "release.yml attest permissions must be contents: read, attestations: write, and id-token: write"
  end
  errors << "release.yml attest job dependencies are invalid" unless Array(attest["needs"]).sort == %w[candidate metadata]

  attest_steps = attest.fetch("steps", [])
  provenance = attest_steps.find { |step| step["uses"] == BUILD_PROVENANCE_ACTION }
  unless provenance&.dig("with", "subject-path") == "candidate/*.tar.gz"
    errors << "release.yml must attest both release archives with #{BUILD_PROVENANCE_ACTION}"
  end
  sbom_attestation = attest_steps.find { |step| step["uses"] == ATTEST_ACTION }
  unless sbom_attestation&.dig("with", "subject-path") == "candidate/*.tar.gz" &&
      sbom_attestation&.dig("with", "sbom-path") == "candidate/SBOM.spdx.json"
    errors << "release.yml must use #{ATTEST_ACTION} for the SPDX SBOM"
  end

  unless publish["permissions"] == { "contents" => "write" }
    errors << "release.yml publish permissions must be contents: write only"
  end
  errors << "release.yml publish job must use the release environment" unless publish["environment"] == "release"
  expected_publish_needs = %w[attest build candidate metadata quality]
  errors << "release.yml publish job dependencies are invalid" unless Array(publish["needs"]).sort == expected_publish_needs

  metadata_script = metadata.fetch("steps", []).filter_map { |step| step["run"] }.join("\n")
  errors << "release.yml must validate release metadata" unless metadata_script.include?("scripts/validate_release.sh")
  build_script = build.fetch("steps", []).filter_map { |step| step["run"] }.join("\n")
  errors << "release.yml must build the reviewed Pages distribution" unless build_script.include?("bash scripts/build_pages.sh")
  unless build_script.include?("find staging") && build_script.include?("-print -quit")
    errors << "release.yml staging scan must stop after its first unsafe entry"
  end
  release_upload = build.fetch("steps", []).find { |step| step["uses"]&.start_with?("actions/upload-artifact@") }
  unless release_upload&.dig("with", "name") == "prompt_smith_release_source_${{ github.run_id }}" &&
      release_upload&.dig("with", "path") == "candidate"
    errors << "release.yml source artifact contract is invalid"
  end
  unless release_upload&.dig("with", "overwrite") == true
    errors << "release.yml source artifact must support full-run retries"
  end

  publish_script = publish.fetch("steps", []).filter_map { |step| step["run"] }.join("\n")
  asset_block = publish_script[/expected_assets=\(\s*\n(?<assets>.*?)\n\s*\)/m, :assets]
  asset_lines = asset_block&.lines&.map(&:strip)&.reject(&:empty?)
  unless asset_lines == RELEASE_ASSET_LINES
    errors << "release.yml must enforce the exact five-asset inventory"
  end
  errors << "release.yml must verify the remote tag before draft creation and publication" if publish_script.scan("git/ref/tags").length < 2
  annotated_comparisons = publish_script.scan('"${outer_tag_type}" == "tag"').length +
    publish_script.scan('"${outer_tag_type}" != "tag"').length
  unless publish_script.scan("outer_tag_type=").length >= 2 && annotated_comparisons >= 2
    errors << "release.yml must require an annotated tag at both remote checks"
  end
  unless publish_script.scan("peel_depth=0").length >= 2 &&
      publish_script.scan("peel_depth > 16").length >= 2
    errors << "release.yml must bound both tag peel loops to 16 objects"
  end
  draft_step = publish.fetch("steps", []).find { |step| step["id"] == "draft" }
  draft_script = draft_step&.fetch("run", "") || ""
  unless draft_script.include?("--method POST") && draft_script.include?("release_id") &&
      draft_script.include?("GITHUB_OUTPUT") &&
      (draft_script.include?("-F draft=true") || draft_script.include?("--draft"))
    errors << "release.yml must create a verified draft release"
  end
  unless publish_script.include?("--method PATCH") &&
      (publish_script.include?("-F draft=false") || publish_script.include?("--draft=false"))
    errors << "release.yml must publish only after draft verification"
  end

  unless publish_script.include?('version_without_build="${VERSION%%+*}"') &&
      publish_script.include?('"${version_without_build}" == *-*')
    errors << "release.yml must derive prerelease state without inspecting build metadata"
  end

  remote_asset_markers = [
    ".assets | length == 5",
    ".assets[].name",
    ".assets[]",
    ".digest",
    "sha256sum"
  ]
  unless remote_asset_markers.all? { |marker| draft_script.include?(marker) }
    errors << "release.yml must verify remote asset names and SHA-256 digests"
  end

  recovery_markers = [
    "--paginate",
    "--slurp",
    ".draft",
    ".tag_name",
    ".target_commitish",
    "--method DELETE"
  ]
  unless recovery_markers.all? { |marker| draft_script.include?(marker) }
    errors << "release.yml must recover its interrupted draft before retrying"
  end

  cleanup_step = publish.fetch("steps", []).find { |step| step["if"] == "${{ failure() }}" }
  cleanup_script = cleanup_step&.fetch("run", "") || ""
  unless cleanup_step&.dig("env", "RELEASE_ID") == "${{ steps.draft.outputs.release_id }}" &&
      cleanup_script.include?(".draft") && cleanup_script.include?("--method DELETE") &&
      cleanup_script.include?("${RELEASE_ID}") && cleanup_script.include?(".tag_name")
    errors << "release.yml must delete its own draft after a failed publication"
  end
end

if errors.empty?
  puts "Workflow contracts passed (organization commit #{REUSABLE_WORKFLOW_COMMIT})."
  exit 0
end

errors.each { |error| warn error }
exit 1
