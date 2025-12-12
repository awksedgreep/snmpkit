# SnmpKit Timeout Documentation

## Overview

SnmpKit uses two distinct types of timeouts to handle SNMP operations safely and efficiently:

1. **PDU Timeout** - How long to wait for each individual SNMP packet response
2. **Task Timeout** - Maximum time allowed for entire operations to prevent hangs

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

### Examples
```elixir
# Single PDU with 5-second timeout
SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0", timeout: 5_000)

# Walk where each GETBULK PDU has 15-second timeout
SnmpKit.SNMP.walk("192.168.1.1", "ifTable", timeout: 15_000)
```

## Task Timeout (internal protection)

Task timeouts protect against operations hanging indefinitely due to bugs or network issues.

### Behavior by Operation Type

#### GET/GETBULK Operations
- **Task timeout**: `PDU_timeout + 1000ms`
- **Purpose**: Quick safeguard against runaway single-PDU operations
- **Example**: 10s PDU timeout → 11s task timeout

#### Walk Operations  
- **Task timeout**: 20 minutes (1,200,000 ms)
- **Purpose**: Allow large table walks while preventing infinite hangs
- **Rationale**: Large tables may need 100+ PDUs × 30s each = substantial time

#### Mixed Operations
- **Task timeout**: 20 minutes if any walks present, otherwise `PDU_timeout + 1000ms`
- **Purpose**: Apply appropriate timeout based on operation mix

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
Task timeout: 20 minutes (allows operation to complete)
```

### Why This Matters
- **Before timeout fixes**: Operations failed after ~11 seconds regardless of PDU success
- **After timeout fixes**: Operations can run up to 20 minutes as long as individual PDUs respond

## Per-Request Timeout Override

Individual requests can override the global timeout:

### Single Target Examples
```elixir
# Global 10s timeout, but this device gets 30s
SnmpKit.SNMP.walk("slow-device", "ifTable", timeout: 30_000)
```

### Multi-Target Examples
```elixir
# Different timeouts per device
MultiV2.walk_multi([
  {"fast-switch", "ifTable", [timeout: 5_000]},    # 5s per PDU
  {"slow-router", "ifTable", [timeout: 30_000]},   # 30s per PDU  
  {"normal-device", "ifTable"}                     # Uses global timeout
], timeout: 15_000)  # Global: 15s per PDU
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
# Task timeout automatically allows up to 20 minutes total
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

### Task Timeout Errors (should be rare after fixes)
```elixir
{:error, {:task_failed, :timeout}}  # Task killed by internal timeout
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
**Check**: Are you getting `{:task_failed, :timeout}` or `:timeout`?
- `{:task_failed, :timeout}`: Internal task timeout (should be fixed)
- `:timeout`: Individual PDU timeout (increase PDU timeout)

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
- `MultiV2.get_multi(targets, opts)` - Global PDU timeout
- `MultiV2.walk_multi(targets, opts)` - Global per-PDU timeout
- Per-request: `{target, oid, [timeout: ms]}` - Override for specific request

### Timeout Parameters
- **Global**: `timeout: milliseconds` in function options
- **Per-request**: `timeout: milliseconds` in individual request options
- **Validation**: Non-positive values fall back to global timeout
- **Task protection**: Automatic, no user configuration needed

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