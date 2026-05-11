# SnmpKit Timeout Documentation

## Overview

SnmpKit uses separate per-PDU and whole-walk timeouts to handle SNMP operations safely and efficiently:

1. **PDU Timeout** - How long to wait for each individual SNMP packet response
2. **Walk Timeout** - Maximum time allowed for an entire walk operation

## PDU Timeout (`:timeout` parameter)

The `:timeout` parameter controls how long to wait for each individual SNMP PDU (Protocol Data Unit) response from the target device.

### Default Values
- **GET/GETBULK operations**: 10 seconds (10,000 ms)
- **Walk operations**: 30 seconds (30,000 ms) 
- **Table walk operations**: 50 seconds (50,000 ms)

### Behavior
- Applied to each individual SNMP packet sent to the device
- If a device doesn't respond within this time, that specific PDU times out
- For multi-PDU operations (walks), each PDU gets its own timeout
- In multi-target APIs, top-level `timeout:` is the default per-PDU timeout for each request

### Examples
```elixir
# Single PDU with 5-second timeout
SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0", timeout: 5_000)

# Walk where each GETBULK PDU has 15-second timeout
SnmpKit.SNMP.walk("192.168.1.1", "ifTable", timeout: 15_000)
```

## Retries (`:retries` parameter)

`retries:` controls how many additional attempts are made after a per-PDU timeout. A request with `timeout: 10_000, retries: 2` can wait up to about 30 seconds for that one PDU before returning `{:error, :timeout}`.

Retries are per PDU, not per walk. If a walk sends 100 GETBULK PDUs, each PDU gets its own timeout and retry budget.

## Walk Timeout (`:walk_timeout` parameter)

Walk timeouts protect against operations hanging indefinitely due to bugs, loops, or a device that stops making progress.

### Behavior
- `timeout:` applies to each individual GETBULK PDU during the walk
- `walk_timeout:` applies to the whole walk
- Defaults allow long-running table walks while still preventing infinite hangs
- User-specified `walk_timeout:` is capped internally to prevent runaway calls

## Walk Operations: Multi-PDU Behavior

Walk operations retrieve all OIDs under a root by sending multiple GETBULK requests:

### Timeline Example
```
Root OID: "1.3.6.1.2.1.2.2.1"  (ifTable)
PDU timeout: 10 seconds
Target has 50 interfaces

PDU 1: Get OIDs 1-30    → 10s timeout → Success
PDU 2: Get OIDs 31-60   → 10s timeout → Success  
PDU 3: Get OIDs 61-90   → 10s timeout → Success
...
Total time: ~50-100 seconds (varies by device response time)
Walk timeout: defaults to a long-running safety cap
```

### Why This Matters
- **Per-PDU timeout**: Fails a single request when the device does not answer
- **Walk timeout**: Fails the whole walk when the complete operation exceeds its safety cap

## Per-Request Timeout Override

Individual requests can override the default per-PDU timeout:

### Single Target Examples
```elixir
# This walk gets 30s per GETBULK PDU
SnmpKit.SNMP.walk("slow-device", "ifTable", timeout: 30_000)
```

### Multi-Target Examples
```elixir
# Different timeouts per device
MultiV2.walk_multi([
  {"fast-switch", "ifTable", [timeout: 5_000]},    # 5s per PDU for this target
  {"slow-router", "ifTable", [timeout: 30_000]},   # 30s per PDU for this target
  {"normal-device", "ifTable"}                     # Uses the call default
], timeout: 15_000)  # Default per-PDU timeout for requests without an override
```

## Common Timeout Scenarios

### Scenario 1: Fast Local Network
```elixir
# Devices respond quickly, use shorter timeouts for faster failure detection
opts = [timeout: 3_000]  # 3 seconds
```

### Scenario 2: Slow WAN Links
```elixir
# Devices over slow links need more time
opts = [timeout: 30_000]  # 30 seconds
```

### Scenario 3: Large Enterprise Tables
```elixir
# Large routing/interface tables need longer per-PDU timeouts
opts = [timeout: 45_000]  # 45 seconds per PDU
# walk_timeout bounds the total walk separately
```

### Scenario 4: Mixed Network Performance
```elixir
# Different devices have different performance characteristics
MultiV2.walk_multi([
  {"core-switch-1", "ifTable", [timeout: 10_000]},     # Fast core
  {"wan-router-1", "bgpRouteTable", [timeout: 60_000]}, # Slow WAN + large table
  {"access-switch-1", "ifTable", [timeout: 5_000]}      # Fast access
], timeout: 15_000)  # Default for devices without specific timeout
```

## Timeout Error Types

### PDU Timeout Errors
```elixir
{:error, :timeout}  # Individual PDU timed out
```

### Walk Timeout Errors
```elixir
{:error, :timeout}  # Whole walk exceeded walk_timeout
```

### Network Errors
```elixir
{:error, {:network_error, :hostname_resolution_failed}}
{:error, {:network_error, :connection_refused}}
```

## Troubleshooting Timeout Issues

### Problem: Operations failing with `:timeout`
**Solution**: Increase PDU timeout for slow devices/networks
```elixir
# Instead of default 10s
SnmpKit.SNMP.walk(target, oid, timeout: 30_000)
```

### Problem: Large table walks failing  
**Check**: Is one PDU timing out, or is the whole walk exceeding `walk_timeout`?
- Single PDU timeout: increase `timeout:` or lower `max_repetitions:`
- Whole walk timeout: increase `walk_timeout:` or narrow the subtree

### Problem: Mixed performance in multi-target operations
**Solution**: Use per-request timeout overrides
```elixir
MultiV2.walk_multi([
  {"fast-device", oid, [timeout: 5_000]},
  {"slow-device", oid, [timeout: 30_000]}
])
```

## API Reference Summary

### Core Functions
- `SnmpKit.SNMP.get(target, oid, opts)` - `:timeout` = PDU timeout
- `SnmpKit.SNMP.walk(target, oid, opts)` - `:timeout` = per-PDU timeout  
- `SnmpKit.SNMP.get_bulk(target, oid, opts)` - `:timeout` = PDU timeout

### Multi-Target Functions
- `MultiV2.get_multi(targets, opts)` - Top-level `timeout:` is the default per-PDU timeout
- `MultiV2.walk_multi(targets, opts)` - Top-level `timeout:` is the default per-PDU timeout; `walk_timeout:` bounds each complete walk
- Per-request: `{target, oid, [timeout: ms]}` - Override for specific request

### Timeout Parameters
- **Call default**: `timeout: milliseconds` in function options
- **Per-request**: `timeout: milliseconds` in individual request options
- **Walk cap**: `walk_timeout: milliseconds` in function or request options
- **Validation**: Non-positive values fall back to the call default

## Migration Notes

### From Older Versions
If upgrading from versions with timeout issues:
- ✅ Existing timeout parameters work unchanged
- ✅ Walk operations no longer fail prematurely  
- ✅ Per-request timeouts now work as documented
- ℹ️ No API changes required

### Best Practices
1. **Start with defaults** - Work for most scenarios
2. **Measure actual response times** - Set timeouts based on real network behavior
3. **Use per-request overrides** - For mixed-performance environments  
4. **Monitor for timeout errors** - Adjust timeouts based on operational data
