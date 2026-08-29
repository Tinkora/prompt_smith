#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
validator="${script_dir}/validate_release.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

reset_fixture() {
  find "${fixture_root}" -mindepth 1 -delete
  mkdir -p "${fixture_root}/crates/prompt_smith_core/src" \
    "${fixture_root}/crates/prompt_smith_web/src"

  printf '%s\n' \
    '[workspace]' \
    'members = ["crates/prompt_smith_core", "crates/prompt_smith_web"]' \
    'resolver = "3"' \
    > "${fixture_root}/Cargo.toml"
  for crate in prompt_smith_core prompt_smith_web; do
    printf '%s\n' \
      '[package]' \
      "name = \"${crate}\"" \
      'version = "0.1.0-alpha.1"' \
      'edition = "2024"' \
      > "${fixture_root}/crates/${crate}/Cargo.toml"
    printf '%s\n' 'pub fn fixture() {}' > "${fixture_root}/crates/${crate}/src/lib.rs"
  done
  printf '%s\n' \
    '{' \
    '  "name": "@tinkora/prompt_smith_web",' \
    '  "version": "0.1.0-alpha.1"' \
    '}' \
    > "${fixture_root}/crates/prompt_smith_web/package.json"
  printf '%s\n' \
    '# Changelog' \
    '' \
    '## [0.1.0-alpha.1] - 2026-08-15' \
    > "${fixture_root}/CHANGELOG.md"

  cargo generate-lockfile --quiet --manifest-path "${fixture_root}/Cargo.toml"
  git -C "${fixture_root}" init --quiet
  git -C "${fixture_root}" config user.name tinkeragora
  git -C "${fixture_root}" config user.email 314183062+tinkeragora@users.noreply.github.com
  git -C "${fixture_root}" add --all
  git -C "${fixture_root}" commit --quiet -m 'chore: initialize release fixture'
}

expect_failure() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    printf 'Expected command to fail: %s\n' "$*" >&2
    exit 1
  fi
  if [[ "${output}" != *"${expected}"* ]]; then
    printf 'Expected failure containing %q, got:\n%s\n' "${expected}" "${output}" >&2
    exit 1
  fi
}

reset_fixture
"${validator}" v0.1.0-alpha.1 "${fixture_root}" canary

expect_failure "stable SemVer" \
  "${validator}" v01.1.0 "${fixture_root}" canary
expect_failure "mode must be canary or tag" \
  "${validator}" v0.1.0-alpha.1 "${fixture_root}" preview

reset_fixture
sed -i.bak 's/version = "0.1.0-alpha.1"/version = "0.2.0"/' \
  "${fixture_root}/crates/prompt_smith_web/Cargo.toml"
rm "${fixture_root}/crates/prompt_smith_web/Cargo.toml.bak"
cargo generate-lockfile --quiet --manifest-path "${fixture_root}/Cargo.toml"
expect_failure "Cargo package versions" \
  "${validator}" v0.1.0-alpha.1 "${fixture_root}" canary

reset_fixture
sed -i.bak 's/0.1.0-alpha.1/0.2.0/' \
  "${fixture_root}/crates/prompt_smith_web/package.json"
rm "${fixture_root}/crates/prompt_smith_web/package.json.bak"
expect_failure "package.json version" \
  "${validator}" v0.1.0-alpha.1 "${fixture_root}" canary

reset_fixture
printf '\n## [0.1.0-alpha.1] - 2026-08-15\n' >> "${fixture_root}/CHANGELOG.md"
expect_failure "exactly one dated section" \
  "${validator}" v0.1.0-alpha.1 "${fixture_root}" canary

reset_fixture
git -C "${fixture_root}" tag v0.1.0-alpha.1
GITHUB_REF=refs/tags/v0.1.0-alpha.1 \
  expect_failure "annotated tag" \
  "${validator}" v0.1.0-alpha.1 "${fixture_root}" tag

reset_fixture
git -C "${fixture_root}" tag -a v0.1.0-alpha.1 -m 'release: prompt_smith 0.1.0-alpha.1'
printf '\n' >> "${fixture_root}/CHANGELOG.md"
git -C "${fixture_root}" add CHANGELOG.md
git -C "${fixture_root}" commit --quiet -m 'docs: move beyond release commit'
GITHUB_REF=refs/tags/v0.1.0-alpha.1 \
  expect_failure "must resolve to HEAD" \
  "${validator}" v0.1.0-alpha.1 "${fixture_root}" tag

reset_fixture
git -C "${fixture_root}" tag -a v0.1.0-alpha.1 -m 'release: prompt_smith 0.1.0-alpha.1'
GITHUB_REF=refs/tags/v0.1.0-alpha.1 \
  "${validator}" v0.1.0-alpha.1 "${fixture_root}" tag

printf 'Release metadata validation tests passed.\n'
