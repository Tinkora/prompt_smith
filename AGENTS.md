# Repository Guide for AI Agents

## Project Overview

prompt_smith is a browser-native LLM prompt template editor. It provides template parsing with `{{variable}}` placeholder detection, variable form filling, real-time preview, token counting, and cost estimation — all running in-browser via WebAssembly (Rust compiled to WASM).

## Architecture

```
prompt_smith/
├── crates/
│   ├── prompt_smith_core/       # Template parsing, token estimation, cost calculation
│   └── prompt_smith_web/        # WASM bridge + HTML editor UI
├── docs/                         # Product specification (zh-CN)
├── skills/                       # Agent Skill definitions (MCP tools)
└── index.html                    # Product landing page
```

## Key Files for AI Context

| File | Purpose |
|------|---------|
| `crates/prompt_smith_core/src/template.rs` | `PromptTemplate` struct, `parse_template`, `render_template`, `validate_template` |
| `crates/prompt_smith_core/src/tokens.rs` | `Model` enum, `TokenEstimate`, `estimate_tokens`, `estimate_cost`, `CostSummary` |
| `crates/prompt_smith_core/src/error.rs` | `CoreError` enum with stable machine codes |
| `crates/prompt_smith_core/src/wasm.rs` | WASM export functions (`wasm_parse_template`, `wasm_render_template`, etc.) |
| `crates/prompt_smith_web/src/lib.rs` | WASM bridge connecting core to JS |
| `crates/prompt_smith_web/static/index.html` | Full-featured HTML editor UI |
| `skills/prompt_smith.md` | Agent usage workflow |
| `skills/mcp-tools.json` | MCP tool definitions |

## Build & Test Commands

```bash
# Run all tests
cargo test --workspace

# Format check
cargo fmt --all -- --check

# Lint (strict)
cargo clippy --workspace --all-targets -- -D warnings

# WASM compilation check
cargo check -p prompt_smith_web --target wasm32-unknown-unknown

# Build Web WASM for deployment
wasm-pack build --target web crates/prompt_smith_web
```

## Design Principles

1. **Browser-first**: All template processing, token counting, and cost estimation happens in-browser via WASM
2. **No server**: No prompts, templates, or variable values ever leave the user's browser
3. **Real-time**: Template parsing, variable detection, and preview rendering update on every keystroke
4. **Character-based heuristics**: No external tokenizer library needed — uses ~4 chars/token for GPT, ~3.5 for Claude
5. **Model-agnostic**: Supports preset models (GPT-4o, Claude 3.5 Sonnet, etc.) and custom model definitions

## Template Syntax

- `{{variable_name}}` — Standard placeholder; variable names matched by regex `\{\{([^}]+)\}\}`
- Variable names: alphanumeric + underscores, case-sensitive
- Unmatched `{{` or `}}` triggers validation warnings
- Empty variable names `{{}}` are treated as errors

## Token Estimation Heuristics

| Model Family | Chars per Token | Notes |
|-------------|-----------------|-------|
| GPT-4 / GPT-4o / GPT-3.5 | 4.0 | OpenAI's documented average |
| Claude 3 / 3.5 | 3.5 | Anthropic's slightly denser encoding |
| Custom | user-defined | Set via `tokens_per_char` |

## Cost Models (per 1K tokens, USD)

| Model | Input | Output |
|-------|-------|--------|
| GPT-4o | $2.50 | $10.00 |
| GPT-4o-mini | $0.15 | $0.60 |
| GPT-4 | $30.00 | $60.00 |
| GPT-3.5 Turbo | $0.50 | $1.50 |
| Claude 3.5 Sonnet | $3.00 | $15.00 |
| Claude 3 Opus | $15.00 | $75.00 |
| Claude 3 Haiku | $0.25 | $1.25 |

## Error Codes (Stable Machine-Readable)

| Code | Meaning |
|------|---------|
| `UNMATCHED_OPENING_BRACE` | `{{` without matching `}}` |
| `UNMATCHED_CLOSING_BRACE` | `}}` without matching `{{` |
| `EMPTY_VARIABLE_NAME` | `{{}}` with nothing between braces |
| `MISSING_VARIABLE_VALUE` | Variable found in template but not provided for rendering |
| `INVALID_MODEL_IDENTIFIER` | Unknown model string passed to WASM |
| `EMPTY_TEMPLATE` | Template string is empty or whitespace-only |

## Frontend Design Requirement

- Before creating, modifying, reviewing, or debugging any HTML page or user-facing frontend, invoke the `ui-ux-pro-max` skill.
- Run the skill's required `--design-system` search before editing, followed by relevant stack and UX searches.
- If `ui-ux-pro-max` is unavailable, stop frontend work and report the missing prerequisite.
- Verify the rendered result in a real browser at 375, 768, 1024, and 1440 pixel widths, including console, keyboard, accessibility, and overflow checks.
