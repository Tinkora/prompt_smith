#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "${script_dir}/.." && pwd -P)"
dist_dir="${repo_root}/dist"
web_dir="${repo_root}/crates/prompt_smith_web"
static_dir="${web_dir}/static"
pkg_dir="${static_dir}/pkg"

if [[ -z "${repo_root}" || "${repo_root}" == "/" || "${dist_dir}" != "${repo_root}/dist" ]]; then
  printf 'Refusing to resolve an unsafe Pages output path.\n' >&2
  exit 1
fi
for source_dir in "${web_dir}" "${static_dir}"; do
  if [[ -L "${source_dir}" || ! -d "${source_dir}" ]]; then
    printf 'Refusing unsafe source directory: %s\n' "${source_dir}" >&2
    exit 1
  fi
done
if [[ -L "${dist_dir}" ]]; then
  printf 'Refusing symlinked Pages output path.\n' >&2
  exit 1
fi

(cd -- "${web_dir}" && npm run build:wasm)

required=(
  "${static_dir}/index.html"
  "${static_dir}/assets/app.js"
  "${static_dir}/assets/styles.css"
  "${pkg_dir}/prompt_smith_web.js"
  "${pkg_dir}/prompt_smith_web_bg.wasm"
)
for source in "${required[@]}"; do
  if [[ -L "${source}" || ! -f "${source}" ]]; then
    printf 'Missing or unsafe Pages source: %s\n' "${source}" >&2
    exit 1
  fi
done

if [[ -e "${dist_dir}" ]]; then
  if [[ ! -d "${dist_dir}" ]]; then
    printf 'Refusing non-directory Pages output path.\n' >&2
    exit 1
  fi
  if find "${dist_dir}" -type l -o \( ! -type f ! -type d \) | grep -q .; then
    printf 'Refusing unsafe existing Pages output.\n' >&2
    exit 1
  fi
  find "${dist_dir}" -mindepth 1 -delete
fi

mkdir -p -- "${dist_dir}/assets" "${dist_dir}/pkg"
cp -- "${static_dir}/index.html" "${dist_dir}/index.html"
cp -- "${static_dir}/assets/app.js" "${dist_dir}/assets/app.js"
cp -- "${static_dir}/assets/styles.css" "${dist_dir}/assets/styles.css"
cp -- "${pkg_dir}/prompt_smith_web.js" "${dist_dir}/pkg/prompt_smith_web.js"
cp -- "${pkg_dir}/prompt_smith_web_bg.wasm" "${dist_dir}/pkg/prompt_smith_web_bg.wasm"
: > "${dist_dir}/.nojekyll"

bash "${script_dir}/test_build_pages.sh"
