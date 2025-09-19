# SNMPKIT Output Cleanup Plan

Purpose
- Eliminate output inconsistencies in 1.x with additive fixes.
- Provide a clear path for future breaking changes (2.0) if needed.

Final Decisions (1.x)
- OID fields:
  - Keep `oid` as a string (backward-compatible).
  - Add `oid_list: [integer]` and document it as the canonical programmatic field.
- formatted field:
  - Always a UTF-8 `String.t` when `include_formatted: true`.
  - For `:octet_string`:
    - If printable UTF-8: use the decoded string.
    - Else: use spaced hex pairs prefixed with `hex:` (e.g., `hex:41 42 00 FF`).
- Default SNMP version: `:v2c` for single-target and multi-target APIs (overridable per call).
- Auto-start behavior:
  - Add `:snmpkit, auto_start_services: true` (default).
  - When `false`, services do not auto-start—require explicit `ensure_started/0`.

Varbind Contract (1.x)
- `%{ name: String.t | nil, oid: String.t, oid_list: [integer], type: atom, value: term, formatted: String.t | nil }`
- `include_names` controls `name`; `include_formatted` controls `formatted`.

Phases and Acceptance Criteria
1) Enrichment and Formatting
- Add `oid_list` to all varbind maps.
- Guarantee `formatted` is `String.t` for all types; non-printable octet strings -> `hex:..` with spaced pairs.
- Tests: assert `formatted` is `String.t`; `oid_list` matches `oid`.

2) Defaults
- Set default version to `:v2c` for single & multi APIs.
- Tests: calling `get`/`walk` without version uses `:v2c`.

3) Auto-start Toggle
- Implement `auto_start_services` config and `ensure_started/0`.
- Tests: with toggle `false`, nothing starts automatically; with `true`, current behavior.

4) Multi and Single Path Consistency
- Centralize enrichment in one helper; apply to single & multi flows identically.
- Tests: inner varbind maps identical across single vs multi.

5) Warnings
- Resolve compile warnings (yaml, telemetry).
- Tests: `mix compile` clean.

Migration Notes
- Prefer `oid_list` for pattern matching and comparisons.
- `formatted` is always a `String.t`; if you previously assumed binaries for octet strings, update expectations.
- To disable auto-start in systems requiring explicit lifecycle control:
  - In `config/runtime.exs`:
    ```elixir
    config :snmpkit, auto_start_services: false
    ```
  - Then ensure services explicitly (e.g., during app init).

Examples
- Before:
  - `%{oid: "1.3.6.1.2.1.1.5.0", type: :octet_string, value: <<...>>}`
- After:
  - `%{oid: "1.3.6.1.2.1.1.5.0", oid_list: [1,3,6,1,2,1,1,5,0], type: :octet_string, value: "host", formatted: "host"}`

Release
- Version: 1.1.0 (additive changes + default updates).
- CHANGELOG: document `oid_list`, `formatted` string guarantee, default `:v2c`, auto-start toggle.
