# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.0-alpha.5] - 2026-08-29

### Fixed

- Honor the shared CI browser executable path for Playwright smoke tests.

## [0.1.0-alpha.1] - 2026-08-15

### Added

- Strict simple double-brace and LangChain f-string subset inspection.
- Stable missing, unused, malformed-field, brace, and resource-limit diagnostics,
  including `value_too_large` and `rendered_output_too_large`.
- Single-pass non-recursive rendering that does not echo values in diagnostics.
- Inclusive UTF-8 resource limits: 256 KiB templates and individual values, 200
  unique template variables, a 1 MiB/200-entry WASM values boundary, and 1 MiB
  rendered output.
- Rust/WASM browser application with English and Chinese interfaces.
- Four-viewport Playwright coverage for real WASM behavior, privacy, keyboard
  focus, reduced motion, and horizontal overflow.
- Release automation for deterministic web/source archives, SHA-256 checksums,
  SPDX SBOM, license inventory, provenance, and SBOM attestations.

### Removed

- Unimplemented token and model-cost estimation claims.
- Unimplemented Agent Skill and MCP tool declarations.
