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
| `SnmpKit.SnmpLib.MIB` (facade) | `SnmpKit.MIB.compile_raw/2`, `compile_string/2`, `load_compiled/1`, `compile_all/2`, or `SnmpKit.MIB.Compiler` directly. |
| `SnmpKit.SnmpLib.Config` | `SnmpKit.SnmpMgr.Config` (manager defaults) and `SnmpKit.SnmpSim.Config` (simulator). |
| `SnmpKit.SnmpLib.Pool`, `Cache`, `Monitor`, `Dashboard` | None. These were unused by the library; copy the 1.4 modules into your application if you depended on them. |
| `SnmpKit.SnmpLib.Security.Keys.secure_wipe/1` | None (it was a no-op). |

## Behaviour unchanged since 1.4

Enriched result maps, the RFC-compliant SNMPv3 stack, SNMPv1/v2c end-of-MIB
semantics, and the `SnmpKit.SnmpSim` configuration API are as in 1.4.0; see
`docs/v1.4.0-release-notes.md`.
