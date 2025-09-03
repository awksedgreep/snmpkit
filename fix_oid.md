# OID Handling Cleanup Plan

## Overview

The OID handling throughout the manager and lib modules is architecturally broken. There's inconsistent handling between string and list formats, excessive conversions, and poor separation of concerns. This document outlines a phased approach to fix these issues.  Please check the code in OFTEN.  After every phase and even within the phase, review the changes and ensure they align with the architectural principles.

## Architectural Principles

1. **Internal Standard**: All internal OID handling MUST use lists of integers `[1,3,6,1,2,1,1,1,0]`
2. **External API Flexibility**: Public APIs MUST accept both string `"1.3.6.1.2.1.1.1.0"` and list `[1,3,6,1,2,1,1,1,0]` formats
3. **Boundary Conversion**: Convert external input to internal list format at API boundaries only
4. **No Internal Conversions**: Never convert internal lists to strings except for final user output
5. **Consistent Types**: Function signatures must be clear about whether they work with strings or lists

## Current Damage Assessment

### Critical Files Requiring Major Changes
- `snmp_mgr/core.ex` - Heavy string/list mixing, broken `parse_oid` function
- `snmp_mgr/adaptive_walk.ex` - String/list conversions throughout
- `snmp_mgr/bulk.ex` - Converting lists to strings unnecessarily
- `snmp_mgr/format.ex` - Mixed handling for output formatting
- `snmp_mgr/mib.ex` - String/list conversions in MIB operations
- `snmp_mgr/v2_walk.ex` - String conversion at entry point
- `snmp_mgr/walk.ex` - Likely similar issues

### Moderate Changes Required
- `snmp_lib/manager.ex` - Mixed handling in normalization functions
- `snmp_lib/mib/registry.ex` - String/list checking and conversions
- Main `snmp_mgr.ex` - API consistency issues

### Minor Changes Required
- `snmp_lib/mib/parser.ex` - Minor OID conversion issues

### Foundation (Good)
- `snmp_lib/oid.ex` - This module is actually well-designed and should be the foundation

## Phase 1: Foundation and API Boundaries

### Goals
- Establish consistent API conversion patterns
- Fix the core parsing and normalization functions
- Ensure all external APIs properly convert input to internal format

### Tasks

#### 1.1 Fix `snmp_mgr/core.ex` ✅ COMPLETED
- **Priority**: CRITICAL
- ✅ Rewritten `parse_oid/1` to always return lists with proper validation
- ✅ Removed string-to-list conversions in internal functions 
- ✅ Updated `send_get_request/3`, `send_get_next_request/3`, `send_set_request/4` to convert OID input to lists immediately
- ✅ Fixed string conversions to only happen for final output format
- ✅ Improved error handling and validation

#### 1.2 Fix Main API in `snmp_mgr.ex` ✅ COMPLETED
- **Priority**: HIGH
- ✅ Updated documentation to clearly state input flexibility (string or list formats)
- ✅ Confirmed all public functions properly delegate to Core which handles conversion
- ✅ Added parameter documentation for OID input formats

#### 1.3 Standardize `snmp_lib/manager.ex` ✅ COMPLETED
- **Priority**: HIGH
- ✅ Enhanced `normalize_oid/1` with proper validation for list inputs
- ✅ Confirmed string-to-list conversion with MIB resolution
- ✅ Ensured all PDU operations work with validated list OIDs

### Expected Outcome ✅ ACHIEVED
After Phase 1, all API entry points will convert external OIDs to internal list format, and core operations will be consistent.

**Completed:**
- Core parsing now always returns validated list format
- API boundaries properly documented for input flexibility
- Internal operations standardized to expect list OIDs
- Improved error handling and validation throughout

## Phase 2: Internal Operations Cleanup 🚧 IN PROGRESS

### Goals
- Remove all internal string/list conversions in operational modules
- Standardize all walk, bulk, and table operations to use list OIDs internally
- Fix result formatting to only convert to strings at the final output stage

### Tasks

#### 2.1 Fix Walk Operations 🚧 NEXT
- **Files**: `snmp_mgr/walk.ex`, `snmp_mgr/v2_walk.ex`, `snmp_mgr/adaptive_walk.ex`
- Remove string OID handling in internal operations
- Keep OIDs as lists throughout walk operations
- Only convert to strings in final result formatting if required by API contract
- **Note**: `v2_walk.ex` identified as having mixed string/list handling in initial state

