# SnmpKit 🚀

[![Hex.pm](https://img.shields.io/hexpm/v/snmpkit.svg)](https://hex.pm/packages/snmpkit)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snmpkit)
[![License](https://img.shields.io/github/license/your-org/snmpkit.svg)](LICENSE)
[![Build Status](https://img.shields.io/github/workflow/status/your-org/snmpkit/CI)](https://github.com/your-org/snmpkit/actions)

**A modern, pure Elixir SNMP library for network monitoring and device simulation.**

SnmpKit is a comprehensive SNMP (Simple Network Management Protocol) implementation built from the ground up in pure Elixir. Unlike traditional Erlang SNMP libraries, SnmpKit provides a modern, developer-friendly API with powerful features for both SNMP client operations and realistic device simulation.

## ✨ Key Features

- 🧬 **Pure Elixir Implementation** - No Erlang SNMP dependencies
- 📋 **Advanced MIB Parsing** - Native MIB file parsing and object resolution
- 🖥️ **Realistic Device Simulation** - Create SNMP devices for testing and development
- ⚡ **High Performance** - Optimized for large-scale operations and concurrent requests
- 🧪 **Testing Friendly** - Comprehensive test helpers and mock devices
- 🔧 **Modern API** - Elixir-friendly interfaces with GenServer patterns
- 📊 **Enterprise Ready** - Support for DOCSIS, standard MIBs, and custom implementations
- 🎯 **Interactive Learning** - Includes comprehensive Livebook tour

## 📖 Quick Start

### Installation

Add `snmpkit` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:snmpkit, "~> 0.1.0"}
  ]
end
```

### Basic SNMP Operations

```elixir
alias SnmpKit.SnmpLib.{Pdu, Message, Types}

# Create a simple GET request
get_request = %Pdu{
  type: :get_request,
  request_id: 12345,
  error_status: 0,
  error_index: 0,
  varbinds: [
    %{oid: "1.3.6.1.2.1.1.1.0", value: nil}  # sysDescr.0
  ]
}

# Parse and work with OIDs
{:ok, parsed_oid} = SnmpKit.SnmpLib.Oid.parse("1.3.6.1.2.1.1.1.0")
```

### MIB Parsing

```elixir
alias SnmpKit.MibParser

# Parse a MIB file
{:ok, mib} = MibParser.parse_file("path/to/your.mib")

# Parse MIB from string
mib_content = """
SIMPLE-MIB DEFINITIONS ::= BEGIN
  simpleObject OBJECT-TYPE
    SYNTAX Integer32
    MAX-ACCESS read-only
    STATUS current
    DESCRIPTION "A simple object"
    ::= { 1 3 6 1 4 1 99999 1 }
END
"""

{:ok, parsed_mib} = MibParser.parse_string(mib_content)
```

### Device Simulation

```elixir
alias SnmpKit.SnmpSim.{Device, TestHelpers.PortAllocator}

# Start the port allocator
{:ok, _pid} = PortAllocator.start_link()

# Reserve a port for our device
{:ok, port} = PortAllocator.reserve_port()

# Create a device profile
device_profile = %{
  device_type: :cable_modem,
  device_id: "cm_001",
  port: port,
  community: "public",
  objects: %{
    "1.3.6.1.2.1.1.1.0" => %{
      value: "ARRIS SURFboard Cable Modem",
      type: :string,
      access: :read_only
    },
    "1.3.6.1.2.1.1.3.0" => %{
      value: 0,
      type: :time_ticks,
      access: :read_only,
      behavior: :counter
    }
  }
}

# Start the simulated device
{:ok, device_pid} = Device.start_link(device_profile)
```

## 🏗️ Architecture

SnmpKit is designed with modularity and extensibility in mind:

```
SnmpKit/
├── SnmpLib/           # Core SNMP protocol implementation
│   ├── Types          # SNMP data types and encoding
│   ├── Pdu            # Protocol Data Unit handling
│   ├── Message        # SNMP message formatting
│   └── Oid            # Object Identifier utilities
├── MibParser/         # Pure Elixir MIB parsing
│   ├── Grammar        # Yacc-based MIB grammar
│   ├── Lexer          # MIB tokenization
│   └── Resolver       # Object resolution
└── SnmpSim/           # Device simulation framework
    ├── Device         # Individual device simulation
    ├── ProfileLoader  # Device profile management
    ├── TestHelpers    # Testing utilities
    └── Application    # Simulation orchestration
```

## 📚 Comprehensive Documentation

### 🎮 Interactive Livebook Tour

Explore SnmpKit interactively with our comprehensive Livebook tour:

```bash
# Start Livebook
livebook server

# Open the tour
open livebooks/snmpkit_tour.livemd
```

The tour covers:
- SNMP fundamentals and operations
- MIB parsing demonstrations
- Device simulation examples
- Performance optimization
- Real-world monitoring scenarios
- Troubleshooting guides
- Best practices and patterns

### 📖 Core Concepts

#### SNMP Operations

SnmpKit supports all standard SNMP operations:

- **GET** - Retrieve specific values
- **GET-NEXT** - Walk the MIB tree
- **GET-BULK** - Efficient bulk retrieval
- **SET** - Modify values (in simulation)
- **WALK** - Complete tree traversal

#### MIB Support

The pure Elixir MIB parser handles:

- Standard MIBs (SNMPv2-SMI, IF-MIB, etc.)
- DOCSIS MIBs (30+ cable modem MIBs tested)
- Enterprise MIBs
- Custom MIB definitions
- Complex object relationships and imports

#### Device Simulation

Create realistic SNMP devices with:

- **Behavior Simulation** - Counters, timers, realistic data patterns
- **Error Injection** - Timeout simulation, packet loss
- **Walk File Support** - Load real device data from captures
- **Large Scale** - Support for thousands of simulated devices
- **Dynamic Values** - Time-based and event-driven value changes

## 🧪 Testing and Development

### Test Helpers

SnmpKit provides comprehensive testing utilities:

```elixir
# Port management for tests
alias SnmpKit.SnmpSim.TestHelpers.PortAllocator

{:ok, _} = PortAllocator.start_link()
{:ok, {start_port, end_port}} = PortAllocator.reserve_port_range(10)

# Mock device creation
mock_devices = DeviceHelper.create_device_population([
  {:cable_modem, count: 100},
  {:switch, count: 20},
  {:router, count: 5}
])
```

### Configuration

```elixir
# config/config.exs
config :snmpkit,
  # Default SNMP settings
  default_community: "public",
  default_timeout: 5000,
  default_retries: 3,
  
  # Simulation settings
  simulation: %{
    port_range: 30_000..39_999,
    max_devices: 10_000,
    default_behaviors: [:realistic_counters, :time_patterns]
  },
  
  # MIB parser settings
  mib_parser: %{
    cache_parsed_mibs: true,
    max_cache_size: 100
  }
```

## 🚀 Advanced Usage

### Large-Scale Device Simulation

```elixir
# Create a population of mixed devices
device_configs = [
  {:cable_modem, {:walk_file, "priv/walks/cm.walk"}, count: 1000},
  {:switch, {:walk_file, "priv/walks/switch.walk"}, count: 50},
  {:router, {:oid_walk, "priv/walks/router.walk"}, count: 10}
]

{:ok, devices} = SnmpKit.TestSupport.start_device_population(
  device_configs,
  port_range: 30_000..39_999,
  behaviors: [:realistic_counters, :correlations, :time_patterns]
)
```

### Custom MIB Development

```elixir
# Define enterprise-specific objects
enterprise_mib = """
ACME-NETWORK-MIB DEFINITIONS ::= BEGIN

IMPORTS
    MODULE-IDENTITY, OBJECT-TYPE, Integer32
        FROM SNMPv2-SMI;

acmeNetworkMIB MODULE-IDENTITY
    LAST-UPDATED "202312010000Z"
    ORGANIZATION "ACME Networks"
    DESCRIPTION "ACME Network Equipment MIB"
    ::= { enterprises 12345 }

acmeTemperature OBJECT-TYPE
    SYNTAX      Integer32 (-40..100)
    UNITS       "degrees Celsius"
    MAX-ACCESS  read-only
    STATUS      current
    DESCRIPTION "System temperature"
    ::= { acmeNetworkMIB 1 }

END
"""

{:ok, mib} = SnmpKit.MibParser.parse_string(enterprise_mib)
```

### Performance Optimization

```elixir
# Batch operations for efficiency
oids = ["1.3.6.1.2.1.2.2.1.10.1", "1.3.6.1.2.1.2.2.1.16.1"]

bulk_request = %Pdu{
  type: :get_bulk_request,
  request_id: 54321,
  error_status: 0,  # non-repeaters
  error_index: 10,  # max-repetitions
  varbinds: Enum.map(oids, &%{oid: &1, value: nil})
}

# Use connection pooling for high-volume applications
# Configure appropriate timeouts and retry strategies
```

## 📊 Performance Characteristics

SnmpKit is optimized for performance:

- **MIB Parsing**: 100+ objects/ms on modern hardware
- **Device Simulation**: Support for 10,000+ concurrent devices
- **Memory Efficiency**: Optimized data structures and garbage collection
- **Concurrent Operations**: Built on Elixir's actor model for scalability

## 🛠️ Development and Contributing

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-org/snmpkit.git
cd snmpkit

# Install dependencies
mix deps.get

# Run tests
mix test

# Run with coverage
mix test --cover

# Generate documentation
mix docs
```

### Running the Test Suite

```bash
# Run all tests
mix test

# Run specific test files
mix test test/snmp_lib_test.exs
mix test test/mib_parser_test.exs

# Run tests with detailed output
mix test --trace

# Run performance benchmarks
mix test test/performance/
```

### Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📝 Use Cases

SnmpKit is perfect for:

### Network Monitoring Applications
- ISP infrastructure monitoring
- Cable modem management systems
- Switch and router monitoring
- Performance dashboards

### Testing and Development
- SNMP application testing
- Network simulation
- Load testing SNMP systems
- Educational purposes

### Enterprise Integration
- Custom network management tools
- Integration with existing monitoring systems
- Automated network discovery
- Performance analytics

## 🤝 Community and Support

- **Documentation**: [HexDocs](https://hexdocs.pm/snmpkit)
- **Issues**: [GitHub Issues](https://github.com/your-org/snmpkit/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/snmpkit/discussions)
- **Examples**: Check the `examples/` directory and Livebook tour

## 📄 License

SnmpKit is released under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- The Elixir community for inspiration and support
- SNMP RFC authors for the protocol specification
- Contributors who have helped improve this library

## 🔧 Troubleshooting

### Network Connectivity Issues

If you encounter `:ehostunreach` or similar network errors when running SNMP operations:

#### Common Solutions

1. **Network State Refresh**
   ```bash
   # Flush routing cache (macOS)
   sudo route flush
   
   # Flush ARP cache
   sudo arp -a -d
   
   # Flush DNS cache (macOS)
   sudo dscacheutil -flushcache
   ```

2. **Network Interface Reset**
   ```bash
   # Restart network interface (replace en0 with your interface)
   sudo ifconfig en0 down && sudo ifconfig en0 up
   ```

3. **Check Network Configuration**
   ```bash
   # Verify target is reachable
   ping 192.168.1.1
   
   # Check routing table
   route -n get 192.168.1.1
   
   # Verify SNMP port is accessible
   nc -u -z 192.168.1.1 161
   ```

#### Built-in Diagnostic Tools

SnmpKit includes comprehensive diagnostic scripts:

```bash
# Run network connectivity diagnostics
mix run scripts/debug_network_routing.exs

# Test SNMP functionality step by step
mix run scripts/debug_snmp_connectivity.exs
```

The library automatically retries failed connections with network state refresh, but persistent issues may require manual network troubleshooting.

## 🔮 Roadmap

- [ ] SNMPv3 support with authentication and encryption
- [ ] SNMP trap/notification handling
- [ ] Web-based device management interface
- [ ] Integration with popular monitoring systems
- [ ] Performance optimizations and benchmarking suite
- [ ] Additional MIB modules and enterprise support

---

**Built with ❤️ in Elixir**

*SnmpKit: Making SNMP development enjoyable and productive.*