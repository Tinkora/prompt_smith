# Repository Guide for AI Agents

## Product Boundary

Prompt Smith is a browser-local strict preflight checker for prompt template
variable contracts. It supports the variable-only simple double-brace syntax
and the documented LangChain f-string subset in `docs/PRODUCT_SPEC.md`.

Do not add token or cost estimates, model calls, prompt evaluation, persistence,
cloud synchronization, or Agent transports without new independent demand
evidence and an executable end-to-end implementation.

## Architecture

```text
crates/prompt_smith_core/        parsing, diagnostics, and strict rendering
crates/prompt_smith_web/         WASM bridge, static application, and browser tests
docs/                            bilingual product specification
scripts/                         repository and release contract checks
.github/workflows/               quality, Pages, security, and release automation
```

The Rust core owns template semantics. JavaScript may localize and present a
report but must not reimplement parsing or rendering.

## Development

Use Rust 1.85 or newer and keep `Cargo.lock` and
`crates/prompt_smith_web/package-lock.json` committed.

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

Public code comments must be written in English. Add outcome-focused regression
tests for every parser diagnostic, WASM contract, or browser behavior change.

## Commit Language

Write commit subjects and bodies in English and follow Conventional Commits.
This repository-level rule overrides any global preference for another
commit-message language.

## Frontend Design Requirement

- Before creating, modifying, reviewing, or debugging any HTML page or user-facing frontend, invoke the `ui-ux-pro-max` skill.
- Run the skill's required `--design-system` search before editing, followed by relevant stack and UX searches.
- If `ui-ux-pro-max` is unavailable, stop frontend work and report the missing prerequisite.
- Verify the rendered result in a real browser at 375, 768, 1024, and 1440 pixel widths, including console, keyboard, accessibility, and overflow checks.
