# Feature Request: Enriched MIB Context in reverse lookup (SnmpKit)

## Summary
Add an enriched reverse lookup (or object info) API in SnmpKit that returns MIB metadata for an OID (or base column name), including SYNTAX and TEXTUAL-CONVENTION. This enables deterministic formatting of OCTET STRING values (e.g., DisplayString vs PhysAddress vs InetAddress) and avoids error-prone heuristics based on length or content.

## Motivation
Today, consumers often “guess” how to format OCTET STRING values (e.g., treat 6 bytes as a MAC address), which breaks for values like `ifDescr` (DisplayString) that happen to be six characters (e.g., "ether5"). Intrinsic MIB metadata clearly indicates the intended interpretation:

- IF-MIB::ifDescr → DisplayString (octet string → text)
- IF-MIB::ifPhysAddress → PhysAddress (octet string → MAC)
- IP-MIB::ipAdEntAddr (or INET-ADDRESS-MIB types) → IpAddress/InetAddress (octet string → IP)

Exposing this metadata in reverse lookup allows SnmpKit consumers to format values correctly and consistently.

## Proposed API
Non-breaking: keep existing `reverse_lookup/1` behavior. Add one or more of the following:

1) New function (preferred)

```elixir path=null start=null
@spec object_info(name_or_oid :: String.t() | [integer]) ::
  {:ok, map()} | {:error, term()}
```

Returns a map (or struct) with enriched MIB metadata for the base object. If `name_or_oid` includes an instance index, return both base and instance information.

2) Enriched reverse lookup variant

```elixir path=null start=null
@spec reverse_lookup_enriched(name_or_oid :: String.t() | [integer]) ::
  {:ok, map()} | {:error, term()}
```

3) Batch variants (for performance)

```elixir path=null start=null
@spec object_info_many([String.t() | [integer]]) :: {:ok, [map()]} | {:error, term()}
@spec reverse_lookup_many_enriched([String.t() | [integer]]) :: {:ok, [map()]} | {:error, term()}
```

### Returned shape (map)

Minimal recommended fields:

```elixir path=null start=null
%{
  name: "ifDescr",                # base column name without instance suffix
  module: "IF-MIB",               # MIB module
  oid: [1,3,6,1,2,1,2,2,1,2],      # base column OID (no instance)
  # Optionals when input includes instance
  instance_index: 6,               # numeric index when applicable
  instance_oid: [1,3,6,1,2,1,2,2,1,2,6],
  # Syntax information
  syntax: %{
    base: :octet_string | :integer | :timeticks | :counter32 | :counter64 | :gauge32 | ...,
    textual_convention: "DisplayString" | "PhysAddress" | "InetAddress" | nil,
    display_hint: String.t() | nil
  },
  # Optional extras (nice to have)
  access: :read_only | :read_write | :not_accessible | :read_create | :accessible_for_notify | nil,
  status: :current | :deprecated | :obsolete | nil,
  description: String.t() | nil
}
```

## Examples

### ifDescr instance
Input: `"1.3.6.1.2.1.2.2.1.2.6"` → IF-MIB::ifDescr.6

```elixir path=null start=null
{:ok, info} = SnmpKit.MIB.object_info("1.3.6.1.2.1.2.2.1.2.6")
info == %{
  name: "ifDescr",
  module: "IF-MIB",
  oid: [1,3,6,1,2,1,2,2,1,2],
  instance_index: 6,
  instance_oid: [1,3,6,1,2,1,2,2,1,2,6],
  syntax: %{base: :octet_string, textual_convention: "DisplayString", display_hint: "255a"}
}
```

Consumer can render `tval` as readable text for DisplayString and avoid misinterpreting it as a MAC address.

### ifPhysAddress instance
Input: `"1.3.6.1.2.1.2.2.1.6.10"` → IF-MIB::ifPhysAddress.10

```elixir path=null start=null
{:ok, info} = SnmpKit.MIB.object_info([1,3,6,1,2,1,2,2,1,6,10])
info.syntax.textual_convention == "PhysAddress"
# Consumer formats octet string as a MAC address (aa:bb:cc:dd:ee:ff)
```

### ifHighSpeed instance
Input: `"1.3.6.1.2.1.31.1.1.1.15.14"` → IF-MIB::ifHighSpeed.14

```elixir path=null start=null
{:ok, info} = SnmpKit.MIB.object_info("1.3.6.1.2.1.31.1.1.1.15.14")
info.syntax.base == :gauge32
# Consumer uses numeric val directly
```

## Consumer guidelines (how this helps)
- For OCTET STRINGs, choose formatter by `textual_convention`:
  - DisplayString → return text
  - PhysAddress/MacAddress → format as MAC
  - IpAddress/InetAddress → format IP (v4/v6)
  - Unknown → if printable → text; else → hex:...
- For TimeTicks → pretty uptime
- For numerics → use `val` (with correct type)
- For tables → use `instance_index` to label (e.g., `{"ifIndex" => idx}`)

## Performance considerations
- Provide batch variants for reverse lookups on collections
- Cache object metadata internally (ETS) keyed by base OID/name
- Ensure base-column vs instance handling avoids redundant lookups

## Backward compatibility
- Keep `reverse_lookup/1` unchanged (string name or basic form)
- Introduce new functions (or opt-in enriched mode) to avoid breaking existing consumers
- Recommend migration: use enriched API when formatting OCTET STRINGs, fall back to legacy if metadata unavailable

## Implementation approach (suggestion)
- Extend the MIB compiler/loader to store:
  - Object name → {module, base_oid, syntax_base, textual_convention, display_hint, access, status, description}
- Implement fast lookup by base OID/name
- When input includes instances, parse the last component as index and return both base and instance data

## Acceptance criteria
- Given IF-MIB::ifDescr.6, API returns textual_convention = "DisplayString"
- Given IF-MIB::ifPhysAddress.10, API returns textual_convention = "PhysAddress"
- Given IF-MIB::ifHighSpeed.14, API returns syntax.base = :gauge32
- Batch variants return results consistent with single-call API
- Performance: metadata lookup should be O(1) after first load per base object

## Optional extras
- Add `children/1`, `parent/1` enriched variants that also include syntax metadata
- Add `object_type/1` (scalar vs column) and “table context” (which table/entry this column belongs to)

## Why this matters for downstream users
- Eliminates guesswork when rendering OCTET STRINGs
- Ensures consistent formatting across devices/vendors
- Avoids false MAC/IP interpretations of human-readable strings (e.g., `ifDescr = "ether5"`)

## Minimal stopgap (if full metadata requires more time)
- Provide a small, curated mapping for high-value objects (IF-MIB ifDescr, ifName, ifAlias → DisplayString; ifPhysAddress → PhysAddress) while the full enriched API is implemented.

