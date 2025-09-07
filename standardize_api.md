# API Standardization Plan (target: 1.0)

This document proposes a standardized, uniform result shape and option set across all SNMP request types in SnmpKit. The goal is to make outputs more informative by default, reduce special cases, and keep performance tunable with simple flags.

## Objectives

- Always include SNMP type in results
- Include both MIB names and numeric OIDs by default (configurable)
- Include formatted (human-readable) values by default while preserving raw
- Apply the same enriched shape across single-target and multi-target APIs
- Provide opt-outs for performance-sensitive paths
- Clearly document breaking changes and migration steps

## Result shape

Each varbind is represented as a map. Defaults shown (include_names: true, include_formatted: true):

- Raw helpers (get_with_type, walk, bulk_walk, etc.):
  %{
    name: "sysUpTime.0",           # nil if reverse lookup fails or include_names: false
    oid: "1.3.6.1.2.1.1.3.0",      # always present
    type: :timeticks,               # always present
    value: 12345678                 # always present (raw value)
  }

- Pretty helpers (get_pretty, walk_pretty, bulk_pretty, etc.) include an extra formatted field:
  %{
    name: "sysUpTime.0",
    oid: "1.3.6.1.2.1.1.3.0",
    type: :timeticks,
    value: 12345678,                # raw
    formatted: "1 day, 10 hours, 17 minutes, 36 seconds"  # formatted per type
  }

Rules:
- If include_names: false, omit name
- If include_formatted: false, omit formatted
- type is always present

## Options (per-call and global)

- include_names (default: true)
  - true: attach MIB name (reverse lookup) alongside numeric OID
  - false: omit name (numeric OID only)

- include_formatted (default: true)
  - true: add formatted field computed from value and type
  - false: omit formatted

Both options should be available:
- Per-call via opts
- Globally via application config (with per-call override)

## Affected APIs (single-target)

- get/3
  - Before: {:ok, value}
  - After: {:ok, %{oid, [name], type, value, [formatted]}}
  - Breaking: yes (shape change)

- get_with_type/3 (no longer needed, please remove)
  - Before: {:ok, {oid_string, type, value}}
  - After: {:ok, %{oid, [name], type, value, [formatted]}}
  - Breaking: yes (shape change)

- get_next/3
  - Before: {:ok, {oid_string, value}}
  - After: {:ok, %{oid, [name], type, value, [formatted]}}
  - Breaking: yes (shape change and type now included)

- get_next_with_type/3 (no longer needed, please remove)
  - Before: {:ok, {oid_string, type, value}}
  - After: {:ok, %{oid, [name], type, value, [formatted]}}
  - Breaking: yes

- get_bulk/3
  - Before: {:ok, [{oid_list, type, value}, ...]}
  - After: {:ok, [%{oid, [name], type, value, [formatted]}, ...]}
  - Breaking: yes

- walk/3, walk_table/3, bulk_walk/3
  - Before: {:ok, [{oid_string, type, value}, ...]}
  - After: {:ok, [%{oid, [name], type, value, [formatted]}, ...]}
  - Breaking: yes

- pretty helpers (get_pretty/3, walk_pretty/3, bulk_pretty/3)
  - Before: formatted-only outputs (no type)
  - After: same enriched map shape, with formatted present and type preserved
  - Breaking: yes (shape change)

## Affected APIs (multi-target)

Outer return structures remain the same (:list, :with_targets, :map), but inner results switch to the enriched map(s):

- get_multi/2
  - Before (default :list): [ {:ok, value} | {:error, reason}, ... ]
  - After: [ {:ok, %{...}} | {:error, reason}, ... ]

- get_bulk_multi/2, walk_multi/2, walk_table_multi/2
  - Before: [ {:ok, [{oid, type, value}, ...]} | {:error, _}, ... ] (or other return_format variants)
  - After: [ {:ok, [%{oid, [name], type, value, [formatted]}, ...]} | {:error, _}, ...]

