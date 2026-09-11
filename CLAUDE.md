# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Testing
- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run specific test file
- `mix test --only unit` - Run unit tests only
- `mix test --only integration` - Run integration tests only
- Tags excluded by default (see `test/test_helper.exs`): `:mib_oracle`, `:manual`, `:real_device`, `:performance`, `:memory`, `:needs_simulator`; include one with `mix test --include <tag>`

### Development
- `mix compile` - Compile the project
- `mix docs` - Generate documentation
- `mix deps.get` - Install dependencies
- `mix dialyzer` - Run type checking
- `mix lint` - `mix format --check-formatted` followed by `mix dialyzer` (there is no Credo)
- `mix format` - Format code
- `mix snmpkit.get`, `mix snmpkit.walk`, `mix snmpkit.sim`, `mix snmpkit.mib.compile`, `mix snmpkit.mib.lint` - command-line front ends (`lib/mix/tasks/`)

### Release
- `mix hex.publish` - Publish to Hex (package manager)

## Architecture

SnmpKit is a pure Elixir SNMP toolkit. The public API is a set of facade modules over the internal layers:

### Core Architecture
- **SnmpKit** (`lib/snmpkit.ex`) - Main entry point with convenience functions
- **SnmpKit.SNMP** - High-level SNMP protocol operations (enriched varbind maps)
- **SnmpKit.MIB** - MIB compilation, loading and OID resolution
- **SnmpKit.Sim** - Device simulation for testing
- **SnmpKit.Agent** (`lib/snmpkit/agent.ex`) - SNMP agent serving application data
- **SnmpKit.Trap** (`lib/snmpkit/trap.ex`) - Trap and inform receiver
- **SnmpKit.SNMP.Rate**, **SnmpKit.Telemetry** - counter rates, `:telemetry` events

### Internal Architecture
- **SnmpLib** (`lib/snmpkit/snmp_lib/`) - Low-level SNMP protocol implementation
  - PDU encoding/decoding, ASN.1 handling, transport layer, security (SNMPv3)
- **SnmpMgr** (`lib/snmpkit/snmp_mgr/`) - SNMP manager functionality
  - Core operations, multi-target support, walking, bulk operations, `Config` (defaults for `:timeout`, `:retries`, `:walk_timeout`)
- **MIB toolchain** (`lib/snmpkit/mib/`) - tokenizer and yecc grammar ported from OTP's `snmpc`, parser, compiler, linter, built-in object tables (`Builtin`), registry
- **SnmpSim** (`lib/snmpkit/snmp_sim/`) - Device simulation
  - Virtual devices, MIB profiles, error injection, USM agent
- **SnmpKit.SafeFile** (`lib/snmpkit/safe_file.ex`) - size and `:input_roots` confinement for every file the library reads (profiles, walks, MIB sources)

### Key Design Principles
- **Pure Elixir** - No dependencies on Erlang's SNMP library
- **Unified API** - Consistent interface across all operations
- **Type Safety** - Preserves SNMP type information throughout operations
- **Concurrent Operations** - Built for high-performance multi-target operations
- **Extensible MIB Support** - Native MIB parsing and compilation

### Transport and Communication
- UDP transport via `SnmpKit.SnmpLib.Transport`
- One shared socket per VM in `SnmpKit.SnmpMgr.Engine`, started on demand; its calls return `{:error, :services_not_started}` when the manager services are down
- Request/response correlation via request IDs
- Invalid OIDs are `{:error, {:invalid_oid, input, reason}}`; `:retries` defaults to 1 everywhere

### Testing Infrastructure
- Comprehensive test suite with unit, integration, and walk tests
- Built-in device simulation for testing
- Test helpers in `test/support/`
- Extensive MIB testing with real-world MIB files; optional cross-check against libsmi and net-snmp (`docs/mib-parser-oracle.md`)

### SNMPv3 Support
- Complete USM (User-based Security Model) implementation
- Authentication (MD5, SHA-1, SHA-2 family) and privacy (DES, AES-128/192/256) support
- Engine ID discovery and time synchronization
- Security parameter handling
