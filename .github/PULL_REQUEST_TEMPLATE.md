# Pull Request

## What

<!-- Describe what this PR does -->

## Type

- [ ] feat: New feature
- [ ] fix: Bug fix
- [ ] docs: Documentation
- [ ] refactor: Refactoring
- [ ] test: Tests
- [ ] chore: Maintenance

## Checklist

- [ ] `cargo fmt --all -- --check` passes
- [ ] `cargo test --workspace --locked` passes
- [ ] `cargo clippy --workspace --all-targets --locked -- -D warnings` passes
- [ ] `cargo check -p prompt_smith_web --target wasm32-unknown-unknown --locked` passes
- [ ] If WASM or browser behavior changes: `npm --prefix crates/prompt_smith_web ci --ignore-scripts`, `npm --prefix crates/prompt_smith_web run build:wasm`, and `npm --prefix crates/prompt_smith_web run test:wasm-smoke` pass
- [ ] If documentation changes: `ruby scripts/test_check_docs.rb` and `ruby scripts/check_docs.rb` pass

## Related Issues

<!-- Reference related issues -->

Closes #
