# SnmpKit Examples

This directory contains practical examples demonstrating SnmpKit's features and capabilities.

## Quick Start

If you're new to SnmpKit, start with:

1. **[getting_started.exs](getting_started.exs)** - Comprehensive introduction to all major features
2. **[unified_api_demo.exs](unified_api_demo.exs)** - Overview of the unified API design

## Examples Overview

### Basic Usage
- **[getting_started.exs](getting_started.exs)** - Complete introduction with simulated device
- **[unified_api_demo.exs](unified_api_demo.exs)** - Demonstrates the clean, organized API

### Device Simulation
- **[cable_modem_simulation.exs](cable_modem_simulation.exs)** - DOCSIS cable modem simulation
- **[quick_cable_modem.exs](quick_cable_modem.exs)** - Simple cable modem example
- **[cable_modem_profile.json](cable_modem_profile.json)** - Device profile configuration

### DOCSIS/Cable Networks
- **[docsis_mib_example.exs](docsis_mib_example.exs)** - Working with DOCSIS MIBs

## Running Examples

### Prerequisites

Make sure you have Elixir 1.14+ installed:

```bash
elixir --version
```

### Running Individual Examples

Most examples are self-contained and can be run directly:

```bash
# Run the getting started example
elixir examples/getting_started.exs

# Run the unified API demo
elixir examples/unified_api_demo.exs

# Run the cable modem simulation
elixir examples/cable_modem_simulation.exs
```

### Adding SnmpKit to Your Project

Add SnmpKit to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:snmpkit, "~> 1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Example Categories

### 🚀 Getting Started
Perfect for newcomers to SnmpKit or SNMP in general.

**[getting_started.exs](getting_started.exs)**
- Creates a simulated SNMP device
- Demonstrates GET, WALK, and bulk operations
- Shows MIB resolution and reverse lookup
- Includes error handling examples
- Performance timing demonstrations

### 🎯 Unified API
Shows the clean, context-based API design.

**[unified_api_demo.exs](unified_api_demo.exs)**
- `SnmpKit.SNMP` for protocol operations
- `SnmpKit.MIB` for MIB management
- `SnmpKit.Sim` for device simulation
- Direct access functions for convenience

### 🖥️ Device Simulation
Learn how to create realistic SNMP devices for testing.

**[cable_modem_simulation.exs](cable_modem_simulation.exs)**
- Comprehensive DOCSIS cable modem simulation
- Realistic device behavior and responses
- Integration with testing frameworks

**[quick_cable_modem.exs](quick_cable_modem.exs)**
- Simple cable modem setup
- Quick testing scenarios
- Basic DOCSIS operations

### 📡 DOCSIS/Cable Networks
Specialized examples for cable network management.

**[docsis_mib_example.exs](docsis_mib_example.exs)**
- Loading DOCSIS MIBs
- Cable modem status monitoring
- Signal quality measurements
- Upstream/downstream channel information

### ⚡ High-Performance Polling
Examples for scalable, high-concurrency SNMP operations.

**[scalable_high_concurrency_polling.exs](scalable_high_concurrency_polling.exs)**
- Poll thousands of devices efficiently
- Demonstrates new MultiV2 architecture
- Eliminates GenServer bottlenecks
- Cable modem fleet management patterns
- Performance benchmarking and monitoring

## Code Patterns

### Basic SNMP Operations

```elixir
# Simple GET (enriched map)
{:ok, %{formatted: description}} = SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")

# Walk a subtree (list of enriched maps)
{:ok, interfaces} = SnmpKit.SNMP.walk("192.168.1.1", "ifTable")

# Bulk operations for efficiency (list of enriched maps)
{:ok, results} = SnmpKit.SNMP.bulk_walk("192.168.1.1", "system")
```

### MIB Operations

```elixir
# Resolve OID names
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")

# Reverse lookup
{:ok, name} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])

# Tree navigation
{:ok, children} = SnmpKit.MIB.children([1, 3, 6, 1, 2, 1, 1])
```

### Device Simulation

```elixir
# Create device profile
profile = %{
  name: "Test Device",
  objects: %{
    [1, 3, 6, 1, 2, 1, 1, 1, 0] => "Test Device Description"
  }
}

# Start simulated device
{:ok, device} = SnmpKit.Sim.start_device(profile, port: 1161)
```

## Testing Integration

Many examples show how to integrate SnmpKit with testing frameworks:

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  
  setup do
    # Start simulated device for testing
    {:ok, profile} = load_device_profile(:router)
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: 30161)
    
    %{target: "127.0.0.1:30161", device: device}
  end
  
  test "can query device", %{target: target} do
{:ok, %{formatted: description}} = SnmpKit.SNMP.get(target, "sysDescr.0")
    assert String.contains?(description, "Router")
  end
end
```

## Performance Examples

Several examples include performance measurements and optimization techniques:

```elixir
# Measure operation timing
{time, {:ok, results}} = :timer.tc(fn ->
  SnmpKit.SNMP.walk("192.168.1.1", "interfaces")
end)

IO.puts("Walk completed in #{time/1000}ms")

# Concurrent operations
tasks = for target <- targets do
  Task.async(fn -> SnmpKit.SNMP.get(target, "sysDescr.0") end)
end

results = Task.await_many(tasks, 10_000)
```

## Error Handling Patterns

Examples demonstrate robust error handling:

```elixir
case SnmpKit.SNMP.get(target, oid) do
  {:ok, %{value: value}} -> 
    process_value(value)
  {:error, :timeout} ->
    Logger.warn("Device #{target} timeout")
    {:error, :device_unreachable}
  {:error, :no_such_name} ->
    Logger.warn("OID #{oid} not found on #{target}")
    {:error, :oid_not_found}
  {:error, reason} ->
    Logger.error("SNMP error: #{inspect(reason)}")
    {:error, reason}
end
```

## Advanced Features

### Streaming Large Results

```elixir
# Stream large walks to avoid memory issues
SnmpKit.SNMP.walk_stream("192.168.1.1", "largeTable")
|> Stream.take(1000)
|> Enum.each(&process_entry/1)
```

### Circuit Breakers

```elixir
# Automatic failure handling
{:ok, result} = SnmpKit.SNMP.with_circuit_breaker("unreliable.host", fn ->
  SnmpKit.SNMP.get("unreliable.host", "sysDescr.0")
end)
```

### Custom Device Profiles

```elixir
# Load device behavior from files
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(
  :custom_device,
  {:walk_file, "priv/walks/device.walk"}
)
```

## Getting Help

- **Documentation**: [https://hexdocs.pm/snmpkit](https://hexdocs.pm/snmpkit)
- **Interactive Tour**: [../livebooks/snmpkit_tour.livemd](../livebooks/snmpkit_tour.livemd)
- **Guides**: [../docs/](../docs/)
- **Issues**: [GitHub Issues](https://github.com/awksedgreep/snmpkit/issues)

## Contributing Examples

We welcome contributions of new examples! Please:

1. Follow the existing code style
2. Include comprehensive comments
3. Add error handling
4. Test your example before submitting
5. Update this README if adding new categories

See [../CONTRIBUTING.md](../CONTRIBUTING.md) for detailed guidelines.

---

**Happy SNMP monitoring with SnmpKit!** 🚀