- return_format: :with_targets
  - Each item remains {target, oid_or_root, result}, with result enriched as above

- return_format: :map
  - Keys remain {target, oid_or_root}, values enriched as above

## Backward compatibility and versioning

- This is a breaking set of changes; bump major version (proposed: 1.0)
- Provide clear migration guidance (see below)
- Provide application config defaults, with per-call overrides, to control include_names and include_formatted

## Migration guide

Common patterns and their replacements (Elixir):

- GET (single, defaults to v2c)
  - Before:
    {:ok, value} = SnmpKit.SNMP.get(target, "sysDescr.0")
  - After (default):
    {:ok, %{name: name, oid: oid, type: type, value: value, formatted: formatted}} =
      SnmpKit.SNMP.get(target, "sysDescr.0")
  - After (performance):
    {:ok, %{oid: oid, type: type, value: value}} =
      SnmpKit.SNMP.get(target, "sysDescr.0", include_names: false, include_formatted: false)

- WALK (defaults to v2c)
  - Before:
    {:ok, results} = SnmpKit.SNMP.walk(target, "system")
    # results: [{oid, type, value}, ...]
  - After:
    {:ok, results} = SnmpKit.SNMP.walk(target, "system")
    # results: [%{oid, name, type, value, formatted}, ...]

- Pretty helpers now keep type and raw value:
  - Before:
    {:ok, "1 day, 10 hours"} = SnmpKit.SNMP.get_pretty(target, "sysUpTime.0")
  - After:
    {:ok, %{oid: _, type: :timeticks, value: _, formatted: "1 day, 10 hours"}} =
      SnmpKit.SNMP.get_pretty(target, "sysUpTime.0")

- Multi-target (with_targets)
  - Before:
    [{host, oid, {:ok, value_or_list}} | ...]
  - After:
    [{host, oid, {:ok, %{...}}} | ...] or lists of maps for bulk/walk

## Performance considerations

- include_formatted: false avoids all formatting work and returns only raw values (fastest)
- include_names: false avoids reverse lookup per varbind
- Both flags are per-call and can be set globally via config

## Implementation plan

1. Option plumbing
   - Merge include_names: true and include_formatted: true in config/opts
   - Ensure options flow through single-target and multi-target paths

2. Enrichment helper (single source of truth)
   - Input: {oid_string, type, value}
   - Output: %{oid, [name], type, value, [formatted]}
   - Gracefully set name: nil on reverse-lookup failures

3. Single-target wiring
   - get, get_with_type, get_next, get_next_with_type
   - get_bulk, walk, walk_table, bulk_walk
   - pretty variants produce the same map, adding formatted

4. Multi-target wiring
   - get_multi, get_bulk_multi, walk_multi, walk_table_multi
   - Apply enrichment per-result while preserving outer return_format

5. Tests
   - Assert type is always present and correct across all paths
   - Validate include_names/include_formatted toggles
   - Multi-target formats: :list, :with_targets, :map

6. Documentation
   - Update README and guides
   - Call out breaking changes and migration steps
   - Changelog for 1.0

## Open questions

- Global defaults: ship with include_names: true and include_formatted: true?
- Any additional type-specific formatting we should add (e.g., MAC, OID value formatting)
- Should pretty also include both numeric and symbolic OID value rendering when type == :object_identifier?

## Examples

- Minimal, formatted-rich default:
  {:ok, %{name: name, oid: oid, type: type, value: raw, formatted: fmt}} =
    SnmpKit.SNMP.get(target, "sysUpTime.0")

- High-performance walk:
  {:ok, rows} = SnmpKit.SNMP.walk(target, "ifTable", include_names: false, include_formatted: false)
  # rows: [%{oid: "1.3.6...", type: :integer, value: 1}, ...]

---

This standardization unifies the API, aligns with user expectations (type and names visible by default), and gives clear levers to optimize performance when needed.

