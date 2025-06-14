# SnmpKit Test Suite

This directory contains the unified test suite for SnmpKit, combining tests from the original three projects: snmp_lib, snmp_sim, and snmp_mgr.

## Test Organization

### `/test/snmp_lib/`
Core library tests for SNMP protocol handling, including:
- ASN.1 encoding/decoding
- PDU construction and parsing
- OID handling
- MIB parsing and compilation
- Security (USM, authentication, privacy)
- Transport layer
- Connection pooling

### `/test/snmp_sim/`
SNMP simulator tests, including:
- Device simulation
- Walk file parsing
- Bulk operations simulation
- Error injection
- Performance optimizations
- Time-based value patterns

### `/test/snmp_mgr/`
SNMP manager tests, including:
- Core SNMP operations (GET, SET, WALK)
- Bulk operations
- Table processing
- Circuit breaker functionality
- Multi-target operations
- Stream processing
- Adaptive walking

### `/test/integration/`
Integration tests that verify component interactions:
- End-to-end SNMP communication
- Manager-Simulator integration
- Performance benchmarks
- Real-world scenario testing

### `/test/support/`
Shared test utilities:
- `snmp_test_helpers.ex` - Common SNMP test functions
- `snmp_simulator.ex` - Test device creation utilities

### `/test/fixtures/`
Test data files:
- `/mibs/` - MIB files for testing
- `/walks/` - Walk files for simulator testing (in `/priv/walks/`)

## Running Tests

```bash
# Run all tests
mix test

# Run specific test categories
mix test test/snmp_lib
mix test test/snmp_sim
mix test test/snmp_mgr

# Run integration tests (may be slower)
mix test --include integration

# Run performance tests
mix test --include performance

# Run tests with specific tags
mix test --include slow
mix test --include docsis
mix test --include needs_simulator
```

## Test Tags

Tests can be tagged for selective execution:
- `:integration` - Integration tests
- `:performance` - Performance benchmarks
- `:slow` - Tests that take longer to run
- `:docsis` - DOCSIS-specific tests
- `:needs_simulator` - Tests requiring SNMP simulator
- `:erlang` - Tests using Erlang SNMP library
- `:optional` - Optional/experimental tests

## Test Helpers

The test suite includes several helper modules:

### SnmpKit.TestHelpers.SNMPTestHelpers
Provides functions for sending SNMP requests in tests:
- `send_snmp_get/3`
- `send_snmp_getbulk/5`
- `send_snmp_getnext/3`

### SnmpKit.TestSupport.SNMPSimulator
Creates test SNMP devices:
- `create_test_device/1`
- `create_switch_device/1`
- `create_router_device/1`
- `create_device_fleet/1`

## Notes

- Tests are configured to suppress SNMP library debug output
- Port conflicts are automatically resolved before tests run
- Test timeout is set to 10 seconds by default
- Tests run in parallel using multiple cores