# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Testing
- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run specific test file
- `mix test --only unit` - Run unit tests only
- `mix test --only integration` - Run integration tests only

### Development
- `mix compile` - Compile the project
- `mix docs` - Generate documentation
- `mix deps.get` - Install dependencies
- `mix dialyzer` - Run type checking
- `mix credo` - Run static analysis
- `mix format` - Format code

### Release
- `mix hex.publish` - Publish to Hex (package manager)

## Architecture

SnmpKit is a pure Elixir SNMP toolkit organized into three main modules:

### Core Architecture
- **SnmpKit** - Main entry point with convenience functions
- **SnmpKit.SNMP** - High-level SNMP protocol operations
- **SnmpKit.MIB** - MIB management and OID resolution
- **SnmpKit.Sim** - Device simulation for testing

### Internal Architecture
- **SnmpLib** (`lib/snmpkit/snmp_lib/`) - Low-level SNMP protocol implementation
  - PDU encoding/decoding, ASN.1 handling, transport layer, security (SNMPv3)
- **SnmpMgr** (`lib/snmpkit/snmp_mgr/`) - SNMP manager functionality
  - Core operations, multi-target support, walking, bulk operations
- **SnmpSim** (`lib/snmpkit/snmp_sim/`) - Device simulation
  - Virtual devices, MIB profiles, realistic network behavior

### Key Design Principles
- **Pure Elixir** - No dependencies on Erlang's SNMP library
- **Unified API** - Consistent interface across all operations
- **Type Safety** - Preserves SNMP type information throughout operations
- **Concurrent Operations** - Built for high-performance multi-target operations
- **Extensible MIB Support** - Native MIB parsing and compilation

### Transport and Communication
- UDP transport via `SnmpKit.SnmpLib.Transport`
- Connection pooling in `SnmpKit.SnmpMgr.Engine`
- Request/response correlation via request IDs
- Circuit breaker pattern for error handling

### Testing Infrastructure
- Comprehensive test suite with unit, integration, and walk tests
- Built-in device simulation for testing
- Test helpers in `test/support/`
- Extensive MIB testing with real-world MIB files

### SNMPv3 Support
- Complete USM (User-based Security Model) implementation
- Authentication (MD5, SHA) and privacy (DES, AES) support
- Engine ID discovery and time synchronization
- Security parameter handling