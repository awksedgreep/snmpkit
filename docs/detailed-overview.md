# SnmpKit Detailed Overview

This page describes how SnmpKit is put together. For call-by-call usage see
the [unified API guide](unified-api-guide.md).

## Layers

```
SnmpKit, SnmpKit.SNMP, SnmpKit.MIB, SnmpKit.Sim      public entry points
        |                 |               |
SnmpKit.SnmpMgr      SnmpKit.MIB.*   SnmpKit.SnmpSim     manager / MIB toolchain / simulator
        |
SnmpKit.SnmpLib                                          PDUs, ASN.1, OIDs, transport, SNMPv3
```

- **SnmpLib** (`lib/snmpkit/snmp_lib/`) encodes and decodes SNMP messages
  (`PDU`, `ASN1`, `OID`, `Types`), sends them (`Transport`, `Manager`), and
  implements the SNMPv3 User-based Security Model (`Security.*`).
- **SnmpMgr** (`lib/snmpkit/snmp_mgr/`) is the manager: single-target
  operations (`Core`), walks (`Walk`, `AdaptiveWalk`, `Bulk`, `Stream`),
  table helpers (`Table`), result enrichment (`Format`), the shared-socket
  `Engine` and the multi-target coordinator (`Multi`).
- **MIB** (`lib/snmpkit/mib/`) is the native MIB toolchain: tokenizer, yecc
  grammar, parser, compiler and registry, plus `Builtin`, `Resolver` and
  `Import` behind the `SnmpKit.SnmpMgr.MIB` name registry.
- **SnmpSim** (`lib/snmpkit/snmp_sim/`) simulates agents: profiles loaded
  from walk files or maps, per-device behaviours, error injection, and
  supervised populations.

## A request's life

1. `SnmpKit.SNMP.get/3` merges call options with the configured defaults and
   resolves the OID name through the MIB registry.
2. `SnmpMgr.Core` builds the PDU with `SnmpLib.PDU`, opens a socket for the
   call (single-target) and sends it, retrying `retries:` times on timeout.
3. The response is decoded, the error-status checked (v1 `noSuchName`, v2c
   exception varbinds such as `endOfMibView` and `noSuchObject`), and each
   varbind is enriched with its name, type and formatted value.

Multi-target calls skip step 2's per-call socket: `SnmpMgr.Engine` owns one
UDP socket with a large receive buffer, `RequestIdGenerator` hands out ids
from an ETS counter, and `SnmpMgr.Multi` sends directly on the socket and
waits for the correlated responses. Walks keep one GETBULK in flight per
target and are bounded by `walk_timeout:`.

## Result shape

All operations return enriched varbind maps:

```elixir
%{name: "ifInOctets.1", oid: "1.3.6.1.2.1.2.2.1.10.1", oid_list: [...],
  type: :counter32, value: 1234567, formatted: "1234567"}
```

`include_names: false` skips the reverse lookup and `include_formatted: false`
skips formatting; both are worth turning off when walking large tables.

## SNMPv3

`SnmpKit.SnmpLib.Security` implements USM per RFC 3414 with HMAC-MD5 and the
SHA family (RFC 7860) for authentication, DES (RFC 3414) and AES (RFC 3826,
with the Reeder/Blumenthal extension for longer keys) for privacy, key
localization, engine discovery and time synchronization. Use `version: :v3`
with `security_name:`, `auth_protocol:`, `auth_password:`, `priv_protocol:`
and `priv_password:` options; the `SnmpKit.SnmpLib.Security.USM` docs list
the full option set.

## MIB toolchain

```
MIB text -> SnmpTokenizer -> yecc grammar (src/mib_grammar_elixir.yrl)
         -> Parser (Elixir maps + warnings) -> Compiler (symbol table)
         -> SnmpMgr.MIB registry (name <-> OID, metadata)
```

The tokenizer never creates atoms from input, so untrusted MIB files are
safe to parse. Vendor constructs that net-snmp tolerates (enumerations on
`Integer32`, uppercase labels, `MAX-ACCESS write-only`, `UNITS` on SMIv1
objects) parse with a warning; the parser is cross-checked against libsmi and
net-snmp over the fixture corpus (see [mib-parser-oracle.md](mib-parser-oracle.md)).

## Simulator

- **Profiles** (`SnmpKit.SnmpSim.ProfileLoader`): bundled walks
  (`:cable_modem`, `:router`, `:switch`), `{:walk_file, path}`,
  `{:oid_walk, path}`, `{:json_profile, path}` or `{:manual, map}`.
- **Devices** (`SnmpKit.SnmpSim.Device`): one process per device, answering
  GET, GETNEXT, GETBULK and SET with correct v1/v2c semantics. Counters and
  gauges can evolve over time through behaviours.
- **Error injection** (`SnmpKit.SnmpSim.ErrorInjector`): timeouts, packet
  loss, protocol errors, malformed responses and reboots, attached to a
  running device.
- **Populations**: `SnmpKit.Sim.start_device_population/2` for lists of
  devices, `SnmpKit.SnmpSim.start/1` for configuration-driven groups with
  supervision, `list_devices/0`, `stop_device/1` and `stop/0`.

Simulated devices are also what the test suite runs against, so every
operation in this library is exercised end to end without real hardware.

## Configuration

```elixir
config :snmpkit,
  community: "public", timeout: 5_000, retries: 1, port: 161, version: :v2c,
  include_names: true, include_formatted: true, auto_start_services: true,
  max_input_file_bytes: 50_000_000, max_compiled_mib_bytes: 50_000_000,
  input_roots: ["priv"]
```

The same keys can be changed at runtime with the setters on
`SnmpKit.SnmpMgr.Config`.

## Performance notes

- Multi-target calls avoid per-request processes and sockets; the shared
  engine is the path to use for fleets.
- `max_repetitions:` is not capped; tune it to the devices and MTU.
- Streams (`walk_stream/3`, `bulk_walk_stream/3`, `table_bulk_stream/3`) keep
  memory flat on very large tables.
- `adaptive_walk/3` and `benchmark_device/3` measure a device's response to
  different bulk sizes and pick one.

## Testing

```sh
mix test                        # unit and integration tests, simulated devices
mix test --include snmpv3       # SNMPv3 suites
mix test --include performance  # timing-sensitive tests
mix test --include mib_oracle   # parser cross-check (needs smilint / snmptranslate)
mix lint                        # format, credo --strict, dialyzer
```
