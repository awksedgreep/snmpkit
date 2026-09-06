# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - Unreleased (branch `2.x`)

Breaking release. See `docs/v2-migration.md` for the rename/removal table.

### Removed
- The opt-in request-batching engine (no default operation used it): `SnmpMgr.Engine` (old), `Router`, `CircuitBreaker`, `Metrics`, `SnmpMgr.Supervisor`, `SnmpMgr.Application`, and `SnmpMgr.start_engine/engine_request/engine_batch/get_engine_stats/with_circuit_breaker/record_metric` plus their `SnmpKit.SNMP` delegates.
- Task-per-target `SnmpMgr.Multi` and the `strategy:` option on multi-target calls.
- `SnmpLib.MIB` facade, `SnmpLib.Config`, `SnmpLib.Pool`, `SnmpLib.Cache`, `SnmpLib.Monitor`, `SnmpLib.Dashboard`.
- `SnmpKit.TestSupport` (lib) and the deprecated `Keys.secure_wipe/1`.
- `SnmpMgr.SocketManager`: the Engine owns the shared UDP socket (`Engine.get_socket/1`, `get_port/1`, `get_buffer_stats/1`, `health_check/1`); responses land in the engine directly instead of being forwarded.

### Changed
- `SnmpMgr.EngineV2` -> `SnmpMgr.Engine`; `SnmpMgr.MultiV2` -> `SnmpMgr.Multi`.
- `SnmpKit.SnmpLib.MIB.*` -> `SnmpKit.MIB.*`.
- `SnmpKit.SnmpSim.Device.ErrorInjector` -> `SnmpKit.SnmpSim.Device.ErrorConditions`.
- `SnmpKit.Sim.start_device/2` and `start_device_population/2` are implemented on `SnmpKit.SnmpSim`.
- `SnmpSim.Device.OidHandler`, `SnmpSim.ValueSimulator`, `SnmpLib.Types` and `SnmpLib.Manager` are split into focused submodules; public functions stay where they were.
- `SnmpMgr.MIB` is split: built-in tables in `SnmpKit.MIB.Builtin`, pure lookups in `SnmpKit.MIB.Resolver`, parsed/compiled data import in `SnmpKit.MIB.Import`; the GenServer keeps the public API. `SnmpMgr.MIB.load/1` now merges loaded objects into the registry (it silently discarded them before).
- MIB tokenizer no longer creates atoms: identifier tokens carry binaries, so parsing an untrusted MIB cannot exhaust the atom table. Raw parse output (`SnmpKit.MIB.Parser.parse/1` before conversion) has binary names where it had atoms; the converted maps are unchanged except that a `DEFVAL { true }` / `{ false }` label is now the string `"true"` / `"false"` rather than an Elixir boolean.
- Hex and binary string literals (`'C0A8'H`, `''h`, `'0101'B`) are tokenized as in OTP's `snmpc_tok`: `DEFVAL` values decode to byte lists and they are accepted in `SIZE` ranges (previously a syntax error on some MIBs).
- MIB tokenizer reports libsmi-style lexical warnings (`SnmpTokenizer.scan/1`; `warnings` key on parsed MIBs; `Compiler` honours `warnings_as_errors`): underscores or trailing hyphens in identifiers, odd-length hex strings, binary strings not a multiple of 8 bits. Non-UTF-8 MIB files are decoded as Latin-1 with a warning instead of raising. Backslashes inside quoted strings are literal (SMI has no escapes) and `--` ends an identifier. Illegal-character errors are `{:illegal, char, line}`. A `:mib_oracle`-tagged test cross-checks the parser against libsmi and net-snmp (`docs/mib-parser-oracle.md`).
- MIB grammar accepts, with a warning, vendor constructs net-snmp loads: enumerations on `Integer32`/`Unsigned32` (treated as `INTEGER`), uppercase enumeration labels, `MAX-ACCESS write-only`, and `UNITS` on SMIv1 objects. Impossible `LAST-UPDATED`/`REVISION` dates are reported as warnings.

