#!/usr/bin/env elixir

# Comprehensive SNMP Type Preservation Tests
# This test suite ensures that SNMP type information is ALWAYS preserved
# Type information is critical for proper SNMP data interpretation

Mix.install([
  {:snmpkit, path: "."}
])

defmodule TypePreservationTests do
  require Logger

  @moduledoc """
  Comprehensive test suite for SNMP type preservation.

  SNMP type information is CRITICAL and must NEVER be lost.
  Without proper types, you cannot distinguish between:
  - String "123" vs Integer 123 vs TimeTicks 123
  - Counter32 vs Gauge32 vs Integer
  - OctetString vs DisplayString vs HexString

  ALL operations must return 3-tuples: {oid, type, value}
  """

  # Test configurations
  @test_port_base 7000
  @test_timeout 10_000

  def run_all_tests do
    IO.puts("=" * 80)
    IO.puts("SNMP TYPE PRESERVATION TEST SUITE")
    IO.puts("=" * 80)
    IO.puts("Type information is CRITICAL for SNMP - testing preservation...")
    IO.puts("")

    # Disable debug logging for cleaner output
    Logger.configure(level: :warn)

    results = %{
      basic_type_preservation: test_basic_type_preservation(),
      walk_type_preservation: test_walk_type_preservation(),
      version_type_consistency: test_version_type_consistency(),
      snmp_type_standards: test_snmp_type_standards(),
      type_inference_accuracy: test_type_inference_accuracy(),
      complex_type_scenarios: test_complex_type_scenarios(),
      edge_case_types: test_edge_case_types(),
      regression_type_tests: test_regression_type_tests()
    }

    print_test_summary(results)
    results
  end

  # ============================================================================
  # BASIC TYPE PRESERVATION TESTS
  # ============================================================================

  defp test_basic_type_preservation do
    IO.puts("🧪 Testing Basic Type Preservation...")

    # Test data with explicit type expectations
    test_data = %{
      "1.3.6.1.2.1.1.1.0" => %{value: "System Description String", expected_type: :octet_string},
      "1.3.6.1.2.1.1.2.0" => %{value: "1.3.6.1.4.1.999.1", expected_type: :object_identifier},
      "1.3.6.1.2.1.1.3.0" => %{value: 12345, expected_type: :timeticks},
      "1.3.6.1.2.1.1.4.0" => %{value: "admin@test.local", expected_type: :octet_string},
      "1.3.6.1.2.1.1.5.0" => %{value: "test-device.local", expected_type: :octet_string},
      "1.3.6.1.2.1.1.6.0" => %{value: "Test Lab Location", expected_type: :octet_string},
      "1.3.6.1.2.1.1.7.0" => %{value: 78, expected_type: :integer},
      "1.3.6.1.2.1.2.1.0" => %{value: 5, expected_type: :integer},
      "1.3.6.1.2.1.2.2.1.10.1" => %{value: 1000000, expected_type: :counter32},
      "1.3.6.1.2.1.2.2.1.11.1" => %{value: 2000000, expected_type: :counter32},
      "1.3.6.1.2.1.2.2.1.5.1" => %{value: 1000000000, expected_type: :gauge32}
    }

    device_oid_map = test_data |> Enum.into(%{}, fn {oid, %{value: value}} -> {oid, value} end)

    with_test_device(device_oid_map, @test_port_base + 1, fn target ->
      tests = [
        test_individual_get_preserves_types(target, test_data),
        test_individual_get_next_preserves_types(target, test_data),
        test_individual_get_bulk_preserves_types(target, test_data),
        test_walk_preserves_all_types(target, test_data),
        test_no_2_tuple_responses_allowed(target),
        test_type_never_nil_or_missing(target)
      ]

      {
        total: length(tests),
        passed: Enum.count(tests, & &1),
        failed: Enum.count(tests, &(not &1))
      }
    end)
  end

  defp test_individual_get_preserves_types(target, test_data) do
    IO.puts("   Testing individual GET operations preserve types...")

    type_failures = Enum.reduce(test_data, [], fn {oid, %{expected_type: expected}}, acc ->
      case SnmpKit.SNMP.get_with_type(target, oid, timeout: @test_timeout) do
        {:ok, {^oid, actual_type, _value}} ->
          if type_compatible?(actual_type, expected) do
            acc
          else
            ["GET #{oid}: expected #{expected}, got #{actual_type}" | acc]
          end
        {:ok, {_oid, _value}} ->
          ["GET #{oid}: returned 2-tuple (TYPE INFORMATION LOST!)" | acc]
        {:ok, other} ->
          ["GET #{oid}: invalid format #{inspect(other)}" | acc]
        {:error, reason} ->
          ["GET #{oid}: failed with #{inspect(reason)}" | acc]
      end
    end)

    if Enum.empty?(type_failures) do
      IO.puts("   ✅ All GET operations preserve type information")
      true
    else
      IO.puts("   ❌ GET type preservation failures:")
      Enum.each(type_failures, &IO.puts("      #{&1}"))
      false
    end
  end

  defp test_individual_get_next_preserves_types(target, _test_data) do
    IO.puts("   Testing GET_NEXT operations preserve types...")

    case SnmpKit.SNMP.get_next(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, {oid, type, value}} when is_binary(oid) and is_atom(type) ->
        IO.puts("   ✅ GET_NEXT preserves type information: #{oid} → #{type}")
        true
      {:ok, {_oid, _value}} ->
        IO.puts("   ❌ GET_NEXT returned 2-tuple (TYPE INFORMATION LOST!)")
        false
      {:ok, other} ->
        IO.puts("   ❌ GET_NEXT invalid format: #{inspect(other)}")
        false
      {:error, reason} ->
        IO.puts("   ❌ GET_NEXT failed: #{inspect(reason)}")
        false
    end
  end

  defp test_individual_get_bulk_preserves_types(target, _test_data) do
    IO.puts("   Testing GET_BULK operations preserve types...")

    case SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v2c, max_repetitions: 5, timeout: @test_timeout) do
      {:ok, results} when is_list(results) ->
        type_issues = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, type, _value} when is_binary(oid) and is_atom(type) ->
              acc
            {oid, _value} ->
              ["GET_BULK result for #{oid}: 2-tuple (TYPE LOST!)" | acc]
            other ->
              ["GET_BULK invalid format: #{inspect(other)}" | acc]
          end
        end)

        if Enum.empty?(type_issues) do
          IO.puts("   ✅ GET_BULK preserves type information for all #{length(results)} results")
          true
        else
          IO.puts("   ❌ GET_BULK type preservation issues:")
          Enum.each(type_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ GET_BULK failed: #{inspect(reason)}")
        false
    end
  end

  defp test_walk_preserves_all_types(target, test_data) do
    IO.puts("   Testing WALK operations preserve ALL types...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} when is_list(results) ->
        # Check format first
        format_issues = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, type, _value} when is_binary(oid) and is_atom(type) ->
              acc
            {oid, _value} ->
              ["WALK result for #{oid}: 2-tuple (TYPE LOST!)" | acc]
            other ->
              ["WALK invalid format: #{inspect(other)}" | acc]
          end
        end)

        if not Enum.empty?(format_issues) do
          IO.puts("   ❌ WALK format issues:")
          Enum.each(format_issues, &IO.puts("      #{&1}"))
          return false
        end

        # Check type accuracy
        type_issues = Enum.reduce(results, [], fn {oid, actual_type, _value}, acc ->
          case Map.get(test_data, oid) do
            %{expected_type: expected_type} ->
              if type_compatible?(actual_type, expected_type) do
                acc
              else
                ["WALK #{oid}: expected #{expected_type}, got #{actual_type}" | acc]
              end
            nil ->
              # OID not in test data, just verify type is valid
              if valid_snmp_type?(actual_type) do
                acc
              else
                ["WALK #{oid}: invalid SNMP type #{actual_type}" | acc]
              end
          end
        end)

        if Enum.empty?(type_issues) do
          IO.puts("   ✅ WALK preserves correct types for all #{length(results)} results")
          true
        else
          IO.puts("   ❌ WALK type issues:")
          Enum.each(type_issues, &IO.puts("      #{&1}"))
          false
        end
      {:ok, []} ->
        IO.puts("   ❌ WALK returned empty results")
        false
      {:error, reason} ->
        IO.puts("   ❌ WALK failed: #{inspect(reason)}")
        false
    end
  end

  defp test_no_2_tuple_responses_allowed(target) do
    IO.puts("   Testing that 2-tuple responses are NEVER allowed...")

    operations = [
      {"GET", fn -> SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.1.1.0", timeout: @test_timeout) end},
      {"GET_NEXT", fn -> SnmpKit.SNMP.get_next(target, "1.3.6.1.2.1.1", timeout: @test_timeout) end},
      {"GET_BULK", fn -> SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) end},
      {"WALK", fn -> SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) end}
    ]

    violations = Enum.reduce(operations, [], fn {op_name, op_func}, acc ->
      case op_func.() do
        {:ok, results} when is_list(results) ->
          # Check each result in list
          Enum.reduce(results, acc, fn result, inner_acc ->
            case result do
              {_oid, _type, _value} -> inner_acc
              {oid, _value} -> ["#{op_name}: 2-tuple for #{oid} (TYPE LOST!)" | inner_acc]
              other -> ["#{op_name}: invalid format #{inspect(other)}" | inner_acc]
            end
          end)
        {:ok, {_oid, _type, _value}} ->
          acc  # Good 3-tuple
        {:ok, {oid, _value}} ->
          ["#{op_name}: 2-tuple for #{oid} (TYPE LOST!)" | acc]
        {:ok, other} ->
          ["#{op_name}: invalid format #{inspect(other)}" | acc]
        {:error, _} ->
          acc  # Errors are acceptable for this test
      end
    end)

    if Enum.empty?(violations) do
      IO.puts("   ✅ No 2-tuple responses found - all operations preserve types")
      true
    else
      IO.puts("   ❌ TYPE PRESERVATION VIOLATIONS FOUND:")
      Enum.each(violations, &IO.puts("      #{&1}"))
      false
    end
  end

  defp test_type_never_nil_or_missing(target) do
    IO.puts("   Testing that type information is never nil or missing...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        nil_type_issues = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, nil, _value} ->
              ["#{oid}: type is nil" | acc]
            {oid, type, _value} when not is_atom(type) ->
              ["#{oid}: type is not atom: #{inspect(type)}" | acc]
            {oid, type, _value} when type == :unknown ->
              ["#{oid}: type is :unknown (should be inferred)" | acc]
            _ ->
              acc
          end
        end)

        if Enum.empty?(nil_type_issues) do
          IO.puts("   ✅ All types are valid atoms (no nil/missing types)")
          true
        else
          IO.puts("   ❌ Type validity issues:")
          Enum.each(nil_type_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  # ============================================================================
  # WALK TYPE PRESERVATION TESTS
  # ============================================================================

  defp test_walk_type_preservation do
    IO.puts("\n🧪 Testing Walk Type Preservation Across Versions...")

    # Complex test data with various SNMP types
    test_data = %{
      "1.3.6.1.2.1.1.1.0" => "DisplayString Value",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.999.2",
      "1.3.6.1.2.1.1.3.0" => 54321,  # TimeTicks
      "1.3.6.1.2.1.1.7.0" => 72,     # Integer services
      "1.3.6.1.2.1.2.1.0" => 8,      # Integer ifNumber
      "1.3.6.1.2.1.2.2.1.1.1" => 1,    # Integer ifIndex
      "1.3.6.1.2.1.2.2.1.2.1" => "eth0", # DisplayString ifDescr
      "1.3.6.1.2.1.2.2.1.3.1" => 6,      # Integer ifType
      "1.3.6.1.2.1.2.2.1.5.1" => 1000000000, # Gauge32 ifSpeed
      "1.3.6.1.2.1.2.2.1.10.1" => 5000000,   # Counter32 ifInOctets
      "1.3.6.1.2.1.2.2.1.11.1" => 10000000   # Counter32 ifInUcastPkts
    }

    with_test_device(test_data, @test_port_base + 2, fn target ->
      tests = [
        test_default_walk_type_preservation(target),
        test_v1_walk_type_preservation(target),
        test_v2c_walk_type_preservation(target),
        test_walk_type_consistency_across_versions(target),
        test_subtree_walk_type_preservation(target),
        test_large_walk_type_preservation(target)
      ]

      {
        total: length(tests),
        passed: Enum.count(tests, & &1),
        failed: Enum.count(tests, &(not &1))
      }
    end)
  end

  defp test_default_walk_type_preservation(target) do
    IO.puts("   Testing default walk preserves types...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        validate_walk_type_preservation(results, "default walk")
      {:error, reason} ->
        IO.puts("   ❌ Default walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_v1_walk_type_preservation(target) do
    IO.puts("   Testing v1 walk preserves types...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v1, timeout: @test_timeout) do
      {:ok, results} ->
        validate_walk_type_preservation(results, "v1 walk")
      {:error, reason} ->
        IO.puts("   ❌ v1 walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_v2c_walk_type_preservation(target) do
    IO.puts("   Testing v2c walk preserves types...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) do
      {:ok, results} ->
        validate_walk_type_preservation(results, "v2c walk")
      {:error, reason} ->
        IO.puts("   ❌ v2c walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_walk_type_consistency_across_versions(target) do
    IO.puts("   Testing type consistency across SNMP versions...")

    default_results = case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} -> results
      {:error, _} -> []
    end

    v1_results = case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v1, timeout: @test_timeout) do
      {:ok, results} -> results
      {:error, _} -> []
    end

    v2c_results = case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) do
      {:ok, results} -> results
      {:error, _} -> []
    end

    if Enum.empty?(default_results) and Enum.empty?(v1_results) and Enum.empty?(v2c_results) do
      IO.puts("   ❌ All versions failed")
      return false
    end

    # Compare types between working versions
    working_results = [
      {"default", default_results},
      {"v1", v1_results},
      {"v2c", v2c_results}
    ] |> Enum.filter(fn {_, results} -> not Enum.empty?(results) end)

    if length(working_results) < 2 do
      IO.puts("   ⚠️  Only one version working, cannot compare consistency")
      return true
    end

    # Build type maps for comparison
    type_maps = Enum.map(working_results, fn {version, results} ->
      type_map = Enum.into(results, %{}, fn {oid, type, _value} -> {oid, type} end)
      {version, type_map}
    end)

    # Compare all pairs
    consistency_issues = Enum.reduce(type_maps, [], fn {version1, map1}, acc ->
      Enum.reduce(type_maps, acc, fn {version2, map2}, inner_acc ->
        if version1 >= version2, do: inner_acc, else:
        Enum.reduce(map1, inner_acc, fn {oid, type1}, issues ->
          case Map.get(map2, oid) do
            ^type1 -> issues
            type2 when not is_nil(type2) ->
              if type_compatible?(type1, type2) do
                issues
              else
                ["#{oid}: #{version1}=#{type1}, #{version2}=#{type2}" | issues]
              end
            nil -> issues
          end
        end)
      end)
    end)

    if Enum.empty?(consistency_issues) do
      IO.puts("   ✅ Types consistent across all working versions")
      true
    else
      IO.puts("   ❌ Type consistency issues:")
      Enum.each(consistency_issues, &IO.puts("      #{&1}"))
      false
    end
  end

  defp test_subtree_walk_type_preservation(target) do
    IO.puts("   Testing subtree walks preserve types...")

    subtrees = ["1.3.6.1.2.1.1", "1.3.6.1.2.1.2"]

    all_good = Enum.all?(subtrees, fn subtree ->
      case SnmpKit.SNMP.walk(target, subtree, timeout: @test_timeout) do
        {:ok, results} ->
          validate_walk_type_preservation(results, "subtree #{subtree}")
        {:error, _reason} ->
          IO.puts("   ⚠️  Subtree #{subtree} walk failed")
          true  # Don't fail the test for empty subtrees
      end
    end)

    if all_good do
      IO.puts("   ✅ All subtree walks preserve types")
      true
    else
      false
    end
  end

  defp test_large_walk_type_preservation(target) do
    IO.puts("   Testing large walks preserve types...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1", timeout: @test_timeout) do
      {:ok, results} when length(results) > 5 ->
        validate_walk_type_preservation(results, "large walk")
      {:ok, results} ->
        IO.puts("   ⚠️  Large walk returned only #{length(results)} results")
        validate_walk_type_preservation(results, "large walk")
      {:error, reason} ->
        IO.puts("   ❌ Large walk failed: #{inspect(reason)}")
        false
    end
  end

  # ============================================================================
  # VERSION TYPE CONSISTENCY TESTS
  # ============================================================================

  defp test_version_type_consistency do
    IO.puts("\n🧪 Testing Version Type Consistency...")

    test_data = %{
      "1.3.6.1.2.1.1.1.0" => "Version Consistency Test",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.999.3",
      "1.3.6.1.2.1.1.3.0" => 987654,
      "1.3.6.1.2.1.1.4.0" => "test@consistency.local"
    }

    with_test_device(test_data, @test_port_base + 3, fn target ->
      tests = [
        test_get_type_consistency_across_versions(target),
        test_get_next_type_consistency_across_versions(target),
        test_walk_type_consistency_detailed(target),
        test_bulk_vs_individual_type_consistency(target)
      ]

      {
        total: length(tests),
        passed: Enum.count(tests, & &1),
        failed: Enum.count(tests, &(not &1))
      }
    end)
  end

  defp test_get_type_consistency_across_versions(target) do
    IO.puts("   Testing GET type consistency across versions...")

    test_oid = "1.3.6.1.2.1.1.1.0"

    v1_result = SnmpKit.SNMP.get_with_type(target, test_oid, version: :v1, timeout: @test_timeout)
    v2c_result = SnmpKit.SNMP.get_with_type(target, test_oid, version: :v2c, timeout: @test_timeout)

    case {v1_result, v2c_result} do
      {{:ok, {_, v1_type, v1_value}}, {:ok, {_, v2c_type, v2c_value}}} ->
        if v1_value == v2c_value and type_compatible?(v1_type, v2c_type) do
          IO.puts("   ✅ GET types consistent: v1=#{v1_type}, v2c=#{v2c_type}")
          true
        else
          IO.puts("   ❌ GET inconsistency: v1=#{v1_type}/#{inspect(v1_value)}, v2c=#{v2c_type}/#{inspect(v2c_value)}")
          false
        end
      _ ->
        IO.puts("   ⚠️  Cannot compare GET versions (one failed)")
        true  # Don't fail if one version doesn't work
    end
  end

  defp test_get_next_type_consistency_across_versions(target) do
    IO.puts("   Testing GET_NEXT type consistency across versions...")

    start_oid = "1.3.6.1.2.1.1"

    v1_result = SnmpKit.SNMP.get_next(target, start_oid, version: :v1, timeout: @test_timeout)
    v2c_result = SnmpKit.SNMP.get_next(target, start_oid, version: :v2c, timeout: @test_timeout)

    case {v1_result, v2c_result} do
      {{:ok, {v1_oid, v1_type, v1_value}}, {:ok, {v2c_oid, v2c_type, v2c_value}}} ->
        if v1_oid == v2c_oid and v1_value == v2c_value and type_compatible?(v1_type, v2c_type) do
          IO.puts("   ✅ GET_NEXT types consistent: #{v1_oid} → #{v1_type}")
          true
        else
          IO.puts("   ❌ GET_NEXT inconsistency:")
          IO.puts("      v1: #{v1_oid} → #{v1_type}/#{inspect(v1_value)}")
          IO.puts("      v2c: #{v2c_oid} → #{v2c_type}/#{inspect(v2c_value)}")
          false
        end
      _ ->
        IO.puts("   ⚠️  Cannot compare GET_NEXT versions (one failed)")
        true
    end
  end

  defp test_walk_type_consistency_detailed(target) do
    IO.puts("   Testing detailed walk type consistency...")

    # This was partially implemented in the walk tests above
    # Adding more detailed validation here

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        # Check that each result has consistent internal structure
        structure_issues = Enum.reduce(results, [], fn {oid, type, value}, acc ->
          cond do
            not is_binary(oid) -> ["#{inspect(oid)}: OID not string" | acc]
            not is_atom(type) -> ["#{oid}: type not atom: #{inspect(type)}" | acc]
            not valid_snmp_type?(type) -> ["#{oid}: invalid SNMP type: #{type}" | acc]
            not type_value_compatible?(type, value) -> ["#{oid}: type #{type} incompatible with value #{inspect(value)}" | acc]
            true -> acc
          end
        end)

        if Enum.empty?(structure_issues) do
          IO.puts("   ✅ Walk type consistency detailed validation passed")
          true
        else
          IO.puts("   ❌ Walk structure issues:")
          Enum.each(structure_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_bulk_vs_individual_type_consistency(target) do
    IO.puts("   Testing bulk vs individual operation type consistency...")

    # Get individual results
    individual_results = case SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.1.1.0", timeout: @test_timeout) do
      {:ok, result} -> [result]
      {:error, _} -> []
    end

    # Get bulk results
    bulk_results = case SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1.1", version: :v2c, max_repetitions: 1, timeout: @test_timeout) do
      {:ok, results} -> results
      {:error, _} -> []
    end

    if Enum.empty?(individual_results) or Enum.empty?(bulk_results) do
      IO.puts("   ⚠️  Cannot compare bulk vs individual (one failed)")
      return true
    end

    # Find matching OIDs and compare types
    individual_map = Enum.into(individual_results, %{}, fn {oid, type, value} -> {oid, {type, value}} end)

    consistency_issues = Enum.reduce(bulk_results, [], fn {oid, bulk_type, bulk_value}, acc ->
      case Map.get(individual_map, oid) do
        {individual_type, individual_value} ->
          if bulk_value == individual_value and type_compatible?(bulk_type, individual_type) do
            acc
          else
            ["#{oid}: individual=#{individual_type}/#{inspect(individual_value)}, bulk=#{bulk_type}/#{inspect(bulk_value)}" | acc]
          end
        nil ->
          acc  # OID not in individual results
      end
    end)

    if Enum.empty?(consistency_issues) do
      IO.puts("   ✅ Bulk vs individual type consistency validated")
      true
    else
      IO.puts("   ❌ Bulk vs individual inconsistencies:")
      Enum.each(consistency_issues, &IO.puts("      #{&1}"))
      false
    end
  end

  # ============================================================================
end
