# prompt_smith

[![CI](https://github.com/Tinkora/prompt_smith/actions/workflows/test.yml/badge.svg)](https://github.com/Tinkora/prompt_smith/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![Rust 1.95+](https://img.shields.io/badge/rust-1.95%2B-orange.svg)](https://www.rust-lang.org)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

A browser-native LLM prompt template editor. Create prompt templates with `{{variable}}` placeholders, fill variables via form, preview the rendered prompt, estimate token count and cost for various models. All processing runs in-browser via WebAssembly.

## ✨ Features

- 📝 **Template Editor** — Write prompt templates with `{{variable}}` placeholders with real-time syntax highlighting
- 🔍 **Auto-Detection** — Variables are detected as you type and automatically surfaced in the variables panel
- 🧩 **Variable Form** — Fill detected variables via input fields, textareas, or multi-line editors
- 👁️ **Live Preview** — Rendered prompt updates in real-time as you type or change variable values
- 📊 **Token Estimation** — Character-based BPE approximation estimating token counts for popular models
- 💰 **Cost Calculation** — Estimate cost for GPT-4o, GPT-4o-mini, Claude 3.5 Sonnet, and more
- 🎨 **Modern Dark UI** — Chinese-labeled interface with responsive split-panel layout
- 🔒 **Privacy First** — All processing happens in-browser; no prompts leave your machine
- 📋 **Copy & Download** — One-click copy rendered prompt or download as text/markdown

## 🚀 Quick Start

```bash
# Clone
git clone https://github.com/Tinkora/prompt_smith.git
cd prompt_smith

# Build Web WASM
wasm-pack build --target web crates/prompt_smith_web

# Launch
cp crates/prompt_smith_web/pkg/* crates/prompt_smith_web/static/pkg/
cd crates/prompt_smith_web/static && python3 -m http.server 8080
```

Open `http://localhost:8080` in your browser.

## 📂 Project Structure

| Component | Description | Status |
|-----------|-------------|--------|
| `prompt_smith_core` | Template parsing, token counting, cost estimation | ✅ |
| `prompt_smith_web` | WASM bridge + HTML editor UI | ✅ |
| `skills/` | Agent Skill definition (MCP tools) | ✅ |

## 🔧 Development

```bash
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo check -p prompt_smith_web --target wasm32-unknown-unknown
```

## 📄 Docs

- [Product Spec (zh-CN)](docs/product_spec.zh-CN.md)

## 🤝 Community

- [Contributing](./CONTRIBUTING.md)
- [Code of Conduct](./CODE_OF_CONDUCT.md)
- [Security](./SECURITY.md)
- [Changelog](./CHANGELOG.md)

## Support

If prompt_smith saves you time, support Tinkora on [Ko-fi](https://ko-fi.com/tinkora).
Support is optional and never affects access or issue priority.

See [SUPPORT.md](./SUPPORT.md) for questions, bug reports, and security reports.

## 📜 License

MIT © [Tinkora](https://github.com/Tinkora)
