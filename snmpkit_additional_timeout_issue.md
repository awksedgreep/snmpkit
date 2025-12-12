# SnmpKit Bug: Per-Request Timeout Not Used in Walk Operations

**Issue**: When calling `walk_multi/2` with per-request timeouts, the per-request timeout is ignored and the global timeout is used instead.

**Location**: `lib/snmpkit/snmp_mgr/multi_v2.ex`

## Root Cause

In `execute_multi_operation/3` (line ~176):
```elixir
timeout = Keyword.get(opts, :timeout, @default_timeout)
```

This global timeout is passed to `execute_single_operation/2` (line ~186):
```elixir
fn request -> execute_single_operation(request, timeout) end
```

But in `execute_single_operation/2` (line ~266), this global timeout is used directly without checking for a per-request override:
```elixir
defp execute_single_operation(request, timeout) do
  ...
  :walk ->
    SnmpKit.SnmpMgr.V2Walk.walk(request, timeout)  # Uses global, ignores request.opts[:timeout]
```

The per-request opts ARE correctly merged in `normalize_requests/3` (line ~217):
```elixir
opts: Keyword.merge(global_opts, request_opts)
```

But `execute_single_operation` never reads `request.opts[:timeout]`.

## Reproduction

```elixir
# Per-request timeout of 30s is ignored, default 10s (or global) is used
SnmpKit.SnmpMgr.MultiV2.walk_multi([
  {"192.168.1.1", "1.3.6.1.2.1.31.1.1.1", [timeout: 30_000]}
])
```

## Fix Applied ✅

**Date:** 2024-01-XX  
**Status:** FIXED  

The issue has been resolved by modifying both `execute_single_operation/2` and `execute_single_request/2` in `lib/snmpkit/snmp_mgr/multi_v2.ex`.

**Changes Made:**

In `execute_single_operation/2` (line ~265):
```elixir
# Before:
defp execute_single_operation(request, timeout) do

# After:
defp execute_single_operation(request, global_timeout) do
  # Use per-request timeout if specified, otherwise use global timeout
  timeout = Keyword.get(request.opts, :timeout, global_timeout)
  
  # Validate timeout is a positive integer
  timeout = if is_integer(timeout) and timeout > 0, do: timeout, else: global_timeout
```

In `execute_single_request/2` (line ~291):
```elixir
# Before:
defp execute_single_request(request, timeout) do

# After:
defp execute_single_request(request, global_timeout) do
  # Use per-request timeout if specified, otherwise use global timeout
  timeout = Keyword.get(request.opts, :timeout, global_timeout)
  
  # Validate timeout is a positive integer
  timeout = if is_integer(timeout) and timeout > 0, do: timeout, else: global_timeout
```

**Verification:**
- All existing tests continue to pass
- New test suite added (`test/snmp_mgr/simple_per_request_timeout_test.exs`) verifying per-request timeout functionality
- Demonstration script confirms per-request timeouts are used correctly
- Edge cases (invalid timeout values) handled safely with fallback to global timeout

**Impact:**
This fix resolves the issue where per-request timeout options were ignored. Now:
- ✅ Per-request timeouts take precedence over global timeout
- ✅ Different requests can have different timeout values in the same call
- ✅ Global timeout is used as fallback when no per-request timeout specified  
- ✅ Works for all operation types: GET, GETBULK, WALK, and mixed operations
- ✅ Invalid timeout values safely fall back to global timeout

**Usage Example:**
```elixir
# Now works correctly - each request uses its specified timeout
SnmpKit.SnmpMgr.MultiV2.walk_multi([
  {"device1", "ifTable", [timeout: 30_000]},  # 30 second timeout
  {"device2", "ifTable", [timeout: 10_000]},  # 10 second timeout  
  {"device3", "ifTable"}                      # Uses global timeout
], timeout: 15_000)  # 15 second global timeout
```
