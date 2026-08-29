# Prompt Smith

[简体中文](README.zh-CN.md)

[![CI](https://github.com/Tinkora/prompt_smith/actions/workflows/quality.yml/badge.svg)](https://github.com/Tinkora/prompt_smith/actions/workflows/quality.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Rust 1.85+](https://img.shields.io/badge/rust-1.85%2B-orange.svg)](https://www.rust-lang.org)

> Status: `v0.1.0-alpha.3` release candidate. The implementation and release
> metadata target the Alpha dated 2026-08-15; publication is complete only
> after CI, Pages, release assets, checksums, SBOM, and attestations are
> verified.

Prompt Smith is a local prompt-template preflight checker. It catches missing
values, unused values, malformed placeholders, and ambiguous literal braces
before a prompt reaches an Agent framework.

The need is observable in real framework failures, including
[LangChain #32702](https://github.com/langchain-ai/langchain/issues/32702) and
[Langfuse #14721](https://github.com/langfuse/langfuse/issues/14721). Prompt
Smith stays deliberately smaller than Promptfoo, Langfuse, or a template
registry: it performs one strict check and render pass without an account,
model call, or server.

## Supported Syntax

| Dialect | Variable | Literal braces | Boundary |
|---|---|---|---|
| Simple double brace | `{{name}}` | Single braces are literal | Variable-only Tinkora syntax |
| LangChain f-string subset | `{name}` | `{{` and `}}` | No positional, attribute, index, conversion, format, or nested fields |

Variable names match `[A-Za-z_][A-Za-z0-9_]*`. Rendering is strict and
non-recursive: every referenced variable needs a supplied value, and inserted
values are never parsed again as template syntax.

## Browser Workflow

The application runs the Rust core through WebAssembly and provides:

- dialect selection;
- unique variable fields in first-seen order;
- stable diagnostics with severity and byte offset;
- strict local render preview;
- English and Chinese interfaces;
- copy and text download commands.

Open the deployed application at
[tinkora.github.io/prompt_smith](https://tinkora.github.io/prompt_smith/) after
the Pages workflow is published.

## Privacy and Resource Boundaries

- Templates and values remain in browser memory.
- The application makes no runtime request after same-origin assets load.
- It does not call an LLM, execute template code, read environment variables,
  persist input, or provide cloud synchronization.
- Diagnostics never contain variable values.

Limits are inclusive and measured as UTF-8 bytes. Resource failures prevent a
rendered preview.

| Boundary | Limit | Failure contract |
|---|---:|---|
| Template | 256 KiB | `template_too_large` error |
| Unique template variables | 200 | `too_many_variables` error |
| Each supplied value | 256 KiB | `value_too_large` error naming only the variable |
| Values JSON passed to WASM | 1 MiB and 200 object entries | Bridge error before a report is produced |
| Rendered output | 1 MiB | `rendered_output_too_large` error and no output |

Prompt Smith does not estimate tokens or model cost, evaluate prompt quality,
provide a registry, or expose MCP tools.

## Local Development

Requirements: Rust 1.85 or newer, the `wasm32-unknown-unknown` target,
`wasm-pack 0.15`, and Node.js 24.

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

To inspect the built page manually:

```bash
cd crates/prompt_smith_web/static
python3 -m http.server 8080 --bind 127.0.0.1
```

Then open `http://127.0.0.1:8080`.

## Documentation

- [Product specification](docs/PRODUCT_SPEC.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Support](SUPPORT.md)
- [Changelog](CHANGELOG.md)

## Support Tinkora

If Prompt Smith saves you time, you can support continued maintenance on
[Ko-fi](https://ko-fi.com/tinkora). Support is optional and never affects
access or issue priority.

## License

MIT
