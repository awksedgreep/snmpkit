defmodule SnmpKit.WalkIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Permanent integration tests for SNMP walk operations.

  These tests validate walk operations against real SNMP simulators and
  ensure end-to-end functionality works correctly. These tests are critical
  for preventing walk regression bugs.

  All tests must pass to ensure walk integration is working properly.
  """

  require Logger

  @test_timeout 30_000
  @integration_port 11612
  @integration_host "127.0.0.1"

  setup_all do
    # Start dedicated integration test simulator
    simulator_config = %{
      port: @integration_port,
      community: "public",
      version: :v2c,
      device_type: :test_device_integration
    }

    case start_integration_simulator(simulator_config) do
      {:ok, sim_pid} ->
        # Wait for simulator initialization
        :timer.sleep(3000)

        # Verify simulator is responding before running tests
        case verify_simulator_ready() do
          :ok ->
            Logger.info("Integration test simulator ready on port #{@integration_port}")

            on_exit(fn ->
              if Process.alive?(sim_pid) do
                Process.exit(sim_pid, :normal)
              end
            end)

            {:ok, simulator_pid: sim_pid}

          {:error, reason} ->
            Logger.error("Integration simulator not ready: #{inspect(reason)}")

            if Process.alive?(sim_pid) do
              Process.exit(sim_pid, :normal)
            end

            {:skip, "Simulator not responding"}
        end

      {:error, reason} ->
        Logger.warning("Could not start integration simulator: #{inspect(reason)}")
        {:skip, "No simulator available"}
    end
  end

  describe "End-to-End Walk Integration" do
    @tag timeout: @test_timeout
    test "complete walk workflow returns expected results" do
      # Test the full walk workflow from start to finish
      {:ok, results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      # Verify basic response structure
      assert is_list(results), "Walk should return a list"
      assert length(results) > 0, "Walk should return non-empty results"

      # Verify every result is properly formatted
      Enum.each(results, fn result ->
        assert match?({oid, type, value}, result),
               "Every result must be 3-tuple {oid, type, value}, got: #{inspect(result)}"

        {oid, type, value} = result
        assert is_binary(oid), "OID must be string"
        assert is_atom(type), "Type must be atom"
        assert type in valid_snmp_types(), "Type must be valid SNMP type: #{type}"
        assert value != nil, "Value should not be nil"
      end)

      # Verify results are within expected boundaries
      Enum.each(results, fn {oid, _type, _value} ->
        assert String.starts_with?(oid, "1.3.6.1.2.1.1."),
               "All results should be within system subtree: #{oid}"
      end)

      # Verify we get standard system OIDs
      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)

      # Should contain sysDescr
      assert Enum.any?(oids, &String.starts_with?(&1, "1.3.6.1.2.1.1.1.")),
             "Should contain sysDescr OID"

      # Should contain sysObjectID
      assert Enum.any?(oids, &String.starts_with?(&1, "1.3.6.1.2.1.1.2.")),
             "Should contain sysObjectID OID"

      # Should contain sysUpTime
      assert Enum.any?(oids, &String.starts_with?(&1, "1.3.6.1.2.1.1.3.")),
             "Should contain sysUpTime OID"
    end

    @tag timeout: @test_timeout
    test "walk integration with different SNMP versions" do
      # Test v1 walk
      {:ok, v1_results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          version: :v1,
          port: @integration_port,
          timeout: @test_timeout
        )

      # Test v2c walk
      {:ok, v2c_results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          version: :v2c,
          port: @integration_port,
          timeout: @test_timeout
        )

      # Both should return results
      assert length(v1_results) > 0, "v1 walk should return results"
      assert length(v2c_results) > 0, "v2c walk should return results"

      # Both should have proper format
      verify_result_format(v1_results, "v1")
      verify_result_format(v2c_results, "v2c")

      # Should have overlapping OIDs (same device, same subtree)
      v1_oids = MapSet.new(v1_results, fn {oid, _type, _value} -> oid end)
      v2c_oids = MapSet.new(v2c_results, fn {oid, _type, _value} -> oid end)

      common_oids = MapSet.intersection(v1_oids, v2c_oids)
      assert MapSet.size(common_oids) > 0, "v1 and v2c should have common OIDs"

      # Types should be consistent for common OIDs
      v1_map = Map.new(v1_results, fn {oid, type, value} -> {oid, {type, value}} end)
      v2c_map = Map.new(v2c_results, fn {oid, type, value} -> {oid, {type, value}} end)

      common_oids
      |> MapSet.to_list()
      |> Enum.each(fn oid ->
        {v1_type, _v1_value} = Map.get(v1_map, oid)
        {v2c_type, _v2c_value} = Map.get(v2c_map, oid)

        assert v1_type == v2c_type,
               "Type mismatch for OID #{oid}: v1=#{v1_type}, v2c=#{v2c_type}"
      end)
    end

    @tag timeout: @test_timeout
    test "walk integration with different subtrees" do
      # Test multiple subtrees to ensure walk works across different MIB areas
      test_subtrees = [
        {"1.3.6.1.2.1.1", "system"},
        {"1.3.6.1.2.1.2", "interfaces"}
      ]

      Enum.each(test_subtrees, fn {oid, description} ->
        {:ok, results} =
          SnmpKit.SNMP.walk(@integration_host, oid,
            port: @integration_port,
            timeout: @test_timeout
          )

        assert length(results) > 0, "#{description} walk should return results"

        # Verify all results are within the requested subtree
        Enum.each(results, fn {result_oid, _type, _value} ->
          assert String.starts_with?(result_oid, oid <> "."),
                 "Result OID #{result_oid} should be within #{description} subtree #{oid}"
        end)

        verify_result_format(results, description)
      end)
    end

    @tag timeout: @test_timeout
    test "walk integration handles bulk parameters correctly" do
      # Test with different bulk parameters
      bulk_params = [
        [max_repetitions: 5],
        [max_repetitions: 10],
        [max_repetitions: 25]
      ]

      base_results = nil

      Enum.each(bulk_params, fn params ->
        {:ok, results} =
          SnmpKit.SNMP.walk(
            @integration_host,
            "1.3.6.1.2.1.1",
            params ++ [port: @integration_port, timeout: @test_timeout]
          )

        assert length(results) > 0, "Walk with #{inspect(params)} should return results"
        verify_result_format(results, "bulk_#{inspect(params)}")

        if base_results == nil do
          base_results = results
        else
          # Different bulk parameters should return same OIDs (just different performance)
          base_oids = MapSet.new(base_results, fn {oid, _type, _value} -> oid end)
          current_oids = MapSet.new(results, fn {oid, _type, _value} -> oid end)

          assert MapSet.equal?(base_oids, current_oids),
                 "Different bulk parameters should return same OIDs"
        end
      end)
    end

    @tag timeout: @test_timeout
    test "walk integration performance meets requirements" do
      # Measure walk performance
      start_time = System.monotonic_time(:millisecond)

      {:ok, results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert length(results) > 0, "Performance test should return results"
      assert duration < 15_000, "Walk should complete within 15 seconds, took #{duration}ms"

      # Calculate performance metrics
      results_per_second = length(results) / (duration / 1000)
      assert results_per_second > 1, "Should process at least 1 result per second"

      Logger.info(
        "Walk performance: #{length(results)} results in #{duration}ms (#{Float.round(results_per_second, 2)} results/sec)"
      )
    end
  end

  describe "Walk Error Handling Integration" do
    @tag timeout: @test_timeout
    test "walk handles network timeouts gracefully" do
      # Test with very short timeout
      case SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
             port: @integration_port,
             timeout: 1
           ) do
        {:ok, results} ->
          # If it completes quickly, that's fine
          assert is_list(results)

        {:error, :timeout} ->
          # Timeout is expected and acceptable
          :ok

        {:error, reason} ->
          # Other reasonable errors are acceptable
          assert is_atom(reason) or is_tuple(reason),
                 "Error should be reasonable format"
      end
    end

    @tag timeout: @test_timeout
    test "walk handles non-existent OIDs gracefully" do
      case SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.99.99.99",
             port: @integration_port,
             timeout: @test_timeout
           ) do
        {:ok, []} ->
          # Empty results are acceptable for non-existent OIDs
          :ok

        {:ok, results} ->
          # If results are returned, they should be properly formatted
          verify_result_format(results, "non_existent_oid")

        {:error, _reason} ->
          # Errors are also acceptable for non-existent OIDs
          :ok
      end
    end

    @tag timeout: @test_timeout
    test "walk handles invalid target gracefully" do
      result =
        SnmpKit.SNMP.walk("192.168.255.255", "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: 2000
        )

      assert match?({:error, _}, result), "Walk to invalid target should return error"
    end
  end

  describe "Walk Comparison Integration" do
    @tag timeout: @test_timeout
    test "walk vs individual GET comparison" do
      # Get individual system OIDs
      system_oids = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.2.0",
        "1.3.6.1.2.1.1.3.0",
        "1.3.6.1.2.1.1.4.0",
        "1.3.6.1.2.1.1.5.0",
        "1.3.6.1.2.1.1.6.0",
        "1.3.6.1.2.1.1.7.0"
      ]

      individual_results = []

      for oid <- system_oids do
        case SnmpKit.SNMP.get_with_type(@integration_host, oid,
               port: @integration_port,
               timeout: @test_timeout
             ) do
          {:ok, result} ->
            individual_results = [result | individual_results]

          {:error, _} ->
            # Some OIDs might not exist
            :ok
        end
      end

      # Walk the system group
      {:ok, walk_results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      # Walk should return at least as many results as successful individual GETs
      assert length(individual_results) > 0, "Should get some individual results"

      assert length(walk_results) >= length(individual_results),
             "Walk should return at least as many results as individual GETs"

      # All individual results should be found in walk results
      walk_oids = MapSet.new(walk_results, fn {oid, _type, _value} -> oid end)

      Enum.each(individual_results, fn {oid, _type, _value} ->
        assert MapSet.member?(walk_oids, oid),
               "Walk results should include individually retrieved OID: #{oid}"
      end)
    end

    @tag timeout: @test_timeout
    test "walk vs bulk_walk comparison" do
      {:ok, walk_results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      {:ok, bulk_results} =
        SnmpKit.SnmpMgr.bulk_walk(@integration_host, "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      # Both should return results
      assert length(walk_results) > 0, "Walk should return results"
      assert length(bulk_results) > 0, "Bulk walk should return results"

      # Convert to maps for comparison
      walk_map = Map.new(walk_results, fn {oid, type, value} -> {oid, {type, value}} end)
      bulk_map = Map.new(bulk_results, fn {oid, type, value} -> {oid, {type, value}} end)

      # Should have same OIDs
      walk_oids = MapSet.new(Map.keys(walk_map))
      bulk_oids = MapSet.new(Map.keys(bulk_map))

      assert MapSet.equal?(walk_oids, bulk_oids),
             "Walk and bulk_walk should return same OIDs"

      # Should have same data for each OID
      Enum.each(Map.keys(walk_map), fn oid ->
        walk_data = Map.get(walk_map, oid)
        bulk_data = Map.get(bulk_map, oid)

        assert walk_data == bulk_data,
               "Walk and bulk_walk should return same data for OID #{oid}"
      end)
    end
  end

  describe "Walk Type Preservation Integration" do
    @tag timeout: @test_timeout
    test "walk preserves all SNMP types in real data" do
      {:ok, results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      # Should find multiple different SNMP types
      found_types =
        results
        |> Enum.map(fn {_oid, type, _value} -> type end)
        |> Enum.uniq()
        |> Enum.sort()

      # Should find at least basic types
      required_types = [:integer, :octet_string, :object_identifier]
      missing_types = required_types -- found_types

      assert Enum.empty?(missing_types),
             "Should find required SNMP types, missing: #{inspect(missing_types)}"

      # All types should be valid
      Enum.each(found_types, fn type ->
        assert type in valid_snmp_types(), "Invalid SNMP type found: #{type}"
      end)

      Logger.info("Found SNMP types in integration test: #{inspect(found_types)}")
    end

    @tag timeout: @test_timeout
    test "walk never loses type information in real scenarios" do
      {:ok, results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      # Every single result must have type information
      Enum.each(results, fn result ->
        assert match?({_oid, type, _value} when is_atom(type), result),
               "Every result must have type information: #{inspect(result)}"

        {_oid, type, _value} = result
        assert type != nil, "Type must not be nil"
        assert type != :unknown, "Type must not be unknown/inferred"
        assert type in valid_snmp_types(), "Type must be valid SNMP type: #{type}"
      end)
    end
  end

  describe "Walk Regression Prevention Integration" do
    @tag timeout: @test_timeout
    test "walk does not return zero results for system group" do
      # This is the specific bug from the bug report
      {:ok, results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      refute length(results) == 0,
             "Walk MUST NOT return zero results for system group - this was the main bug!"

      assert length(results) >= 4,
             "System group should have at least 4 OIDs (sysDescr, sysObjectID, sysUpTime, sysContact)"
    end

    @tag timeout: @test_timeout
    test "walk iteration continues until proper completion" do
      {:ok, results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          port: @integration_port,
          timeout: @test_timeout
        )

      # Should not stop after just one result
      refute length(results) == 1, "Walk should not stop after single result"

      # Should find multiple system objects
      oids = Enum.map(results, fn {oid, _type, _value} -> oid end)

      # Check for different system objects
      prefixes = ["1.3.6.1.2.1.1.1.", "1.3.6.1.2.1.1.2.", "1.3.6.1.2.1.1.3."]

      found_prefixes =
        Enum.filter(prefixes, fn prefix ->
          Enum.any?(oids, &String.starts_with?(&1, prefix))
        end)

      assert length(found_prefixes) >= 2,
             "Should find multiple different system objects, found: #{inspect(found_prefixes)}"
    end

    @tag timeout: @test_timeout
    test "walk with explicit v1 does not fail due to parameter conflicts" do
      # This addresses the v1 parameter contamination issue
      {:ok, results} =
        SnmpKit.SNMP.walk(@integration_host, "1.3.6.1.2.1.1",
          version: :v1,
          port: @integration_port,
          timeout: @test_timeout
        )

      assert length(results) > 0, "v1 walk should not fail due to parameter conflicts"
      verify_result_format(results, "v1_regression_test")
    end
  end

  # Helper Functions

  defp start_integration_simulator(config) do
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

  defp verify_simulator_ready do
    try do
      case SnmpKit.SNMP.get_with_type(@integration_host, "1.3.6.1.2.1.1.1.0",
             port: @integration_port,
             timeout: 5000
           ) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end

  defp verify_result_format(results, test_name) do
    assert is_list(results), "#{test_name}: Results should be a list"

    Enum.each(results, fn result ->
      assert match?({oid, type, _value}, result),
             "#{test_name}: Result must be 3-tuple {oid, type, value}, got: #{inspect(result)}"

      {oid, type, _value} = result
      assert is_binary(oid), "#{test_name}: OID must be string"
      assert is_atom(type), "#{test_name}: Type must be atom"
      assert type in valid_snmp_types(), "#{test_name}: Invalid SNMP type: #{type}"
    end)
  end

  defp valid_snmp_types do
    [
      :integer,
      :octet_string,
      :null,
      :object_identifier,
      :oid,
      :boolean,
      :counter32,
      :counter64,
      :gauge32,
      :unsigned32,
      :timeticks,
      :ip_address,
      :opaque,
      :string,
      :no_such_object,
      :no_such_instance,
      :end_of_mib_view
    ]
  end
end
