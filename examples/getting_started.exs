#!/usr/bin/env elixir

# SnmpKit Getting Started Example
# ==============================
#
# This example demonstrates the core features of SnmpKit by creating a simulated
# SNMP device and then performing various operations against it.
#
# Run this script with: elixir examples/getting_started.exs

Mix.install([
  {:snmpkit, "~> 1.0"}
])

defmodule GettingStartedExample do
  @moduledoc """
  A comprehensive getting started example for SnmpKit.

  This module demonstrates:
  - Device simulation
  - Basic SNMP operations
  - MIB operations
  - Error handling
  - Advanced features
  """

  alias SnmpKit.{SNMP, MIB, Sim}

  def run do
    IO.puts("""

    🚀 SnmpKit Getting Started Example
    ==================================

    This example will guide you through SnmpKit's core features:
    1. Create a simulated SNMP device
    2. Perform basic SNMP operations
    3. Explore MIB functionality
    4. Demonstrate advanced features

    """)

    with {:ok, device_info} <- setup_simulated_device(),
         :ok <- demonstrate_basic_operations(device_info),
         :ok <- demonstrate_mib_operations(),
         :ok <- demonstrate_advanced_features(device_info),
         :ok <- cleanup(device_info) do

      IO.puts("""

      ✅ Example completed successfully!

      Next steps:
      - Explore the API documentation: https://hexdocs.pm/snmpkit
      - Try the interactive Livebook: livebooks/snmpkit_tour.livemd
      - Read the guides: docs/mib-guide.md and docs/testing-guide.md
      - Check out more examples in the examples/ directory

      """)
    else
      {:error, reason} ->
        IO.puts("❌ Example failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp setup_simulated_device do
    IO.puts("📡 Setting up simulated SNMP device...")

    # Create a custom device profile with realistic data
    device_profile = %{
      name: "Example Router",
      description: "Getting Started Example Device",
      objects: create_device_objects()
    }

    # Start the simulated device
    case Sim.start_device(device_profile, port: 30161) do
      {:ok, device} ->
        target = "127.0.0.1:30161"

        # Wait for device to be ready
        :timer.sleep(100)

        IO.puts("✅ Simulated device started on #{target}")
        {:ok, %{device: device, target: target}}

      {:error, reason} ->
        IO.puts("❌ Failed to start device: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_device_objects do
    %{
      # System group
      [1, 3, 6, 1, 2, 1, 1, 1, 0] => "SnmpKit Example Router v1.0 - Getting Started Demo",
      [1, 3, 6, 1, 2, 1, 1, 2, 0] => [1, 3, 6, 1, 4, 1, 99999, 1, 1],
      [1, 3, 6, 1, 2, 1, 1, 3, 0] => 12345,
      [1, 3, 6, 1, 2, 1, 1, 4, 0] => "Example Admin <admin@example.com>",
      [1, 3, 6, 1, 2, 1, 1, 5, 0] => "getting-started-router",
      [1, 3, 6, 1, 2, 1, 1, 6, 0] => "SnmpKit Demo Lab",
      [1, 3, 6, 1, 2, 1, 1, 7, 0] => 72, # supports application, internet, end-to-end

      # Interface table - simulate 4 interfaces
      [1, 3, 6, 1, 2, 1, 2, 1, 0] => 4, # ifNumber

      # Interface 1 - Loopback
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1] => 1,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1] => "lo0",
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 1] => 24, # softwareLoopback
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 1] => 10_000_000,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 1] => 1, # up
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1] => 1_000_000,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 1] => 500_000,

      # Interface 2 - Ethernet
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 2] => 2,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 2] => "eth0",
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 2] => 6, # ethernetCsmacd
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 2] => 1_000_000_000,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 2] => 1, # up
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 2] => 50_000_000,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 2] => 25_000_000,

      # Interface 3 - Another Ethernet (down)
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 3] => 3,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 3] => "eth1",
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 3] => 6,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 3] => 1_000_000_000,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 3] => 2, # down
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 3] => 0,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 3] => 0,

      # Interface 4 - Serial
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 4] => 4,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 4] => "serial0",
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 4] => 22, # propPointToPointSerial
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 4] => 1_544_000,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 4] => 1, # up
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 4] => 10_000_000,
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 4] => 8_000_000
    }
  end

  defp demonstrate_basic_operations(%{target: target}) do
    IO.puts("""

    📡 Demonstrating Basic SNMP Operations
    =====================================
    """)

    # GET operation
    IO.puts("🔍 GET Operation:")
    case SNMP.get(target, "sysDescr.0") do
      {:ok, %{formatted: description}} ->
        IO.puts("   System Description: #{description}")
      {:error, reason} ->
        IO.puts("   ❌ GET failed: #{inspect(reason)}")
        return {:error, reason}
    end

    # Multiple GET operations
    IO.puts("\n🔍 Multiple GET Operations:")
    system_oids = ["sysDescr.0", "sysUpTime.0", "sysName.0", "sysLocation.0"]

    for oid <- system_oids do
      case SNMP.get(target, oid) do
        {:ok, %{formatted: formatted}} ->
          IO.puts("   #{oid}: #{formatted}")
        {:ok, %{value: value}} ->
          IO.puts("   #{oid}: #{inspect(value)}")
        {:error, reason} ->
          IO.puts("   #{oid}: ❌ #{inspect(reason)}")
      end
    end

    # WALK operation
    IO.puts("\n🚶 WALK Operation (System Group):")
    case SNMP.walk(target, "system") do
      {:ok, results} ->
        IO.puts("   Found #{length(results)} objects in system group:")
        results
        |> Enum.take(5)
        |> Enum.each(fn %{oid: oid_str, formatted: formatted} ->
          IO.puts("     #{oid_str} = #{formatted}")
        end)
        if length(results) > 5 do
          IO.puts("     ... and #{length(results) - 5} more")
        end
      {:error, reason} ->
        IO.puts("   ❌ WALK failed: #{inspect(reason)}")
        return {:error, reason}
    end

    # Interface table walk
    IO.puts("\n🌐 Interface Table Walk:")
    case SNMP.walk(target, "ifTable") do
      {:ok, results} ->
        IO.puts("   Found #{length(results)} interface objects")

        # Group by interface index
        interfaces = group_interface_data(results)

        for {index, data} <- interfaces do
          name = Map.get(data, "ifDescr", "unknown")
          status = case Map.get(data, "ifOperStatus") do
            1 -> "UP"
            2 -> "DOWN"
            n -> "UNKNOWN(#{n})"
          end
          IO.puts("     Interface #{index}: #{name} - #{status}")
        end
      {:error, reason} ->
        IO.puts("   ❌ Interface walk failed: #{inspect(reason)}")
    end

    :ok
  end

  defp group_interface_data(results) do
    results
    |> Enum.reduce(%{}, fn %{oid: oid_str, value: value}, acc ->
      case SnmpKit.SnmpLib.OID.string_to_list(oid_str) do
        {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, column, index]} ->
          interface_data = Map.get(acc, index, %{})
          field_name = case column do
            2 -> "ifDescr"
            8 -> "ifOperStatus"
            _ -> "other"
          end
          Map.put(acc, index, Map.put(interface_data, field_name, value))
        _ ->
          acc
      end
    end)
  end

  defp demonstrate_mib_operations do
    IO.puts("""

    📚 Demonstrating MIB Operations
    ===============================
    """)

    # OID resolution
    IO.puts("🔍 OID Resolution:")
    test_oids = [
      "sysDescr.0",
      "sysUpTime.0",
      "ifTable",
      "ifInOctets.1"
    ]

    for oid_name <- test_oids do
      case MIB.resolve(oid_name) do
        {:ok, oid} ->
          oid_str = Enum.join(oid, ".")
          IO.puts("   #{oid_name} → #{oid_str}")
        {:error, reason} ->
          IO.puts("   #{oid_name} → ❌ #{inspect(reason)}")
      end
    end

    # Reverse lookup
    IO.puts("\n🔄 Reverse OID Lookup:")
    test_numeric_oids = [
      [1, 3, 6, 1, 2, 1, 1, 1, 0],
      [1, 3, 6, 1, 2, 1, 1, 3, 0],
      [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1]
    ]

    for oid <- test_numeric_oids do
      oid_str = Enum.join(oid, ".")
      case MIB.reverse_lookup(oid) do
        {:ok, name} ->
          IO.puts("   #{oid_str} → #{name}")
        {:error, reason} ->
          IO.puts("   #{oid_str} → ❌ #{inspect(reason)}")
      end
    end

    # Tree navigation
    IO.puts("\n🌳 MIB Tree Navigation:")
    case MIB.resolve("system") do
      {:ok, system_oid} ->
        IO.puts("   System OID: #{Enum.join(system_oid, ".")}")

        case MIB.children(system_oid) do
          {:ok, children} ->
            IO.puts("   System has #{length(children)} child objects")
            for child_oid <- Enum.take(children, 3) do
              case MIB.reverse_lookup(child_oid) do
                {:ok, name} ->
                  IO.puts("     - #{name}")
                {:error, _} ->
                  IO.puts("     - #{Enum.join(child_oid, ".")}")
              end
            end
          {:error, reason} ->
            IO.puts("   ❌ Could not get children: #{inspect(reason)}")
        end
      {:error, reason} ->
        IO.puts("   ❌ Could not resolve system: #{inspect(reason)}")
    end

    :ok
  end

  defp demonstrate_advanced_features(%{target: target}) do
    IO.puts("""

    ⚡ Demonstrating Advanced Features
    =================================
    """)

    # Bulk operations
    IO.puts("📦 Bulk Walk Operation:")
    case SNMP.bulk_walk(target, "system") do
      {:ok, results} ->
        IO.puts("   Bulk walk retrieved #{length(results)} objects")
      {:error, reason} ->
        IO.puts("   ❌ Bulk walk failed: #{inspect(reason)}")
    end

    # Async operations
    IO.puts("\n🚀 Async Operations:")
    async_tasks = [
      Task.async(fn -> SNMP.get(target, "sysDescr.0") end),
      Task.async(fn -> SNMP.get(target, "sysUpTime.0") end),
      Task.async(fn -> SNMP.get(target, "sysName.0") end)
    ]

    results = Task.await_many(async_tasks, 5000)
    IO.puts("   Completed #{length(results)} async operations")

    for {i, result} <- Enum.with_index(results, 1) do
      case result do
        {:ok, value} ->
          IO.puts("     Task #{i}: Success - #{inspect(value)}")
        {:error, reason} ->
          IO.puts("     Task #{i}: Error - #{inspect(reason)}")
      end
    end

    # Performance timing
    IO.puts("\n⏱️  Performance Timing:")
    {time, result} = :timer.tc(fn ->
      SNMP.walk(target, "system")
    end)

    case result do
      {:ok, objects} ->
        time_ms = time / 1000
        IO.puts("   System walk: #{length(objects)} objects in #{:erlang.float_to_binary(time_ms, decimals: 2)}ms")
      {:error, reason} ->
        IO.puts("   ❌ Timing test failed: #{inspect(reason)}")
    end

    # Error handling demonstration
    IO.puts("\n❌ Error Handling:")
    test_cases = [
      {"Non-existent host", "192.0.2.1", "sysDescr.0"},
      {"Invalid OID", target, "nonExistent.0"},
      {"Timeout test", target, "sysDescr.0"}
    ]

    for {test_name, test_target, test_oid} <- test_cases do
      timeout = if String.contains?(test_name, "Timeout"), do: 100, else: 2000

      case SNMP.get(test_target, test_oid, timeout: timeout) do
        {:ok, _value} ->
          IO.puts("   #{test_name}: Unexpected success")
        {:error, reason} ->
          IO.puts("   #{test_name}: Expected error - #{inspect(reason)}")
      end
    end

    :ok
  end

  defp cleanup(%{device: device}) do
    IO.puts("""

    🧹 Cleanup
    ==========
    """)

    # Stop the simulated device
    if Process.alive?(device) do
      GenServer.stop(device)
      IO.puts("✅ Simulated device stopped")
    end

    :ok
  end
end

# Print banner
IO.puts("""

  ███████╗███╗   ██╗███╗   ███╗██████╗ ██╗  ██╗██╗████████╗
  ██╔════╝████╗  ██║████╗ ████║██╔══██╗██║ ██╔╝██║╚══██╔══╝
  ███████╗██╔██╗ ██║██╔████╔██║██████╔╝█████╔╝ ██║   ██║
  ╚════██║██║╚██╗██║██║╚██╔╝██║██╔═══╝ ██╔═██╗ ██║   ██║
  ███████║██║ ╚████║██║ ╚═╝ ██║██║     ██║  ██╗██║   ██║
  ╚══════╝╚═╝  ╚═══╝╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝   ╚═╝

  A modern, comprehensive SNMP toolkit for Elixir
  Version 1.0 - Getting Started Example

""")

# Run the example
GettingStartedExample.run()