### Added
- Notifications: `SnmpKit.Trap` receives SNMPv1 traps, SNMPv2c traps and informs (acknowledged automatically) and dispatches them to a function, MFA or pid; `SnmpKit.SNMP.send_trap/4` and `send_inform/4` send them; `SnmpKit.Sim.send_trap/4` sends from a simulated device. `SnmpKit.SnmpLib.PDU` gains Trap-PDU (v1), SNMPv2-Trap, InformRequest and Report encoding/decoding with `build_trap_v1/6`, `build_trap_v2/4` and `build_inform/4`. The built-in MIB knows `snmpTrapOID` and the standard `snmpTraps` names. (#28)
- SNMPv3 end to end. Manager: `SnmpKit.SNMP.get/walk/...` with `version: :v3` plus `security_name`, `auth_protocol`/`auth_password`, `priv_protocol`/`priv_password` now perform USM requests (`SnmpKit.SnmpLib.Manager.V3`): engine discovery, key localization, time synchronisation and report-driven retries, with engines cached per target in `SnmpKit.SnmpLib.Security.EngineCache`. In 1.x the manager had the security primitives but no v3 request path. Simulator: devices started with `v3_users:` run an agent-side USM (`SnmpKit.SnmpSim.Core.UsmAgent`): engine id, boots/time, per-user localized keys, authentication and privacy on both directions, security-level enforcement, and the `usmStats` reports (unknownEngineIDs, unknownUserNames, unsupportedSecLevels, notInTimeWindows, wrongDigests, decryptionErrors). Every auth (MD5, SHA-1, SHA-256, SHA-512) and priv (DES, AES-128/192/256) combination is exercised end to end in the default test run. (#31)
- `SnmpKit.MIB.Lint` and `mix snmpkit.mib.lint`: semantic MIB checks in the spirit of smilint levels 1-2 (unresolved parents, duplicate names/OIDs, unknown types, SMIv1 constructs in SMIv2 modules, missing MODULE-IDENTITY, rows without INDEX, index strings without SIZE, SEQUENCE/column mismatches, undefined objects in notifications and groups, plus the parser's warnings) with `context:` MIBs to satisfy imports. The parser now converts SEQUENCE, NOTIFICATION-TYPE, TRAP-TYPE, OBJECT-GROUP, NOTIFICATION-GROUP, MODULE-COMPLIANCE and AGENT-CAPABILITIES definitions into maps, and compiled MIBs keep their `imports`. (#34)
- IPv6 end to end: `"[2001:db8::1]:161"`, bare IPv6 literals and AAAA-only hostnames work for every single-target call, multi-target calls (the engine opens an IPv6 socket on first use), walks, traps and informs; simulated devices and `SnmpKit.Trap` accept `bind_address: "::1"`. `Transport.family/1` and `target_family/1`. (#38)
- Mix tasks: `mix snmpkit.get HOST OID...`, `mix snmpkit.walk HOST [OID] [--table] [--no-bulk]`, `mix snmpkit.mib.compile PATH...` (warnings per file, non-zero exit on failure) and `mix snmpkit.sim CONFIG | --device TYPE | --sample PATH`. (#35)
- Property-based tests (`test/snmp_lib/property_test.exs`, StreamData 1.x) round-trip BER integers across the 64-bit range, octet strings through every length form, OIDs with sub-identifiers up to 2^32-1, and whole v1/v2c messages, GETBULKs, responses, traps and informs with random varbinds; truncated messages must decode to an error rather than a shorter varbind list. (#37)
- Named table rows: `SnmpKit.SNMP.get_table(target, table, named: true)` returns rows keyed by column name with the INDEX objects decoded (integers, IpAddress, fixed and variable-length strings, OIDs, IMPLIED), for the built-in tables and any loaded MIB. `SnmpKit.SnmpMgr.MIB.table_layout/1`, `SnmpKit.SnmpMgr.Table.to_named_table/2` and `SnmpKit.MIB.TableIndex`. (#39)
- `SnmpKit.Sim.record/3` (`SnmpKit.SnmpSim.Recorder`) walks a real device and writes the walk file the simulator loads, in net-snmp's numeric format. (#36)
- `SnmpKit.SNMP.Rate`: `delta/2`, `rate/3` and `rates/3` compute deltas and per-second rates from successive samples with Counter32/Counter64 wraparound handled, pair whole walks by OID, take the interval from `sysUpTime.0`, and report device restarts. (#32)
- MIB-aware formatting: `formatted` now uses the object's MIB metadata: enumeration labels (`ifOperStatus` -> `"up"`, `ifType` -> `"ethernetCsmacd"`, `TruthValue`, `RowStatus`, DOCSIS status values, ...), DISPLAY-HINTs (`PhysAddress` -> `"00:1a:2b:3c:4d:5e"`, `DateAndTime`, `d-1` style integer hints) and textual conventions, from the built-in tables (`SnmpKit.MIB.Builtin.enumerations/1`, `meta/1`) or from any loaded MIB. New `SnmpKit.MIB.Syntax` (describes grammar syntax terms) and `SnmpKit.MIB.DisplayHint` (RFC 2579 hint interpreter); `SnmpKit.SnmpMgr.MIB.reverse_lookup_with_meta/1` and `Format.format_value/3`. (#33)
- Several objects per PDU: `SnmpKit.SNMP.get(target, [oid, ...])` returns one enriched map per OID from a single GET (SNMPv2c exceptions kept per element as the type, `noSuchName` for v1); `SnmpKit.SNMP.set_many/3` sends one atomic SET; `get_multi` accepts a list of OIDs per request. Underneath: `SnmpLib.Manager.get_varbinds/3`, `set_varbinds/3`, `PDU.build_set_request_multi/2`, `Response.extract_varbinds/1`, `SnmpMgr.Core.send_get_varbinds/3`, `send_set_varbinds/3`. (#30)
- Telemetry: `[:snmpkit, :request | :walk | :multi, :start | :stop | :exception]` spans around every single-target PDU exchange, walk and multi-target call, plus `[:snmpkit, :engine, :timeout]`, `[:snmpkit, :trap, :received | :rejected]` and `[:snmpkit, :sim, :request]` events; documented in `SnmpKit.Telemetry`. `telemetry` is now a required dependency. (#29)
- `SnmpKit.SnmpSim.ProfileLoader.load_profile/1` loads the bundled walks (`:cable_modem`, `:router`, `:switch`).
- `SnmpKit.Sim.start_device/2` accepts a plain `%{objects: %{oid => value}}` map; `SnmpKit.Sim.start_device_population/2` accepts `%{type:, port:, community:}` maps as well as `{type, source, count: n}` tuples, starts the device pool itself and returns `[%{type, port, pid, target}]`.
- `config :snmpkit, ...` is read for manager defaults (`community`, `timeout`, `retries`, `port`, `version`, `include_names`, `include_formatted`, `auto_start_services`); the old `:snmp_mgr` application key still works.
- `SnmpKit.MIB.load/1` accepts the compiled MIB map returned by `compile/1` as well as a path.
- `SnmpKit.SNMP.table_bulk_stream/3` supports `columns:`.

### Fixed
- Simulated devices built from a profile served fixed values for `ifSpeed.1` (100 Mbps), `ifMtu.1` and zeroed `ifInOctets.1`/`ifOutOctets.1` regardless of the profile; those defaults now apply only to devices without any profile data. `Hex-STRING` walk values are served as the octets they denote instead of their hex text.
- Loading a compiled MIB registered no names when its objects used relative OIDs (`::= { parent 1 }`, which is every real MIB): the parser turned sub-identifier lists into strings and the importer could not resolve parents. Sub-identifiers stay integers and `SnmpKit.MIB.Resolver.resolve_definition_oids/2` resolves parents against the other definitions and the registry, so `SnmpKit.MIB.compile/1` + `load/1` now make a vendor MIB's names resolvable and its enumerations and hints usable by the formatter.
- `formatted` no longer guesses from bare values: an INTEGER 1 or 2 was rendered as `"up"`/`"down"`, 3..200 as an interface type name, and counters or gauges above one million as speeds or byte sizes, whatever the object was. Values now format plainly unless the MIB says otherwise. `Format.interface_status/1`, `interface_type/1`, `speed/1` and `bytes/1` remain as explicit helpers.
- Simulated devices could not answer a GETBULK that reached a walk-file value outside its type's range (the bundled router walk had an 8 Gbps `ifSpeed` in a Gauge32), so single-target walks of that device timed out. Walk values are now clamped to the type's range on load with a warning, and the bundled walk is corrected.
- `SnmpKit.SNMP.get_async/3` and `get_bulk_async/3` return a `Task` (they returned a bare reference and a message the docs never described).
- `SnmpKit.SNMP.benchmark_device/3` raised on integer division; `analyze_table/2` rejected the list `walk_table/3` returns; `table_bulk_stream/3` raised on its first chunk and walked past the table.
- `SnmpKit.SnmpMgr.PerformanceBenchmark` referenced the removed `TestSupport` simulator.
- Documentation sweep for 2.0: README, guides, livebooks and examples describe the current API and return shapes (multi-target calls return a plain list; simulated devices answer SET with `{:error, :not_writable}`; no more references to removed modules).

## [1.4.0] - 2026-09-05

Final 1.x release. Full notes: `docs/v1.4.0-release-notes.md`.

### Added
- `SnmpKit.SnmpSim` top-level API: start device groups from a config map or JSON/YAML file; list, count and stop devices.
- Opt-in per-target circuit breaker in `SnmpMgr.Engine`; `CircuitBreaker.allow?/2`.
- `SnmpKit.SnmpSim.SafeFile` with size cap and optional directory jail for simulator inputs.
- `.credo.exs`, `mix lint`, HexDocs module groups, specs on core SnmpMgr modules; CI checks formatting and warnings.

### Changed
- SNMPv3 authentication, privacy and key derivation follow RFC 3414/3826/7860 (breaks interop with 1.3.x v3 traffic; DES keys are 16 octets).
- SNMPv2c GET of an unknown object returns `{:error, :no_such_object}`; SNMPv1 end-of-MIB is a noSuchName error, SNMPv2c an endOfMibView exception.
- Simulator GETBULK honours `max-repetitions` as requested (no 50 cap) and stops at a single endOfMibView.
- `SnmpMgr.Walk` returns enriched maps on the SNMPv1 path too; docs updated.
- Manager services start supervised with the application; `Engine.submit_request/3` waits `:timeout` + 1s.
- `SharedProfiles` reads come straight from ETS with an ordered OID index.

### Fixed
- OID BER encoding of the first two arcs (X.690 8.19); malformed PDUs are errors, not empty results.
- `:port` option honoured on every manager request path.
- Engine double replies, timer/socket leaks, pool saturation; Router crash propagation and atom minting; SocketManager health math.
- Simulator worker/packet bounds, atom creation from input, frozen bulk counters, hard-coded sysUpTime, `IO.inspect` in lib.
- Compiled MIBs load with `binary_to_term(:safe)`; MIB grammar compile errors are reported.

### Deprecated
- `SnmpKit.SnmpLib.Security.Keys.secure_wipe/1` (no-op; removed in 2.0).

### Removed
- Superseded root `test/walk_*` debug test files and the `lsof`/`kill -9` port sweep in `test_helper.exs`.

## [1.3.5] - 2025-12-25

### Fixed
- **ExDoc Warnings**: Fixed relative path warnings in ExDoc generation for cleaner documentation builds

## [1.3.4] - 2025-12-25

### Fixed
- **Documentation References**: Fixed docs references to renamed livebooks after tutorial reorganization

## [1.3.3] - 2025-12-25

### Changed
- **Livebook Reorganization**: Reorganized livebooks into 5 focused tutorials for better learning experience

## [1.3.2] - 2025-12-12

### Fixed
- **Per-Request Timeout**: Fixed per-request timeout being ignored in `walk_multi` and other multi-target operations
  - Per-request options were properly merged into request.opts but never read
  - Now extracts timeout from request.opts with fallback to global timeout
  - Different requests can have different timeout values in the same call
  - Works for all operation types: GET, GETBULK, WALK, and mixed operations

### Added
- **Timeout Documentation**: Added comprehensive timeout documentation to address missing documentation
  - New `TIMEOUT_DOCUMENTATION.md` with complete timeout reference guide
  - Documents PDU timeout vs task timeout distinction
  - Clarifies per-request timeout overrides
  - Explains walk operation timeout behavior
  - Added timeout documentation to `MultiV2`, `Core`, and main `SnmpKit` modules

## [1.3.1] - 2025-12-11

### Fixed
- **Task.async_stream Timeout**: Fixed Task.async_stream timeout killing `walk_multi` operations prematurely
  - Problem: `walk_multi` failed with `{:task_failed, :timeout}` for large SNMP tables
  - Root cause: Task.async_stream timeout of 'pdu_timeout + 1000ms' killed entire walks even when individual PDUs responded successfully
  - Solution: Use 20-minute maximum timeout for walk operations; non-walk operations keep short timeout + 1000ms safeguard
  - Impact: `walk_multi` now works reliably for large interface/routing tables in enterprise environments

## [1.3.0] - 2025-12-11

### Fixed
- **Counter64 Decoding**: Fixed Counter64 decoding for values that use fewer than 8 bytes
  - SNMP Counter64 values with fewer bytes were incorrectly decoded
  - Now properly handles variable-length Counter64 encoding

## [1.2.1] - 2025-12-04

### Fixed
- **Long Octet String Support**: Support for longer octet strings with multi-byte length encoding
  - PDU decoder now properly handles ASN.1 long-form length encoding
  - Fixes decoding of SNMP values with lengths > 127 bytes

## [1.2.0] - 2025-09-23

### Added
- **Extended OID Lookup Support**: Major enhancements to MIB module for OID lookups
  - Expanded `SnmpKit.SnmpMgr.Mib` with comprehensive lookup capabilities
  - Added MIB context feature for scoped lookups
  - Enhanced MIB registry with improved OID resolution

## [1.1.0] - 2025-09-18

### Changed
- **API Consistency**: Made enrichment idempotent; unified API outputs across walk/bulk/stream operations
- **Test Improvements**: Hardened test cleanup for more reliable test runs

## [1.0.0] - 2025-09-07

- API: Multi-target operations now default to Concurrent Multi (high-throughput) behavior. The legacy path remains available via `strategy: :simple`.
- API: No manual engine/service start is required for multi-target operations. The Concurrent Multi components are auto-ensured at call time.
- Docs: Rename "Multi v2" to "Concurrent Multi" and clarify that high-throughput multi-target execution is the recommended default approach.
- Docs: Remove "start a service first" wording from examples; advanced examples may still show explicit starts for demonstration purposes.

Note: For migration guidance from 0.x to 1.x enriched output, see docs/enriched-output-migration.md

### Breaking
- Standardized enriched map result across all SNMP operations: `%{name?, oid, type, value, formatted?}`
- Type always included; names and formatted included by default (configurable via include_names/include_formatted)
- Pretty helpers now include type and raw value; return the same map shape
- Removed `get_with_type/3` and `get_next_with_type/3`
- Multi-target APIs preserve outer shape but enrich inner items
- Migration: see `docs/enriched-output-migration.md`

## [0.6.6] - 2025-01-12

### Fixed
- **Multi-Walk Bug Fix**: Fixed critical bug in `SnmpKit.SnmpMgr.MultiV2.walk_multi/2` where walk operations were only returning the first result instead of performing complete iterative walks
- **SNMP v2c Compliance**: Removed obsolete v1-style GET_NEXT code paths from MultiV2 module to ensure all operations use proper SNMP v2c GET_BULK operations
- **Walk Operation Delegation**: Walk operations now properly delegate to `SnmpKit.SnmpMgr.V2Walk` module for complete iterative walk functionality

### Technical Details
- Multi-walk operations now return all discovered results (1000+ items) instead of just 1 result
- Confirmed exclusive use of GET_BULK PDU operations (0xA5) for efficient bulk retrieval
- Maintained high performance with ~3.5 results per packet efficiency

## [0.6.0] - 2025-08-18

### Added
- New concise helpers on `SnmpKit` for bulk and multi operations:
  - `get_bulk/2-3`, `bulk_walk/2-3`, `walk_table/2-3`
  - `get_bulk_multi/1-2`, `walk_multi/1-2`
- Bang variants for bulk helpers in `SnmpKit.SNMP`:
  - `get_bulk!/3`, `bulk_walk!/3`
- Streaming helpers that enforce bulk semantics (v2c) in `SnmpKit.SNMP`:
  - `bulk_walk_stream/3`, `table_bulk_stream/3`
- Documentation updates to prefer concise `SnmpKit` helpers by default

### Changed
- Unified API Guide updated to show `SnmpKit.*` helpers as the preferred entry points

### Notes
- These are thin delegates; no underlying behavior changes to request/response processing
- Backward compatibility preserved; namespaced `SnmpKit.SNMP.*` APIs remain available

## [0.3.7] - 2024-12-22

### Fixed
- **Port Option Handling**: Fixed critical bug where the `:port` option in function calls was being ignored
  - When target was specified as hostname without port (e.g., `"device.local"`), the port option was incorrectly overwritten with default port 161
  - Target with embedded port (e.g., `"device.local:8161"`) now correctly takes precedence over port option
  - Established clear port precedence rules: embedded port > port option > default port (161)
  - Fixed in `SnmpKit.SnmpMgr.Core.send_get_request/3`, `send_set_request/4`, and `send_get_bulk_request/3`
  - Added comprehensive unit tests for port option handling
  - Maintains full backward compatibility

## [0.3.4] - 2024-12-16

### Added
- **New API Function**: `get_next_with_type/2,3` for consistent API completeness
  - Added to both `SnmpKit.SnmpMgr` and `SnmpKit.SNMP` modules
  - Provides type information for GET-NEXT operations
  - Maintains consistency with `get_with_type/2,3` pattern

### Fixed
- **Critical API Return Format Fixes**:
  - Fixed `get/3` to return `{:ok, value}` instead of `{:ok, {type, value}}`
  - Fixed `get_next/3` to return `{:ok, {oid, value}}` instead of `{:ok, {oid, type, value}}`
  - Preserved `get_with_type/3` and `get_next_with_type/3` for when type info is needed
  
- **SNMP Type Encoding Issues**:
  - Fixed improper type conversion from `"OCTET STRING"` to `:"octet string"` (with quotes)
  - Now correctly converts to `:octet_string` (with underscore)
  - Added proper type mapping in multiple modules:
    - `lib/snmpkit/snmp_sim/device/oid_handler.ex`
    - `lib/snmpkit/snmp_sim/device/walk_pdu_processor.ex`
    - `lib/snmpkit/snmp_sim/mib/shared_profiles.ex`

- **Empty Device Handling**:
  - Fixed empty OID map logic to properly return `:no_such_name` errors
  - Changed condition from checking `map_size(oid_map) > 0` to just `Map.has_key?(state, :oid_map)`

- **Code Quality**:
  - Removed unused module attribute that was causing compiler warnings
  - Removed dead code pattern matching that was unreachable after API fixes
  - Fixed unused variable warning in test files

### Changed
- **Documentation Updates**:
  - Updated all examples to show correct 3-tuple format `{oid, type, value}` for bulk operations
  - Fixed examples in `get_bulk`, `walk`, `walk_table`, and multi-operation functions
  - Added comprehensive type specifications for consistency
  - All bulk operations now correctly show type information in examples

- **API Consistency**:
  - Simple operations (`get`, `get_next`) provide clean interfaces without type info
  - Type-aware operations (`get_with_type`, `get_next_with_type`) preserve full SNMP information
  - All bulk operations (`get_bulk`, `walk`, `bulk_walk`) always include type information
  - Pretty operations continue to provide formatted output for display

### Performance
- **Test Optimization**:
  - Made selected tests async-safe for faster test execution
  - Added `async: true` to pure computation tests:
    - `test/snmpkit_test.exs`
    - `test/snmp_lib/mib/docsis_mib_test.exs`
    - `test/snmp_sim/correlation_engine_test.exs`

### Technical Details

#### API Return Formats (Now Consistent)
```elixir
# Simple operations (no type info)
{:ok, value} = SnmpKit.SNMP.get(target, oid)
{:ok, {oid, value}} = SnmpKit.SNMP.get_next(target, oid)

# Type-aware operations (with type info)
{:ok, {oid, type, value}} = SnmpKit.SNMP.get_with_type(target, oid)
{:ok, {oid, type, value}} = SnmpKit.SNMP.get_next_with_type(target, oid)

# Bulk operations (always with type info)
{:ok, [{oid, type, value}]} = SnmpKit.SNMP.get_bulk(target, oid)
{:ok, [{oid, type, value}]} = SnmpKit.SNMP.walk(target, oid)
```

#### Type Mapping Improvements
- `"OCTET STRING"` → `:octet_string`
- `"INTEGER"` → `:integer`
- `"OBJECT IDENTIFIER"` → `:object_identifier`
- `"TIMETICKS"` → `:timeticks`
- `"COUNTER32"` → `:counter32`
- `"GAUGE32"` → `:gauge32`
- `"COUNTER64"` → `:counter64`

### Testing
- ✅ All 1159 tests pass
- ✅ 76 doctests pass
- ✅ No breaking changes to existing functionality
- ✅ Type specifications validated
- ✅ Examples tested against real simulator

### Backward Compatibility
- All changes maintain backward compatibility
- Existing code using bulk operations will continue to work as before
- Simple operations now return cleaner formats as originally intended
- Type-aware variants available for applications needing full SNMP type information

### Files Modified
- `lib/snmp_mgr.ex` - Main API fixes and type specs
- `lib/snmpkit.ex` - Added `get_next_with_type` delegation
- `lib/snmpkit/snmp_mgr/core.ex` - Core API return format fixes
- `lib/snmpkit/snmp_mgr/walk.ex` - Removed dead code and warnings
- `lib/snmpkit/snmp_sim/device/oid_handler.ex` - Fixed type conversion logic
- `lib/snmpkit/snmp_sim/device/walk_pdu_processor.ex` - Fixed type mapping
- `lib/snmpkit/snmp_sim/mib/shared_profiles.ex` - Enhanced type mapping
- Multiple test files - Fixed warnings and added async optimization
- Documentation and examples throughout codebase

---

## [0.3.3] - Previous Release
- Previous functionality and features

## [0.3.2] - Previous Release  
- Previous functionality and features

## [0.3.1] - Previous Release
- Previous functionality and features

---

For upgrade instructions and migration guides, see the [README.md](README.md) file.