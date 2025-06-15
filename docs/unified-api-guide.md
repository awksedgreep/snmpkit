# SnmpKit Unified API Guide

*A comprehensive guide to SnmpKit's new unified API design*

## 🎯 Overview

SnmpKit v0.2.0 introduces a **unified API** that organizes all functionality into logical, context-based modules. This design eliminates naming conflicts, improves discoverability, and provides a cleaner developer experience while maintaining 100% backward compatibility.

## 🏗️ API Architecture

### Context-Based Modules

| Module | Purpose | Functions |
|--------|---------|-----------|
| `SnmpKit.SNMP` | SNMP protocol operations | get, walk, bulk, set, multi-target, streaming |
| `SnmpKit.MIB` | MIB management | resolve, compile, load, tree navigation |
| `SnmpKit.Sim` | Device simulation | start devices, create populations, testing |
| `SnmpKit` | Direct access | Common operations for convenience |

### Design Benefits

✅ **No Naming Conflicts** - Context prevents function name collisions  
✅ **Improved Discoverability** - Related functions grouped logically  
✅ **Clear Documentation** - Module boundaries define responsibilities  
✅ **Backward Compatibility** - Existing code continues to work  
✅ **Flexible Usage** - Choose namespaced or direct access as preferred  

## 📡 SNMP Operations (`SnmpKit.SNMP`)

### Basic Operations

```elixir
# GET operations
{:ok, value} = SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")
{:ok, {oid, type, value}} = SnmpKit.SNMP.get_with_type("192.168.1.1", "sysUpTime.0")

# SET operations (to simulation devices)
:ok = SnmpKit.SNMP.set("127.0.0.1:1161", "sysContact.0", "admin@example.com")

# WALK operations
{:ok, results} = SnmpKit.SNMP.walk("192.168.1.1", "system")
{:ok, table} = SnmpKit.SNMP.get_table("192.168.1.1", "ifTable")
```

### Bulk Operations

```elixir
# Efficient bulk retrieval
{:ok, results} = SnmpKit.SNMP.get_bulk("192.168.1.1", "interfaces", max_repetitions: 10)

# Adaptive bulk walking (auto-optimizes)
{:ok, results} = SnmpKit.SNMP.adaptive_walk("192.168.1.1", "interfaces")

# Traditional bulk walk
{:ok, results} = SnmpKit.SNMP.bulk_walk("192.168.1.1", "system")
```

### Multi-Target Operations

```elixir
# Query multiple devices simultaneously
targets_and_oids = [
  {"router1.example.com", "sysDescr.0"},
  {"switch1.example.com", "sysUpTime.0"},
  {"ap1.example.com", "sysLocation.0"}
]

{:ok, results} = SnmpKit.SNMP.get_multi(targets_and_oids)

# Bulk operations across multiple targets
{:ok, results} = SnmpKit.SNMP.walk_multi([
  {"host1", "interfaces"},
  {"host2", "system"}
])
```

### Streaming Operations

```elixir
# Memory-efficient streaming for large datasets
stream = SnmpKit.SNMP.walk_stream("192.168.1.1", "interfaces")
results = stream |> Stream.take(1000) |> Enum.to_list()

# Table streaming
table_stream = SnmpKit.SNMP.table_stream("192.168.1.1", "ifTable")
```

### Async Operations

```elixir
# Non-blocking operations
task = SnmpKit.SNMP.get_async("192.168.1.1", "sysDescr.0")
{:ok, result} = Task.await(task, 5000)

# Bulk async operations
task = SnmpKit.SNMP.get_bulk_async("192.168.1.1", "interfaces")
```

### Pretty Formatting

```elixir
# Human-readable output
{:ok, formatted} = SnmpKit.SNMP.get_pretty("192.168.1.1", "sysUpTime.0")
# Returns: "12 days, 4:32:10.45"

{:ok, formatted_walk} = SnmpKit.SNMP.walk_pretty("192.168.1.1", "system")
# Returns: [{"sysDescr.0", "Linux router"}, {"sysUpTime.0", "12 days, 4:32:10.45"}]

{:ok, formatted_bulk} = SnmpKit.SNMP.bulk_walk_pretty("192.168.1.1", "interfaces")
```

