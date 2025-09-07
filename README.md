# SnmpKit 🚀

IMPORTANT: Breaking changes in 1.0
- Standardized result shape: all SNMP operations now return enriched maps per varbind: `%{name?, oid, type, value, formatted?}`
- `include_names: true` by default (can be disabled per call or globally)
- `include_formatted: true` by default (can be disabled to avoid formatting overhead)
- Pretty helpers now preserve type and raw value and return the same enriched map shape
- Migration guide: see docs/enriched-output-migration.md
- Removed deprecated functions: `get_with_type/3` and `get_next_with_type/3` (use `get/3` and `get_next/3` which now always include type in the enriched map)
- Multi-target APIs keep their outer return_format but inner items are enriched maps

[![Hex.pm](https://img.shields.io/hexpm/v/snmpkit.svg)](https://hex.pm/packages/snmpkit)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snmpkit)
[![License](https://img.shields.io/github/license/awksedgreep/snmpkit.svg)](LICENSE)

**A modern, comprehensive SNMP toolkit for Elixir - featuring a unified API, pure Elixir implementation, and powerful device simulation.**

SnmpKit is a complete SNMP (Simple Network Management Protocol) solution built from the ground up in pure Elixir. It provides a clean, organized API for SNMP operations, MIB management, and realistic device simulation.

## ✨ Key Features

Performance and result toggles
- include_names: true by default; set include_names: false per call or via application config to skip reverse lookup and speed up response processing
- include_formatted: true by default; set include_formatted: false to skip formatting and return raw values only

Examples
- High-throughput walk without formatting or name resolution:

```elixir
{:ok, rows} = SnmpKit.SNMP.walk("192.168.1.1", "ifTable", include_names: false, include_formatted: false)
# rows: [%{oid: "1.3.6...", type: :integer, value: 1}, ...]
```

Multi-target defaults (1.0)
- Concurrent Multi is the default for multi-target operations (get_multi, get_bulk_multi, walk_multi)
- Default SNMP version for multi-target operations is :v2c (override with version: :v1 if needed)
- No manual engine/service start is required — components are ensured at call time
- Legacy/simple behavior is still available via `strategy: :simple`
- Note: Single-target operations default to :v1 (configurable via SnmpKit.SnmpMgr.Config)

```elixir
# Default: Concurrent Multi
{:ok, results} = SnmpKit.get_multi([{"h1", "sysDescr.0"}, {"h2", "sysUpTime.0"}])

# Legacy/simple path (opt-in)
{:ok, results} = SnmpKit.get_multi([{"h1", "sysDescr.0"}, {"h2", "sysUpTime.0"}], strategy: :simple)
```

- 🎯 **Unified API** - Clean, context-based modules (`SnmpKit.SNMP`, `SnmpKit.MIB`, `SnmpKit.Sim`)
- 🧬 **Pure Elixir Implementation** - No Erlang SNMP dependencies
- 📋 **Advanced MIB Support** - Native parsing, compilation, and object resolution
- 🖥️ **Realistic Device Simulation** - Create SNMP devices for testing and development
- ⚡ **High Performance** - Optimized for large-scale operations and concurrent requests
- 🧪 **Testing Friendly** - Comprehensive test helpers and simulated devices

## 🚀 Quick Start

### Installation

```elixir
def deps do
  [
    {:snmpkit, "~> 1.0"}
  ]
end
```

### Basic Usage

```elixir
# Basic SNMP operations return enriched maps
{:ok, %{name: name, oid: oid, type: type, value: description, formatted: formatted}} =
  SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")

{:ok, system_info} = SnmpKit.SNMP.walk("192.168.1.1", "system")
# system_info: [
#   %{name: "sysDescr.0", oid: "1.3.6.1.2.1.1.1.0", type: :octet_string, value: "...", formatted: "..."},
#   ...
# ]

# MIB operations
{:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
{:ok, name} = SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])

# Device simulation
device_profile = %{
  name: "Test Router",
  objects: %{[1, 3, 6, 1, 2, 1, 1, 1, 0] => "Test Router v1.0"}
}
{:ok, device} = SnmpKit.Sim.start_device(device_profile, port: 1161)
```

## 🏗️ Architecture

- **`SnmpKit.SNMP`** - Complete SNMP protocol operations
- **`SnmpKit.MIB`** - Comprehensive MIB management  
- **`SnmpKit.Sim`** - Realistic device simulation
- **`SnmpKit`** - Direct access for convenience

## 📚 Documentation

- **[Complete API Documentation](https://hexdocs.pm/snmpkit)** - Full function reference
- **[Concurrent Multi (High-Throughput Multi-Target)](https://hexdocs.pm/snmpkit/concurrent-multi.html)** - Concepts, defaults, and return formats
- **[Enriched Output Migration Guide](https://hexdocs.pm/snmpkit/enriched-output-migration.html)** - Migrate from 0.x to 1.x
- **[Interactive Livebook Tour](https://hexdocs.pm/snmpkit/snmpkit_tour.html)** - Learn by doing
- **[MIB Guide](https://hexdocs.pm/snmpkit/mib-guide.html)** - Working with MIBs
- **[Testing Guide](https://hexdocs.pm/snmpkit/testing-guide.html)** - Testing strategies
- **[Contributing Guide](https://hexdocs.pm/snmpkit/contributing.html)** - Development guidelines

## 🤝 Contributing

We welcome contributions! Please see the [Contributing Guide](https://hexdocs.pm/snmpkit/contributing.html) for guidelines.

## 📄 License

SnmpKit is released under the [MIT License](LICENSE).

---

**Ready to simplify your SNMP operations?** Get started with SnmpKit today! 🚀