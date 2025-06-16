# SnmpKit 🚀

[![Hex.pm](https://img.shields.io/hexpm/v/snmpkit.svg)](https://hex.pm/packages/snmpkit)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snmpkit)
[![License](https://img.shields.io/github/license/awksedgreep/snmpkit.svg)](LICENSE)

**A modern, comprehensive SNMP toolkit for Elixir - featuring a unified API, pure Elixir implementation, and powerful device simulation.**

SnmpKit is a complete SNMP (Simple Network Management Protocol) solution built from the ground up in pure Elixir. It provides a clean, organized API for SNMP operations, MIB management, and realistic device simulation.

## ✨ Key Features

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
    {:snmpkit, "~> 0.3.5"}
  ]
end
```

### Basic Usage

```elixir
# Basic SNMP operations
{:ok, description} = SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")
{:ok, system_info} = SnmpKit.SNMP.walk("192.168.1.1", "system")

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