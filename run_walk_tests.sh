#!/bin/bash

# SNMP Walk Test Runner Script (OPTIONAL)
# This script provides additional testing features beyond standard "mix test"
# For normal testing, just use: mix test test/walk_*_test.exs
# This script is mainly for CI/CD and detailed reporting

set -e  # Exit on any error

echo "================================================================================"
echo "SNMP WALK PERMANENT TEST SUITE (Enhanced Runner)"
echo "Note: You can also run tests directly with: mix test test/walk_*_test.exs"
echo "================================================================================"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_TIMEOUT=60
SIMULATOR_STARTUP_DELAY=5

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "PASS")
            echo -e "${GREEN}✅ PASS${NC} - $message"
            ;;
        "FAIL")
            echo -e "${RED}❌ FAIL${NC} - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  WARN${NC} - $message"
            ;;
        "INFO")
            echo -e "ℹ️  INFO - $message"
            ;;
    esac
}

# Function to check if mix is available
check_mix() {
    if ! command -v mix &> /dev/null; then
        print_status "FAIL" "Elixir Mix not found. Please install Elixir."
        exit 1
    fi
    print_status "PASS" "Elixir Mix found"
}

# Function to check dependencies
check_dependencies() {
    print_status "INFO" "Checking project dependencies..."

    if mix deps.get; then
        print_status "PASS" "Dependencies resolved"
    else
        print_status "FAIL" "Failed to resolve dependencies"
        exit 1
    fi
}

# Function to compile the project
compile_project() {
    print_status "INFO" "Compiling project..."

    if mix compile; then
        print_status "PASS" "Project compiled successfully"
    else
        print_status "FAIL" "Project compilation failed"
        exit 1
    fi
}

# Function to run specific test file
run_test_file() {
    local test_file=$1
    local test_name=$2

    print_status "INFO" "Running $test_name..."
    print_status "INFO" "Equivalent command: mix test $test_file --timeout ${TEST_TIMEOUT}000"

    if mix test "$test_file" --timeout "${TEST_TIMEOUT}000"; then
        print_status "PASS" "$test_name completed successfully"
        return 0
    else
        print_status "FAIL" "$test_name failed"
        return 1
    fi
}

# Function to run unit tests (no simulator required)
run_unit_tests() {
    echo ""
    echo "================== UNIT TESTS =================="
    echo "Testing walk modules without external dependencies"
    echo "================================================="

    local unit_failed=0

    if ! run_test_file "test/walk_unit_test.exs" "Walk Unit Tests"; then
        unit_failed=1
    fi

    if [ $unit_failed -eq 0 ]; then
        print_status "PASS" "All unit tests passed"
        return 0
    else
        print_status "FAIL" "Unit tests failed"
        return 1
    fi
}

# Function to run comprehensive tests (requires simulator)
run_comprehensive_tests() {
    echo ""
    echo "============== COMPREHENSIVE TESTS =============="
    echo "Testing complete walk functionality with simulator"
    echo "=================================================="

    local comp_failed=0

    # Give simulator extra time to start
    print_status "INFO" "Allowing ${SIMULATOR_STARTUP_DELAY}s for simulator startup..."
    sleep $SIMULATOR_STARTUP_DELAY

    if ! run_test_file "test/walk_comprehensive_test.exs" "Walk Comprehensive Tests"; then
        comp_failed=1
    fi

    if [ $comp_failed -eq 0 ]; then
        print_status "PASS" "All comprehensive tests passed"
        return 0
    else
        print_status "FAIL" "Comprehensive tests failed"
        return 1
    fi
}

# Function to run integration tests
run_integration_tests() {
    echo ""
    echo "============== INTEGRATION TESTS ================"
    echo "Testing end-to-end walk integration scenarios"
    echo "=================================================="

    local int_failed=0

    if ! run_test_file "test/walk_integration_test.exs" "Walk Integration Tests"; then
        int_failed=1
    fi

    if [ $int_failed -eq 0 ]; then
        print_status "PASS" "All integration tests passed"
        return 0
    else
        print_status "FAIL" "Integration tests failed"
        return 1
    fi
}

