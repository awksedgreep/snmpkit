# Permanent SNMP Walk Tests Documentation

## Overview

This document describes the comprehensive permanent test suite for SNMP walk operations. These tests are designed to prevent regressions and ensure that walk functionality remains stable across all scenarios.

## Critical Importance

**These tests must ALWAYS pass.** Any failure indicates a critical bug that could break walk functionality for users. The walk operation is fundamental to SNMP network management, and failures can have severe operational impact.

## Test Suite Structure

### 1. Unit Tests (`test/walk_unit_test.exs`)

**Purpose**: Test walk modules in isolation without external dependencies.

**Key Tests**:
- Module existence and function exports
- Absence of type inference functions (regression prevention)
- Source code validation for type preservation patterns
- Parameter validation and error handling
- Version handling logic
- Code quality checks

**Why Critical**: Unit tests catch basic module structure issues and ensure that type preservation code patterns are maintained.

**Run With**: `mix test test/walk_unit_test.exs`

### 2. Comprehensive Tests (`test/walk_comprehensive_test.exs`)

**Purpose**: Test complete walk functionality against a live SNMP simulator.

**Key Tests**:
- Basic walk functionality (returns non-empty results)
- 3-tuple format validation `{oid, type, value}`
- Version-specific walks (v1, v2c)
- Type preservation across all operations
- Boundary detection
- Performance requirements
- Large dataset handling

**Why Critical**: These tests verify that walks actually work end-to-end and return properly formatted results.

**Requirements**: SNMP simulator on port 11611

**Run With**: `mix test test/walk_comprehensive_test.exs`

### 3. Integration Tests (`test/walk_integration_test.exs`)

**Purpose**: Test end-to-end walk operations in realistic scenarios.

**Key Tests**:
- Complete walk workflows
- Cross-version consistency
- Different subtree handling
- Bulk parameter effects
- Performance benchmarks
- Error condition handling
- Walk vs individual GET comparisons

**Why Critical**: Integration tests ensure walks work correctly in real-world usage patterns.

**Requirements**: SNMP simulator on port 11612

**Run With**: `mix test test/walk_integration_test.exs`

### 4. Regression Tests (`test/walk_regression_test.exs`)

**Purpose**: Prevent specific known bugs from reoccurring.

**Critical Regressions Tested**:

#### Zero Results Bug (CRITICAL)
- **Issue**: Walk returning 0 results for system group
- **Tests**: 
  - `REGRESSION: walk MUST NOT return zero results for system group`
  - `REGRESSION: walk MUST NOT return zero results for interfaces group`
  - `REGRESSION: walk MUST NOT return zero results for symbolic OIDs`

#### Single Result Bug (CRITICAL)
- **Issue**: Walk stopping after first result instead of continuing
- **Tests**:
  - `REGRESSION: walk MUST NOT stop after single result`
  - `REGRESSION: walk iteration continues until proper end`

#### Type Information Loss (CRITICAL)
- **Issue**: Walk returning 2-tuple responses without type information
- **Tests**:
  - `REGRESSION: walk MUST NEVER return 2-tuple responses`
  - `REGRESSION: walk MUST preserve valid SNMP types`
  - `REGRESSION: walk MUST NOT use type inference`

#### Version-Specific Issues (CRITICAL)
- **Issue**: v1 walks failing due to parameter conflicts
- **Tests**:
  - `REGRESSION: v1 walk MUST NOT fail due to max_repetitions parameter`
  - `REGRESSION: default version MUST be v2c not v1`
  - `REGRESSION: v1 and v2c walks MUST return consistent types`

#### Collection Logic Issues (CRITICAL)
- **Issue**: Walk not processing multiple GET_BULK responses
- **Tests**:
  - `REGRESSION: walk MUST NOT fail to collect GET_BULK responses`
  - `REGRESSION: walk MUST process responses until end_of_mib_view`
  - `REGRESSION: walk MUST handle boundary detection correctly`

**Why Critical**: These tests specifically target bugs that have already been found and fixed. Their failure indicates that a critical regression has been introduced.

**Requirements**: SNMP simulator on port 11613

**Run With**: `mix test test/walk_regression_test.exs`

## Test Execution

### Test Execution

```bash
# Run all walk tests
mix test test/walk_*_test.exs

# Run specific test file
mix test test/walk_unit_test.exs
mix test test/walk_comprehensive_test.exs  
mix test test/walk_integration_test.exs
mix test test/walk_regression_test.exs

# Run with extended timeout
mix test test/walk_comprehensive_test.exs --timeout 30000

# Run only regression tests (most critical)
mix test test/walk_regression_test.exs

# Optional: Use test runner script for CI/CD
./run_walk_tests.sh
```

