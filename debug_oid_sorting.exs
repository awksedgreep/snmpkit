#!/usr/bin/env elixir

# Enhanced debug script to test OID sorting and simulator walk operations
# Tests the complete flow from manual OID definitions to SNMP walk operations

Mix.install([
  {:snmpkit, path: "."}
])

defmodule OIDSortingDebug do
  @moduledoc """
  Comprehensive debug helper to test OID sorting, device state, and walk operations
  """

  def test_oid_sorting do
    IO.puts("=== Testing OID Sorting Logic ===\n")

    # Sample OIDs like what we create in the Livebook
    sample_oids = [
      "1.3.6.1.2.1.1.1.0",
      "1.3.6.1.2.1.1.3.0",
      "1.3.6.1.2.1.1.4.0",
      "1.3.6.1.2.1.1.5.0",
      "1.3.6.1.2.1.2.1.0",
      "1.3.6.1.2.1.2.2.1.1.1",
      "1.3.6.1.2.1.2.2.1.1.2",
      "1.3.6.1.2.1.2.2.1.2.1",
      "1.3.6.1.2.1.2.2.1.2.2"
    ]

    IO.puts("Original OIDs:")
    Enum.each(sample_oids, fn oid -> IO.puts("  #{oid}") end)

    # Test string sorting (wrong way)
    string_sorted = Enum.sort(sample_oids)
    IO.puts("\nString sorted (WRONG):")
    Enum.each(string_sorted, fn oid -> IO.puts("  #{oid}") end)

    # Test numeric sorting (correct way)
    numeric_sorted = Enum.sort_by(sample_oids, &parse_oid/1)
    IO.puts("\nNumeric sorted (CORRECT):")
    Enum.each(numeric_sorted, fn oid -> IO.puts("  #{oid}") end)

    # Test using the built-in OID library
    oid_lib_sorted =
      sample_oids
      |> Enum.map(&string_to_oid_list/1)
      |> SnmpKit.SnmpLib.OID.sort()
      |> Enum.map(&oid_list_to_string/1)
    IO.puts("\nOID library sorted (BEST):")
    Enum.each(oid_lib_sorted, fn oid -> IO.puts("  #{oid}") end)

    # Test get_next logic
    IO.puts("\n=== Testing get_next logic ===")
    test_get_next(numeric_sorted, "1.3.6.1.2.1.1.1.0")
    test_get_next(numeric_sorted, "1.3.6.1.2.1.1.2")  # Non-existent middle OID
    test_get_next(numeric_sorted, "1.3.6.1.2.1.2.2.1.2.2") # Last OID
    test_get_next(numeric_sorted, "1.3.6.1.2.1.1") # Partial OID - should find first child
  end

  def test_manual_device_creation do
    IO.puts("\n=== Testing Manual Device Creation ===\n")

    # Create the same OIDs as in the Livebook with mixed value types
    cable_modem_oids = %{
      "1.3.6.1.2.1.1.1.0" => "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem",
      "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 0},
      "1.3.6.1.2.1.1.4.0" => "admin@example.com",
      "1.3.6.1.2.1.1.5.0" => "cm-001",
      "1.3.6.1.2.1.2.1.0" => 2,
      "1.3.6.1.2.1.2.2.1.1.1" => 1,
      "1.3.6.1.2.1.2.2.1.1.2" => 2,
      "1.3.6.1.2.1.2.2.1.2.1" => "cable-downstream0",
      "1.3.6.1.2.1.2.2.1.2.2" => "cable-upstream0"
    }

    IO.puts("Creating manual device profile...")
    case SnmpKit.SnmpSim.ProfileLoader.load_profile(
      :debug_cable_modem,
      {:manual, cable_modem_oids},
      behaviors: [:counter_increment]
    ) do
      {:ok, profile} ->
        IO.puts("✅ Profile created successfully")
        IO.puts("Profile contains #{map_size(profile.oid_map)} OIDs")

        # Debug profile structure
        IO.puts("\nProfile structure:")
        IO.puts("  device_type: #{inspect(profile.device_type)}")
        IO.puts("  source_type: #{inspect(profile.source_type)}")
        IO.puts("  behaviors: #{inspect(profile.behaviors)}")
        IO.puts("  oid_map sample:")
        profile.oid_map
        |> Enum.take(3)
        |> Enum.each(fn {oid, value} ->
          IO.puts("    #{oid} => #{inspect(value)}")
        end)

        # Try to start the device
        case SnmpKit.Sim.start_device(profile, port: 9999, community: "public") do
          {:ok, device} ->
            IO.puts("✅ Device started successfully (PID: #{inspect(device)})")

            # Check device state
            test_device_state(device)

            # Test operations
            test_device_operations(device, "127.0.0.1:9999")

            # Cleanup
            SnmpKit.SnmpSim.Device.stop(device)
            Process.sleep(100)  # Give time for cleanup

          {:error, reason} ->
            IO.puts("❌ Device failed to start: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Profile creation failed: #{inspect(reason)}")
    end
  end

  defp test_device_state(device) do
    IO.puts("\n--- Testing Device State ---")

    try do
      state = :sys.get_state(device)
      IO.puts("Device state keys: #{inspect(Map.keys(state))}")

      # Check if oid_map is present
      case Map.get(state, :oid_map) do
        nil ->
          IO.puts("❌ Device state missing :oid_map")
        oid_map when map_size(oid_map) == 0 ->
          IO.puts("❌ Device :oid_map is empty")
        oid_map ->
          IO.puts("✅ Device has :oid_map with #{map_size(oid_map)} entries")
          IO.puts("  has_walk_data: #{inspect(Map.get(state, :has_walk_data))}")

          # Show a few OID entries
          oid_map
          |> Enum.take(3)
          |> Enum.each(fn {oid, value} ->
            IO.puts("    #{oid} => #{inspect(value)}")
          end)
      end
    rescue
      error ->
        IO.puts("❌ Failed to get device state: #{inspect(error)}")
    end
  end

  defp test_device_operations(device, target) do
    IO.puts("\n--- Testing Device Operations ---")

    # Test basic GET
    case SnmpKit.SNMP.get(target, "1.3.6.1.2.1.1.1.0") do
      {:ok, value} ->
        IO.puts("✅ GET works: #{value}")
      {:error, reason} ->
        IO.puts("❌ GET failed: #{inspect(reason)}")
    end

    # Test get_next on individual OIDs at device level
    IO.puts("\nTesting device-level get_next operations:")
    test_oids = [
      "1.3.6.1.2.1.1.1.0",
      "1.3.6.1.2.1.1.2",  # Should find 1.3.6.1.2.1.1.3.0
      "1.3.6.1.2.1.1",    # Should find first child
      "1.3.6.1.2.1.2",    # Should find 1.3.6.1.2.1.2.1.0
      "1.3.6.1.2.1"       # Should find 1.3.6.1.2.1.1.1.0
    ]

    Enum.each(test_oids, fn oid ->
      try do
        case GenServer.call(device, {:get_next_oid, oid}, 5000) do
          {:ok, {next_oid, type, value}} ->
            IO.puts("  ✅ get_next(#{oid}) → #{next_oid} (#{type}): #{inspect(value)}")
          {:error, reason} ->
            IO.puts("  ❌ get_next(#{oid}) failed: #{inspect(reason)}")
          other ->
            IO.puts("  ❓ get_next(#{oid}) unexpected: #{inspect(other)}")
        end
      catch
        :exit, {:timeout, _} ->
          IO.puts("  ⏰ get_next(#{oid}) timeout")
        error ->
          IO.puts("  💥 get_next(#{oid}) crashed: #{inspect(error)}")
      end
    end)

    # Test walk operation at device level
    IO.puts("\nTesting device-level walk operations:")
    walk_roots = ["1.3.6.1.2.1.1", "1.3.6.1.2.1.2", "1.3.6.1.2.1"]

    Enum.each(walk_roots, fn root ->
      try do
        case GenServer.call(device, {:walk_oid, root}, 10000) do
          {:ok, results} ->
            IO.puts("  ✅ walk(#{root}) returned #{length(results)} results:")
            results
            |> Enum.sort_by(fn {oid, _, _} -> parse_oid(oid) end)
            |> Enum.take(5)
            |> Enum.each(fn {oid, type, value} ->
              IO.puts("    #{oid} (#{type}): #{inspect(value)}")
            end)
            if length(results) > 5, do: IO.puts("    ... and #{length(results) - 5} more")
          {:error, reason} ->
            IO.puts("  ❌ walk(#{root}) failed: #{inspect(reason)}")
          other ->
            IO.puts("  ❓ walk(#{root}) unexpected: #{inspect(other)}")
        end
      catch
        :exit, {:timeout, _} ->
          IO.puts("  ⏰ walk(#{root}) timeout")
        error ->
          IO.puts("  💥 walk(#{root}) crashed: #{inspect(error)}")
      end
    end)

    # Test SNMP.walk (higher level - the real test!)
    IO.puts("\nTesting SnmpKit.SNMP.walk (this is the main test!):")
    walk_tests = [
      "1.3.6.1.2.1.1",
      "1.3.6.1.2.1.2",
      "system"  # Named OID
    ]

    Enum.each(walk_tests, fn root ->
      try do
        case SnmpKit.SNMP.walk(target, root, timeout: 10000) do
          {:ok, results} ->
            IO.puts("  ✅ SNMP.walk(#{root}) returned #{length(results)} results:")
            results
            |> Enum.take(5)
            |> Enum.each(fn {oid, value} ->
              IO.puts("    #{oid}: #{inspect(value)}")
            end)
            if length(results) > 5, do: IO.puts("    ... and #{length(results) - 5} more")
          {:error, reason} ->
            IO.puts("  ❌ SNMP.walk(#{root}) failed: #{inspect(reason)}")
        end
      catch
        error ->
          IO.puts("  💥 SNMP.walk(#{root}) crashed: #{inspect(error)}")
      end
    end)

    # Test SNMP.get_next (lower level protocol test)
    IO.puts("\nTesting SnmpKit.SNMP.get_next:")
    get_next_tests = [
      "1.3.6.1.2.1.1.1.0",
      "1.3.6.1.2.1.1",
      "1.3.6.1.2.1"
    ]

    Enum.each(get_next_tests, fn oid ->
      case SnmpKit.SNMP.get_next(target, oid) do
        {:ok, {next_oid, value}} ->
          IO.puts("  ✅ get_next(#{oid}) → #{next_oid}: #{inspect(value)}")
        {:error, reason} ->
          IO.puts("  ❌ get_next(#{oid}) failed: #{inspect(reason)}")
      end
    end)
  end

  defp test_get_next(sorted_oids, target_oid) do
    IO.puts("Testing get_next for '#{target_oid}':")

    target_parts = parse_oid(target_oid)

    result = Enum.find(sorted_oids, fn candidate ->
      candidate_parts = parse_oid(candidate)
      compare_oids(candidate_parts, target_parts) == :gt
    end)

    case result do
      nil -> IO.puts("  → End of MIB (no next OID)")
      next_oid -> IO.puts("  → #{next_oid}")
    end
  end

  defp parse_oid(oid_string) do
    oid_string
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end

  defp string_to_oid_list(oid_string) do
    oid_string
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end

  defp oid_list_to_string(oid_list) do
    oid_list
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
  end

  defp compare_oids([], []), do: :eq
  defp compare_oids([], _), do: :lt
  defp compare_oids(_, []), do: :gt
  defp compare_oids([h1 | t1], [h2 | t2]) when h1 < h2, do: :lt
  defp compare_oids([h1 | t1], [h2 | t2]) when h1 > h2, do: :gt
  defp compare_oids([h1 | t1], [h2 | t2]) when h1 == h2, do: compare_oids(t1, t2)

  # New comprehensive test runner
  def run_comprehensive_tests do
    IO.puts("🔍 SnmpKit Simulator Walk Fix - Comprehensive Test Suite")
    IO.puts("=" |> String.duplicate(60))

    test_oid_sorting()
    test_profile_creation()
    test_manual_device_creation()
    test_edge_cases()

    IO.puts("\n🎯 All tests complete!")
  end

  def test_profile_creation do
    IO.puts("\n=== Testing Profile Creation Variations ===\n")

    # Test 1: Simple string values
    simple_oids = %{
      "1.3.6.1.2.1.1.1.0" => "Simple string value",
      "1.3.6.1.2.1.1.2.0" => "Another string"
    }

    test_profile_variant("Simple strings", simple_oids)

    # Test 2: Mixed value types
    mixed_oids = %{
      "1.3.6.1.2.1.1.1.0" => "String value",
      "1.3.6.1.2.1.1.2.0" => 42,
      "1.3.6.1.2.1.1.3.0" => %{type: "Counter32", value: 1000}
    }

    test_profile_variant("Mixed types", mixed_oids)

    # Test 3: Empty OID map
    empty_oids = %{}
    test_profile_variant("Empty map", empty_oids)
  end

  defp test_profile_variant(name, oid_map) do
    IO.puts("Testing #{name}:")
    case SnmpKit.SnmpSim.ProfileLoader.load_profile(
      :test_device,
      {:manual, oid_map}
    ) do
      {:ok, profile} ->
        IO.puts("  ✅ Profile created with #{map_size(profile.oid_map)} OIDs")
      {:error, reason} ->
        IO.puts("  ❌ Profile creation failed: #{inspect(reason)}")
    end
  end

  def test_edge_cases do
    IO.puts("\n=== Testing Edge Cases ===\n")

    # Test sparse OID map (gaps in the tree)
    sparse_oids = %{
      "1.3.6.1.2.1.1.1.0" => "First",
      "1.3.6.1.2.1.1.5.0" => "Fifth (missing 2,3,4)",
      "1.3.6.1.2.1.2.1.0" => "Different subtree",
      "1.3.6.1.4.1.100.1.0" => "Enterprise OID"
    }

    IO.puts("Testing sparse OID tree...")
    case SnmpKit.SnmpSim.ProfileLoader.load_profile(
      :sparse_device,
      {:manual, sparse_oids}
    ) do
      {:ok, profile} ->
        IO.puts("✅ Sparse profile created")

        case SnmpKit.Sim.start_device(profile, port: 9998) do
          {:ok, device} ->
            IO.puts("✅ Sparse device started")

            # Test walking sparse tree
            IO.puts("Testing sparse tree walk:")
            try do
              case SnmpKit.SNMP.walk("127.0.0.1:9998", "1.3.6.1.2.1.1") do
                {:ok, results} ->
                  IO.puts("  ✅ Sparse walk returned #{length(results)} results")
                  Enum.each(results, fn {oid, value} ->
                    IO.puts("    #{oid}: #{inspect(value)}")
                  end)
                {:error, reason} ->
                  IO.puts("  ❌ Sparse walk failed: #{inspect(reason)}")
              end
            after
              SnmpKit.SnmpSim.Device.stop(device)
            end

          {:error, reason} ->
            IO.puts("❌ Sparse device failed to start: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Sparse profile creation failed: #{inspect(reason)}")
    end
  end
end

# Run the comprehensive tests
OIDSortingDebug.run_comprehensive_tests()
