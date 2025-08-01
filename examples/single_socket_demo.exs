#!/usr/bin/env elixir

# Single Socket Demo for SnmpKit Multi Operations
# This demo shows how the updated multi.ex functions use a single shared socket
# for all SNMP operations instead of creating individual sockets per request.

# Start the application
Application.ensure_all_started(:snmpkit)

# Define some test targets (these will fail but show the architecture)
targets_and_oids = [
  {"192.168.1.1", "1.3.6.1.2.1.1.1.0"},
  {"192.168.1.2", "1.3.6.1.2.1.1.3.0"},
  {"192.168.1.3", "1.3.6.1.2.1.1.5.0"}
]

IO.puts("=== Single Socket Architecture Demo ===")
IO.puts("Testing multi-target SNMP operations with shared socket...")
IO.puts("Targets: #{inspect(targets_and_oids)}")
IO.puts("")

# Test 1: Basic multi-get with shared socket
IO.puts("1. Testing get_multi with shared socket:")
start_time = System.monotonic_time(:millisecond)

results = SnmpKit.SnmpMgr.Multi.get_multi(targets_and_oids, 
  timeout: 1000, 
  community: "public"
)

end_time = System.monotonic_time(:millisecond)
IO.puts("   Results: #{inspect(results)}")
IO.puts("   Duration: #{end_time - start_time}ms")
IO.puts("")

# Test 2: Different return formats
IO.puts("2. Testing different return formats:")

# With targets format
results_with_targets = SnmpKit.SnmpMgr.Multi.get_multi(targets_and_oids, 
  return_format: :with_targets,
  timeout: 1000
)
IO.puts("   With targets: #{inspect(results_with_targets)}")

# Map format  
results_map = SnmpKit.SnmpMgr.Multi.get_multi(targets_and_oids, 
  return_format: :map,
  timeout: 1000
)
IO.puts("   Map format: #{inspect(results_map)}")
IO.puts("")

# Test 3: Bulk operations with shared socket
IO.puts("3. Testing get_bulk_multi with shared socket:")
bulk_targets = [
  {"192.168.1.1", "1.3.6.1.2.1.2.2.1"},
  {"192.168.1.2", "1.3.6.1.2.1.2.2.1"}
]

bulk_results = SnmpKit.SnmpMgr.Multi.get_bulk_multi(bulk_targets,
  timeout: 1000,
  max_repetitions: 10
)
IO.puts("   Bulk results: #{inspect(bulk_results)}")
IO.puts("")

# Test 4: Mixed operations
IO.puts("4. Testing execute_mixed with shared socket:")
mixed_operations = [
  {:get, "192.168.1.1", "1.3.6.1.2.1.1.1.0", []},
  {:get_bulk, "192.168.1.2", "1.3.6.1.2.1.2.2.1", [max_repetitions: 5]},
  {:get, "192.168.1.3", "1.3.6.1.2.1.1.5.0", []}
]

mixed_results = SnmpKit.SnmpMgr.Multi.execute_mixed(mixed_operations, timeout: 1000)
IO.puts("   Mixed results: #{inspect(mixed_results)}")
IO.puts("")

IO.puts("=== Architecture Benefits ===")
IO.puts("✓ Single UDP socket shared across all operations")
IO.puts("✓ Request correlation via unique request IDs")
IO.puts("✓ Reduced resource usage (no socket per request)")
IO.puts("✓ Better performance for high-volume operations")
IO.puts("✓ Centralized timeout and error handling")
IO.puts("✓ Maintains backward compatibility")