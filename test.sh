#!/bin/bash

# SnmpKit Test Runner Script
# Provides convenient commands for running different test suites

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to run tests with proper output
run_tests() {
    local test_name=$1
    local test_command=$2
    
    print_color "$YELLOW" "\n🧪 Running $test_name..."
    
    if eval "$test_command"; then
        print_color "$GREEN" "✅ $test_name passed!"
    else
        print_color "$RED" "❌ $test_name failed!"
        exit 1
    fi
}

# Main test runner
case ${1:-all} in
    all)
        print_color "$GREEN" "Running all SnmpKit tests..."
        run_tests "All Tests" "mix test"
        ;;
    
    lib)
        print_color "$GREEN" "Running SnmpLib tests..."
        run_tests "SnmpLib Tests" "mix test test/snmp_lib"
        ;;
    
    sim)
        print_color "$GREEN" "Running SnmpSim tests..."
        run_tests "SnmpSim Tests" "mix test test/snmp_sim"
        ;;
    
    mgr)
        print_color "$GREEN" "Running SnmpMgr tests..."
        run_tests "SnmpMgr Tests" "mix test test/snmp_mgr"
        ;;
    
    integration)
        print_color "$GREEN" "Running integration tests..."
        run_tests "Integration Tests" "mix test test/integration --include integration"
        ;;
    
    unit)
        print_color "$GREEN" "Running unit tests only..."
        run_tests "Unit Tests" "mix test --exclude integration --exclude performance --exclude slow"
        ;;
    
    performance)
        print_color "$GREEN" "Running performance tests..."
        run_tests "Performance Tests" "mix test --include performance"
        ;;
    
    slow)
        print_color "$GREEN" "Running all tests including slow ones..."
        run_tests "All Tests (including slow)" "mix test --include slow --include integration"
        ;;
    
    coverage)
        print_color "$GREEN" "Running tests with coverage..."
        run_tests "Coverage Tests" "mix coveralls.html"
        print_color "$GREEN" "Coverage report generated at cover/excoveralls.html"
        ;;
    
    watch)
        print_color "$GREEN" "Running tests in watch mode..."
        # Note: Requires fswatch to be installed
        if command -v fswatch &> /dev/null; then
            fswatch -o lib test | xargs -n1 -I{} mix test
        else
            print_color "$RED" "fswatch not found. Install with: brew install fswatch"
            exit 1
        fi
        ;;
    
    clean)
        print_color "$YELLOW" "Cleaning test artifacts..."
        rm -rf _build/test
        rm -rf cover
        mix clean
        print_color "$GREEN" "✅ Test artifacts cleaned!"
        ;;
    
    help|*)
        echo "SnmpKit Test Runner"
        echo ""
        echo "Usage: ./test.sh [command]"
        echo ""
        echo "Commands:"
        echo "  all         - Run all tests (default)"
        echo "  lib         - Run SnmpLib tests only"
        echo "  sim         - Run SnmpSim tests only"
        echo "  mgr         - Run SnmpMgr tests only"
        echo "  integration - Run integration tests"
        echo "  unit        - Run unit tests only (excludes integration/performance)"
        echo "  performance - Run performance tests"
        echo "  slow        - Run all tests including slow ones"
        echo "  coverage    - Run tests with coverage report"
        echo "  watch       - Run tests in watch mode (requires fswatch)"
        echo "  clean       - Clean test artifacts"
        echo "  help        - Show this help message"
        echo ""
        echo "Examples:"
        echo "  ./test.sh            # Run all tests"
        echo "  ./test.sh lib        # Run only SnmpLib tests"
        echo "  ./test.sh coverage   # Generate coverage report"
        ;;
esac