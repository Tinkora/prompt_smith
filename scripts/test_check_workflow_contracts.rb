# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

class CheckWorkflowContractsTest < Minitest::Test
  CHECKER = File.expand_path("check_workflow_contracts.rb", __dir__)
  COMMIT = "92df6f4d1a1f4d66fe605a0d30a81f3c2994ef99"
  CHECKOUT = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
  BUILD_PROVENANCE = "actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8"
  ATTEST = "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6"

  def test_valid_workflows_pass
    with_fixture do |root|
      result = run_checker(root)

      assert result[:status].success?, result[:output]
      assert_includes result[:output], "Workflow contracts passed"
    end
  end

  def test_floating_step_action_fails
    with_fixture(checkout: "actions/checkout@v4") do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "external use must be pinned to a full commit SHA"
    end
  end

  def test_floating_reusable_reference_fails
    with_fixture(reusable_commit: "main") do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "must use Tinkora/.github"
    end
  end

  def test_missing_wasm_job_fails
    with_fixture(include_wasm: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "quality.yml job wasm must use"
    end
  end

  def test_pull_request_target_fails
    with_fixture(pull_request_target: true) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "must not use pull_request_target"
    end
  end

  def test_missing_release_workflow_fails
    with_fixture(include_release: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "Missing workflow: release.yml"
    end
  end

  def test_deprecated_sbom_attestation_action_fails
    with_fixture(attest_action: "actions/attest-sbom@c604332985a26aa8cf1bdc465b92731239ec6b9e") do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml must use #{ATTEST} for the SPDX SBOM"
    end
  end

  def test_release_publish_permissions_are_minimal
    with_fixture(publish_permissions: { "contents" => "write", "id-token" => "write" }) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml publish permissions must be contents: write only"
    end
  end

  def test_release_asset_inventory_is_exact
    with_fixture(asset_inventory: %w[SHA256SUMS SBOM.spdx.json LICENSES.json prompt_smith-web]) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml must enforce the exact five-asset inventory"
    end
  end

  def test_release_prerelease_detection_ignores_build_metadata
    with_fixture(safe_prerelease: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml must derive prerelease state without inspecting build metadata"
    end
  end

  def test_release_verifies_remote_asset_names_and_digests
    with_fixture(verify_remote_assets: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml must verify remote asset names and SHA-256 digests"
    end
  end

  def test_failed_release_cleans_up_only_its_draft
    with_fixture(cleanup_draft: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml must delete its own draft after a failed publication"
    end
  end

  def test_pages_artifact_can_be_replaced_on_rerun
    with_fixture(pages_overwrite: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "pages.yml artifact must support full-run retries"
    end
  end

  def test_release_source_artifact_can_be_replaced_on_rerun
    with_fixture(release_overwrite: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml source artifact must support full-run retries"
    end
  end

  def test_release_requires_annotated_tags_at_both_remote_checks
    with_fixture(annotated_tag_checks: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml must require an annotated tag at both remote checks"
    end
  end

  def test_release_tag_peeling_is_bounded
    with_fixture(bounded_tag_peeling: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml must bound both tag peel loops to 16 objects"
    end
  end

  def test_release_staging_scan_cannot_fail_open_on_sigpipe
    with_fixture(safe_staging_scan: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml staging scan must stop after its first unsafe entry"
    end
  end

  def test_release_recovers_an_interrupted_matching_draft
    with_fixture(recover_draft: false) do |root|
      result = run_checker(root)

      refute result[:status].success?
      assert_includes result[:output], "release.yml must recover its interrupted draft before retrying"
    end
  end

  private

  def with_fixture(
    checkout: CHECKOUT,
    reusable_commit: COMMIT,
    include_wasm: true,
    pull_request_target: false,
    include_release: true,
    attest_action: ATTEST,
    publish_permissions: { "contents" => "write" },
    asset_inventory: %w[LICENSES.json SBOM.spdx.json SHA256SUMS prompt_smith-source prompt_smith-web],
    safe_prerelease: true,
    verify_remote_assets: true,
    cleanup_draft: true,
    pages_overwrite: true,
    release_overwrite: true,
    annotated_tag_checks: true,
    bounded_tag_peeling: true,
    safe_staging_scan: true,
    recover_draft: true
  )
    Dir.mktmpdir("workflow-contracts-") do |root|
      quality_jobs = {
        "rust" => {
          "uses" => "Tinkora/.github/.github/workflows/reusable-rust-quality.yml@#{reusable_commit}"
        }
      }
      if include_wasm
        quality_jobs["wasm"] = {
          "uses" => "Tinkora/.github/.github/workflows/reusable-wasm-quality.yml@#{reusable_commit}"
        }
      end
      write_workflow(root, "quality.yml", {
        "on" => { "workflow_call" => nil },
        "permissions" => { "contents" => "read" },
        "jobs" => quality_jobs
      })
      write_workflow(root, "docs-quality.yml", basic_workflow(checkout, pull_request_target))
      write_workflow(root, "supply-chain.yml", {
        "on" => { "pull_request" => nil },
        "permissions" => { "contents" => "read" },
        "jobs" => {
          "rust-audit" => {
            "uses" => "Tinkora/.github/.github/workflows/reusable-supply-chain.yml@#{reusable_commit}"
          },
          "npm-audit" => {
            "runs-on" => "ubuntu-24.04",
            "steps" => [
              { "uses" => checkout },
              { "run" => "npm audit --audit-level=high --registry=https://registry.npmjs.org" }
            ]
          }
        }
      })
      write_workflow(root, "pages.yml", {
        "on" => { "push" => { "branches" => ["main"] } },
        "permissions" => { "contents" => "read" },
        "jobs" => {
          "quality" => { "uses" => "./.github/workflows/quality.yml" },
          "build" => {
            "needs" => "quality",
            "runs-on" => "ubuntu-24.04",
            "steps" => [
              { "uses" => checkout },
              { "run" => "bash scripts/build_pages.sh" },
              {
                "uses" => "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
                "with" => {
                  "name" => "prompt_smith_pages_${{ github.run_id }}",
                  "path" => "dist",
                  "overwrite" => pages_overwrite
                }
              }
            ]
          },
          "deploy" => {
            "uses" => "Tinkora/.github/.github/workflows/reusable-pages.yml@#{reusable_commit}",
            "needs" => "build"
          }
        }
      })
      write_release_workflow(
        root,
        reusable_commit,
        checkout,
        attest_action,
        publish_permissions,
        asset_inventory,
        safe_prerelease,
        verify_remote_assets,
        cleanup_draft,
        release_overwrite,
        annotated_tag_checks,
        bounded_tag_peeling,
        safe_staging_scan,
        recover_draft
      ) if include_release
      yield root
    end
  end

  def write_release_workflow(
    root,
    reusable_commit,
    checkout,
    attest_action,
    publish_permissions,
    asset_inventory,
    safe_prerelease,
    verify_remote_assets,
    cleanup_draft,
    release_overwrite,
    annotated_tag_checks,
    bounded_tag_peeling,
    safe_staging_scan,
    recover_draft
  )
    inventory = asset_inventory.map do |asset|
      case asset
      when "prompt_smith-source"
        '"prompt_smith-source-v${VERSION}.tar.gz"'
      when "prompt_smith-web"
        '"prompt_smith-web-v${VERSION}.tar.gz"'
      else
        asset
      end
    end.join("\n")
    prerelease_script = if safe_prerelease
      <<~SHELL
        version_without_build="${VERSION%%+*}"
        [[ "${version_without_build}" == *-* ]]
      SHELL
    else
      '[[ "${VERSION}" == *-* ]]'
    end
    remote_asset_script = verify_remote_assets ? <<~SHELL : ""
      jq -e '.assets | length == 5' <<< "${release_json}"
      jq -r '.assets[].name' <<< "${release_json}"
      jq -r '.assets[].digest' <<< "${release_json}"
      sha256sum -- candidate/LICENSES.json
    SHELL
    tag_check_script = <<~SHELL
      gh api git/ref/tags
      #{annotated_tag_checks ? 'outer_tag_type="tag"; [[ "${outer_tag_type}" == "tag" ]]' : ''}
      #{bounded_tag_peeling ? 'peel_depth=0; ((peel_depth > 16))' : ''}
    SHELL
    recovery_script = recover_draft ? <<~SHELL : ""
      stale_draft_id="$(gh api --paginate --slurp repos/example/releases --jq '.[] | select(.draft == true and .tag_name == "v1.0.0" and .target_commitish == "commit") | .id')"
      gh api --method DELETE "repos/example/releases/${stale_draft_id}"
    SHELL
    publish_steps = [{
      "id" => "draft",
      "run" => <<~SHELL
        expected_assets=(
        #{inventory.lines.map { |line| "  #{line.strip}" }.join("\n")}
        )
        #{prerelease_script}
        #{recovery_script}
        release_id="$(gh api --method POST repos/example/releases --jq .id)"
        echo "release_id=${release_id}" >> "${GITHUB_OUTPUT}"
        #{tag_check_script}
        gh release create --draft --verify-tag
        release_json="$(gh api "repos/example/releases/${release_id}")"
        #{remote_asset_script}
        #{tag_check_script}
        gh api --method PATCH "repos/example/releases/${release_id}" -F draft=false
        gh release edit --draft=false
      SHELL
    }]
    if cleanup_draft
      publish_steps << {
        "if" => "${{ failure() }}",
          "env" => { "RELEASE_ID" => "${{ steps.draft.outputs.release_id }}" },
          "run" => <<~SHELL
          release_json="$(gh api "repos/example/releases/${RELEASE_ID}")"
          jq -e '.draft == true and .tag_name == "v1.0.0"' <<< "${release_json}"
          gh api --method DELETE "repos/example/releases/${RELEASE_ID}"
        SHELL
      }
    end

    write_workflow(root, "release.yml", {
      "on" => { "push" => { "tags" => ["v*"] } },
      "permissions" => { "contents" => "read" },
      "jobs" => {
        "metadata" => {
          "runs-on" => "ubuntu-24.04",
          "steps" => [{ "uses" => checkout }, { "run" => "bash scripts/validate_release.sh" }]
        },
        "quality" => { "uses" => "./.github/workflows/quality.yml" },
        "build" => {
          "needs" => %w[metadata quality],
          "runs-on" => "ubuntu-24.04",
          "steps" => [
            { "uses" => checkout },
            {
              "run" => safe_staging_scan ?
                "bash scripts/build_pages.sh\nfind staging -type l -print -quit | grep -q ." :
                "bash scripts/build_pages.sh\nfind staging -type l | grep -q ."
            },
            {
              "uses" => "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
              "with" => {
                "name" => "prompt_smith_release_source_${{ github.run_id }}",
                "path" => "candidate",
                "overwrite" => release_overwrite
              }
            }
          ]
        },
        "candidate" => {
          "needs" => %w[metadata build],
          "uses" => "Tinkora/.github/.github/workflows/reusable-release.yml@#{reusable_commit}",
          "permissions" => { "contents" => "read" },
          "with" => { "publish" => false }
        },
        "attest" => {
          "needs" => %w[metadata candidate],
          "runs-on" => "ubuntu-24.04",
          "permissions" => { "contents" => "read", "attestations" => "write", "id-token" => "write" },
          "steps" => [
            { "uses" => BUILD_PROVENANCE, "with" => { "subject-path" => "candidate/*.tar.gz" } },
            {
              "uses" => attest_action,
              "with" => {
                "subject-path" => "candidate/*.tar.gz",
                "sbom-path" => "candidate/SBOM.spdx.json"
              }
            }
          ]
        },
        "publish" => {
          "needs" => %w[metadata quality build candidate attest],
          "runs-on" => "ubuntu-24.04",
          "environment" => "release",
          "permissions" => publish_permissions,
          "steps" => publish_steps
        }
      }
    })
  end

  def basic_workflow(checkout, pull_request_target)
    triggers = pull_request_target ? { "pull_request_target" => nil } : { "pull_request" => nil }
    {
      "on" => triggers,
      "permissions" => { "contents" => "read" },
      "jobs" => {
        "docs" => {
          "runs-on" => "ubuntu-24.04",
          "steps" => [
            { "uses" => checkout },
            {
              "run" => <<~SHELL
                ruby scripts/test_check_commit_policy.rb
                ruby scripts/test_check_docs.rb
                ruby scripts/test_check_workflow_contracts.rb
                ruby scripts/check_commit_policy.rb
                ruby scripts/check_docs.rb
                ruby scripts/check_workflow_contracts.rb
              SHELL
            }
          ]
        }
      }
    }
  end

  def write_workflow(root, name, document)
    path = File.join(root, ".github/workflows", name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(document), encoding: "UTF-8")
  end

  def run_checker(root)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, CHECKER, "--root", root)
    { output: stdout + stderr, status: status }
  end
end