#### 2.2 Fix Bulk Operations  
- **File**: `snmp_mgr/bulk.ex`
- Remove unnecessary list-to-string conversions in `filter_table_results/2`
- Keep OIDs as lists throughout bulk operations
- Update result processing to work with list OIDs

#### 2.3 Fix MIB Operations
- **File**: `snmp_mgr/mib.ex`
- Update `reverse_lookup/1` to work primarily with lists
- Fix string OID handling to convert at entry point only
- Remove internal string/list checking patterns

### Expected Outcome
After Phase 2, all internal operations will be consistent with list OIDs, and only final output formatting will handle string conversion.

## Phase 3: Advanced Operations and Utilities

### Goals
- Clean up advanced features like multi-target operations
- Fix formatting and display utilities
- Ensure streaming and async operations are consistent

### Tasks

#### 3.1 Fix Format and Display
- **File**: `snmp_mgr/format.ex`
- Update to clearly separate internal list handling from output string formatting
- Keep `pretty_print/1` working with final string output
- Remove mixed OID handling in formatting functions

#### 3.2 Fix Registry and MIB Support
- **File**: `snmp_lib/mib/registry.ex`
- Update symbolic name resolution to return lists
- Fix OID checking patterns to expect lists internally
- Remove redundant string/list validation

#### 3.3 Update Advanced Operations
- Review multi-target operations for consistency
- Ensure streaming operations maintain list OIDs internally
- Fix any async operation OID handling

### Expected Outcome
After Phase 3, all advanced features will be consistent with the new OID handling standards.

## Phase 4: Testing and Validation

### Goals
- Ensure all changes maintain backward compatibility
- Validate performance improvements from reduced conversions
- Comprehensive testing of all OID formats

### Tasks

#### 4.1 API Compatibility Testing
- Test that all public APIs still accept both string and list OID formats
- Validate that output formats remain consistent with existing API contracts
- Test edge cases and error conditions

#### 4.2 Performance Validation
- Measure reduction in string/list conversions
- Validate improved performance in bulk operations
- Test memory usage improvements

#### 4.3 Integration Testing
- Test with real SNMP devices
- Validate MIB resolution still works correctly
- Test all walk and bulk operations

### Expected Outcome
Full validation that the cleanup maintains compatibility while improving consistency and performance.

## Implementation Guidelines

### Do's
- Always use `SnmpKit.SnmpLib.OID.string_to_list/1` for external input conversion
- Always use `SnmpKit.SnmpLib.OID.list_to_string/1` for final output conversion
- Keep function signatures clear about expected OID format
- Add `@spec` annotations to clarify OID types
- Use pattern matching to enforce list OIDs: `when is_list(oid)`

### Don'ts
- Don't add ad-hoc string/list conversion code
- Don't mix string and list handling in the same function
- Don't convert lists to strings for internal operations
- Don't change public API contracts that users depend on
- Don't skip input validation at API boundaries

### Error Handling
- Validate OID format at API boundaries using `SnmpKit.SnmpLib.OID.valid_oid?/1`
- Return clear error messages for invalid OID formats
- Maintain existing error types for backward compatibility

## Risk Mitigation

### Breaking Changes Risk
- **Risk**: Medium - Changes to internal APIs might break undocumented usage
- **Mitigation**: Maintain all public API signatures and behavior

### Performance Risk
- **Risk**: Low - Should improve performance by reducing conversions
- **Mitigation**: Measure before/after performance

### Regression Risk
- **Risk**: High - Complex changes across many modules
- **Mitigation**: Implement in phases with testing at each phase

## Success Criteria

1. All internal OID handling uses lists of integers
2. All public APIs accept both string and list formats
3. No unnecessary string/list conversions in internal operations
4. All existing tests continue to pass
5. Performance improvement measurable in bulk operations
6. Code is more maintainable with clear separation of concerns

## Estimated Timeline

- **Phase 1**: 2-3 days (critical foundation work)
- **Phase 2**: 2-3 days (internal operations)
- **Phase 3**: 1-2 days (advanced features)
- **Phase 4**: 1-2 days (testing and validation)

**Total**: 6-10 days of focused work

This cleanup is essential for the long-term maintainability and performance of the SNMP toolkit. The current mixed approach creates bugs, performance issues, and makes the code difficult to reason about.
