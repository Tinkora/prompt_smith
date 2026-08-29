#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
dist_dir="${repo_root}/dist"
static_dir="${repo_root}/crates/prompt_smith_web/static"

expected=$'.nojekyll\nassets/app.js\nassets/styles.css\nindex.html\npkg/prompt_smith_web.js\npkg/prompt_smith_web_bg.wasm'
actual="$(find "${dist_dir}" -type f -print 2>/dev/null | sed "s#^${dist_dir}/##" | LC_ALL=C sort || true)"
if [[ "${actual}" != "${expected}" ]]; then
  printf 'Pages artifact inventory is not exact.\n' >&2
  diff -u <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") >&2 || true
  exit 1
fi

if find "${dist_dir}" -type l -o \( ! -type f ! -type d \) | grep -q .; then
  printf 'Pages artifact contains a symlink or special file.\n' >&2
  exit 1
fi

for relative in index.html assets/app.js assets/styles.css; do
  if ! cmp -s -- "${static_dir}/${relative}" "${dist_dir}/${relative}"; then
    printf 'Pages artifact differs from reviewed source: %s\n' "${relative}" >&2
    exit 1
  fi
done

for relative in pkg/prompt_smith_web.js pkg/prompt_smith_web_bg.wasm; do
  if [[ ! -s "${dist_dir}/${relative}" ]]; then
    printf 'Pages runtime asset is empty: %s\n' "${relative}" >&2
    exit 1
  fi
done

if ! grep -Fq "default-src 'self'" "${dist_dir}/index.html"; then
  printf 'Pages entry point is missing its CSP baseline.\n' >&2
  exit 1
fi

printf 'Pages artifact contract passed.\n'
