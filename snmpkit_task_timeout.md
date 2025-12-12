# Bug Report: MultiV2.walk_multi Task.async_stream timeout kills entire walk

## Summary

`SnmpKit.SnmpMgr.MultiV2.walk_multi/2` wraps the walk operation in `Task.async_stream` with a hard timeout that kills the entire walk, even when individual SNMP PDUs are responding successfully within their per-PDU timeout.

## Expected Behavior

The `:timeout` option should control the per-PDU timeout (how long to wait for each SNMP response). A walk of a large table should continue as long as individual PDUs respond within the timeout.

## Actual Behavior

The timeout is used for **both**:
1. Per-PDU timeout in `V2Walk.walk/2` (correct)
2. `Task.async_stream` `:timeout` option (kills entire walk)

For large SNMP tables that take many PDU round-trips, the walk succeeds for the first N PDUs, then the Task.async_stream timeout fires and kills the entire operation with `{:error, {:task_failed, :timeout}}`.

## Root Cause

In `lib/snmpkit/snmp_mgr/multi_v2.ex`:

```elixir
defp execute_multi_operation(targets_and_data, operation_type, opts) do
  timeout = Keyword.get(opts, :timeout, @default_timeout)
  
  results =
    normalized_requests
    |> Task.async_stream(
      fn request -> execute_single_operation(request, timeout) end,
      max_concurrency: max_concurrent,
      timeout: timeout + 1000,  # <-- THIS KILLS THE WHOLE WALK
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:task_failed, reason}}  # <-- Returns this on timeout
    end)

  results
end
```

The `Task.async_stream` timeout (line with `timeout: timeout + 1000`) is meant to be a safeguard, but for walk operations it's counter-productive. A walk may need 100+ PDU round-trips, each taking the full timeout, so the total walk time can be `N_pdus * timeout`.

## Reproduction

```elixir
# Walk a large SNMP table (e.g., ifXTable on a device with many interfaces)
# With default 10s timeout, walk fails even though device responds to each PDU in <1s

SnmpKit.SnmpMgr.MultiV2.walk_multi([{"10.48.8.2", "1.3.6.1.2.1.31.1.1", [community: "public"]}])
# => [{:error, {:task_failed, :timeout}}]

# But command line works fine (takes ~8-10 seconds for full walk):
# snmpbulkwalk -v2c -On -c public 10.48.8.2 .1.3.6.1.2.1.31.1.1
```

## Workaround

Call `V2Walk.walk/2` directly to bypass the Task.async_stream wrapper:

```elixir
request = %{
  target: "10.48.8.2",
  oid: "1.3.6.1.2.1.31.1.1",
  opts: [community: "public", max_repetitions: 40, version: :v2c]
}

# Timeout is now truly per-PDU
SnmpKit.SnmpMgr.V2Walk.walk(request, 30_000)
# => {:ok, [...varbinds...]}
```

## Suggested Fix

Option 1: Remove Task.async_stream timeout for walk operations (let per-PDU timeout handle it):

```elixir
def walk_multi(targets_and_oids, opts \\ []) do
  opts = Keyword.put_new(opts, :timeout, @default_timeout * 3)
  # Don't use Task.async_stream wrapper for walks - V2Walk handles timeouts
  execute_walk_operation(targets_and_oids, opts)
end
```

Option 2: Add a separate `:walk_timeout` option that defaults to `:infinity` for the Task wrapper:

```elixir
walk_timeout = Keyword.get(opts, :walk_timeout, :infinity)

Task.async_stream(..., timeout: walk_timeout, ...)
```

Option 3: Calculate Task timeout based on expected PDU count (less ideal, hard to estimate):

```elixir
# For walks, use a much longer Task timeout
task_timeout = if operation_type in [:walk, :walk_table], do: timeout * 100, else: timeout + 1000
```

## Environment

- SnmpKit version: 1.x (from deps)
- Elixir: 1.19.1
- OTP: 27

## Impact

This bug makes `walk_multi` unusable for large SNMP tables. Users must either:
1. Call `V2Walk.walk` directly (not documented as public API)
2. Use unreasonably high timeouts (defeats the purpose of per-PDU timeout)

## Fix Applied ✅

**Date:** 2024-01-XX  
**Status:** FIXED  

The issue has been resolved by implementing a simple, safe timeout strategy in `lib/snmpkit/snmp_mgr/multi_v2.ex`.

**Changes Made:**

1. **Walk operations use 20-minute maximum timeout**: Walk operations now use a fixed 20-minute timeout instead of the problematic `timeout + 1000` that killed long walks.

2. **Mixed operations detect walks**: The `execute_mixed/2` function detects when walks are present and uses 20-minute timeout, otherwise uses short timeout.

3. **Non-walk operations retain task timeout protection**: GET and GETBULK operations still use `timeout + 1000` as a safeguard against runaway tasks.

**Code Changes:**
```elixir
# Before (line ~181):
timeout: timeout + 1000,

# After (line ~181):  
timeout: if(operation_type in [:walk, :walk_table], do: 1_200_000, else: timeout + 1000),
```

**Safety & Simplicity:**
- **20-minute cap**: Generous enough for largest enterprise SNMP tables, short enough to prevent infinite hangs
- **No configuration needed**: Simple, fixed timeout that works for all realistic scenarios  
- **Backwards compatible**: Existing code works unchanged

**Verification:**
- All existing tests continue to pass
- New test suite verifies walk operations no longer fail with `{:task_failed, :timeout}`

**Impact:**
This fix resolves the core issue with a simple, safe approach:
- ✅ Walk operations can handle large enterprise tables
- ✅ No risk of infinite hangs (20-minute maximum)
- ✅ Per-PDU timeout still controls individual SNMP requests
- ✅ Simple solution - no complex configuration needed

**Example:**
```elixir
# This now works for large tables:
SnmpKit.SnmpMgr.MultiV2.walk_multi([
  {"10.48.8.2", "1.3.6.1.2.1.31.1.1", [community: "public"]}
])
# => [{:ok, [...hundreds of varbinds...]}] instead of [{:error, {:task_failed, :timeout}}]
```