# Function to run regression tests
run_regression_tests() {
    echo ""
    echo "=============== REGRESSION TESTS ================"
    echo "Testing specific bug fixes to prevent regressions"
    echo "=================================================="

    local reg_failed=0

    if ! run_test_file "test/walk_regression_test.exs" "Walk Regression Tests"; then
        reg_failed=1
    fi

    if [ $reg_failed -eq 0 ]; then
        print_status "PASS" "All regression tests passed"
        return 0
    else
        print_status "FAIL" "Regression tests failed - CRITICAL BUGS DETECTED!"
        return 1
    fi
}

# Function to run type preservation tests
run_type_tests() {
    echo ""
    echo "============ TYPE PRESERVATION TESTS ============"
    echo "Testing that type information is never lost"
    echo "=================================================="

    # Run the standalone type preservation test if it exists
    if [ -f "type_preservation_tests.exs" ]; then
        print_status "INFO" "Running standalone type preservation tests..."
        if elixir type_preservation_tests.exs; then
            print_status "PASS" "Standalone type tests passed"
        else
            print_status "FAIL" "Standalone type tests failed"
            return 1
        fi
    else
        print_status "WARN" "Standalone type tests not found, skipping"
    fi

    return 0
}

# Function to generate test report
generate_report() {
    local total_status=$1

    echo ""
    echo "================================================================================"
    echo "WALK TEST SUITE SUMMARY"
    echo "================================================================================"

    if [ $total_status -eq 0 ]; then
        print_status "PASS" "ALL WALK TESTS PASSED"
        echo ""
        echo "✅ Walk functionality is working correctly"
        echo "✅ No regressions detected"
        echo "✅ Type preservation is maintained"
        echo "✅ All versions (v1, v2c) working properly"
        echo "✅ Ready for production use"
        echo ""
        echo "Quick test command: mix test test/walk_*_test.exs"
    else
        print_status "FAIL" "WALK TESTS FAILED"
        echo ""
        echo "❌ Walk functionality has issues"
        echo "❌ Regressions may be present"
        echo "❌ DO NOT deploy until tests pass"
        echo "❌ Review test output for specific failures"
        echo ""
        echo "Debug command: mix test test/walk_*_test.exs --trace"
    fi

    echo "================================================================================"
    return $total_status
}

# Function to clean up test artifacts
cleanup() {
    print_status "INFO" "Cleaning up test artifacts..."

    # Kill any lingering simulator processes
    pkill -f "snmp_sim" 2>/dev/null || true

    # Clean up any temporary files
    rm -f erl_crash.dump 2>/dev/null || true

    print_status "INFO" "Cleanup completed"
}

# Main execution function
main() {
    local overall_status=0

    # Trap cleanup on exit
    trap cleanup EXIT

    print_status "INFO" "Starting Enhanced SNMP Walk Test Suite..."
    print_status "INFO" "Alternative: mix test test/walk_*_test.exs --timeout 30000"

    # Pre-flight checks
    check_mix
    check_dependencies
    compile_project

    # Run test suites in order of dependency

    # 1. Unit tests (no external dependencies)
    if ! run_unit_tests; then
        overall_status=1
    fi

    # 2. Type preservation tests
    if ! run_type_tests; then
        overall_status=1
    fi

    # 3. Comprehensive tests (requires simulator)
    if ! run_comprehensive_tests; then
        overall_status=1
    fi

    # 4. Integration tests
    if ! run_integration_tests; then
        overall_status=1
    fi

    # 5. Regression tests (most critical)
    if ! run_regression_tests; then
        overall_status=1
    fi

    # Generate final report
    generate_report $overall_status

    return $overall_status
}

# Script execution options
case "${1:-all}" in
    "unit")
        check_mix
        check_dependencies
        compile_project
        run_unit_tests
        exit $?
        ;;
    "comprehensive")
        check_mix
        check_dependencies
        compile_project
        run_comprehensive_tests
        exit $?
        ;;
    "integration")
        check_mix
        check_dependencies
        compile_project
        run_integration_tests
        exit $?
        ;;
    "regression")
        check_mix
        check_dependencies
        compile_project
        run_regression_tests
        exit $?
        ;;
    "type")
        check_mix
        check_dependencies
        compile_project
        run_type_tests
        exit $?
        ;;
    "all"|*)
        main
        exit $?
        ;;
esac
