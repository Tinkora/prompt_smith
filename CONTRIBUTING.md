# Contributing to Prompt Smith

Prompt Smith accepts focused fixes, compatibility evidence, diagnostics, tests,
documentation, and accessibility improvements within the published product
boundary.

## Requirements

- Rust 1.85 or newer
- `wasm32-unknown-unknown` target
- `wasm-pack 0.15`
- Node.js 24

## Project Structure

```text
crates/prompt_smith_core/         parser, diagnostics, and strict renderer
crates/prompt_smith_web/          WASM bridge, static app, and browser tests
docs/                             English and Chinese product specifications
.github/workflows/                quality, security, Pages, and release automation
```

## Validate a Change

```bash
cargo fmt --all -- --check
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo check -p prompt_smith_web --target wasm32-unknown-unknown --locked

cd crates/prompt_smith_web
npm ci --ignore-scripts
npm run build:wasm
npm run test:wasm-smoke
```

Parser changes need outcome-focused native tests. WASM contract changes need
bridge tests. User-visible behavior changes need real-browser coverage at 375,
768, 1024, and 1440 pixels.

## Pull Requests

1. Open an issue when a change expands syntax or product scope and include
   independent compatibility or user-demand evidence.
2. Create a focused branch and use English Conventional Commits.
3. Keep public code comments in English.
4. Update both language versions when changing user-facing documentation.
5. Run the relevant validation commands before opening the pull request.

By participating, you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
