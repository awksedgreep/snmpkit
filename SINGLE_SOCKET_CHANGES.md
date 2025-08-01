# Single Socket Architecture Implementation

## Summary

Successfully updated SnmpKit's multi-target operations to use a single shared socket instead of creating individual sockets for each request. This provides better resource efficiency and enables proper request correlation via unique request IDs.

## Changes Made

### 1. Updated `multi.ex` Functions
- **Modified functions**: `get_multi/2`, `get_bulk_multi/2`, `walk_multi/2`, `walk_table_multi/2`, `execute_mixed/2`
- **Key changes**:
  - Removed `Task.async` approach with individual sockets
  - Integrated with `SnmpKit.SnmpMgr.Engine` for shared socket operations
  - Added request normalization for engine processing
  - Maintained backward compatibility for all return formats

### 2. Enhanced `engine.ex` for Shared Socket Support
- **Added to state**: `shared_socket`, `pending_requests`, `request_counter`
- **New functions**:
  - `send_snmp_request_shared/2` - Send requests via shared socket
  - `handle_udp_response_shared/5` - Handle responses on shared socket
  - `handle_snmp_response_shared/3` - Correlate responses to requests
  - `handle_request_timeout_shared/2` - Handle timeouts for shared socket
  - `find_request_by_ref/2` - Find requests by reference for correlation
  - `extract_response_data/2` - Format response data by request type

### 3. Request Correlation System
- **Sequential Request IDs**: Generated via `next_request_id/1` for better correlation
- **Pending Requests Map**: `%{request_id => request_info}` for tracking active requests
- **Response Routing**: Incoming UDP responses matched to waiting processes via request ID

### 4. Support for All Operation Types
- **GET operations**: Direct PDU building
- **GET_BULK operations**: Bulk request PDU building
- **WALK operations**: Implemented via GET_NEXT PDU building
- **WALK_TABLE operations**: Implemented via GET_NEXT PDU building

## Architecture Benefits

### Before (Individual Sockets)
```elixir
# Each request created its own socket
Task.async(fn -> 
  # Creates new socket
  SnmpKit.SnmpMgr.get(target, oid, opts)
end)
```

### After (Shared Socket)
```elixir
# Single socket shared across all requests
engine = get_or_start_engine()
request = %{type: :get, target: target, oid: oid, request_id: unique_id}
submit_request_to_engine(engine, request)
```

## Performance Improvements

1. **Resource Efficiency**: Single UDP socket vs. N sockets for N requests
2. **Better Correlation**: Sequential request IDs ensure proper response matching
3. **Centralized Management**: All requests managed by single engine process
4. **Reduced Overhead**: No task spawning for socket creation per request

## Backward Compatibility

✅ All existing function signatures maintained
✅ All return formats supported (`:list`, `:with_targets`, `:map`)
✅ All options preserved (`timeout`, `community`, `version`, etc.)
✅ Error handling behavior unchanged

## Testing

- All existing tests pass
- Multi-target operations work with shared socket
- Different return formats function correctly
- Error handling (timeouts, network failures) works as expected

## Usage Example

```elixir
# Works exactly the same as before
targets = [
  {"device1", "sysDescr.0"},
  {"device2", "sysUpTime.0"},
  {"device3", "ifNumber.0"}
]

# But now uses single socket internally
results = SnmpKit.SnmpMgr.Multi.get_multi(targets, 
  return_format: :with_targets,
  timeout: 5000
)
```

## Files Modified

- `lib/snmpkit/snmp_mgr/multi.ex` - Updated all multi functions
- `lib/snmpkit/snmp_mgr/engine.ex` - Enhanced for shared socket support
- `examples/single_socket_demo.exs` - Demo script
- `CLAUDE.md` - Updated architecture documentation