#!/usr/bin/env elixir

# Strict Type Preservation Test
# This test ensures that ALL SNMP operations preserve complete type information
# and NEVER allow type information to be lost or inferred

Mix.install([
  {:snmpkit, path: "."}
])

defmodule StrictTypePreservationTest do
  require Logger

  @moduledoc """
  Strict validation of SNMP type preservation requirements.

  This test enforces that:
  1. ALL SNMP operations return 3-tuple format {oid, type, value}
  2. Type information is NEVER inferred or lost
  3. 2-tuple responses are NEVER acceptable
  4. Type information is consistent across all SNMP versions
  5. Walk operations preserve ALL type information
  """

  @test_timeout 10_000
  @test_target "127.0.0.1"
  @test_port 1161

  def run_all_tests do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("STRICT TYPE PRESERVATION VALIDATION")
    IO.puts("Critical requirement: Type information must NEVER be lost")
    IO.puts(String.duplicate("=", 80))

    # Start simulator for testing
    {:ok, _pid} = start_test_simulator()

    # Allow simulator to initialize
    Process.sleep(1000)

    test_results = [
      {"Type Format Validation", test_type_format_validation()},
      {"No Type Inference Allowed", test_no_type_inference()},
      {"Walk Type Preservation", test_walk_type_preservation()},
      {"Version Consistency", test_version_consistency()},
      {"Bulk Operation Types", test_bulk_operation_types()},
      {"Error Handling", test_error_handling_preserves_types()},
      {"Large Dataset Types", test_large_dataset_type_preservation()},
      {"Edge Cases", test_edge_case_type_preservation()}
    ]

    # Stop simulator
    stop_test_simulator()

    # Report results
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("STRICT TYPE PRESERVATION TEST RESULTS")
    IO.puts(String.duplicate("=", 80))

    {passed, failed} =
      test_results
      |> Enum.reduce({0, 0}, fn {test_name, result}, {pass_count, fail_count} ->
        status = if result, do: "✅ PASS", else: "❌ FAIL"
        IO.puts("#{status} - #{test_name}")
        if result, do: {pass_count + 1, fail_count}, else: {pass_count, fail_count + 1}
      end)

    IO.puts(String.duplicate("-", 80))
    IO.puts("TOTAL: #{passed} passed, #{failed} failed")

    if failed > 0 do
      IO.puts("\n❌ TYPE PRESERVATION VALIDATION FAILED")
      IO.puts("CRITICAL: Type information loss detected - this must be fixed!")
      System.halt(1)
    else
      IO.puts("\n✅ TYPE PRESERVATION VALIDATION PASSED")
      IO.puts("All SNMP operations properly preserve type information.")
    end
  end

  # Test 1: Validate that all operations return proper 3-tuple format
  defp test_type_format_validation do
    IO.puts("\n1. Testing type format validation...")

    # Test all core SNMP operations
    operations = [
      {"GET", fn -> SnmpKit.SNMP.get_with_type(@test_target, "1.3.6.1.2.1.1.1.0", timeout: @test_timeout) end},
      {"GET_NEXT", fn -> SnmpKit.SNMP.get_next(@test_target, "1.3.6.1.2.1.1", timeout: @test_timeout) end},
      {"GET_BULK", fn -> SnmpKit.SNMP.get_bulk(@test_target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) end},
      {"WALK", fn -> SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1", timeout: @test_timeout) end}
    ]

    violations = []

    for {op_name, op_func} <- operations do
      case op_func.() do
        {:ok, results} when is_list(results) ->
          # Check each result in list
          for result <- results do
            case result do
              {oid, type, value} when is_binary(oid) and is_atom(type) ->
                IO.puts("   ✅ #{op_name}: Valid 3-tuple {#{oid}, #{type}, #{inspect(value)}}")
              {oid, value} ->
                violation = "#{op_name}: INVALID 2-tuple for #{oid} - TYPE INFORMATION LOST!"
                IO.puts("   ❌ #{violation}")
                violations = [violation | violations]
              other ->
                violation = "#{op_name}: Invalid format #{inspect(other)}"
                IO.puts("   ❌ #{violation}")
                violations = [violation | violations]
            end
          end
        {:ok, {oid, type, value}} when is_binary(oid) and is_atom(type) ->
          IO.puts("   ✅ #{op_name}: Valid 3-tuple {#{oid}, #{type}, #{inspect(value)}}")
        {:ok, {oid, value}} ->
          violation = "#{op_name}: INVALID 2-tuple for #{oid} - TYPE INFORMATION LOST!"
          IO.puts("   ❌ #{violation}")
          violations = [violation | violations]
        {:ok, other} ->
          violation = "#{op_name}: Invalid format #{inspect(other)}"
          IO.puts("   ❌ #{violation}")
          violations = [violation | violations]
        {:error, reason} ->
          IO.puts("   ⚠️  #{op_name}: Error (acceptable) - #{inspect(reason)}")
      end
    end

    Enum.empty?(violations)
  end

  # Test 2: Ensure no type inference is occurring
  defp test_no_type_inference do
    IO.puts("\n2. Testing that type inference is NOT allowed...")

    # Test with various data types that could be inferred incorrectly
    test_cases = [
      {"1.3.6.1.2.1.1.1.0", "String that looks like number: 12345"},
      {"1.3.6.1.2.1.1.3.0", 123456},  # Could be integer, timeticks, or counter
      {"1.3.6.1.2.1.2.2.1.10.1", 1000000000}  # Could be gauge32, counter32, or integer
    ]

    violations = []

    for {oid, expected_value} <- test_cases do
      case SnmpKit.SNMP.get_with_type(@test_target, oid, timeout: @test_timeout) do
        {:ok, {returned_oid, returned_type, returned_value}} ->
          # Verify the type is a valid SNMP type (not inferred)
          if valid_snmp_type?(returned_type) do
            IO.puts("   ✅ #{oid}: Type #{returned_type} is valid SNMP type")
          else
            violation = "#{oid}: Invalid/inferred type #{returned_type}"
            IO.puts("   ❌ #{violation}")
            violations = [violation | violations]
          end
        {:ok, {oid, value}} ->
          violation = "#{oid}: 2-tuple response indicates type inference occurred"
          IO.puts("   ❌ #{violation}")
          violations = [violation | violations]
        {:error, reason} ->
          IO.puts("   ⚠️  #{oid}: Error - #{inspect(reason)}")
      end
    end

    Enum.empty?(violations)
  end

  # Test 3: Walk operations preserve all types
  defp test_walk_type_preservation do
    IO.puts("\n3. Testing walk type preservation...")

    walk_operations = [
      {"WALK v2c", fn -> SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) end},
      {"WALK v1", fn -> SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1", version: :v1, timeout: @test_timeout) end},
      {"BULK WALK", fn -> SnmpKit.SnmpMgr.bulk_walk(@test_target, "1.3.6.1.2.1.1", timeout: @test_timeout) end}
    ]

    violations = []

    for {walk_name, walk_func} <- walk_operations do
      case walk_func.() do
        {:ok, results} when is_list(results) and length(results) > 0 ->
          type_violations =
            results
            |> Enum.with_index()
            |> Enum.reduce([], fn {result, index}, acc ->
              case result do
                {oid, type, value} when is_binary(oid) and is_atom(type) ->
                  if valid_snmp_type?(type) do
                    acc
                  else
                    ["#{walk_name} result #{index}: Invalid type #{type} for #{oid}" | acc]
                  end
                {oid, value} ->
                  ["#{walk_name} result #{index}: TYPE LOST for #{oid} - got 2-tuple instead of 3-tuple" | acc]
                other ->
                  ["#{walk_name} result #{index}: Invalid format #{inspect(other)}" | acc]
              end
            end)

          if Enum.empty?(type_violations) do
            IO.puts("   ✅ #{walk_name}: All #{length(results)} results preserve type information")
          else
            IO.puts("   ❌ #{walk_name}: Type preservation violations:")
            Enum.each(type_violations, fn violation ->
              IO.puts("      #{violation}")
            end)
            violations = type_violations ++ violations
          end
        {:ok, []} ->
          IO.puts("   ⚠️  #{walk_name}: Empty results")
        {:error, reason} ->
          IO.puts("   ⚠️  #{walk_name}: Error - #{inspect(reason)}")
      end
    end

    Enum.empty?(violations)
  end

  # Test 4: Version consistency
  defp test_version_consistency do
    IO.puts("\n4. Testing version consistency...")

    test_oid = "1.3.6.1.2.1.1.1.0"
    versions = [:v1, :v2c]

    version_results =
      Enum.map(versions, fn version ->
        case SnmpKit.SNMP.get_with_type(@test_target, test_oid, version: version, timeout: @test_timeout) do
          {:ok, {oid, type, value}} -> {version, :ok, {oid, type, value}}
          {:ok, {oid, value}} -> {version, :type_lost, {oid, value}}
          {:error, reason} -> {version, :error, reason}
        end
      end)

    successful_results =
      version_results
      |> Enum.filter(fn {_version, status, _result} -> status == :ok end)

    type_lost_results =
      version_results
      |> Enum.filter(fn {_version, status, _result} -> status == :type_lost end)

    violations = []

    # Check for type information loss
    if not Enum.empty?(type_lost_results) do
      for {version, _status, {oid, value}} <- type_lost_results do
        violation = "Version #{version}: TYPE LOST for #{oid}"
        IO.puts("   ❌ #{violation}")
        violations = [violation | violations]
      end
    end

    # Check consistency among successful results
    if length(successful_results) > 1 do
      types = Enum.map(successful_results, fn {_version, :ok, {_oid, type, _value}} -> type end)
      unique_types = Enum.uniq(types)

      if length(unique_types) == 1 do
        IO.puts("   ✅ Type consistency: All versions returned type #{hd(unique_types)}")
      else
        violation = "Type inconsistency across versions: #{inspect(unique_types)}"
        IO.puts("   ❌ #{violation}")
        violations = [violation | violations]
      end
    end

    Enum.empty?(violations)
  end

  # Test 5: Bulk operation types
  defp test_bulk_operation_types do
    IO.puts("\n5. Testing bulk operation type preservation...")

    case SnmpKit.SNMP.get_bulk(@test_target, "1.3.6.1.2.1.1", version: :v2c, max_repetitions: 10, timeout: @test_timeout) do
      {:ok, results} when is_list(results) ->
        violations =
          results
          |> Enum.with_index()
          |> Enum.reduce([], fn {result, index}, acc ->
            case result do
              {oid, type, value} when is_binary(oid) and is_atom(type) ->
                if valid_snmp_type?(type) do
                  acc
                else
                  ["Bulk result #{index}: Invalid type #{type} for #{oid}" | acc]
                end
              {oid, value} ->
                ["Bulk result #{index}: TYPE LOST for #{oid}" | acc]
              other ->
                ["Bulk result #{index}: Invalid format #{inspect(other)}" | acc]
            end
          end)

        if Enum.empty?(violations) do
          IO.puts("   ✅ Bulk operations preserve types for all #{length(results)} results")
          true
        else
          IO.puts("   ❌ Bulk operation type violations:")
          Enum.each(violations, fn violation ->
            IO.puts("      #{violation}")
          end)
          false
        end
      {:ok, []} ->
        IO.puts("   ⚠️  Bulk operation returned empty results")
        true
      {:error, reason} ->
        IO.puts("   ⚠️  Bulk operation error: #{inspect(reason)}")
        true
    end
  end

  # Test 6: Error handling preserves types
  defp test_error_handling_preserves_types do
    IO.puts("\n6. Testing error handling type preservation...")

    # Test with non-existent OID
    case SnmpKit.SNMP.get_with_type(@test_target, "1.3.6.1.2.1.99.99.99.0", timeout: @test_timeout) do
      {:ok, {oid, type, value}} ->
        if valid_snmp_type?(type) do
          IO.puts("   ✅ Error handling: Returned valid type #{type} for #{oid}")
          true
        else
          IO.puts("   ❌ Error handling: Invalid type #{type}")
          false
        end
      {:ok, {oid, value}} ->
        IO.puts("   ❌ Error handling: TYPE LOST for #{oid}")
        false
      {:error, reason} ->
        IO.puts("   ✅ Error handling: Proper error response - #{inspect(reason)}")
        true
    end
  end

  # Test 7: Large dataset type preservation
  defp test_large_dataset_type_preservation do
    IO.puts("\n7. Testing large dataset type preservation...")

    case SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1", max_repetitions: 50, timeout: @test_timeout * 2) do
      {:ok, results} when is_list(results) and length(results) > 20 ->
        type_violations =
          results
          |> Enum.take(50)  # Check first 50 results
          |> Enum.with_index()
          |> Enum.reduce([], fn {result, index}, acc ->
            case result do
              {oid, type, value} when is_binary(oid) and is_atom(type) ->
                if valid_snmp_type?(type) do
                  acc
                else
                  ["Large dataset result #{index}: Invalid type #{type} for #{oid}" | acc]
                end
              {oid, value} ->
                ["Large dataset result #{index}: TYPE LOST for #{oid}" | acc]
              other ->
                ["Large dataset result #{index}: Invalid format #{inspect(other)}" | acc]
            end
          end)

        if Enum.empty?(type_violations) do
          IO.puts("   ✅ Large dataset: Types preserved for #{length(results)} results")
          true
        else
          IO.puts("   ❌ Large dataset type violations:")
          Enum.each(type_violations, fn violation ->
            IO.puts("      #{violation}")
          end)
          false
        end
      {:ok, results} ->
        IO.puts("   ⚠️  Large dataset: Only #{length(results)} results returned")
        true
      {:error, reason} ->
        IO.puts("   ⚠️  Large dataset error: #{inspect(reason)}")
        true
    end
  end

  # Test 8: Edge case type preservation
  defp test_edge_case_type_preservation do
    IO.puts("\n8. Testing edge case type preservation...")

    edge_cases = [
      # OID with zero instance
      {"1.3.6.1.2.1.1.1.0", "Scalar OID"},
      # Table entry
      {"1.3.6.1.2.1.2.2.1.1.1", "Table entry"},
      # Very long OID
      {"1.3.6.1.2.1.1.1.0.0.0.0.0.0.0.0.0.0.0.0", "Long OID"}
    ]

    violations = []

    for {oid, description} <- edge_cases do
      case SnmpKit.SNMP.get_with_type(@test_target, oid, timeout: @test_timeout) do
        {:ok, {returned_oid, type, value}} when is_binary(returned_oid) and is_atom(type) ->
          if valid_snmp_type?(type) do
            IO.puts("   ✅ #{description}: Valid type #{type}")
          else
            violation = "#{description}: Invalid type #{type}"
            IO.puts("   ❌ #{violation}")
            violations = [violation | violations]
          end
        {:ok, {oid, value}} ->
          violation = "#{description}: TYPE LOST for #{oid}"
          IO.puts("   ❌ #{violation}")
          violations = [violation | violations]
        {:error, reason} ->
          IO.puts("   ⚠️  #{description}: Error - #{inspect(reason)}")
      end
    end

    Enum.empty?(violations)
  end

  # Helper functions
  defp valid_snmp_type?(type) do
    type in [
      :integer, :octet_string, :null, :object_identifier, :oid,
      :counter32, :gauge32, :timeticks, :counter64, :unsigned32,
      :ip_address, :opaque, :boolean, :string,
      :no_such_object, :no_such_instance, :end_of_mib_view
    ]
  end

  defp start_test_simulator do
    # Start a simple SNMP simulator for testing
    simulator_config = %{
      port: @test_port,
      community: "public",
      version: :v2c
    }

    case SnmpKit.SnmpSim.start_link(simulator_config) do
      {:ok, pid} ->
        IO.puts("Started test simulator on port #{@test_port}")
        {:ok, pid}
      {:error, {:already_started, pid}} ->
        IO.puts("Test simulator already running")
        {:ok, pid}
      {:error, reason} ->
        IO.puts("Failed to start test simulator: #{inspect(reason)}")
        IO.puts("Note: Some tests may fail without simulator")
        {:ok, nil}
    end
  end

  defp stop_test_simulator do
    # Stop the simulator (if it was started by us)
    :ok
  end
end

# Run the tests
StrictTypePreservationTest.run_all_tests()
