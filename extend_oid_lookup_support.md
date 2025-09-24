# Proposal: Extend OID Lookup Support in SnmpKit (Normalization + Enriched Info)

## Summary
Several numeric OIDs that belong to IF-MIB tables (ifTable and ifXTable) are occasionally resolved by reverse lookup to dotted names such as "ifName.11" when the base column is not `ifName`. This leads downstream consumers to mislabel metrics (e.g., labeling ifHCOutUcastPkts as ifName). This proposal requests two improvements:

1) Normalize reverse_lookup so the returned name is the base column symbol (no ".<instance>" suffix).
2) Provide an enriched object info API that returns base/instance separation and MIB syntax metadata for deterministic formatting.

This complements the companion feature request document we prepared: `snmpkit_feature_request_mib_context.md`.

## Problem
For numeric OIDs with instances under IF-MIB::ifXEntry and IF-MIB::ifEntry, reverse lookup sometimes returns a dotted name string that includes a numeric fragment that is actually the column id, which can be confused as part of the base symbol.

Examples observed in the field:

- 1.3.6.1.2.1.31.1.1.1.11.3  # IF-MIB::ifHCOutUcastPkts.3
- 1.3.6.1.2.1.31.1.1.1.10.4  # IF-MIB::ifHCOutOctets.4
- 1.3.6.1.2.1.31.1.1.1.9.14  # IF-MIB::ifHCInBroadcastPkts.14
- 1.3.6.1.2.1.31.1.1.1.8.7   # IF-MIB::ifHCInMulticastPkts.7
- 1.3.6.1.2.1.2.2.1.10.5     # IF-MIB::ifInOctets.5

Expected behavior:
- reverse lookup should return the base column symbol (e.g., "ifHCOutUcastPkts") and, optionally, the instance index separately (3).

Actual behavior (intermittent):
- reverse lookup returns a dotted name like "ifName.11", which—after normalization—becomes "ifName". This is incorrect for columns 8–13 and 10–22 of ifXTable/ifTable.

## Proposed changes

### 1. Normalize reverse_lookup result (short-term, non-breaking)
- When the input is a numeric OID that includes an instance index:
  - Identify the base OID by removing the last numeric component (the instance)
  - Resolve the base symbol from the base OID
  - Return that symbol as the name, without any trailing ".<n>"
- Optionally, parse and return the instance index separately in an enriched form, or at least guarantee the name is the base symbol.

This alone eliminates mislabeled metrics where a column under ifXEntry is incorrectly labeled as ifName.

### 2. Add an enriched object info API (longer-term)
- Provide `object_info/1` (or `reverse_lookup_enriched/1`) that returns:
  - name (base symbol), module (IF-MIB), base_oid
  - instance_index and instance_oid for instance inputs
  - syntax and textual conventions (e.g., DisplayString vs PhysAddress)
  - optional description/access/status/display-hint
- We provided a detailed shape in `snmpkit_feature_request_mib_context.md`.

## Acceptance criteria
- Given these inputs, the API returns the correct base symbol:
  - 1.3.6.1.2.1.31.1.1.1.11.3 → name: "ifHCOutUcastPkts", instance_index: 3
  - 1.3.6.1.2.1.31.1.1.1.10.4 → name: "ifHCOutOctets", instance_index: 4
  - 1.3.6.1.2.1.31.1.1.1.9.14 → name: "ifHCInBroadcastPkts", instance_index: 14
  - 1.3.6.1.2.1.31.1.1.1.8.7 → name: "ifHCInMulticastPkts", instance_index: 7
  - 1.3.6.1.2.1.2.2.1.10.5 → name: "ifInOctets", instance_index: 5
- reverse_lookup never returns a dotted name where the head symbol is unrelated to the base OID (e.g., no "ifName.11" for column 11 under ifXEntry).

## Test suggestions
- Unit tests covering ifTable (1.3.6.1.2.1.2.2.1.x) and ifXTable (1.3.6.1.2.1.31.1.1.1.x):

```elixir
# Pseudocode
for {oid, expected_name, idx} <- [
  {[1,3,6,1,2,1,31,1,1,1,11,3], "ifHCOutUcastPkts", 3},
  {[1,3,6,1,2,1,31,1,1,1,10,4], "ifHCOutOctets", 4},
  {[1,3,6,1,2,1,31,1,1,1,9,14], "ifHCInBroadcastPkts", 14},
  {[1,3,6,1,2,1,31,1,1,1,8,7], "ifHCInMulticastPkts", 7},
  {[1,3,6,1,2,1,2,2,1,10,5], "ifInOctets", 5}
] do
  {:ok, info} = MIB.object_info(oid)
  assert info.name == expected_name
  assert info.instance_index == idx
end
```

- Negative test: feeding a full OID should never return a base name that’s mismatched with the numeric column id.

## Rationale
- Normalization fixes surprising dotted-name artifacts and aligns names with their base OIDs.
- Enriched metadata enables correct formatting (e.g., distinguishing DisplayString vs PhysAddress) and cleaner downstream logic.
- IF-MIB tables are foundational—getting them right benefits many users immediately.

## Migration / Backward compatibility
- Keep `reverse_lookup/1` behavior stable except for removing trailing ".<instance>" from the returned name, which should be viewed as a bug fix.
- New enriched API is additive.

## References
- Companion feature request: `snmpkit_feature_request_mib_context.md` (enriched MIB context)
- IF-MIB tables:
  - ifTable: 1.3.6.1.2.1.2.2.1
  - ifXTable: 1.3.6.1.2.1.31.1.1.1