### CI/CD Integration

```yaml
# Example GitHub Actions configuration
name: SNMP Walk Tests
on: [push, pull_request]
jobs:
  walk-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '25'
          elixir-version: '1.15'
      - run: mix deps.get
      - run: mix compile
      - run: mix test test/walk_*_test.exs --timeout 30000
```

## Test Requirements

### SNMP Simulators

The tests require SNMP simulators on different ports:
- **Port 11611**: Comprehensive tests
- **Port 11612**: Integration tests  
- **Port 11613**: Regression tests

Simulators are automatically started by the test suites.

### System Requirements

- Elixir 1.12+
- OTP 24+
- Available ports 11611-11613
- At least 2GB RAM (for simulators)

### Test Data

Tests expect standard MIB-II objects:
- System group (`1.3.6.1.2.1.1`)
- Interfaces group (`1.3.6.1.2.1.2`)
- Basic SNMP types (integer, octet_string, object_identifier, timeticks)

## Success Criteria

### All Tests Must Pass

**No exceptions.** A single test failure indicates a critical issue that must be resolved before deployment.

### Performance Requirements

- Walk operations must complete within 15 seconds
- Must achieve at least 1 result per second throughput
- Memory usage must remain reasonable (< 100MB per walk)

### Type Preservation Requirements

- **100% 3-tuple format**: All results must be `{oid, type, value}`
- **No type inference**: Type information must come from SNMP responses
- **Valid SNMP types**: Only recognized SNMP types allowed
- **Cross-version consistency**: Same types across SNMPv1 and SNMPv2c

### Functional Requirements

- **Non-zero results**: Walk must return results for standard MIB objects
- **Proper boundaries**: Results must stay within requested subtree
- **Lexicographic order**: Results must be properly sorted
- **Complete iteration**: Must continue until end of subtree

## Failure Analysis

### Common Failure Patterns

1. **Zero Results**: Walk returns empty list
   - **Cause**: Collection logic not iterating properly
   - **Fix**: Check walk iteration and termination conditions

2. **Type Information Lost**: 2-tuple responses found
   - **Cause**: Type preservation code removed or bypassed
   - **Fix**: Restore type preservation enforcement

3. **Single Result**: Walk stops after first result
   - **Cause**: Iteration logic failing to continue
   - **Fix**: Fix walk continuation logic

4. **Parameter Conflicts**: v1 operations receiving v2c parameters
   - **Cause**: Version-specific parameter handling broken
   - **Fix**: Restore parameter filtering for different versions

5. **Performance Degradation**: Tests timing out
   - **Cause**: Inefficient walk algorithms or infinite loops
   - **Fix**: Review walk performance and termination conditions

### Debugging Failed Tests

1. **Check Test Logs**: ExUnit provides detailed failure information
2. **Run Individual Tests**: Isolate specific failing scenarios
3. **Enable Debug Logging**: Add `Logger.debug` to walk operations
4. **Check Simulator Status**: Ensure simulators are responding
5. **Verify Source Code**: Check for regression patterns in code

### Emergency Procedures

If tests are failing in production:

1. **STOP DEPLOYMENT**: Do not deploy failing code
2. **Identify Regression**: Determine which specific test is failing
3. **Rollback Changes**: Revert to last known good state
4. **Fix Root Cause**: Address the underlying issue
5. **Verify Fix**: Ensure all tests pass before redeploying

## Maintenance

### Adding New Tests

When adding new walk functionality:

1. **Add Unit Tests**: Test new functions in isolation
2. **Add Integration Tests**: Test end-to-end functionality
3. **Add Regression Tests**: If fixing a bug, add specific regression test
4. **Update Documentation**: Keep this document current

### Test Data Updates

When MIB data changes:
1. Update expected OID lists in tests
2. Adjust performance expectations if needed
3. Verify type mappings are still correct

### Simulator Updates

When updating simulators:
1. Ensure backward compatibility with existing tests
2. Add tests for new simulator features
3. Verify all ports and configurations work

## Monitoring

### Test Execution Metrics

Track these metrics over time:
- Test execution time
- Test pass/fail rates
- Performance benchmarks
- Memory usage during tests

### Alerting

Set up alerts for:
- Any test failures in CI/CD
- Performance degradation beyond thresholds
- New test additions without proper review

## Documentation Updates

This document should be updated when:
- New test files are added
- Test requirements change
- New failure patterns are discovered
- Performance requirements are modified

## Contact and Support

For issues with walk tests:
1. Check this documentation first
2. Review test failure logs
3. Examine source code for regression patterns
4. Create detailed bug reports with test output

Remember: **Walk functionality is critical for SNMP operations. These tests are the last line of defense against regressions that could break production systems.**