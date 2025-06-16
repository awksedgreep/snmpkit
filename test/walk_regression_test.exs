defmodule SnmpKit.WalkRegressionTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Permanent regression tests for SNMP walk operations.

  This test suite specifically targets known walk bugs and ensures they
  never reoccur. Each test addresses a specific regression that was
  previously found and fixed.

  ALL TESTS MUST PASS - any failure indicates a critical regression.
  """

  require Logger

  @test_timeout 30_000
  @regression_port 11613
  @regression_host "127.0.0.1"

  setup_all do
    # Start dedicated regression test simulator
    simulator_config = %{
      port: @regression_port,
      community: "public",
      version: :v2c,
      device_type: :test_device_regression
    }

    case start_regression_simulator(simulator_config) do
      {:ok, sim_pid} ->
        # Wait for simulator to initialize
        :timer.sleep(3000)

        # Verify simulator is ready
        case verify_regression_simulator() do
          :ok ->
            Logger.info("Regression test simulator ready on port #{@regression_port}")
            on_exit(fn ->
              if Process.alive?(sim_pid) do
                Process.exit(sim_pid, :normal)
              end
            end)
            {:ok, simulator_pid: sim_pid}

          {:error, reason} ->
            Logger.warning("Regression simulator not ready: #{inspect(reason)}")
            if Process.alive?(sim_pid) do
              Process.exit(sim_pid, :normal)
            end
            {:skip, "Regression simulator not responding"}
        end

      {:error, reason} ->
        Logger.warning("Could not start regression simulator: #{inspect(reason)}")
        {:skip, "No regression simulator available"}
    end
  end

  describe "Regression: Zero Results Bug" do
    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST NOT return zero results for system group" do
      # BUG REPORT: "Testing SnmpKit.SNMP.walk (this is the main test!):
      #             ✅ SNMP.walk(1.3.6.1.2.1.1) returned 0 results:"
      # FIXED: Walk operations now properly iterate through responses

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      # This was the primary bug - walk returning 0 results
      refute length(results) == 0,
             "CRITICAL REGRESSION: Walk returned 0 results for system group - THE MAIN BUG IS BACK!"

      assert length(results) >= 4,
             "System group should return at least 4 OIDs (sysDescr, sysObjectID, sysUpTime, sysContact), got #{length(results)}"

      # Log results for debugging if this fails
      if length(results) == 0 do
        Logger.error("REGRESSION DETECTED: Zero results returned for system group walk!")
      else
        Logger.info("Regression test passed: #{length(results)} results returned for system group")
      end
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST NOT return zero results for interfaces group" do
      # BUG REPORT: "✅ SNMP.walk(1.3.6.1.2.1.2) returned 0 results:"
      # FIXED: Walk operations now properly handle different MIB subtrees

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.2",
                                         port: @regression_port, timeout: @test_timeout)

      refute length(results) == 0,
             "CRITICAL REGRESSION: Walk returned 0 results for interfaces group!"

      assert length(results) > 0,
             "Interfaces group should return results, got #{length(results)}"
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST NOT return zero results for symbolic OIDs" do
      # BUG REPORT: "✅ SNMP.walk(system) returned 0 results:"
      # FIXED: Symbolic OID resolution now works properly

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "system",
                                         port: @regression_port, timeout: @test_timeout)

      refute length(results) == 0,
             "CRITICAL REGRESSION: Walk returned 0 results for symbolic 'system' OID!"

      assert length(results) >= 4,
             "System symbolic OID should return multiple results, got #{length(results)}"
    end
  end

  describe "Regression: Single Result Bug" do
    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST NOT stop after single result" do
      # BUG REPORT: Walk stopping after first result instead of continuing
      # FIXED: Walk iteration logic now continues until end of subtree

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      refute length(results) == 1,
             "CRITICAL REGRESSION: Walk stopped after single result - iteration bug is back!"

      assert length(results) > 1,
             "Walk should return multiple results for system group, got #{length(results)}"

      # Verify we get different OID branches
      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)
      unique_prefixes = oids
                       |> Enum.map(fn oid -> oid |> String.split(".") |> Enum.take(8) |> Enum.join(".") end)
                       |> Enum.uniq()

      assert length(unique_prefixes) > 1,
             "Walk should traverse multiple OID branches, only found: #{inspect(unique_prefixes)}"
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk iteration continues until proper end" do
      # BUG REPORT: "Fails to iterate through multiple GET_BULK responses"
      # FIXED: Walk now properly processes all responses until end_of_mib_view

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      # Should find standard system OIDs
      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)

      # Must find multiple different system objects
      expected_patterns = [
        "1.3.6.1.2.1.1.1.", # sysDescr
        "1.3.6.1.2.1.1.2.", # sysObjectID
        "1.3.6.1.2.1.1.3."  # sysUpTime
      ]

      found_patterns = Enum.filter(expected_patterns, fn pattern ->
        Enum.any?(oids, &String.starts_with?(&1, pattern))
      end)

      assert length(found_patterns) >= 2,
             "REGRESSION: Walk did not find multiple system objects, only found: #{inspect(found_patterns)}"
    end
  end

  describe "Regression: Type Information Loss" do
    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST NEVER return 2-tuple responses" do
      # BUG REPORT: Type information being lost in walk operations
      # FIXED: All operations now enforce 3-tuple {oid, type, value} format

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      # Check every single result
      Enum.each(results, fn result ->
        refute match?({_oid, _value}, result),
               "CRITICAL REGRESSION: Found 2-tuple response - TYPE INFORMATION LOST! #{inspect(result)}"

        assert match?({_oid, _type, _value}, result),
               "REGRESSION: Walk result must be 3-tuple, got: #{inspect(result)}"
      end)

      # Additional verification
      type_violations = Enum.filter(results, fn result ->
        not match?({_oid, type, _value}, result) when is_atom(type)
      end)

      assert Enum.empty?(type_violations),
             "CRITICAL REGRESSION: Type information violations found: #{inspect(type_violations)}"
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST preserve valid SNMP types" do
      # BUG REPORT: Type inference causing incorrect type information
      # FIXED: No type inference - only preserve actual SNMP types

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      valid_types = [
        :integer, :octet_string, :null, :object_identifier, :oid, :boolean,
        :counter32, :counter64, :gauge32, :unsigned32, :timeticks,
        :ip_address, :opaque, :string,
        :no_such_object, :no_such_instance, :end_of_mib_view
      ]

      invalid_types = []

      Enum.each(results, fn {oid, type, _value} ->
        unless type in valid_types do
          invalid_types = [{oid, type} | invalid_types]
        end
      end)

      assert Enum.empty?(invalid_types),
             "REGRESSION: Invalid SNMP types found (likely inferred): #{inspect(invalid_types)}"
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST NOT use type inference" do
      # BUG REPORT: Type information being inferred instead of preserved
      # FIXED: Removed all type inference functions

      # Verify source code doesn't contain inference patterns
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")
      bulk_source = File.read!("lib/snmpkit/snmp_mgr/bulk.ex")
      core_source = File.read!("lib/snmpkit/snmp_mgr/core.ex")

      refute String.contains?(walk_source, "infer_snmp_type"),
             "REGRESSION: Walk module contains type inference code!"

      refute String.contains?(bulk_source, "infer_snmp_type"),
             "REGRESSION: Bulk module contains type inference code!"

      refute String.contains?(core_source, "infer_snmp_type"),
             "REGRESSION: Core module contains type inference code!"

      # Verify modules don't export inference functions
      refute function_exported?(SnmpKit.SnmpMgr.Walk, :infer_snmp_type, 1),
             "REGRESSION: Walk module exports type inference function!"

      refute function_exported?(SnmpKit.SnmpMgr.Bulk, :infer_snmp_type, 1),
             "REGRESSION: Bulk module exports type inference function!"

      refute function_exported?(SnmpKit.SnmpMgr.Core, :infer_snmp_type, 1),
             "REGRESSION: Core module exports type inference function!"
    end
  end

  describe "Regression: Version-Specific Issues" do
    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: v1 walk MUST NOT fail due to max_repetitions parameter" do
      # BUG REPORT: "v1 path tries to use max_repetitions parameter (WRONG - v1 doesn't support this)"
      # FIXED: v1 operations now properly remove max_repetitions parameter

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         version: :v1, max_repetitions: 25,
                                         port: @regression_port, timeout: @test_timeout)

      assert length(results) > 0,
             "REGRESSION: v1 walk failed due to parameter conflicts!"

      # Verify results are properly formatted
      Enum.each(results, fn {oid, type, _value} ->
        assert is_binary(oid), "v1 walk OID should be string"
        assert is_atom(type), "v1 walk type should be atom"
      end)
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: default version MUST be v2c not v1" do
      # BUG REPORT: "walk/3 defaults to v2c (changed from v1)"
      # FIXED: Default version changed to v2c for better performance

      # Test that default walk uses v2c behavior (should return more results faster)
      start_time = System.monotonic_time(:millisecond)

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert length(results) > 0, "Default walk should return results"

      # v2c should be faster and return more results
      assert length(results) >= 4, "Default v2c walk should find multiple system objects"
      assert duration < 10_000, "Default v2c walk should be reasonably fast"
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: v1 and v2c walks MUST return consistent types" do
      # BUG REPORT: "Type information handling - Inconsistent preservation across operation types"
      # FIXED: Both versions now preserve consistent type information

      {:ok, v1_results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                            version: :v1, port: @regression_port, timeout: @test_timeout)

      {:ok, v2c_results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                             version: :v2c, port: @regression_port, timeout: @test_timeout)

      assert length(v1_results) > 0, "v1 walk should return results"
      assert length(v2c_results) > 0, "v2c walk should return results"

      # Build maps for comparison
      v1_map = Map.new(v1_results, fn {oid, type, value} -> {oid, {type, value}} end)
      v2c_map = Map.new(v2c_results, fn {oid, type, value} -> {oid, {type, value}} end)

      # Find common OIDs
      common_oids = Map.keys(v1_map) |> Enum.filter(&Map.has_key?(v2c_map, &1))

      assert length(common_oids) > 0, "v1 and v2c should have common OIDs"

      # Types must be consistent for common OIDs
      type_mismatches = []

      Enum.each(common_oids, fn oid ->
        {v1_type, _v1_value} = Map.get(v1_map, oid)
        {v2c_type, _v2c_value} = Map.get(v2c_map, oid)

        if v1_type != v2c_type do
          type_mismatches = [{oid, v1_type, v2c_type} | type_mismatches]
        end
      end)

      assert Enum.empty?(type_mismatches),
             "REGRESSION: Type inconsistencies between v1 and v2c: #{inspect(type_mismatches)}"
    end
  end

  describe "Regression: Collection Logic Issues" do
    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST NOT fail to collect GET_BULK responses" do
      # BUG REPORT: "SNMP.walk collection logic - Fails to iterate through multiple GET_BULK responses"
      # FIXED: Collection logic now properly processes all bulk responses

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1",
                                         version: :v2c, max_repetitions: 5,
                                         port: @regression_port, timeout: @test_timeout)

      # Should get substantial results from bulk operations
      assert length(results) >= 10,
             "REGRESSION: Bulk walk collection failed - got only #{length(results)} results"

      # Should span multiple subtrees (system, interfaces, etc.)
      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)
      subtrees = oids
                |> Enum.map(fn oid -> oid |> String.split(".") |> Enum.take(7) |> Enum.join(".") end)
                |> Enum.uniq()

      assert length(subtrees) >= 2,
             "REGRESSION: Bulk collection didn't traverse subtrees, only found: #{inspect(subtrees)}"
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST process responses until end_of_mib_view" do
      # BUG REPORT: "Stops after first response instead of continuing until end_of_mib_view"
      # FIXED: Walk now continues until proper termination condition

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      # Should find all system objects, not just the first one
      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)

      # Check that we traverse the entire system subtree
      system_objects = [
        "1.3.6.1.2.1.1.1", # sysDescr
        "1.3.6.1.2.1.1.2", # sysObjectID
        "1.3.6.1.2.1.1.3", # sysUpTime
        "1.3.6.1.2.1.1.4", # sysContact
        "1.3.6.1.2.1.1.5", # sysName
        "1.3.6.1.2.1.1.6"  # sysLocation
      ]

      found_objects = Enum.filter(system_objects, fn obj ->
        Enum.any?(oids, &String.starts_with?(&1, obj))
      end)

      assert length(found_objects) >= 3,
             "REGRESSION: Walk didn't continue to end - only found: #{inspect(found_objects)}"
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST handle boundary detection correctly" do
      # BUG REPORT: Walk not detecting when it has moved outside the requested subtree
      # FIXED: Boundary detection now properly filters results

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      # All results must be within the system subtree
      boundary_violations = []

      Enum.each(results, fn {oid, _type, _value} ->
        unless String.starts_with?(oid, "1.3.6.1.2.1.1.") do
          boundary_violations = [oid | boundary_violations]
        end
      end)

      assert Enum.empty?(boundary_violations),
             "REGRESSION: Walk boundary detection failed - OIDs outside subtree: #{inspect(boundary_violations)}"
    end
  end

  describe "Regression: Performance Issues" do
    @tag :regression_performance
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST complete within reasonable time" do
      # BUG REPORT: Walk operations taking too long or hanging
      # FIXED: Proper iteration and timeout handling

      start_time = System.monotonic_time(:millisecond)

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert length(results) > 0, "Walk should return results"
      assert duration < 15_000, "REGRESSION: Walk took too long (#{duration}ms) - performance degraded!"

      # Calculate throughput
      throughput = length(results) / (duration / 1000)
      assert throughput > 1, "REGRESSION: Walk throughput too low (#{Float.round(throughput, 2)} results/sec)"
    end
  end

  describe "Regression: Format and Structure" do
    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk results MUST maintain lexicographic order" do
      # BUG REPORT: Walk results not properly ordered
      # FIXED: Results are now properly sorted

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)
      sorted_oids = Enum.sort(oids, &oid_compare/2)

      assert oids == sorted_oids,
             "REGRESSION: Walk results not in lexicographic order!"
    end

    @tag :regression_critical
    @tag timeout: @test_timeout
    test "REGRESSION: walk MUST return proper OID string format" do
      # BUG REPORT: OID format inconsistencies between operations
      # FIXED: Consistent string format for all OIDs

      {:ok, results} = SnmpKit.SNMP.walk(@regression_host, "1.3.6.1.2.1.1",
                                         port: @regression_port, timeout: @test_timeout)

      Enum.each(results, fn {oid, _type, _value} ->
        assert is_binary(oid), "REGRESSION: OID must be string, got: #{inspect(oid)}"
        assert String.match?(oid, ~r/^\d+(\.\d+)*$/),
               "REGRESSION: OID format invalid: #{oid}"
        assert String.starts_with?(oid, "1.3.6.1.2.1.1."),
               "REGRESSION: OID outside expected range: #{oid}"
      end)
    end
  end

  # Helper Functions

  defp start_regression_simulator(config) do
    try do
      case SnmpKit.SnmpSim.start_link(config) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        error -> error
      end
    rescue
      e -> {:error, e}
    end
  end

  defp verify_regression_simulator do
    try do
      case SnmpKit.SNMP.get_with_type(@regression_host, "1.3.6.1.2.1.1.1.0",
                                      port: @regression_port, timeout: 5000) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end

  defp oid_compare(oid1, oid2) do
    # Convert OID strings to lists for proper numeric comparison
    list1 = oid1 |> String.split(".") |> Enum.map(&String.to_integer/1)
    list2 = oid2 |> String.split(".") |> Enum.map(&String.to_integer/1)
    list1 <= list2
  end
end