### Advanced Features

```elixir
# Engine management for performance
{:ok, _engine} = SnmpKit.SNMP.start_engine()
{:ok, stats} = SnmpKit.SNMP.get_engine_stats()

# Circuit breaker for reliability
{:ok, result} = SnmpKit.SNMP.with_circuit_breaker("unreliable.host", fn ->
  SnmpKit.SNMP.get("unreliable.host", "sysDescr.0")
end)

# Performance analysis
{:ok, analysis} = SnmpKit.SNMP.analyze_table(table_data)
{:ok, benchmark} = SnmpKit.SNMP.benchmark_device("192.168.1.1", "system")

# Metrics recording
SnmpKit.SNMP.record_metric(:counter, :requests_total, 1, %{host: "router1"})
```

## 📚 MIB Operations (`SnmpKit.MIB`)

### OID Resolution

```elixir
# Name to OID resolution
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
# Returns: [1, 3, 6, 1, 2, 1, 1, 1, 0]

{:ok, oid} = SnmpKit.MIB.resolve("ifInOctets.1")
# Returns: [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1]

# Group resolution
{:ok, oid} = SnmpKit.MIB.resolve("system")
# Returns: [1, 3, 6, 1, 2, 1, 1]

# Reverse lookup
{:ok, name} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
# Returns: "sysDescr.0"
```

### MIB Tree Navigation

```elixir
# Get children of an OID node
{:ok, children} = SnmpKit.MIB.children([1, 3, 6, 1, 2, 1, 1])
# Returns: [[1, 3, 6, 1, 2, 1, 1, 1], [1, 3, 6, 1, 2, 1, 1, 2], ...]

# Get parent of an OID
{:ok, parent} = SnmpKit.MIB.parent([1, 3, 6, 1, 2, 1, 1, 1, 0])
# Returns: [1, 3, 6, 1, 2, 1, 1, 1]

# Walk MIB tree
{:ok, tree} = SnmpKit.MIB.walk_tree([1, 3, 6, 1, 2, 1, 1])
```

### MIB Compilation and Loading

```elixir
# High-level compilation (recommended)
{:ok, compiled} = SnmpKit.MIB.compile("MY-ENTERPRISE-MIB.mib")
{:ok, _} = SnmpKit.MIB.load(compiled)

# Compile entire directory
{:ok, results} = SnmpKit.MIB.compile_dir("mibs/")

# Low-level compilation (advanced)
{:ok, mib} = SnmpKit.MIB.compile_raw("MY-MIB.mib")
{:ok, _} = SnmpKit.MIB.load_compiled("compiled_mib.bin")

# Compile multiple files
{:ok, compiled_mibs} = SnmpKit.MIB.compile_all(["mib1.mib", "mib2.mib"])
```

### MIB Parsing and Analysis

```elixir
# Parse MIB file
{:ok, parsed} = SnmpKit.MIB.parse_mib_file("CUSTOM-MIB.mib")

# Parse MIB content string
mib_content = File.read!("MY-MIB.mib")
{:ok, parsed} = SnmpKit.MIB.parse_mib_content(mib_content)

# Enhanced resolution with custom MIBs
{:ok, oid} = SnmpKit.MIB.resolve_enhanced("customObject.0")

# Integrate compilation and parsing
{:ok, integrated} = SnmpKit.MIB.load_and_integrate_mib("ENTERPRISE-MIB.mib")
```

### Standard MIBs

```elixir
# Load built-in standard MIBs
:ok = SnmpKit.MIB.load_standard_mibs()

# Start MIB registry (for advanced usage)
{:ok, _pid} = SnmpKit.MIB.start_link()
```

## 🧪 Device Simulation (`SnmpKit.Sim`)

### Single Device Simulation

