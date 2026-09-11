# Migrating to SnmpKit 2.0

2.0 removes duplicate implementations and dead infrastructure so that each
concern has one module. Most calls on the SNMP facade (`SnmpKit`,
`SnmpKit.SNMP`, `SnmpKit.MIB`, `SnmpKit.Sim`) keep their request/response
shapes from 1.4; the exceptions are listed below. Most applications only need
to update module names they referenced directly.

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
6. Invalid OIDs are errors instead of MIB-root queries, lower-layer retry
   defaults are now one, and formatting is driven by MIB metadata rather than
   guesses based only on a value and its wire type.

If you referenced internal modules, use the tables below: everything renamed
or removed is listed with its replacement.

## Renamed modules

| 1.x | 2.0 |
|-----|-----|
| `SnmpKit.SnmpMgr.EngineV2` | `SnmpKit.SnmpMgr.Engine` |
| `SnmpKit.SnmpMgr.MultiV2` | `SnmpKit.SnmpMgr.Multi` |
| `SnmpKit.SnmpSim.SafeFile` | `SnmpKit.SafeFile` (the old name delegates to it) |
| `SnmpKit.SnmpLib.MIB.Compiler` (and `AST`, `Error`, `Logger`, `Parser`, `Preprocessor`, `Registry`, `SnmpTokenizer`, `Utilities`) | `SnmpKit.MIB.Compiler` (same submodule names under `SnmpKit.MIB`) |
| `SnmpKit.SnmpSim.Device.ErrorInjector` | `SnmpKit.SnmpSim.Device.ErrorConditions` |
| `SnmpKit.TestSupport.start_device/2`, `start_device_population/2` | `SnmpKit.SnmpSim.start_device/2`, `SnmpKit.SnmpSim.start_device_population/2` (`SnmpKit.Sim` still delegates) |

The test-only helper `SnmpKit.TestSupport.SNMPSimulator` under `test/support`
is unaffected.

## Removed modules and functions

| Removed | Replacement |
|---------|-------------|
| `SnmpKit.SnmpMgr.Engine` (the 1.x opt-in request-batching engine; not used by `get`, `walk`, the streams or the default multi-target calls), `Router`, `CircuitBreaker`, `Metrics`, `SnmpMgr.Supervisor`, `SnmpMgr.Application` | The one engine (`SnmpKit.SnmpMgr.Engine`, formerly EngineV2), started on demand. Per-target backpressure: `SnmpKit.SnmpLib.ErrorHandler.quarantine_device/2` and `quarantined?/1` around `SnmpKit.SNMP` calls, or your own. |
| `SnmpKit.SnmpMgr.start_engine`, `engine_request`, `engine_batch`, `get_engine_stats`, `with_circuit_breaker`, `record_metric` and the `SnmpKit.SNMP` delegates | `SnmpKit.SNMP.get_multi/2`, `walk_multi/2`, `get_bulk_multi/2` for batches; `SnmpKit.SnmpMgr.Engine.get_stats/1` and `get_buffer_stats/1` for statistics. |
| The Task-per-target `SnmpKit.SnmpMgr.Multi` and the `strategy: :simple | :concurrent` option | `SnmpKit.SnmpMgr.Multi` is the concurrent implementation; drop the `:strategy` option. |
| `SnmpKit.SnmpMgr.SocketManager` | `SnmpKit.SnmpMgr.Engine` owns the socket: `Engine.get_socket/1`, `get_port/1`, `get_stats/1`, `get_buffer_stats/1`, `health_check/1`. `SnmpKit.SnmpMgr.ensure_started/0` starts `RequestIdGenerator` and `Engine`. |
| `SnmpKit.SnmpLib.MIB` (facade) | `SnmpKit.MIB.compile_raw/2`, `compile_string/2`, `load_compiled/1`, `compile_all/2`, or `SnmpKit.MIB.Compiler` directly. |
| `SnmpKit.SnmpLib.Config` | `SnmpKit.SnmpMgr.Config` (manager defaults) and `SnmpKit.SnmpSim.Config` (simulator). |
| `SnmpKit.SnmpLib.Pool`, `Cache`, `Monitor`, `Dashboard` | None. These were unused by the library; copy the 1.4 modules into your application if you depended on them. |
| `SnmpKit.SnmpLib.Security.Keys.secure_wipe` | None (it was a no-op). |
| `SnmpKit.SnmpMgr.Multi`'s removed `monitor/3` | Run the multi-target call from your application's scheduler or monitoring process. |
| `SnmpKit.SnmpLib.ErrorHandler`'s removed `start_circuit_breaker/2`, `call_through_breaker/3` | Use `quarantine_device/2` and `quarantined?/1` around `SnmpKit.SNMP` calls, or implement application-level backpressure. |
| `SnmpKit.SnmpMgr.Core`'s removed `send_get_request/3`, `send_get_request_async/3`, `send_get_bulk_request_async/3`; `SnmpKit.SnmpMgr.Bulk`'s removed `get_bulk_multi/2` | `Core.send_get_request_with_type/3`; the Task-returning facade async calls; and `SnmpKit.SnmpMgr.Multi.get_bulk_multi/2`, respectively. |
| `Security.update_user/2`, `validate_security_params/2`; `Security.Auth.verify_batch/4`, `benchmark_protocol/4`; `Security.Priv.benchmark_protocol/5`; `Security.USM.increment_engine_boots/1`, `get_engine_time/1`, `generate_error_report/2`; `Security.Keys.export_key/3`, `validate_imported_key/2` | None. These were unused helpers rather than part of the working manager request path. |
| `SnmpKit.SnmpSim.Application`, `MultiDeviceStartup`, `TestScenarios`, `TestHelpers.*`, `Performance.*` | Use `SnmpKit.SnmpSim`, `SnmpKit.Sim`, `LazyDevicePool`, and application-owned test/benchmark helpers as appropriate. The library's port helpers now live under `test/support` and are not shipped. |

