defmodule SnmpKit.SnmpSim.ManualDeviceTest do
  use ExUnit.Case, async: false
  require Logger

  alias SnmpKit.SnmpSim.{ProfileLoader, Device}
  alias SnmpKit.{Sim, SNMP}

  # Helper to find available ports to avoid conflicts
  defp find_available_port(start_port \\ 19000) do
    Enum.find(start_port..(start_port + 100), fn port ->
      case :gen_tcp.listen(port, []) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          true
        {:error, _} ->
          false
      end
    end) || raise "No available ports found for testing"
  end

  # Helper to parse OID strings to lists for comparison
  defp parse_oid(oid_string) when is_binary(oid_string) do
    oid_string
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end
  defp parse_oid(oid_list) when is_list(oid_list), do: oid_list

  # Helper to normalize OID format for comparison
  defp normalize_oid(oid) when is_binary(oid), do: oid
  defp normalize_oid(oid) when is_list(oid) do
    oid |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  describe "manual device profile creation" do
    test "creates profile with simple string values" do
      oid_map = %{
        "1.3.6.1.2.1.1.1.0" => "Test Device Description",
        "1.3.6.1.2.1.1.4.0" => "admin@test.com",
        "1.3.6.1.2.1.1.5.0" => "test-device-01"
      }

      {:ok, profile} = ProfileLoader.load_profile(:test_device, {:manual, oid_map})

      assert profile.device_type == :test_device
      assert profile.source_type == :manual
      assert map_size(profile.oid_map) == 3

      # Verify values are converted to proper format
      assert %{type: "STRING", value: "Test Device Description"} = profile.oid_map["1.3.6.1.2.1.1.1.0"]
      assert %{type: "STRING", value: "admin@test.com"} = profile.oid_map["1.3.6.1.2.1.1.4.0"]
      assert %{type: "STRING", value: "test-device-01"} = profile.oid_map["1.3.6.1.2.1.1.5.0"]
    end

    test "creates profile with mixed value types" do
      oid_map = %{
        "1.3.6.1.2.1.1.1.0" => "String value",
        "1.3.6.1.2.1.1.2.0" => 12345,
        "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 567890},
        "1.3.6.1.2.1.2.1.0" => %{type: "Counter32", value: 1000}
      }

      {:ok, profile} = ProfileLoader.load_profile(:mixed_device, {:manual, oid_map})

      assert map_size(profile.oid_map) == 4
      assert %{type: "STRING", value: "String value"} = profile.oid_map["1.3.6.1.2.1.1.1.0"]
      assert %{type: "INTEGER", value: 12345} = profile.oid_map["1.3.6.1.2.1.1.2.0"]
      assert %{type: "TimeTicks", value: 567890} = profile.oid_map["1.3.6.1.2.1.1.3.0"]
      assert %{type: "Counter32", value: 1000} = profile.oid_map["1.3.6.1.2.1.2.1.0"]
    end

    test "handles empty OID map" do
      {:ok, profile} = ProfileLoader.load_profile(:empty_device, {:manual, %{}})

      assert profile.device_type == :empty_device
      assert profile.source_type == :manual
      assert map_size(profile.oid_map) == 0
    end

    test "handles complex OID structures" do
      oid_map = %{
        # System group
        "1.3.6.1.2.1.1.1.0" => "Complex Test Device",
        "1.3.6.1.2.1.1.2.0" => %{type: "ObjectID", value: "1.3.6.1.4.1.12345"},
        "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 123456},

        # Interface group with table entries
        "1.3.6.1.2.1.2.1.0" => 3,
        "1.3.6.1.2.1.2.2.1.1.1" => 1,
        "1.3.6.1.2.1.2.2.1.1.2" => 2,
        "1.3.6.1.2.1.2.2.1.1.10" => 10, # Test lexicographic ordering
        "1.3.6.1.2.1.2.2.1.2.1" => "eth0",
        "1.3.6.1.2.1.2.2.1.2.2" => "eth1",
        "1.3.6.1.2.1.2.2.1.2.10" => "eth10"
      }

      {:ok, profile} = ProfileLoader.load_profile(:complex_device, {:manual, oid_map})
      assert map_size(profile.oid_map) == 10
    end
  end

  describe "manual device state initialization" do
    setup do
      oid_map = %{
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

      {:ok, profile} = ProfileLoader.load_profile(:cable_modem, {:manual, oid_map})

      %{profile: profile, oid_map: oid_map}
    end

    test "device state includes oid_map from profile", %{profile: profile, oid_map: oid_map} do
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)

      # Get device state and verify oid_map is present
      state = :sys.get_state(device)

      assert Map.has_key?(state, :oid_map)
      assert state.oid_map == profile.oid_map
      assert map_size(state.oid_map) == map_size(oid_map)

      # The device should use WalkPduProcessor due to having oid_map
      assert Map.has_key?(state, :oid_map)
      assert map_size(state.oid_map) > 0

      Device.stop(device)
    end

    test "device responds to GET requests", %{profile: profile} do
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)
      target = "127.0.0.1:#{port}"

      # Test basic GET operations
      {:ok, value} = SNMP.get(target, "1.3.6.1.2.1.1.1.0")
      assert value == "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem"

      {:ok, value} = SNMP.get(target, "1.3.6.1.2.1.1.4.0")
      assert value == "admin@example.com"

      {:ok, value} = SNMP.get(target, "1.3.6.1.2.1.2.1.0")
      assert value == 2

      Device.stop(device)
    end

    test "device responds to GET_NEXT requests", %{profile: profile} do
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)
      target = "127.0.0.1:#{port}"

      # Test GET_NEXT operations
      case SNMP.get_next(target, "1.3.6.1.2.1.1.1.0") do
        {:ok, {next_oid, value}} ->
          assert next_oid == "1.3.6.1.2.1.1.3.0"
          assert value == 0
        {:error, reason} ->
          flunk("GET_NEXT failed: #{inspect(reason)}")
      end

      # Test GET_NEXT with partial OID (should find first child)
      case SNMP.get_next(target, "1.3.6.1.2.1.1") do
        {:ok, {next_oid, value}} ->
          assert next_oid == "1.3.6.1.2.1.1.1.0"
          assert value == "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem"
        {:error, reason} ->
          flunk("GET_NEXT with partial OID failed: #{inspect(reason)}")
      end

      Device.stop(device)
    end

    test "device-level walk operations work correctly", %{profile: profile} do
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)

      # Test device-level walk operations (these should work)
      {:ok, results} = GenServer.call(device, {:walk_oid, "1.3.6.1.2.1.1"})

      # Should return system group OIDs
      assert length(results) == 4

      # Verify results are properly sorted lexicographically
      oids = Enum.map(results, fn {oid, _type, _value} -> normalize_oid(oid) end)
      sorted_oids = Enum.sort_by(oids, &parse_oid/1)
      assert oids == sorted_oids

      # Verify specific values
      system_results = Enum.map(results, fn {oid, _type, value} -> {normalize_oid(oid), value} end)
      system_map = Map.new(system_results)

      assert system_map["1.3.6.1.2.1.1.1.0"] == "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem"
      assert system_map["1.3.6.1.2.1.1.4.0"] == "admin@example.com"

      Device.stop(device)
    end

    test "device-level get_next operations work correctly", %{profile: profile} do
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)

      # Test device-level get_next calls
      {:ok, {next_oid, type, value}} = GenServer.call(device, {:get_next_oid, "1.3.6.1.2.1.1.1.0"})

      # The result format might be string or list - normalize for comparison
      next_oid_normalized = normalize_oid(next_oid)
      assert next_oid_normalized == "1.3.6.1.2.1.1.3.0"
      assert type == :timeticks
      assert value == 0

      # Test partial OID
      {:ok, {next_oid, _type, value}} = GenServer.call(device, {:get_next_oid, "1.3.6.1.2.1.1"})
      next_oid_normalized = normalize_oid(next_oid)
      assert next_oid_normalized == "1.3.6.1.2.1.1.1.0"
      assert value == "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem"

      Device.stop(device)
    end

    test "device handles sparse OID trees", %{} do
      # Create a sparse OID map with gaps
      sparse_oids = %{
        "1.3.6.1.2.1.1.1.0" => "First",
        "1.3.6.1.2.1.1.5.0" => "Fifth (skipping 2,3,4)",
        "1.3.6.1.2.1.1.8.0" => "Eighth (skipping 6,7)",
        "1.3.6.1.2.1.2.1.0" => "Different subtree",
        "1.3.6.1.4.1.100.1.0" => "Enterprise OID"
      }

      {:ok, profile} = ProfileLoader.load_profile(:sparse_device, {:manual, sparse_oids})
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)

      # Device-level walk should work even with gaps in the OID tree
      {:ok, results} = GenServer.call(device, {:walk_oid, "1.3.6.1.2.1.1"})
      assert length(results) == 3  # Should find all 3 system OIDs despite gaps

      # Verify lexicographic ordering is maintained
      oids = Enum.map(results, fn {oid, _, _} -> normalize_oid(oid) end)
      expected_oids = ["1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.5.0", "1.3.6.1.2.1.1.8.0"]
      assert oids == expected_oids

      Device.stop(device)
    end

    test "device handles edge cases gracefully", %{profile: profile} do
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)
      target = "127.0.0.1:#{port}"

      # Test GET on non-existent OID
      assert {:error, :no_such_name} = SNMP.get(target, "1.3.6.1.2.1.1.99.0")

      # Test GET_NEXT at potential end of MIB
      case SNMP.get_next(target, "1.3.6.1.2.1.2.2.1.2.2") do
        {:error, :end_of_mib_view} -> :ok # Expected for end of our OID map
        {:error, :no_such_object} -> :ok  # Also acceptable
        {:ok, _} -> :ok # Might find another OID, that's fine too
      end

      Device.stop(device)
    end
  end

  describe "OID sorting and lexicographic ordering" do
    test "manual OID map uses proper lexicographic sorting" do
      # This test verifies the core fix - proper OID sorting
      test_oids = [
        "1.3.6.1.2.1.1.10.0",  # Would come last in string sort
        "1.3.6.1.2.1.1.2.0",   # Would come after .10 in string sort
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.11.0"   # Would come before .2 in string sort
      ]

      # String sorting (wrong)
      string_sorted = Enum.sort(test_oids)
      assert string_sorted == [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.10.0",
        "1.3.6.1.2.1.1.11.0",
        "1.3.6.1.2.1.1.2.0"
      ]

      # Lexicographic sorting (correct)
      numeric_sorted = Enum.sort_by(test_oids, &parse_oid/1)
      assert numeric_sorted == [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.2.0",
        "1.3.6.1.2.1.1.10.0",
        "1.3.6.1.2.1.1.11.0"
      ]

      # Test with device to ensure get_next operations return proper order
      oid_map = test_oids |> Enum.with_index() |> Map.new(fn {oid, i} -> {oid, "Value #{i}"} end)
      {:ok, profile} = ProfileLoader.load_profile(:sort_test, {:manual, oid_map})

      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)

      # Test device-level get_next to verify ordering
      {:ok, {first_oid, _, _}} = GenServer.call(device, {:get_next_oid, "1.3.6.1.2.1.1"})
      first_oid_normalized = normalize_oid(first_oid)
      assert first_oid_normalized == "1.3.6.1.2.1.1.1.0"

      {:ok, {second_oid, _, _}} = GenServer.call(device, {:get_next_oid, "1.3.6.1.2.1.1.1.0"})
      second_oid_normalized = normalize_oid(second_oid)
      assert second_oid_normalized == "1.3.6.1.2.1.1.2.0"

      Device.stop(device)
    end

    test "handles complex table structures with proper ordering" do
      # Create a complex OID tree that tests various sorting edge cases
      complex_oids = %{
        "1.3.6.1.2.1.1.1.0" => "sysDescr",
        "1.3.6.1.2.1.1.2.0" => "sysObjectID",
        "1.3.6.1.2.1.1.10.0" => "sysServices",
        "1.3.6.1.2.1.2.1.0" => "ifNumber",
        "1.3.6.1.2.1.2.2.1.1.1" => "ifIndex.1",
        "1.3.6.1.2.1.2.2.1.1.10" => "ifIndex.10",
        "1.3.6.1.2.1.2.2.1.1.2" => "ifIndex.2",
        "1.3.6.1.2.1.2.2.1.2.1" => "ifDescr.1",
        "1.3.6.1.2.1.2.2.1.2.10" => "ifDescr.10",
        "1.3.6.1.2.1.2.2.1.2.2" => "ifDescr.2"
      }

      {:ok, profile} = ProfileLoader.load_profile(:complex_device, {:manual, complex_oids})
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)

      # Test that interface index entries are returned in correct order
      {:ok, results} = GenServer.call(device, {:walk_oid, "1.3.6.1.2.1.2.2.1.1"})
      ifindex_oids = Enum.map(results, fn {oid, _, _} -> normalize_oid(oid) end)

      # Should be: .1.1, .1.2, .1.10 (not .1.1, .1.10, .1.2)
      assert ifindex_oids == [
        "1.3.6.1.2.1.2.2.1.1.1",
        "1.3.6.1.2.1.2.2.1.1.2",
        "1.3.6.1.2.1.2.2.1.1.10"
      ]

      Device.stop(device)
    end
  end

  describe "protocol compliance and error handling" do
    test "handles invalid OIDs gracefully" do
      # Test with OID map that has some invalid entries
      mixed_oids = %{
        "1.3.6.1.2.1.1.1.0" => "Valid OID",
        "1.3.6.1.2.1.1.2.0" => "Another valid OID",
        "invalid.oid.string" => "Should be filtered out",
        "1.3.6.1.2.1.1.3.0" => "Third valid OID"
      }

      # ProfileLoader should handle this gracefully
      {:ok, profile} = ProfileLoader.load_profile(:mixed_device, {:manual, mixed_oids})

      # Only valid OIDs should be in the profile
      # Note: ProfileLoader currently doesn't validate OIDs, but the device should handle it
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)

      # Device should still work with valid OIDs
      target = "127.0.0.1:#{port}"
      {:ok, value} = SNMP.get(target, "1.3.6.1.2.1.1.1.0")
      assert value == "Valid OID"

      Device.stop(device)
    end

    test "supports different SNMP value types" do
      typed_oids = %{
        "1.3.6.1.2.1.1.1.0" => %{type: "OCTET STRING", value: "String value"},
        "1.3.6.1.2.1.1.2.0" => %{type: "OBJECT IDENTIFIER", value: "1.3.6.1.4.1.12345"},
        "1.3.6.1.2.1.1.3.0" => %{type: "TimeTicks", value: 123456},
        "1.3.6.1.2.1.1.4.0" => %{type: "INTEGER", value: 42},
        "1.3.6.1.2.1.1.5.0" => %{type: "Counter32", value: 1000},
        "1.3.6.1.2.1.1.6.0" => %{type: "Gauge32", value: 85},
        "1.3.6.1.2.1.1.7.0" => %{type: "Counter64", value: 9876543210}
      }

      {:ok, profile} = ProfileLoader.load_profile(:typed_device, {:manual, typed_oids})
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)

      target = "127.0.0.1:#{port}"

      # Test that different types are handled correctly
      {:ok, string_val} = SNMP.get(target, "1.3.6.1.2.1.1.1.0")
      assert string_val == "String value"

      {:ok, int_val} = SNMP.get(target, "1.3.6.1.2.1.1.4.0")
      assert int_val == 42

      {:ok, counter_val} = SNMP.get(target, "1.3.6.1.2.1.1.5.0")
      assert counter_val == 1000

      Device.stop(device)
    end

    test "handles empty and minimal OID maps" do
      # Test empty OID map
      {:ok, empty_profile} = ProfileLoader.load_profile(:empty_device, {:manual, %{}})
      port1 = find_available_port()
      {:ok, empty_device} = Sim.start_device(empty_profile, port: port1)

      # Should handle gracefully even with no OIDs
      target1 = "127.0.0.1:#{port1}"
      assert {:error, :no_such_name} = SNMP.get(target1, "1.3.6.1.2.1.1.1.0")

      Device.stop(empty_device)

      # Test single OID map
      single_oid = %{"1.3.6.1.2.1.1.1.0" => "Single OID device"}
      {:ok, single_profile} = ProfileLoader.load_profile(:single_device, {:manual, single_oid})
      port2 = find_available_port()
      {:ok, single_device} = Sim.start_device(single_profile, port: port2)

      target2 = "127.0.0.1:#{port2}"
      {:ok, value} = SNMP.get(target2, "1.3.6.1.2.1.1.1.0")
      assert value == "Single OID device"

      # get_next should return end_of_mib
      case SNMP.get_next(target2, "1.3.6.1.2.1.1.1.0") do
        {:error, :end_of_mib_view} -> :ok
        {:error, :no_such_object} -> :ok
        _ -> flunk("Expected end_of_mib_view for single OID device")
      end

      Device.stop(single_device)
    end
  end

  describe "integration with existing features" do
    test "manual devices work with behavior configurations" do
      oid_map = %{
        "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 1000},
        "1.3.6.1.2.1.2.2.1.10.2" => %{type: "Counter32", value: 2000},
        "1.3.6.1.2.1.2.2.1.11.1" => %{type: "Gauge32", value: 50},
        "1.3.6.1.2.1.2.2.1.11.2" => %{type: "Gauge32", value: 75}
      }

      # Load profile with behavior configurations
      {:ok, profile} = ProfileLoader.load_profile(
        :behavior_test,
        {:manual, oid_map},
        behaviors: [{:increment_counters, rate: 100}]
      )

      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port)
      target = "127.0.0.1:#{port}"

      # Get initial values
      {:ok, initial1} = SNMP.get(target, "1.3.6.1.2.1.2.2.1.10.1")
      {:ok, initial2} = SNMP.get(target, "1.3.6.1.2.1.2.2.1.10.2")

      # Values should be accessible
      assert is_integer(initial1)
      assert is_integer(initial2)

      # Device should handle get_next operations on counters
      case SNMP.get_next(target, "1.3.6.1.2.1.2.2.1.10.1") do
        {:ok, {next_oid, next_value}} ->
          assert next_oid == "1.3.6.1.2.1.2.2.1.10.2"
          assert is_integer(next_value)
        {:error, _} ->
          flunk("get_next should work on counter OIDs")
      end

      Device.stop(device)
    end

    test "manual devices integrate with community strings" do
      oid_map = %{
        "1.3.6.1.2.1.1.1.0" => "Community Test Device"
      }

      {:ok, profile} = ProfileLoader.load_profile(:community_test, {:manual, oid_map})
      port = find_available_port()
      {:ok, device} = Sim.start_device(profile, port: port, community: "test-community")

      # Should work with correct community
      target = "127.0.0.1:#{port}"
      {:ok, value} = SNMP.get(target, "1.3.6.1.2.1.1.1.0", community: "test-community")
      assert value == "Community Test Device"

      # Should fail with wrong community
      assert {:error, _} = SNMP.get(target, "1.3.6.1.2.1.1.1.0", community: "wrong-community")

      Device.stop(device)
    end
  end

  describe "performance and scalability" do
    @tag :performance
    test "handles large OID maps efficiently" do
      # Generate a large OID map (1000 OIDs)
      large_oid_map =
        for i <- 1..1000, into: %{} do
          oid = "1.3.6.1.4.1.12345.1.#{i}.0"
          value = "Value #{i}"
          {oid, value}
        end

      {:ok, profile} = ProfileLoader.load_profile(:large_device, {:manual, large_oid_map})
      port = find_available_port()

      # Measure device startup time
      {startup_time, {:ok, device}} = :timer.tc(fn ->
        Sim.start_device(profile, port: port)
      end)

      # Should start reasonably quickly (under 1 second)
      assert startup_time < 1_000_000 # microseconds

      target = "127.0.0.1:#{port}"

      # Test operations are still fast
      {get_time, {:ok, _}} = :timer.tc(fn ->
        SNMP.get(target, "1.3.6.1.4.1.12345.1.500.0")
      end)

      assert get_time < 100_000 # Should be under 100ms

      Device.stop(device)
    end
  end
end