```elixir
# Load a device profile
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(
  :cable_modem,
  {:walk_file, "priv/walks/cable_modem.walk"}
)

# Start simulated device
{:ok, device} = SnmpKit.Sim.start_device(profile, [
  port: 1161,
  community: "public"
])

# Device will respond to SNMP queries on localhost:1161
{:ok, description} = SnmpKit.SNMP.get("127.0.0.1:1161", "sysDescr.0")
```

### Population Simulation

```elixir
# Create multiple devices for testing
device_configs = [
  %{type: :cable_modem, port: 30001, community: "public"},
  %{type: :switch, port: 30002, community: "public"},
  %{type: :router, port: 30003, community: "private"}
]

{:ok, devices} = SnmpKit.Sim.start_device_population(device_configs)

# Query the simulated devices
{:ok, cm_desc} = SnmpKit.SNMP.get("127.0.0.1:30001", "sysDescr.0")
{:ok, switch_desc} = SnmpKit.SNMP.get("127.0.0.1:30002", "sysDescr.0")
```

### Testing Integration

```elixir
defmodule MyNetworkTest do
  use ExUnit.Case
  
  setup do
    # Start mock devices for each test
    {:ok, cable_modem_profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:cable_modem)
    {:ok, router_profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    
    {:ok, cm} = SnmpKit.Sim.start_device(cable_modem_profile, port: 1161)
    {:ok, router} = SnmpKit.Sim.start_device(router_profile, port: 1162)
    
    %{
      cable_modem: "127.0.0.1:1161",
      router: "127.0.0.1:1162"
    }
  end
  
  test "can monitor cable modem", %{cable_modem: cm_target} do
    {:ok, signal_noise} = SnmpKit.SNMP.get(cm_target, "docsIfSigQSignalNoise.1")
    assert is_integer(signal_noise)
  end
  
  test "can get interface statistics", %{router: router_target} do
    {:ok, interfaces} = SnmpKit.SNMP.get_table(router_target, "ifTable")
    assert length(interfaces) > 0
  end
end
```

## 🎯 Direct Access (`SnmpKit`)

For convenience and backward compatibility, common operations are available directly:

```elixir
# These are equivalent to their SnmpKit.SNMP.* counterparts
{:ok, value} = SnmpKit.get("192.168.1.1", "sysDescr.0")
{:ok, results} = SnmpKit.walk("192.168.1.1", "system")
:ok = SnmpKit.set("127.0.0.1:1161", "sysContact.0", "admin@example.com")

# MIB resolution
{:ok, oid} = SnmpKit.resolve("sysDescr.0")
```

## 🔄 Migration Guide

### From Direct Module Usage

```elixir
# Before (still works)
{:ok, value} = SnmpKit.SnmpMgr.get("host", "oid")
{:ok, oid} = SnmpKit.SnmpMgr.MIB.resolve("name")

# After (recommended)
{:ok, value} = SnmpKit.SNMP.get("host", "oid")
{:ok, oid} = SnmpKit.MIB.resolve("name")

# Or use direct access
{:ok, value} = SnmpKit.get("host", "oid")
{:ok, oid} = SnmpKit.resolve("name")
```

### Gradual Migration Strategy

1. **Phase 1**: Start using unified API for new code
2. **Phase 2**: Gradually update existing code module by module
3. **Phase 3**: Adopt consistent style across codebase

### Import Strategy

```elixir
# Option 1: Import specific modules
alias SnmpKit.{SNMP, MIB, Sim}

{:ok, value} = SNMP.get("host", "oid")
{:ok, oid} = MIB.resolve("name")

# Option 2: Use fully qualified names
{:ok, value} = SnmpKit.SNMP.get("host", "oid")
{:ok, oid} = SnmpKit.MIB.resolve("name")

# Option 3: Direct access for simple operations
{:ok, value} = SnmpKit.get("host", "oid")
{:ok, oid} = SnmpKit.resolve("name")
```

## 📚 Function Reference Quick Guide

### Most Common Operations

