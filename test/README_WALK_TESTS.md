# SNMP Walk Tests

This directory contains comprehensive tests for SNMP walk operations. These tests ensure that walk functionality works correctly and prevent regressions.

## Quick Start

Run all walk tests:
```bash
mix test test/walk_*_test.exs
```

Run specific test file:
```bash
mix test test/walk_unit_test.exs
mix test test/walk_comprehensive_test.exs
mix test test/walk_integration_test.exs
mix test test/walk_regression_test.exs
```

## Test Files

### `walk_unit_test.exs`
- **Purpose**: Unit tests for walk modules
- **Requirements**: None (no simulator needed)
- **Runtime**: Fast (~5 seconds)
- **Tests**: Module structure, type preservation, code quality

### `walk_comprehensive_test.exs`
- **Purpose**: Complete walk functionality testing
- **Requirements**: SNMP simulator (auto-started on port 11611)
- **Runtime**: Medium (~30 seconds)
- **Tests**: Basic functionality, type preservation, performance

### `walk_integration_test.exs`
- **Purpose**: End-to-end integration scenarios
- **Requirements**: SNMP simulator (auto-started on port 11612)
- **Runtime**: Medium (~45 seconds)
- **Tests**: Real-world usage patterns, cross-version consistency

### `walk_regression_test.exs`
- **Purpose**: Prevent known bugs from returning
- **Requirements**: SNMP simulator (auto-started on port 11613)
- **Runtime**: Medium (~30 seconds)
- **Tests**: Specific regression scenarios

## Critical Tests

These tests MUST always pass:

```bash
# Zero results bug (main issue from bug report)
mix test test/walk_regression_test.exs -t regression_critical

# Type preservation (prevents type information loss)
mix test test/walk_comprehensive_test.exs --only type_preservation
```

## Common Issues

### Tests Timing Out
```bash
# Increase timeout
mix test test/walk_*_test.exs --timeout 60000
```

### Simulator Port Conflicts
Tests use different ports (11611-11613) to avoid conflicts. If ports are busy:
```bash
# Check what's using the ports
lsof -i :11611-11613

# Kill processes if needed
pkill -f snmp_sim
```

### Debug Failing Tests
```bash
# Run with detailed output
mix test test/walk_regression_test.exs --trace

# Run single test
mix test test/walk_regression_test.exs:67
```

## Success Criteria

All tests must pass with:
- ✅ No zero-result walks
- ✅ All results in 3-tuple format `{oid, type, value}`
- ✅ No type inference (only preserved SNMP types)
- ✅ Performance under 15 seconds per test file

## CI/CD Integration

Add to your workflow:
```yaml
- name: Run Walk Tests
  run: mix test test/walk_*_test.exs --timeout 30000
```

## Manual Testing

For manual verification without full test suite:
```bash
# Quick verification
elixir verify_walk_fixes.exs

# Or test individual operations
iex -S mix
iex> SnmpKit.SNMP.walk("127.0.0.1", "1.3.6.1.2.1.1")
```

## Maintenance

When adding new walk functionality:
1. Add unit tests in `walk_unit_test.exs`
2. Add integration tests in appropriate files
3. If fixing a bug, add regression test in `walk_regression_test.exs`
4. Ensure all tests pass: `mix test test/walk_*_test.exs`

## Getting Help

If tests fail:
1. Check test output for specific error messages
2. Review `PERMANENT_WALK_TESTS.md` for detailed documentation
3. Verify simulator is responding
4. Check for regression patterns in source code

Remember: Walk functionality is critical for SNMP operations. These tests are the primary defense against regressions.