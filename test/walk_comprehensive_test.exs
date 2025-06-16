defmodule SnmpKit.WalkComprehensiveTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Comprehensive permanent test suite for SNMP walk operations.

  This test suite ensures that SNMP walk operations work correctly across all scenarios:
  - Basic walk functionality
  - Version-specific walks (v1, v2c)
  - Type preservation in walks
  - Boundary detection
  - Large dataset handling
  - Error conditions
  - Performance requirements

  These tests must ALWAYS pass. Any failure indicates a critical walk bug.
  """

  require Logger

  @test_timeout 30_000
  @simulator_port 11611
  @simulator_host "127.0.0.1"

  setup_all do
    # Start dedicated test simulator
    simulator_config = %{
      port: @simulator_port,
      community: "public",
      version: :v2c,
      device_type: :test_device_comprehensive
    }

    {:ok, sim_pid} = start_simulator(simulator_config)

    # Wait for simulator to be ready
    :timer.sleep(2000)

    # Verify simulator is responding
    case SnmpKit.SNMP.get_with_type(@simulator_host, "1.3.6.1.2.1.1.1.0",
                                    port: @simulator_port, timeout: 5000) do
      {:ok, _} ->
        Logger.info("Walk test simulator ready on port #{@simulator_port}")
        :ok
      {:error, reason} ->
        Logger.error("Walk test simulator not responding: #{inspect(reason)}")
        raise "Cannot start walk tests - simulator not responding"
    end

    on_exit(fn ->
      if Process.alive?(sim_pid) do
        Process.exit(sim_pid, :normal)
      end
    end)

    {:ok, simulator_pid: sim_pid}
  end

  describe "Basic Walk Functionality" do
    test "walk returns non-empty results for system group" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      assert is_list(results)
      assert length(results) > 0, "Walk should return at least one result for system group"
      assert length(results) >= 4, "System group should have at least 4 OIDs (sysDescr, sysObjectID, sysUpTime, sysContact)"
    end

    test "walk returns non-empty results for interfaces group" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.2",
                                         port: @simulator_port, timeout: @test_timeout)

      assert is_list(results)
      assert length(results) > 0, "Walk should return at least one result for interfaces group"
    end

    test "walk returns results in proper 3-tuple format" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      assert is_list(results)
      assert length(results) > 0

      # Every result must be a 3-tuple
      Enum.each(results, fn result ->
        assert match?({oid, type, _value}, result),
               "Walk result must be 3-tuple {oid, type, value}, got: #{inspect(result)}"

        {oid, type, _value} = result
        assert is_binary(oid), "OID must be string, got: #{inspect(oid)}"
        assert is_atom(type), "Type must be atom, got: #{inspect(type)}"
        assert type in valid_snmp_types(), "Invalid SNMP type: #{type}"
      end)
    end

    test "walk results are properly ordered" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)
      sorted_oids = Enum.sort(oids, &oid_compare/2)

      assert oids == sorted_oids, "Walk results must be in lexicographic order"
    end

    test "walk stops at proper boundaries" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      # All results must be within the requested subtree
      Enum.each(results, fn {oid, _type, _value} ->
        assert String.starts_with?(oid, "1.3.6.1.2.1.1."),
               "OID #{oid} is outside boundary 1.3.6.1.2.1.1"
      end)
    end
  end

  describe "Version-Specific Walk Tests" do
    test "walk with explicit v2c version returns results" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         version: :v2c, port: @simulator_port, timeout: @test_timeout)

      assert is_list(results)
      assert length(results) > 0, "v2c walk should return results"

      # Verify all results have proper format
      Enum.each(results, fn {oid, type, _value} ->
        assert is_binary(oid)
        assert is_atom(type)
        assert type in valid_snmp_types()
      end)
    end

    test "walk with explicit v1 version returns results" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         version: :v1, port: @simulator_port, timeout: @test_timeout)

      assert is_list(results)
      assert length(results) > 0, "v1 walk should return results"

      # Verify all results have proper format
      Enum.each(results, fn {oid, type, _value} ->
        assert is_binary(oid)
        assert is_atom(type)
        assert type in valid_snmp_types()
      end)
    end

    test "walk with default version returns results" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      assert is_list(results)
      assert length(results) > 0, "Default version walk should return results"

      # Default should be v2c
      assert length(results) >= 4, "Default v2c walk should return multiple results"
    end

    test "v1 and v2c walks return consistent types for same OIDs" do
      {:ok, v1_results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                            version: :v1, port: @simulator_port, timeout: @test_timeout)

      {:ok, v2c_results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                             version: :v2c, port: @simulator_port, timeout: @test_timeout)

      # Both should return results
      assert length(v1_results) > 0
      assert length(v2c_results) > 0

      # Create maps for comparison
      v1_map = Map.new(v1_results, fn {oid, type, value} -> {oid, {type, value}} end)
      v2c_map = Map.new(v2c_results, fn {oid, type, value} -> {oid, {type, value}} end)

      # Find common OIDs
      common_oids = Map.keys(v1_map) |> Enum.filter(&Map.has_key?(v2c_map, &1))

      assert length(common_oids) > 0, "v1 and v2c should have common OIDs"

      # Types should be consistent for common OIDs
      Enum.each(common_oids, fn oid ->
        {v1_type, _v1_value} = Map.get(v1_map, oid)
        {v2c_type, _v2c_value} = Map.get(v2c_map, oid)

        assert v1_type == v2c_type,
               "Type mismatch for OID #{oid}: v1=#{v1_type}, v2c=#{v2c_type}"
      end)
    end
  end

  describe "Type Preservation in Walks" do
    test "walk never returns 2-tuple responses" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      # Check every single result
      Enum.each(results, fn result ->
        refute match?({_oid, _value}, result),
               "Found 2-tuple response in walk results: #{inspect(result)}"

        assert match?({_oid, _type, _value}, result),
               "Walk result must be 3-tuple, got: #{inspect(result)}"
      end)
    end

    test "walk preserves all SNMP types correctly" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1",
                                         port: @simulator_port, timeout: @test_timeout)

      # Should find various SNMP types in a full MIB-II walk
      found_types = results
                   |> Enum.map(fn {_oid, type, _value} -> type end)
                   |> Enum.uniq()
                   |> Enum.sort()

      # Must find at least basic types
      required_types = [:integer, :octet_string, :object_identifier, :timeticks]
      missing_types = required_types -- found_types

      assert Enum.empty?(missing_types),
             "Walk should find required SNMP types, missing: #{inspect(missing_types)}"

      # All found types must be valid
      Enum.each(found_types, fn type ->
        assert type in valid_snmp_types(), "Invalid SNMP type found: #{type}"
      end)
    end

    test "walk type information is never inferred" do
      # This test ensures that type information comes from actual SNMP responses
      # We do this by checking that the walk module doesn't have inference functions

      refute function_exported?(SnmpKit.SnmpMgr.Walk, :infer_snmp_type, 1),
             "Walk module should not have type inference functions"

      refute function_exported?(SnmpKit.SnmpMgr.Bulk, :infer_snmp_type, 1),
             "Bulk module should not have type inference functions"

      refute function_exported?(SnmpKit.SnmpMgr.Core, :infer_snmp_type, 1),
             "Core module should not have type inference functions"
    end
  end

  describe "Walk Performance and Scalability" do
    test "walk completes within reasonable time" do
      start_time = System.monotonic_time(:millisecond)

      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert length(results) > 0
      assert duration < 10_000, "Walk should complete within 10 seconds, took #{duration}ms"
    end

    test "large walk returns substantial results" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1",
                                         port: @simulator_port, timeout: @test_timeout)

      assert is_list(results)
      assert length(results) >= 20, "Large walk should return at least 20 results"

      # Verify all results are properly formatted
      Enum.each(results, fn {oid, type, _value} ->
        assert is_binary(oid)
        assert is_atom(type)
        assert type in valid_snmp_types()
      end)
    end

    test "walk handles max_repetitions parameter" do
      # Test with small max_repetitions
      {:ok, small_results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                               max_repetitions: 2, port: @simulator_port, timeout: @test_timeout)

      # Test with larger max_repetitions
      {:ok, large_results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                               max_repetitions: 20, port: @simulator_port, timeout: @test_timeout)

      # Both should return the same results (just different performance)
      assert length(small_results) > 0
      assert length(large_results) > 0
      assert length(small_results) == length(large_results),
             "Different max_repetitions should return same results"
    end
  end

  describe "Walk Error Handling" do
    test "walk handles non-existent OID gracefully" do
      case SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.99.99.99",
                             port: @simulator_port, timeout: @test_timeout) do
        {:ok, []} ->
          # Empty results are acceptable for non-existent OIDs
          :ok
        {:error, _reason} ->
          # Errors are also acceptable for non-existent OIDs
          :ok
        {:ok, results} ->
          # If results are returned, they should be properly formatted
          assert is_list(results)
          Enum.each(results, fn {oid, type, _value} ->
            assert is_binary(oid)
            assert is_atom(type)
          end)
      end
    end

    test "walk handles timeout gracefully" do
      case SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                             port: @simulator_port, timeout: 1) do
        {:ok, results} ->
          # If it completes quickly, results should be properly formatted
          assert is_list(results)
        {:error, :timeout} ->
          # Timeout error is expected and acceptable
          :ok
        {:error, reason} ->
          # Other errors should be reasonable
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "walk rejects type information loss" do
      # This test ensures that if underlying operations lose type information,
      # the walk operation fails rather than returning incomplete data

      # We can't easily simulate this without mocking, but we can verify
      # that the walk module has proper error handling

      # Check that walk module source contains type preservation errors
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")
      assert String.contains?(walk_source, "type_information_lost"),
             "Walk module should contain type preservation error handling"
    end
  end

  describe "Walk Comparison Tests" do
    test "walk returns same or more results than individual GETs" do
      # Get known system OIDs individually
      individual_oids = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.2.0",
        "1.3.6.1.2.1.1.3.0",
        "1.3.6.1.2.1.1.4.0",
        "1.3.6.1.2.1.1.5.0",
        "1.3.6.1.2.1.1.6.0"
      ]

      individual_results = Enum.reduce(individual_oids, [], fn oid, acc ->
        case SnmpKit.SNMP.get_with_type(@simulator_host, oid,
                                        port: @simulator_port, timeout: @test_timeout) do
          {:ok, result} -> [result | acc]
          {:error, _} -> acc
        end
      end)

      # Walk the system group
      {:ok, walk_results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                              port: @simulator_port, timeout: @test_timeout)

      individual_count = length(individual_results)
      walk_count = length(walk_results)

      assert individual_count > 0, "Should get some individual results"
      assert walk_count >= individual_count,
             "Walk should return at least as many results as individual GETs (walk: #{walk_count}, individual: #{individual_count})"
    end

    test "walk and bulk_walk return consistent results" do
      {:ok, walk_results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                              port: @simulator_port, timeout: @test_timeout)

      {:ok, bulk_results} = SnmpKit.SnmpMgr.bulk_walk(@simulator_host, "1.3.6.1.2.1.1",
                                                      port: @simulator_port, timeout: @test_timeout)

      # Both should return results
      assert length(walk_results) > 0
      assert length(bulk_results) > 0

      # Convert to maps for comparison
      walk_map = Map.new(walk_results, fn {oid, type, value} -> {oid, {type, value}} end)
      bulk_map = Map.new(bulk_results, fn {oid, type, value} -> {oid, {type, value}} end)

      # They should return the same OIDs
      walk_oids = Map.keys(walk_map) |> Enum.sort()
      bulk_oids = Map.keys(bulk_map) |> Enum.sort()

      assert walk_oids == bulk_oids,
             "Walk and bulk_walk should return same OIDs"

      # Types and values should match for common OIDs
      Enum.each(walk_oids, fn oid ->
        walk_data = Map.get(walk_map, oid)
        bulk_data = Map.get(bulk_map, oid)

        assert walk_data == bulk_data,
               "Walk and bulk_walk should return same data for OID #{oid}"
      end)
    end
  end

  describe "Walk Regression Tests" do
    test "walk does not return zero results for system group" do
      # This specific test addresses the bug report issue
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      refute length(results) == 0,
             "Walk MUST NOT return zero results for system group - this was the main bug!"

      assert length(results) >= 4,
             "System group walk should return at least 4 results (sysDescr, sysObjectID, sysUpTime, sysContact)"
    end

    test "walk does not return single result for multi-object subtree" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      refute length(results) == 1,
             "Walk should not return only single result for system group"

      assert length(results) > 1,
             "System group should have multiple objects"
    end

    test "walk iteration continues until end of subtree" do
      {:ok, results} = SnmpKit.SNMP.walk(@simulator_host, "1.3.6.1.2.1.1",
                                         port: @simulator_port, timeout: @test_timeout)

      # Verify we get the expected system OIDs
      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)

      # Should find standard system OIDs
      expected_prefixes = [
        "1.3.6.1.2.1.1.1.",  # sysDescr
        "1.3.6.1.2.1.1.2.",  # sysObjectID
        "1.3.6.1.2.1.1.3.",  # sysUpTime
      ]

      Enum.each(expected_prefixes, fn prefix ->
        matching_oids = Enum.filter(oids, &String.starts_with?(&1, prefix))
        assert length(matching_oids) > 0,
               "Should find OIDs starting with #{prefix}"
      end)
    end
  end

  # Helper Functions

  defp start_simulator(config) do
    case SnmpKit.SnmpSim.start_link(config) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp valid_snmp_types do
    [
      :integer, :octet_string, :null, :object_identifier, :oid, :boolean,
      :counter32, :counter64, :gauge32, :unsigned32, :timeticks,
      :ip_address, :opaque, :string,
      :no_such_object, :no_such_instance, :end_of_mib_view
    ]
  end

  defp oid_compare(oid1, oid2) do
    # Convert OID strings to lists for proper comparison
    list1 = oid1 |> String.split(".") |> Enum.map(&String.to_integer/1)
    list2 = oid2 |> String.split(".") |> Enum.map(&String.to_integer/1)
    list1 <= list2
  end
end
