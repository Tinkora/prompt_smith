# Prompt Smith Product Specification

[English](PRODUCT_SPEC.md) | [简体中文](PRODUCT_SPEC.zh-CN.md)

## Objective

Prompt Smith is a browser-native preflight checker and renderer for prompt
template variable contracts. It helps agent developers catch missing values,
unused values, malformed placeholders, and literal JSON or code braces before a
runtime framework turns them into unexpected variables.

The problem is concrete and recurring:

- LangChain issue [#32702](https://github.com/langchain-ai/langchain/issues/32702)
  documents JSON, code placeholders, and empty braces breaking prompt execution.
- Langfuse issue [#14721](https://github.com/langfuse/langfuse/issues/14721)
  documents empty and whitespace-only braces surviving an escaping heuristic and
  breaking LangChain templates.
- ScrapeGraphAI issues [#926](https://github.com/ScrapeGraphAI/Scrapegraph-ai/issues/926)
  and [#931](https://github.com/ScrapeGraphAI/Scrapegraph-ai/issues/931) show the
  same missing-variable failure reaching users through example workflows.
- LangChain issue [#30049](https://github.com/langchain-ai/langchain/issues/30049)
  shows partially supplied variables becoming missing after template composition.

LangChain's current `f-string` implementation uses Python's keyword-only
`StrictFormatter` and validates template variables before formatting. Prompt
Smith follows the documented brace and keyword-variable behavior only for the
explicit subset below; it does not claim full LangChain compatibility.

## Alternatives and position

- Promptfoo provides full prompt evaluation, providers, Nunjucks templates, test
  matrices, and CI. Prompt Smith does not duplicate that platform.
- LangChain validates templates inside Python applications. Prompt Smith provides
  a no-install browser preflight before framework execution.
- General Mustache and Jinja editors support richer languages. Prompt Smith does
  not execute either language or accept untrusted template code.

The independent value is a small, local contract checker with stable diagnostics
and repair-oriented output for common Agent prompt failures.

## Supported dialects

### Simple double brace

- Placeholders use `{{variable_name}}`.
- Surrounding ASCII whitespace inside a placeholder is ignored.
- Names must match `[A-Za-z_][A-Za-z0-9_]*`.
- Single braces are literal text.
- This is a variable-only Tinkora syntax, not full Mustache or Nunjucks.

### LangChain f-string subset

- Placeholders use `{variable_name}`.
- `{{` and `}}` render as literal braces.
- Names must match `[A-Za-z_][A-Za-z0-9_]*`.
- Empty fields, positional fields, attribute/index access, conversions, format
  specifiers, and nested replacement fields are rejected in this release.
- A field containing quotes, whitespace, JSON punctuation, or other non-name
  content receives a literal-brace diagnostic with an escape suggestion.

## Core workflow

1. Select a dialect and enter a template.
2. Prompt Smith parses the template and lists unique variables in first-seen order.
3. Enter values in the generated fields.
4. The report identifies missing values, unused values, invalid fields, and brace
   errors without echoing values in diagnostics.
5. When no error remains, preview, copy, or download the rendered prompt.

## Stable diagnostic boundary

- `empty_template`
- `template_too_large`
- `too_many_variables`
- `unmatched_opening_brace`
- `unmatched_closing_brace`
- `empty_variable_name`
- `invalid_variable_name`
- `unsupported_format_feature`
- `likely_literal_braces`
- `missing_variable_value`
- `unused_variable_value`
- `value_too_large`
- `rendered_output_too_large`

Diagnostics include a severity, byte offset, optional variable name, and generic
message. Variable values must never appear in diagnostics or telemetry.

## Privacy and resource limits

- Processing is local in browser memory through Rust/WASM.
- The application makes no runtime network requests after same-origin assets load.
- It does not call an LLM, execute template code, expand environment variables,
  persist values, or provide cloud synchronization.
- Rendering is a single non-recursive substitution pass. Inserted values are not
  parsed as new template syntax.

All byte limits are inclusive and use UTF-8 byte length.

| Boundary | Limit | Failure semantics |
|---|---:|---|
| Template | 256 KiB | Return `template_too_large` as an error with no variables or rendered output |
| Unique variables discovered in the template | 200 | Return `too_many_variables` as an error, expose only the first 200 variables, and do not render |
| Each supplied value, including unused values | 256 KiB | Return `value_too_large` as an error with the variable name, never the value, and do not render |
| Values JSON at the WASM boundary | 1 MiB and 200 object entries | Reject before producing a core report; values must be a JSON object of strings |
| Rendered output | 1 MiB | Return `rendered_output_too_large` as an error and omit the rendered output |

The rendered-output limit is evaluated only when parsing and value validation
have produced no error. Warnings, including `unused_variable_value`, do not
prevent rendering.

## Explicit non-goals

- Token counting or model cost estimates.
- Prompt evaluation, model comparison, red teaming, or API execution.
- Full Python formatting, Mustache, Nunjucks, Jinja, Handlebars, or Liquid.
- Template nesting, loops, conditions, filters, functions, or arbitrary code.
- MCP or another Agent transport without an executable implementation and
  end-to-end integration test.

## Technology and commands

- Rust 1.85, edition 2024, committed `Cargo.lock`.
- Rust core shared with a `wasm-bindgen` browser bridge.
- Static HTML/CSS/JavaScript application; no runtime framework or CDN dependency.

```bash
cargo fmt --all -- --check
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo check -p prompt_smith_web --target wasm32-unknown-unknown --locked
npm --prefix crates/prompt_smith_web ci --ignore-scripts
npm --prefix crates/prompt_smith_web run build:wasm
npm --prefix crates/prompt_smith_web run test:wasm-smoke
ruby scripts/test_check_docs.rb
ruby scripts/check_docs.rb
```

## Project structure

```text
crates/prompt_smith_core/  parser, diagnostics, rendering, native tests
crates/prompt_smith_web/   WASM bridge and browser application
docs/                      bilingual product specification
scripts/                   documentation, browser, and release contract checks
.github/workflows/         CI, Pages, CodeQL, and Release workflows
```

## Testing strategy

- Native outcome tests cover both dialects, Unicode byte offsets, malformed
  braces, duplicate variables, limits, missing/unused values, and one-pass render.
- WASM tests verify stable JSON reports, bridge input limits, dialect validation,
  and value redaction.
- Browser tests cover typing, dialect switching, generated fields, diagnostics,
  copy/download commands, keyboard access, console output, accessibility, and
  horizontal overflow at 375, 768, 1024, and 1440 pixels.
- CI checks Rust 1.85, formatting, Clippy, dependency policy, audits, pinned
  Actions, documentation links, and the release contract.

## Success criteria

- The public page performs the full edit-check-render workflow without a server.
- Published claims match the supported subset and never imply full framework
  compatibility.
- English is the default README and UI; complete Chinese README/spec links exist.
- Package metadata and release notes remain aligned to `v0.1.0-alpha.1`; CI,
  Pages, checksums, SBOM, provenance, and SBOM attestations are verified from the
  release assets before the Alpha is recorded as published.