| Task | Function | Example |
|------|----------|---------|
| Get single value | `SnmpKit.SNMP.get/3` | `get("host", "sysDescr.0")` |
| Walk OID tree | `SnmpKit.SNMP.walk/3` | `walk("host", "system")` |
| Get table | `SnmpKit.SNMP.get_table/3` | `get_table("host", "ifTable")` |
| Resolve OID name | `SnmpKit.MIB.resolve/1` | `resolve("sysDescr.0")` |
| Start mock device | `SnmpKit.Sim.start_device/2` | `start_device(profile, port: 1161)` |

### Performance Operations

| Task | Function | Example |
|------|----------|---------|
| Bulk retrieval | `SnmpKit.SNMP.get_bulk/3` | `get_bulk("host", "interfaces")` |
| Multi-target query | `SnmpKit.SNMP.get_multi/2` | `get_multi([{"h1", "oid1"}, {"h2", "oid2"}])` |
| Streaming walk | `SnmpKit.SNMP.walk_stream/3` | `walk_stream("host", "large_table")` |
| Adaptive walk | `SnmpKit.SNMP.adaptive_walk/3` | `adaptive_walk("host", "interfaces")` |

### Advanced Operations

| Task | Function | Example |
|------|----------|---------|
| Circuit breaker | `SnmpKit.SNMP.with_circuit_breaker/3` | `with_circuit_breaker("host", fn -> ... end)` |
| Engine stats | `SnmpKit.SNMP.get_engine_stats/1` | `get_engine_stats()` |
| MIB compilation | `SnmpKit.MIB.compile/2` | `compile("MY-MIB.mib")` |
| Tree navigation | `SnmpKit.MIB.children/1` | `children([1,3,6,1,2,1,1])` |

## 🚀 Best Practices

### 1. Choose the Right API Level

```elixir
# For simple scripts and convenience
{:ok, value} = SnmpKit.get("host", "oid")

# For applications with multiple SNMP operations
alias SnmpKit.SNMP
{:ok, value} = SNMP.get("host", "oid")
{:ok, table} = SNMP.get_table("host", "ifTable")

# For complex applications
defmodule MyMonitor do
  alias SnmpKit.{SNMP, MIB, Sim}
  
  def monitor_device(host) do
    with {:ok, description} <- SNMP.get(host, "sysDescr.0"),
         {:ok, interfaces} <- SNMP.get_table(host, "ifTable") do
      %{description: description, interfaces: interfaces}
    end
  end
end
```

### 2. Use Appropriate Operations for Scale

```elixir
# For single values
{:ok, value} = SnmpKit.SNMP.get("host", "oid")

# For multiple values from same host
{:ok, results} = SnmpKit.SNMP.walk("host", "system")

# For multiple hosts
{:ok, results} = SnmpKit.SNMP.get_multi([{"h1", "oid"}, {"h2", "oid"}])

# For large datasets
stream = SnmpKit.SNMP.walk_stream("host", "large_table")
```

### 3. Handle Errors Gracefully

```elixir
case SnmpKit.SNMP.get("host", "oid", timeout: 1000) do
  {:ok, value} -> 
    process_value(value)
  {:error, :timeout} -> 
    log_timeout_error("host")
  {:error, reason} -> 
    log_snmp_error("host", reason)
end
```

### 4. Use Mock Devices for Testing

```elixir
# In test setup
setup do
  {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:generic_device)
  {:ok, _device} = SnmpKit.Sim.start_device(profile, port: 1161)
  %{target: "127.0.0.1:1161"}
end

test "my network function", %{target: target} do
  # Test against mock device
  result = my_network_function(target)
  assert result.status == :ok
end
```

## 🎉 Conclusion

The unified API makes SnmpKit more approachable for new users while maintaining all the power and flexibility for advanced use cases. Choose the approach that best fits your needs:

- **Direct access** (`SnmpKit.*`) for simple operations
- **Namespaced modules** (`SnmpKit.SNMP.*`) for organized applications  
- **Mixed approach** based on context and preference

All approaches provide the same functionality with 100% backward compatibility.

Happy SNMP monitoring! 🚀