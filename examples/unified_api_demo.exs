#!/usr/bin/env elixir

# Unified SnmpKit API Demo
#
# This example demonstrates the new unified API for SnmpKit that provides
# clean, organized access to all SNMP functionality through context-based modules.

Mix.install([{:snmpkit, path: "."}])

defmodule UnifiedAPIDemo do
  @moduledoc """
  Demonstrates the new unified SnmpKit API with examples of:
  - SNMP operations through SnmpKit.SNMP
  - MIB operations through SnmpKit.MIB
  - Simulation through SnmpKit.Sim
  - Direct API access through SnmpKit
  """

  def run do
    IO.puts """

    🚀 SnmpKit Unified API Demo
    ===========================

    This demo shows the new unified API that provides clean access to all
    SnmpKit functionality through organized modules.
    """

    demo_mib_operations()
    demo_snmp_operations()
    demo_direct_api()
    demo_api_organization()
  end

  defp demo_mib_operations do
    IO.puts """

    📚 MIB Operations (SnmpKit.MIB)
    ===============================
    """

    # MIB name resolution
    IO.puts "• Resolving OID names to numeric OIDs:"

    test_names = [
      "sysDescr.0",
      "sysUpTime.0",
      "ifDescr.1",
      "system",
      "interfaces"
    ]

    Enum.each(test_names, fn name ->
      case SnmpKit.MIB.resolve(name) do
        {:ok, oid} ->
          IO.puts "  ✓ #{name} → #{Enum.join(oid, ".")}"
        {:error, reason} ->
          IO.puts "  ✗ #{name} → #{reason}"
      end
    end)

    # Reverse lookup
    IO.puts "\n• Reverse OID lookup:"
    case SnmpKit.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0]) do
      {:ok, name} ->
        IO.puts "  ✓ 1.3.6.1.2.1.1.1.0 → #{name}"
      {:error, reason} ->
        IO.puts "  ✗ Reverse lookup failed: #{reason}"
    end
  end

  defp demo_snmp_operations do
    IO.puts """

    📡 SNMP Operations (SnmpKit.SNMP)
    =================================
    """

    # Note: Using invalid host to demonstrate API without needing real SNMP device
    target = "198.51.100.1"  # RFC 5737 test address

    IO.puts "• Testing SNMP operations (expect connection errors with test address):"

    # Basic GET operation
    IO.puts "\n  - Basic GET:"
    case SnmpKit.SNMP.get(target, "sysDescr.0", timeout: 100) do
      {:ok, value} ->
        IO.puts "    ✓ Got system description: #{value}"
      {:error, reason} ->
        IO.puts "    ✗ Expected error (test address): #{inspect(reason)}"
    end

    # Walk operation
    IO.puts "\n  - SNMP Walk:"
    case SnmpKit.SNMP.walk(target, "system", timeout: 100) do
      {:ok, results} when is_list(results) ->
        IO.puts "    ✓ Walk completed: #{length(results)} objects"
      {:error, reason} ->
        IO.puts "    ✗ Expected error (test address): #{inspect(reason)}"
    end

    # Pretty formatting
    IO.puts "\n  - Pretty formatting:"
    case SnmpKit.SNMP.get_pretty(target, "sysUpTime.0", timeout: 100) do
      {:ok, formatted} ->
        IO.puts "    ✓ Formatted result: #{formatted}"
      {:error, reason} ->
        IO.puts "    ✗ Expected error (test address): #{inspect(reason)}"
    end
  end

  defp demo_direct_api do
    IO.puts """

    🎯 Direct API Access (SnmpKit)
    ==============================

    For backward compatibility and convenience, common operations
    are also available directly on the main SnmpKit module:
    """

    # Direct access examples
    IO.puts "• Direct SnmpKit access:"

    case SnmpKit.resolve("ifInOctets.1") do
      {:ok, oid} ->
        IO.puts "  ✓ SnmpKit.resolve(\"ifInOctets.1\") → #{Enum.join(oid, ".")}"
      error ->
        IO.puts "  ✗ #{inspect(error)}"
    end

    # Show that it's the same as the namespaced version
    case SnmpKit.MIB.resolve("ifInOctets.1") do
      {:ok, oid} ->
        IO.puts "  ✓ SnmpKit.MIB.resolve(\"ifInOctets.1\") → #{Enum.join(oid, ".")} (same result)"
      error ->
        IO.puts "  ✗ #{inspect(error)}"
    end
  end

  defp demo_api_organization do
    IO.puts """

    🏗️  API Organization
    ====================

    The SnmpKit API is organized into logical modules:

    📡 SnmpKit.SNMP - SNMP Protocol Operations
       • get, set, walk, bulk operations
       • Multi-target and async operations
       • Pretty formatting and analysis
       • Engine and performance features

    📚 SnmpKit.MIB - MIB Management
       • OID name resolution and reverse lookup
       • MIB compilation and loading
       • Tree navigation and analysis
       • Both high-level and low-level operations

    🧪 SnmpKit.Sim - Device Simulation
       • Start simulated SNMP devices
       • Create device populations for testing
       • Profile-based device behavior

    🎯 SnmpKit - Direct Access
       • Common operations for convenience
       • Backward compatibility
       • Simple one-import access

    Examples:

    ```elixir
    # SNMP operations
    {:ok, value} = SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")
    {:ok, table} = SnmpKit.SNMP.get_table("192.168.1.1", "ifTable")
    {:ok, results} = SnmpKit.SNMP.walk_multi([
      {"host1", "system"},
      {"host2", "interfaces"}
    ])

    # MIB operations
    {:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
    {:ok, compiled} = SnmpKit.MIB.compile("MY-MIB.mib")
    {:ok, children} = SnmpKit.MIB.children([1, 3, 6, 1, 2, 1, 1])

    # Simulation
    profile = SnmpKit.SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, "device.walk"})
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: 1161)

    # Direct access (backward compatibility)
    {:ok, value} = SnmpKit.get("192.168.1.1", "sysDescr.0")
    {:ok, oid} = SnmpKit.resolve("sysDescr.0")
    ```
    """

    IO.puts """

    ✅ Benefits of the Unified API:

    • Clean Organization: Logical grouping of related functions
    • No Conflicts: Context prevents naming conflicts between modules
    • Discoverability: Easy to find functions by context
    • Backward Compatibility: Existing code continues to work
    • Flexibility: Use namespaced or direct access as preferred
    • Documentation: Clear module boundaries and purposes

    🎉 The unified API makes SnmpKit more approachable for new users
       while maintaining all the power and flexibility for advanced use cases!
    """
  end
end

# Run the demo
UnifiedAPIDemo.run()