## Internal reorganisation

`SnmpKit.SnmpMgr.MIB` keeps its public API but is now ~700 lines: the
built-in name/OID and syntax tables live in `SnmpKit.MIB.Builtin`, the pure
lookup functions in `SnmpKit.MIB.Resolver`, and the conversion of parsed or
compiled MIB data into registry maps in `SnmpKit.MIB.Import`. One behaviour
change: `SnmpMgr.MIB.load/1` merges the loaded objects into the registry
(the 1.x fallback path silently discarded them).

Other large modules were split the same way. `SnmpLib.Types` and
`SnmpLib.Manager` retain their public functions as implementations or delegates;
the simulator splits require the call-site changes shown here:

| Module | Extracted into |
|--------|----------------|
| `SnmpKit.SnmpSim.Device.OidHandler` | `calculate_uptime/1` and `calculate_uptime_ticks/1` moved to `Device.Metrics`. Its other public metric/fallback calculation helpers were removed. The hard-coded per-device-type objects that used to answer when a device had no profile are gone: a device serves its profile or its `objects:` map, and nothing else |
| `SnmpKit.SnmpSim.ValueSimulator` | `simulate_value/3` remains. Counter helpers moved to `ValueSimulator.Counters`; `apply_configurable_jitter/3-4` moved to `ValueSimulator.Variance` |
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
- `SnmpKit.SnmpMgr.Multi.execute_mixed/2` returns enriched varbind maps rather
  than raw `{oid, type, value}` tuples.
- An invalid, empty or mistyped OID is `{:error, {:invalid_oid, input, reason}}`
  on every request path. 1.x silently queried a MIB-root OID (`1.3.6.1` or
  `1.3`) instead, so a typo returned the wrong object rather than an error.
  The `SnmpLib.PDU` builders raise `ArgumentError` for an unparseable OID.
- `:retries` defaults to 1 everywhere, including the multi-target and
  shared-socket walk paths that never retried before, and `SnmpLib.Manager`
  and `SnmpLib.Walker`, which retried three times. An unreachable target now
  takes `timeout * 2` to fail by default; pass `retries: 0` for a single
  attempt.
- GETBULK never changes the requested version: `version: :v3` stays v3 on
  `bulk_pretty`, `Bulk.*` and `adaptive_walk` (they went out as v2c), and
  `version: :v1` is `{:error, {:unsupported_operation, :get_bulk_requires_v2c}}`
  on `adaptive_walk` too. `SnmpMgr.Bulk.get_bulk/3` with more than one OID is
  `{:error, {:unsupported, :multi_oid_get_bulk}}` instead of sending the first.
- The `get_bulk`, `bulk_walk` and `*_pretty` calls return enriched varbind
  maps (they did in 1.4 as well; only the specs and docs said otherwise).
- `Engine` calls return `{:error, :services_not_started}` when the manager
  services are not running instead of exiting with `:noproc`; a failed IPv6
  socket is `{:error, {:ipv6_socket, reason}}`.
- The decoder rejects a Counter32, Gauge32, TimeTicks or Counter64 value that
  is empty, too wide or above its maximum (`{:invalid_varbind, n, reason}`)
  instead of reading it as 0.
- `formatted` values use an object's MIB enumeration, textual convention or
  DISPLAY-HINT. Without metadata, integers and large counters/gauges are
  formatted plainly instead of being guessed as interface states, interface
  types, speeds or byte sizes.
- An SNMPv1 GETNEXT `noSuchName` response is `{:error, :no_such_name}` rather
  than a `:null` varbind, so walks stop at the end of the MIB.
- SNMPv3 privacy configured without authentication is
  `{:error, :priv_requires_auth}` rather than silently deriving a key with MD5.
- `SnmpKit.Agent` drops requests from unknown communities and v3 users at the
  request path too; `:bits` objects accept SET.
- `config :snmpkit, input_roots: [...]` now confines MIB compilation, linting
  and `SnmpMgr.MIB.parse_mib_file/2` (and the `mix snmpkit.mib.*` tasks), not
  only the simulator's profile loaders.
- `:telemetry` is a required dependency rather than an optional one.

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

Enriched result maps, the RFC-compliant SNMPv3 stack, and the
`SnmpKit.SnmpSim` configuration API are as in 1.4.0; see
`docs/v1.4.0-release-notes.md`.
