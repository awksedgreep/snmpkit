# Feature Request: Built-in DOCSIS Modem Upgrade MIB Support (GET/SET) in snmpkit Simulator

## Title
Add built-in DOCSIS modem upgrade MIB support (GET/SET) to snmpkit simulator

## Problem statement
When simulating a cable modem with snmpkit, the standard DOCSIS software upgrade flow is not supported out of the box. This prevents realistic integration tests for workflows that:
- SET the TFTP server and filename
- Trigger the upgrade via admin status
- Poll operational status to watch the upgrade progress

## Motivation
- Enable realistic, self-contained upgrade scenarios without external simulators
- Allow CI tests to exercise firmware upgrade logic end-to-end with `SnmpKit.SnmpMgr.set/4` and reads
- Reduce boilerplate for users building DOCSIS management apps

## Scope
Target device type: `:cable_modem` in `SnmpKit.SnmpSim`
Add default OIDs and behavior for the DOCSIS software upgrade objects.

## Core OIDs to support (DOCS-IF-MIB / DOCS-CABLE-DEVICE-MIB)
Writable and readable values that participate in the upgrade flow:
- docsIfDocsDevSwAdminStatus — `1.3.6.1.2.1.69.1.3.1.0` (INTEGER; read-write)
- docsIfDocsDevSwOperStatus — `1.3.6.1.2.1.69.1.3.2.0` (INTEGER; read-only)
- docsIfDocsDevSwServer — `1.3.6.1.2.1.69.1.3.3.0` (OCTET STRING; read-write)
- docsIfDocsDevSwFilename — `1.3.6.1.2.1.69.1.3.4.0` (OCTET STRING; read-write)

Optional helpful OIDs:
- docsDevSwCurrentVers (vendor-specific or MIB-variant) to report current version post-upgrade

References: DOCSIS MIBs (DOCS-IF, DOCS-CABLE-DEVICE), see RFC 2669 and RFC 4706 for background (exact enum values can vary by MIB version/vendor; proposal is to follow canonical enums documented in those MIBs).

## Desired simulator behavior (GET/SET semantics)
### Default state (pre-upgrade)
- Server = ""
- Filename = ""
- AdminStatus = idle (or device-appropriate “no upgrade requested”)
- OperStatus = unknown or idle

### SET flow (happy path)
1. Write `docsIfDocsDevSwServer` to a host/IP string
2. Write `docsIfDocsDevSwFilename` to a firmware filename
3. Write `docsIfDocsDevSwAdminStatus` to trigger the upgrade (canonical enum value for “upgrade from management software”)
4. Simulator transitions OperStatus through realistic steps over configurable time:
   - checkingName → downloadFromServer → downloadComplete → applyComplete → ok
5. After completion, optionally update a “current version” OID to simulate a successful upgrade

### Error and edge cases
- Missing server or filename when admin status is set → `wrongValue`
- Bad types for server/filename → `wrongType`
- Setting read-only objects → `notWritable`
- If `upgrade_enabled=false` → `notWritable` on admin status
- Optional failure branch when `invalid_server_regex` matches → OperStatus transitions into failed

### SNMP error-status mapping
- `notWritable` (4), `wrongType` (7), `wrongValue` (10), plus other standard statuses where appropriate per SNMPv2c

## Configuration proposal
Allow passing options at device creation (profile or opts):
- `upgrade_enabled`: boolean (default true for `:cable_modem`)
- `upgrade_delay_ms`: total or per-phase timings, e.g. `%{name_check: 200, download: 800, apply: 500}`
- `invalid_server_regex`: optional regex to simulate failure on “bad server”
- `default_version`: initial version string for reporting
- `post_upgrade_version`: version string after a successful upgrade

## Backwards compatibility
- If `upgrade_enabled=false` (or device type ≠ `:cable_modem`), keep current read-only behavior (SETs return `readOnly`/`notWritable`)
- No behavior changes for other device types by default

## Testing and acceptance criteria
### Unit tests (state machine)
- Priming server/filename, triggering admin status, timed OperStatus progression
- Error branches: missing fields, wrong types, `notWritable` paths
- Failure branch when `invalid_server_regex` matches

### Integration tests
- Start a `:cable_modem` device; perform `SnmpMgr.set` on server/filename/admin status
- Poll OperStatus until `ok` or `failed`; assert timing and final state
- Verify other device types are unaffected by default

## Example Elixir usage
```elixir
alias SnmpKit.SnmpMgr

target = "127.0.0.1:1161"
community_ro = "public"
community_rw = "private"

# OIDs
server_oid   = [1,3,6,1,2,1,69,1,3,3,0]
file_oid     = [1,3,6,1,2,1,69,1,3,4,0]
admin_oid    = [1,3,6,1,2,1,69,1,3,1,0]
oper_oid     = [1,3,6,1,2,1,69,1,3,2,0]

# Prime server and filename
{:ok, _} = SnmpMgr.set(target, server_oid, "10.0.0.5", community: community_rw, version: :v2c)
{:ok, _} = SnmpMgr.set(target, file_oid, "cm-fw-1.2.3.bin", community: community_rw, version: :v2c)

# Trigger upgrade (use enum per MIB for “upgrade from mgt sw”)
{:ok, _} = SnmpMgr.set(target, admin_oid, 3, community: community_rw, version: :v2c)

# Poll oper status
status =
  Stream.repeatedly(fn ->
    Process.sleep(200)
    SnmpMgr.get_with_type(target, oper_oid, community: community_ro, version: :v2c)
  end)
  |> Enum.take(20)
  |> Enum.reduce_while(:unknown, fn
    {:ok, {_oid, _type, 4}}, _ -> {:halt, :ok}
    {:ok, {_oid, _type, 9}}, _ -> {:halt, :failed}
    _other, acc -> {:cont, acc}
  end)

IO.inspect(status, label: "final upgrade status")
```

## Out of scope / open questions
- Exact integer enums for `AdminStatus`/`OperStatus` may vary by MIB/vendor; propose canonical DOCS-IF/DOCS-CABLE-DEVICE values and document them
- Optional support for TFTP read checks or file size validations
- SNMPv3 SET permission semantics initially out of scope (could be a follow-up)

## Implementation notes (for maintainers)
- `WalkPduProcessor` currently returns `readOnly` for SET on walk-backed devices. For `:cable_modem`, route SETs for these OIDs to a small state handler in `Device` that:
  - Validates writable OIDs/types/values
  - Stores server/filename as device state
  - On admin status trigger, spawns a task to step `OperStatus` over time
  - Emits telemetry/log entries for phases
- Keep behavior isolated under `device_type == :cable_modem` and `upgrade_enabled == true`

## Backing use case
This enables realistic tests and development for modem firmware upgrades in downstream projects (e.g., initiating upgrades by setting TFTP server and filename OIDs, then toggling admin status and observing OperStatus progression), without external simulators.

