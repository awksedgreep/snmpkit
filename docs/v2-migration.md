# Migrating to SnmpKit 2.0

2.0 removes duplicate implementations and dead infrastructure so that each
concern has one module. The SNMP facade (`SnmpKit`, `SnmpKit.SNMP`,
`SnmpKit.MIB`, `SnmpKit.Sim`) keeps its request/response shapes from 1.4;
most applications only need to update module names they referenced directly.

## Summary

If your code only uses `SnmpKit`, `SnmpKit.SNMP`, `SnmpKit.MIB` and
`SnmpKit.Sim`, the changes that can reach you are:

1. `SnmpKit.SNMP.get_async/3` and `get_bulk_async/3` return a `Task`.
2. Manager defaults come from `config :snmpkit, ...` (see the README);
   `:snmp_mgr` keys still work.
3. `SnmpKit.Sim.start_device_population/2` pre-warms devices and returns
   `[%{type, port, pid, target}]`.
4. `SnmpKit.MIB.load/1` accepts the compiled map directly; parsed MIBs carry
   `warnings` and use binaries where 1.x used atoms.
5. `SnmpKit.SNMP.with_circuit_breaker` and the other engine delegates are
   gone; use the multi-target calls.

If you referenced internal modules, use the tables below: everything renamed
or removed is listed with its replacement.

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
| `SnmpKit.SnmpMgr.Engine` (the 1.x opt-in request-batching engine; not used by `get`, `walk`, the streams or the default multi-target calls), `Router`, `CircuitBreaker`, `Metrics`, `SnmpMgr.Supervisor`, `SnmpMgr.Application` | The one engine (`SnmpKit.SnmpMgr.Engine`, formerly EngineV2), started on demand. Per-target circuit breaking: `SnmpKit.SnmpLib.ErrorHandler.start_circuit_breaker/2` around `SnmpKit.SNMP` calls, or your own. |
| `SnmpKit.SnmpMgr.start_engine`, `engine_request`, `engine_batch`, `get_engine_stats`, `with_circuit_breaker`, `record_metric` and the `SnmpKit.SNMP` delegates | `SnmpKit.SNMP.get_multi/2`, `walk_multi/2`, `get_bulk_multi/2` for batches; `SnmpKit.SnmpMgr.Engine.get_stats/1` and `get_buffer_stats/1` for statistics. |
| The Task-per-target `SnmpKit.SnmpMgr.Multi` and the `strategy: :simple | :concurrent` option | `SnmpKit.SnmpMgr.Multi` is the concurrent implementation; drop the `:strategy` option. |
| `SnmpKit.SnmpMgr.SocketManager` | `SnmpKit.SnmpMgr.Engine` owns the socket: `Engine.get_socket/1`, `get_port/1`, `get_stats/1`, `get_buffer_stats/1`, `health_check/1`. `SnmpKit.SnmpMgr.ensure_started/0` starts `RequestIdGenerator` and `Engine`. |
| `SnmpKit.SnmpLib.MIB` (facade) | `SnmpKit.MIB.compile_raw/2`, `compile_string/2`, `load_compiled/1`, `compile_all/2`, or `SnmpKit.MIB.Compiler` directly. |
| `SnmpKit.SnmpLib.Config` | `SnmpKit.SnmpMgr.Config` (manager defaults) and `SnmpKit.SnmpSim.Config` (simulator). |
| `SnmpKit.SnmpLib.Pool`, `Cache`, `Monitor`, `Dashboard` | None. These were unused by the library; copy the 1.4 modules into your application if you depended on them. |
| `SnmpKit.SnmpLib.Security.Keys.secure_wipe` | None (it was a no-op). |

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

## Behaviour changes you may notice

- `SnmpKit.SNMP.get_async/3` and `get_bulk_async/3` return a `Task`; await it
  with `Task.await/2`. In 1.x they returned a reference and sent
  `{ref, result}` to the caller.
- Manager defaults are read from `config :snmpkit` (the 1.x `:snmp_mgr` key
  is still honoured).
- `SnmpKit.MIB.load/1` takes the compiled map from `compile/1` directly; a
  path to a `:binary` compiled file still works.
- `SnmpKit.Sim.start_device_population/2` pre-warms devices by default and
  returns `[%{type, port, pid, target}]` instead of the raw pool reply.
- `SnmpKit.SNMP.set/4` and `SnmpMgr.set/4` return `:ok` on success instead of
  `{:ok, :success}`, matching `set_many/3`. Errors are unchanged.
- `SnmpKit.SNMP.benchmark_device/3` returns `avg_response_time` as the mean
  over all tested bulk sizes and adds `optimal_response_time`.

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
- Four vendor constructs that were syntax errors now parse with a warning
  (enumerations on `Integer32`/`Unsigned32`, uppercase enumeration labels,
  `MAX-ACCESS write-only`, `UNITS` on SMIv1 objects), matching net-snmp.

## Behaviour unchanged since 1.4

Enriched result maps, the RFC-compliant SNMPv3 stack, SNMPv1/v2c end-of-MIB
semantics, and the `SnmpKit.SnmpSim` configuration API are as in 1.4.0; see
`docs/v1.4.0-release-notes.md`.
