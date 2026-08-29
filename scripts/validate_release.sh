#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
repo_root="${2:-.}"
mode="${3:-canary}"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

if [[ "${mode}" != "canary" && "${mode}" != "tag" ]]; then
  fail "release validation mode must be canary or tag"
fi
semver_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'
if [[ "${tag}" != v* || ! "${tag#v}" =~ ${semver_pattern} ]]; then
  fail "release tag must contain stable SemVer after the v prefix"
fi
version="${tag#v}"

repo_root="$(cd -- "${repo_root}" && pwd -P)"
if [[ -z "${repo_root}" || "${repo_root}" == "/" || ! -f "${repo_root}/Cargo.toml" ]]; then
  fail "release repository root is invalid"
fi
cd -- "${repo_root}"

metadata="$(cargo metadata --locked --no-deps --format-version 1)" ||
  fail "unable to read locked Cargo metadata"
if ! jq -e --arg version "${version}" '
  [.packages[] | select(.name == "prompt_smith_core" or .name == "prompt_smith_web")] as $packages |
  ($packages | length) == 2 and all($packages[]; .version == $version)
' <<< "${metadata}" >/dev/null; then
  fail "Cargo package versions must both equal ${version}"
fi

package_json="crates/prompt_smith_web/package.json"
if ! jq -e --arg version "${version}" '.version == $version' "${package_json}" >/dev/null; then
  fail "package.json version must equal ${version}"
fi

if ! release_date="$(VERSION="${version}" ruby -rdate -e '
  version = ENV.fetch("VERSION")
  pattern = /^## \[#{Regexp.escape(version)}\] - (\d{4}-\d{2}-\d{2})$/
  dates = File.readlines("CHANGELOG.md", encoding: "UTF-8").filter_map do |line|
    match = pattern.match(line.chomp)
    match[1] if match
  end
  abort unless dates.length == 1
  abort unless Date.iso8601(dates.fetch(0)).to_s == dates.fetch(0)
  print dates.fetch(0)
')"; then
  fail "CHANGELOG.md must contain exactly one dated section for ${version}"
fi

case "${mode}" in
  canary)
    if git rev-parse --quiet --verify "refs/tags/${tag}^{commit}" >/dev/null; then
      fail "canary tag must not already exist locally: ${tag}"
    fi
    ;;
  tag)
    tag_type="$(git cat-file -t "refs/tags/${tag}" 2>/dev/null || true)"
    if [[ "${tag_type}" != "tag" ]]; then
      fail "release requires an annotated tag: ${tag}"
    fi
    tag_commit="$(git rev-parse --verify "refs/tags/${tag}^{commit}")"
    head_commit="$(git rev-parse --verify 'HEAD^{commit}')"
    if [[ "${tag_commit}" != "${head_commit}" ]]; then
      fail "tag ${tag} must resolve to HEAD"
    fi
    if [[ -n "${GITHUB_REF:-}" && "${GITHUB_REF}" != "refs/tags/${tag}" ]]; then
      fail "GitHub workflow ref must equal refs/tags/${tag}; found: ${GITHUB_REF}"
    fi
    ;;
esac

printf 'Release metadata is consistent for %s (%s, %s).\n' "${tag}" "${release_date}" "${mode}"
