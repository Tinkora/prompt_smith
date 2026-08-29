# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| Unreleased `main` | Yes |

Support will move to the latest published Alpha after the first release.

## Report a Vulnerability

Do not open a public issue for a vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/Tinkora/prompt_smith/security/advisories/new)
to share reproduction steps, affected inputs, impact, and any proposed fix.

The initial response target is five business days. Tinkora will coordinate
validation, remediation, and disclosure through the private advisory.

## Security Boundary

In scope:

- user-controlled template or value content reaching HTML execution;
- parser resource exhaustion within documented input limits;
- diagnostics exposing supplied variable values;
- unexpected persistence or outbound runtime requests;
- release artifact or workflow integrity problems.

Prompt Smith treats templates and values as untrusted text. The browser presents
them through form values and DOM text, never user-derived HTML. The Rust core
performs one non-recursive substitution pass and does not execute template code,
read files, expand environment variables, or call a model.

The static application loads its JavaScript and WebAssembly from the same origin.
Repository and funding links can navigate away only after an explicit user
action.
