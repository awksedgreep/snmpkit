# SnmpKit 🚀

IMPORTANT: Breaking changes in 1.0
- Unified enriched map results across all operations: `%{name?, oid, type, value, formatted?}`
- `include_names` and `include_formatted` default to true; disable per call or globally
- Pretty helpers return enriched maps (with type and raw value retained)
- Removed `get_with_type/3` and `get_next_with_type/3`

[![Hex.pm](https://img.shields.io/hexpm/v/snmpkit.svg)](https://hex.pm/packages/snmpkit)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snmpkit)
[![License](https://img.shields.io/github/license/awksedgreep/snmpkit.svg)](LICENSE)
[![Build Status](https://img.shields.io/github/workflow/status/awksedgreep/snmpkit/CI)](https://github.com/awksedgreep/snmpkit/actions)

**A modern, comprehensive SNMP toolkit for Elixir - featuring a unified API, pure Elixir implementation, and powerful device simulation.**

SnmpKit is a complete SNMP (Simple Network Management Protocol) solution built from the ground up in pure Elixir. It provides a clean, organized API for SNMP operations, MIB management, and realistic device simulation - perfect for network monitoring, testing, and development.

## ✨ Key Features

- 🎯 **Unified API** - Clean, context-based modules (`SnmpKit.SNMP`, `SnmpKit.MIB`, `SnmpKit.Sim`)
- 🧬 **Pure Elixir Implementation** - No Erlang SNMP dependencies
- 📋 **Advanced MIB Support** - Native parsing, compilation, and object resolution
- 🖥️ **Realistic Device Simulation** - Create SNMP devices for testing and development
- ⚡ **High Performance** - Optimized for large-scale operations and concurrent requests
- 🧪 **Testing Friendly** - Comprehensive test helpers and simulated devices
- 🔧 **Modern Architecture** - GenServer patterns, supervision trees, circuit breakers
- 📊 **Enterprise Ready** - DOCSIS, standard MIBs, and custom implementations
- 🚀 **Zero Warnings** - Clean, production-ready codebase

## 🚀 Quick Start

### Installation

Add `snmpkit` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:snmpkit, "~> 1.0"}
  ]
end
```

### Unified API Examples

SnmpKit provides a clean, organized API through context-based modules:

#### 📡 SNMP Operations (`SnmpKit.SNMP`)

```elixir
# Basic SNMP operations
{:ok, %{formatted: description}} = SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")
{:ok, %{value: uptime}} = SnmpKit.SNMP.get("192.168.1.1", "sysUpTime.0")

# Walk operations
{:ok, system_info} = SnmpKit.SNMP.walk("192.168.1.1", "system")
{:ok, interface_table} = SnmpKit.SNMP.get_table("192.168.1.1", "ifTable")

# Bulk operations for efficiency
{:ok, results} = SnmpKit.SNMP.bulk_walk("192.168.1.1", "interfaces")

# Multi-target operations
{:ok, results} = SnmpKit.SNMP.get_multi([
  {"host1", "sysDescr.0"},
  {"host2", "sysUpTime.0"},
  {"host3", "ifInOctets.1"}
])

# Pretty formatting (enriched map with formatted)
{:ok, %{formatted: formatted}} = SnmpKit.SNMP.get_pretty("192.168.1.1", "sysUpTime.0")
# Returns: "12 days, 4:32:10.45"

# Async operations
task = SnmpKit.SNMP.get_async("192.168.1.1", "sysDescr.0")
{:ok, result} = Task.await(task)
```

#### 📚 MIB Operations (`SnmpKit.MIB`)

```elixir
# OID name resolution
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
# Returns: [1, 3, 6, 1, 2, 1, 1, 1, 0]

# Reverse lookup
{:ok, name} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
# Returns: "sysDescr.0"

# MIB compilation and loading
{:ok, compiled} = SnmpKit.MIB.compile("MY-CUSTOM-MIB.mib")
{:ok, _} = SnmpKit.MIB.load(compiled)

# Tree navigation
{:ok, children} = SnmpKit.MIB.children([1, 3, 6, 1, 2, 1, 1])
{:ok, parent} = SnmpKit.MIB.parent([1, 3, 6, 1, 2, 1, 1, 1, 0])
```

#### 🧪 Device Simulation (`SnmpKit.Sim`)

```elixir
# Load a device profile
{:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(
  :cable_modem,
  {:walk_file, "priv/walks/cable_modem.walk"}
)

# Start a simulated device
{:ok, device} = SnmpKit.Sim.start_device(profile, port: 1161)

# Create a population of devices for testing
device_configs = [
  %{type: :cable_modem, port: 30001, community: "public"},
  %{type: :switch, port: 30002, community: "public"},
  %{type: :router, port: 30003, community: "private"}
]

{:ok, devices} = SnmpKit.Sim.start_device_population(device_configs)
```

#### 🎯 Direct Access (Backward Compatibility)

For convenience, common operations are also available directly:

```elixir
# These work the same as their SnmpKit.SNMP.* equivalents
{:ok, value} = SnmpKit.get("192.168.1.1", "sysDescr.0")
{:ok, results} = SnmpKit.walk("192.168.1.1", "system")

# MIB resolution
{:ok, oid} = SnmpKit.resolve("sysDescr.0")
```

### Advanced Features

#### Engine Management and Performance

```elixir
# Start the SNMP engine for advanced features
{:ok, _engine} = SnmpKit.SNMP.start_engine()

# Get performance statistics
{:ok, stats} = SnmpKit.SNMP.get_engine_stats()

# Batch operations for efficiency
requests = [
  %{type: :get, target: "host1", oid: "sysDescr.0"},
  %{type: :walk, target: "host2", oid: "interfaces"}
]
{:ok, results} = SnmpKit.SNMP.engine_batch(requests)

# Circuit breaker for reliability
{:ok, result} = SnmpKit.SNMP.with_circuit_breaker("unreliable.host", fn ->
  SnmpKit.SNMP.get("unreliable.host", "sysDescr.0")
end)
```

#### Streaming and Large-Scale Operations

```elixir
# Stream large walks to avoid memory issues
stream = SnmpKit.SNMP.walk_stream("192.168.1.1", "interfaces")
stream
|> Stream.take(1000)
|> Enum.to_list()

# Adaptive bulk operations that optimize themselves
{:ok, results} = SnmpKit.SNMP.adaptive_walk("192.168.1.1", "interfaces")

# Performance benchmarking
{:ok, benchmark} = SnmpKit.SNMP.benchmark_device("192.168.1.1", "system")
```

## 🏗️ Architecture

SnmpKit is organized into logical, discoverable modules:

- **`SnmpKit.SNMP`** - Complete SNMP protocol operations
  - Basic operations: get, set, walk, bulk
  - Advanced features: streaming, async, multi-target
  - Performance tools: engine, circuit breaker, metrics
  - Pretty formatting and analysis

- **`SnmpKit.MIB`** - Comprehensive MIB management
  - OID resolution and reverse lookup
  - MIB compilation and loading (both high-level and low-level)
  - Tree navigation and analysis
  - Standard and custom MIB support

- **`SnmpKit.Sim`** - Realistic device simulation
  - Profile-based device behavior
  - Population management for testing
  - Integration with test frameworks

- **`SnmpKit`** - Direct access for convenience
  - Common operations without module prefixes
  - Backward compatibility for existing code
  - Simple one-import access

## 📊 Enterprise Features

### DOCSIS and Cable Modem Support

```elixir
# DOCSIS-specific operations
{:ok, cm_status} = SnmpKit.SNMP.get("10.1.1.100", "docsIfCmtsServiceAdminStatus.1")
{:ok, signal_quality} = SnmpKit.SNMP.get("10.1.1.100", "docsIfSigQSignalNoise.1")

# Load DOCSIS MIBs
{:ok, _} = SnmpKit.MIB.compile("DOCS-CABLE-DEVICE-MIB.mib")
{:ok, _} = SnmpKit.MIB.compile("DOCS-IF-MIB.mib")
```

### Network Monitoring Integration

```elixir
# Monitor interface statistics
interface_oids = [
  "ifInOctets.1", "ifOutOctets.1",
  "ifInErrors.1", "ifOutErrors.1"
]

# Collect metrics from multiple devices
devices = ["router1", "router2", "switch1", "switch2"]

results = 
  for device <- devices,
      oid <- interface_oids do
    {device, oid, SnmpKit.SNMP.get(device, oid)}
  end

# Analyze and format results
analysis = SnmpKit.SNMP.analyze_table(results)
```

## 🧪 Testing and Development

### Simulated Devices for Testing

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  
  setup do
    # Start a simulated device for testing
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:generic_router)
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: 1161)

    %{device: device, target: "127.0.0.1:1161"}
  end

  test "can query simulated device", %{target: target} do
    {:ok, description} = SnmpKit.SNMP.get(target, "sysDescr.0")
    assert description =~ "Simulated Router"
  end
end
```

### Performance Testing

```elixir
# Benchmark different devices and operations
devices = ["fast.device", "slow.device", "unreliable.device"]

benchmarks = 
  for device <- devices do
    SnmpKit.SNMP.benchmark_device(device, "system")
  end

# Compare performance characteristics
for {device, {:ok, benchmark}} <- Enum.zip(devices, benchmarks) do
  IO.puts "#{device}: avg=#{benchmark.avg_response_time}ms, success_rate=#{benchmark.success_rate}%"
end
```

## 📚 Documentation

- **[Full API Documentation](https://hexdocs.pm/snmpkit)** - Complete function reference
- **[Livebook Tour](livebooks/snmpkit_tour.livemd)** - Interactive examples and tutorials
- **[Examples Directory](examples/)** - Practical usage examples
- **[MIB Guide](docs/mib-guide.md)** - Working with MIBs and OID resolution
- **[Testing Guide](docs/testing-guide.md)** - Testing strategies and simulated devices

## 🚀 Migration from Other Libraries

### From `:snmp` (Erlang)

```elixir
# Before (Erlang SNMP)
:snmp.sync_get(manager, oid, timeout)

# After (SnmpKit)
SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0", timeout: 5000)
```

### From Other Elixir SNMP Libraries

```elixir
# SnmpKit provides more features with cleaner syntax
{:ok, results} = SnmpKit.SNMP.walk_multi([
  {"host1", "interfaces"},
  {"host2", "system"}
])

# Built-in formatting and analysis
{:ok, formatted} = SnmpKit.SNMP.walk_pretty("192.168.1.1", "interfaces")
```

## ⚡ Performance

SnmpKit is designed for high-performance network monitoring:

- **Concurrent Operations** - Efficient handling of thousands of simultaneous requests
- **Bulk Operations** - Optimized SNMP bulk protocols for large data sets
- **Connection Pooling** - Managed through the underlying SnmpLib layer
- **Circuit Breakers** - Automatic failure handling and recovery
- **Streaming** - Memory-efficient processing of large SNMP walks
- **Adaptive Algorithms** - Self-tuning bulk sizes and timeouts

## 🔧 Configuration

```elixir
# config/config.exs
config :snmpkit,
  default_community: "public",
  default_timeout: 5000,
  default_retries: 3,
  default_version: :v2c

# For simulation
config :snmpkit, :simulation,
  device_profiles_path: "priv/device_profiles",
  walk_files_path: "priv/walks"

# For MIB management
config :snmpkit, :mib,
  mib_path: ["priv/mibs", "/usr/share/snmp/mibs"],
  auto_load_standard_mibs: true
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
git clone https://github.com/awksedgreep/snmpkit.git
cd snmpkit
mix deps.get
mix test
```

### Running the Test Suite

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test categories
mix test --include docsis
mix test --include integration
```

## 📈 Roadmap

- 🔐 **SNMPv3 Support** - Authentication and encryption
- 🌐 **IPv6 Enhancement** - Full IPv6 support throughout
- 📊 **Advanced Analytics** - Built-in network analysis tools  
- 🔌 **Plugin System** - Custom protocol extensions
- 🎯 **More Device Profiles** - Extended simulation library
- 📱 **Management UI** - Web interface for monitoring

## 📄 License

SnmpKit is released under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- Built with ❤️ for the Elixir community
- Inspired by the need for modern, testable SNMP tools
- Thanks to all contributors and early adopters

---

**Ready to simplify your SNMP operations?** Get started with SnmpKit today! 🚀

For questions, issues, or feature requests, please visit our [GitHub repository](https://github.com/awksedgreep/snmpkit).