# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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