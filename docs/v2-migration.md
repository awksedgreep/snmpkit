# Migrating to SnmpKit 2.0

2.0 removes duplicate implementations and dead infrastructure so that each
concern has one module. The SNMP facade (`SnmpKit`, `SnmpKit.SNMP`,
`SnmpKit.MIB`, `SnmpKit.Sim`) keeps its request/response shapes from 1.4;
most applications only need to update module names they referenced directly.

This document is updated as the `2.x` branch progresses.

## Renamed modules

| 1.x | 2.0 |
|-----|-----|
| `SnmpKit.SnmpMgr.EngineV2` | `SnmpKit.SnmpMgr.Engine` |
| `SnmpKit.SnmpMgr.MultiV2` | `SnmpKit.SnmpMgr.Multi` |
| `SnmpKit.SnmpLib.MIB.Compiler` (and `AST`, `Error`, `Logger`, `Parser`, `Preprocessor`, `Registry`, `SnmpTokenizer`, `Utilities`) | `SnmpKit.MIB.Compiler` (same submodule names under `SnmpKit.MIB`) |
| `SnmpKit.SnmpSim.Device.ErrorInjector` | `SnmpKit.SnmpSim.Device.ErrorConditions` |
| `SnmpKit.TestSupport.start_device/2`, `start_device_population/2` | `SnmpKit.SnmpSim.start_device/2`, `SnmpKit.SnmpSim.start_device_population/2` (`SnmpKit.Sim` still delegates) |

The test-only helper `SnmpKit.TestSupport.SNMPSimulator` under `test/support`
is unaffected.

## Removed modules and functions

| Removed | Replacement |
|---------|-------------|
| `SnmpKit.SnmpMgr.Engine` (streaming engine), `Router`, `CircuitBreaker`, `Metrics`, `SnmpMgr.Supervisor`, `SnmpMgr.Application` | The one engine (`SnmpKit.SnmpMgr.Engine`, formerly EngineV2) plus `SocketManager`; they start with the application. Per-target circuit breaking: implement in the caller around `SnmpKit.SNMP` calls. |
| `SnmpKit.SnmpMgr.start_engine/1`, `engine_request/2`, `engine_batch/2`, `get_engine_stats/1`, `with_circuit_breaker/3`, `record_metric/4` and the `SnmpKit.SNMP` delegates | `SnmpKit.SNMP.get_multi/2`, `walk_multi/2`, `get_bulk_multi/2` for batches; `SnmpKit.SnmpMgr.Engine.get_stats/1` and `SocketManager.get_stats/1` for statistics. |
| The Task-per-target `SnmpKit.SnmpMgr.Multi` and the `strategy: :simple | :concurrent` option | `SnmpKit.SnmpMgr.Multi` is the concurrent implementation; drop the `:strategy` option. |
| `SnmpKit.SnmpMgr.SocketManager` | `SnmpKit.SnmpMgr.Engine` owns the socket: `Engine.get_socket/1`, `get_port/1`, `get_stats/1`, `get_buffer_stats/1`, `health_check/1`. `SnmpKit.SnmpMgr.ensure_started/0` starts `RequestIdGenerator` and `Engine`. |
| `SnmpKit.SnmpLib.MIB` (facade) | `SnmpKit.MIB.compile_raw/2`, `compile_string/2`, `load_compiled/1`, `compile_all/2`, or `SnmpKit.MIB.Compiler` directly. |
| `SnmpKit.SnmpLib.Config` | `SnmpKit.SnmpMgr.Config` (manager defaults) and `SnmpKit.SnmpSim.Config` (simulator). |
| `SnmpKit.SnmpLib.Pool`, `Cache`, `Monitor`, `Dashboard` | None. These were unused by the library; copy the 1.4 modules into your application if you depended on them. |
| `SnmpKit.SnmpLib.Security.Keys.secure_wipe/1` | None (it was a no-op). |

## Internal reorganisation (no call-site changes)

`SnmpKit.SnmpMgr.MIB` keeps its public API but is now ~600 lines: the
built-in name/OID and syntax tables live in `SnmpKit.MIB.Builtin`, the pure
lookup functions in `SnmpKit.MIB.Resolver`, and the conversion of parsed or
compiled MIB data into registry maps in `SnmpKit.MIB.Import`. One behaviour
change: `SnmpMgr.MIB.load/1` merges the loaded objects into the registry
(the 1.x fallback path silently discarded them).

Other large modules were split the same way, with the original module keeping
its public functions (as implementations or delegates):

| Module | Extracted into |
|--------|----------------|
| `SnmpKit.SnmpSim.Device.OidHandler` | `Device.Metrics` (uptime, counter increments, gauges), `Device.BuiltinValues` (hard-coded per-device-type objects and their GETNEXT/GETBULK) |
| `SnmpKit.SnmpSim.ValueSimulator` | `ValueSimulator.Patterns`, `.Counters`, `.Variance` |
| `SnmpKit.SnmpLib.Types` | `Types.Validation`, `Types.Format` (delegates kept on `Types`) |
| `SnmpKit.SnmpLib.Manager` | `Manager.Request` (socket, send/receive/retries), `Manager.Response` (result extraction, error-status decoding) |

## MIB parser

The tokenizer (`SnmpKit.MIB.SnmpTokenizer`) emits identifier values as binaries
instead of interning them as atoms, so parsing untrusted MIB files can no longer
grow the atom table. Effects visible to callers:

- Raw parse trees (`SnmpKit.MIB.Parser.parse/1` before conversion, or anything
  reaching into `kind`/`syntax` tuples) carry `"ifIndex"` where 1.x had
  `:ifIndex`. The converted definition maps already used strings.
- A `DEFVAL { true }` or `{ false }` enumeration label arrives as the string
  `"true"`/`"false"` rather than an Elixir boolean.
- Hex and binary string literals (`'C0A8'H`, `''h`, `'0101'B`) follow OTP's
  `snmpc_tok`: `DEFVAL` decodes to a byte list (`[192, 168]`) and the literals
  are accepted inside `SIZE` ranges. In 1.x the radix suffix was dropped and a
  `'..'b` literal was a syntax error.
- Parsed MIB maps carry a `warnings` list of `{line, message}` lexical
  findings modelled on libsmi (see `docs/mib-parser-oracle.md`);
  `SnmpKit.MIB.Compiler` turns them into errors under `warnings_as_errors: true`.
- Files that are not valid UTF-8 are decoded as Latin-1 (with a warning)
  instead of raising `ArgumentError`.
- Backslashes in quoted strings are no longer treated as escapes, and a `--`
  directly after an identifier starts a comment instead of joining the name.
- Tokenizer illegal-character errors are `{:illegal, char, line}` (was
  `{:illegal, char}`).

## Behaviour unchanged since 1.4

Enriched result maps, the RFC-compliant SNMPv3 stack, SNMPv1/v2c end-of-MIB
semantics, and the `SnmpKit.SnmpSim` configuration API are as in 1.4.0; see
`docs/v1.4.0-release-notes.md`.
