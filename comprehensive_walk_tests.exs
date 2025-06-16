#!/usr/bin/env elixir

# Comprehensive SNMP Walk Test Suite
# This test suite covers all aspects of SNMP walk functionality
# including type preservation, version handling, error conditions, and edge cases

Mix.install([
  {:snmpkit, path: "."}
])

defmodule ComprehensiveWalkTests do
  require Logger

  @moduledoc """
  Comprehensive test suite for SNMP walk functionality.

  Tests cover:
  1. Basic walk operations (v1, v2c, default)
  2. Type information preservation
  3. Error handling and edge cases
  4. Response format consistency
  5. Performance and scalability
  6. Protocol compliance
  7. Simulator integration
  """

  # Test configurations
  @test_port_base 8000
  @test_timeout 10_000

  def run_all_tests do
    IO.puts("=" * 80)
    IO.puts("COMPREHENSIVE SNMP WALK TEST SUITE")
    IO.puts("=" * 80)
    IO.puts("")

    # Disable debug logging for cleaner output
    Logger.configure(level: :warn)

    results = %{
      basic_functionality: test_basic_functionality(),
      type_preservation: test_type_preservation(),
      error_handling: test_error_handling(),
      version_compatibility: test_version_compatibility(),
      response_formats: test_response_formats(),
      edge_cases: test_edge_cases(),
      performance: test_performance(),
      protocol_compliance: test_protocol_compliance(),
      regression_tests: test_regression_tests()
    }

    print_summary(results)
    results
  end

  # ============================================================================
  # BASIC FUNCTIONALITY TESTS
  # ============================================================================

  defp test_basic_functionality do
    IO.puts("🧪 Testing Basic Functionality...")

    test_data = %{
      "1.3.6.1.2.1.1.1.0" => "Test Device Basic",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.999.1",
      "1.3.6.1.2.1.1.3.0" => 12345,
      "1.3.6.1.2.1.1.4.0" => "admin@test.local",
      "1.3.6.1.2.1.1.5.0" => "test-device.local"
    }

    with_test_device(test_data, @test_port_base + 1, fn target ->
      tests = [
        test_default_walk_works(target),
        test_v2c_walk_works(target),
        test_v1_walk_works(target),
        test_walk_returns_expected_count(target, map_size(test_data)),
        test_walk_returns_correct_oids(target, Map.keys(test_data)),
        test_walk_returns_correct_values(target, test_data),
        test_individual_operations_work(target)
      ]

      %{
        total: length(tests),
        passed: Enum.count(tests, & &1),
        failed: Enum.count(tests, &(not &1)),
        details: tests
      }
    end)
  end

  defp test_default_walk_works(target) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} when is_list(results) and length(results) > 0 ->
        IO.puts("   ✅ Default walk returns results")
        true
      {:ok, []} ->
        IO.puts("   ❌ Default walk returns empty list")
        false
      {:error, reason} ->
        IO.puts("   ❌ Default walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_v2c_walk_works(target) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) do
      {:ok, results} when is_list(results) and length(results) > 0 ->
        IO.puts("   ✅ v2c walk returns results")
        true
      {:ok, []} ->
        IO.puts("   ❌ v2c walk returns empty list")
        false
      {:error, reason} ->
        IO.puts("   ❌ v2c walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_v1_walk_works(target) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v1, timeout: @test_timeout) do
      {:ok, results} when is_list(results) and length(results) > 0 ->
        IO.puts("   ✅ v1 walk returns results")
        true
      {:ok, []} ->
        IO.puts("   ⚠️  v1 walk returns empty list (known issue)")
        false
      {:error, reason} ->
        IO.puts("   ❌ v1 walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_walk_returns_expected_count(target, expected_count) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} when length(results) == expected_count ->
        IO.puts("   ✅ Walk returns expected count (#{expected_count})")
        true
      {:ok, results} ->
        IO.puts("   ❌ Walk count mismatch: expected #{expected_count}, got #{length(results)}")
        false
      {:error, reason} ->
        IO.puts("   ❌ Walk failed for count test: #{inspect(reason)}")
        false
    end
  end

  defp test_walk_returns_correct_oids(target, expected_oids) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        returned_oids = extract_oids_from_results(results)
        expected_set = MapSet.new(expected_oids)
        returned_set = MapSet.new(returned_oids)

        if MapSet.equal?(expected_set, returned_set) do
          IO.puts("   ✅ Walk returns correct OIDs")
          true
        else
          missing = MapSet.difference(expected_set, returned_set) |> MapSet.to_list()
          extra = MapSet.difference(returned_set, expected_set) |> MapSet.to_list()
          IO.puts("   ❌ OID mismatch - Missing: #{inspect(missing)}, Extra: #{inspect(extra)}")
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed for OID test: #{inspect(reason)}")
        false
    end
  end

  defp test_walk_returns_correct_values(target, expected_data) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        result_map = results_to_map(results)

        mismatches = Enum.filter(expected_data, fn {oid, expected_value} ->
          case Map.get(result_map, oid) do
            ^expected_value -> false
            actual_value ->
              IO.puts("   ⚠️  Value mismatch for #{oid}: expected #{inspect(expected_value)}, got #{inspect(actual_value)}")
              true
            nil ->
              IO.puts("   ❌ Missing OID in results: #{oid}")
              true
          end
        end)

        if Enum.empty?(mismatches) do
          IO.puts("   ✅ Walk returns correct values")
          true
        else
          IO.puts("   ❌ #{length(mismatches)} value mismatches found")
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed for value test: #{inspect(reason)}")
        false
    end
  end

  defp test_individual_operations_work(target) do
    get_test = case SnmpKit.SNMP.get(target, "1.3.6.1.2.1.1.1.0", timeout: @test_timeout) do
      {:ok, _} -> true
      {:error, reason} ->
        IO.puts("   ❌ GET failed: #{inspect(reason)}")
        false
    end

    get_next_test = case SnmpKit.SNMP.get_next(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, _} -> true
      {:error, reason} ->
        IO.puts("   ❌ GET_NEXT failed: #{inspect(reason)}")
        false
    end

    get_bulk_test = case SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) do
      {:ok, _} -> true
      {:error, reason} ->
        IO.puts("   ❌ GET_BULK failed: #{inspect(reason)}")
        false
    end

    if get_test and get_next_test and get_bulk_test do
      IO.puts("   ✅ Individual SNMP operations work")
      true
    else
      IO.puts("   ❌ Some individual operations failed")
      false
    end
  end

  # ============================================================================
  # TYPE PRESERVATION TESTS
  # ============================================================================

  defp test_type_preservation do
    IO.puts("\n🧪 Testing Type Preservation...")

    # Test data with various SNMP types
    test_data = %{
      "1.3.6.1.2.1.1.1.0" => "String Value",          # Should be :octet_string
      "1.3.6.1.2.1.1.3.0" => 12345,                   # Should be :integer or :timeticks
      "1.3.6.1.2.1.2.1.0" => 5,                       # Should be :integer
      "1.3.6.1.2.1.2.2.1.10.1" => 1000000,           # Should be :counter32
      "1.3.6.1.2.1.2.2.1.11.1" => 2000000             # Should be :counter32
    }

    with_test_device(test_data, @test_port_base + 2, fn target ->
      tests = [
        test_walk_preserves_types(target),
        test_get_next_preserves_types(target),
        test_get_bulk_preserves_types(target),
        test_type_consistency_across_versions(target),
        test_type_inference_when_missing(target)
      ]

      %{
        total: length(tests),
        passed: Enum.count(tests, & &1),
        failed: Enum.count(tests, &(not &1)),
        details: tests
      }
    end)
  end

  defp test_walk_preserves_types(target) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        # Check that all results are 3-tuples with type information
        all_have_types = Enum.all?(results, fn result ->
          case result do
            {_oid, _type, _value} when is_atom(_type) -> true
            _ -> false
          end
        end)

        if all_have_types do
          IO.puts("   ✅ Walk preserves type information (3-tuples)")

          # Check specific types
          type_check = Enum.all?(results, fn {oid, type, value} ->
            expected_type = infer_expected_type(oid, value)
            if type == expected_type or type_compatible?(type, expected_type) do
              true
            else
              IO.puts("   ⚠️  Type mismatch for #{oid}: expected #{expected_type}, got #{type}")
              false
            end
          end)

          if type_check do
            IO.puts("   ✅ All types are correctly inferred/preserved")
            true
          else
            IO.puts("   ❌ Some type mismatches found")
            false
          end
        else
          IO.puts("   ❌ Walk results missing type information")
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed for type test: #{inspect(reason)}")
        false
    end
  end

  defp test_get_next_preserves_types(target) do
    case SnmpKit.SNMP.get_next(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, {_oid, _value}} ->
        IO.puts("   ⚠️  GET_NEXT returns 2-tuple (type info missing)")
        false
      {:ok, {_oid, _type, _value}} ->
        IO.puts("   ✅ GET_NEXT preserves type information")
        true
      {:error, reason} ->
        IO.puts("   ❌ GET_NEXT failed: #{inspect(reason)}")
        false
    end
  end

  defp test_get_bulk_preserves_types(target) do
    case SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) do
      {:ok, results} when is_list(results) ->
        all_have_types = Enum.all?(results, fn result ->
          case result do
            {_oid, _type, _value} -> true
            _ -> false
          end
        end)

        if all_have_types do
          IO.puts("   ✅ GET_BULK preserves type information")
          true
        else
          IO.puts("   ❌ GET_BULK results missing type information")
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ GET_BULK failed: #{inspect(reason)}")
        false
    end
  end

  defp test_type_consistency_across_versions(target) do
    v1_results = case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v1, timeout: @test_timeout) do
      {:ok, results} -> results
      {:error, _} -> []
    end

    v2c_results = case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) do
      {:ok, results} -> results
      {:error, _} -> []
    end

    if Enum.empty?(v1_results) do
      IO.puts("   ⚠️  Cannot compare versions (v1 failed)")
      false
    else
      v1_map = results_to_type_map(v1_results)
      v2c_map = results_to_type_map(v2c_results)

      mismatches = Enum.filter(v1_map, fn {oid, v1_type} ->
        case Map.get(v2c_map, oid) do
          ^v1_type -> false
          v2c_type when not is_nil(v2c_type) ->
            if type_compatible?(v1_type, v2c_type) do
              false
            else
              IO.puts("   ⚠️  Type inconsistency for #{oid}: v1=#{v1_type}, v2c=#{v2c_type}")
              true
            end
          nil ->
            IO.puts("   ⚠️  OID #{oid} missing in v2c results")
            false
        end
      end)

      if Enum.empty?(mismatches) do
        IO.puts("   ✅ Types consistent across SNMP versions")
        true
      else
        IO.puts("   ❌ #{length(mismatches)} type inconsistencies found")
        false
      end
    end
  end

  defp test_type_inference_when_missing(target) do
    # This would test scenarios where type info is missing and needs to be inferred
    # For now, just verify that type inference functions work correctly
    test_cases = [
      {"string value", :octet_string},
      {12345, :integer},
      {{:timeticks, 54321}, :timeticks},
      {{:counter32, 1000}, :counter32}
    ]

    all_correct = Enum.all?(test_cases, fn {value, expected_type} ->
      inferred = infer_snmp_type_for_test(value)
      if inferred == expected_type or type_compatible?(inferred, expected_type) do
        true
      else
        IO.puts("   ❌ Type inference failed: #{inspect(value)} → #{inferred}, expected #{expected_type}")
        false
      end
    end)

    if all_correct do
      IO.puts("   ✅ Type inference works correctly")
      true
    else
      IO.puts("   ❌ Type inference has issues")
      false
    end
  end

  # ============================================================================
  # ERROR HANDLING TESTS
  # ============================================================================

  defp test_error_handling do
    IO.puts("\n🧪 Testing Error Handling...")

    test_data = %{
      "1.3.6.1.2.1.1.1.0" => "Error Test Device"
    }

    with_test_device(test_data, @test_port_base + 3, fn target ->
      tests = [
        test_nonexistent_oid_walk(target),
        test_empty_subtree_walk(target),
        test_network_timeout_handling(),
        test_invalid_target_handling(),
        test_malformed_oid_handling(target),
        test_end_of_mib_handling(target),
        test_version_mismatch_handling(target)
      ]

      %{
        total: length(tests),
        passed: Enum.count(tests, & &1),
        failed: Enum.count(tests, &(not &1)),
        details: tests
      }
    end)
  end

  defp test_nonexistent_oid_walk(target) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.99", timeout: @test_timeout) do
      {:ok, []} ->
        IO.puts("   ✅ Nonexistent OID returns empty list")
        true
      {:ok, results} ->
        IO.puts("   ⚠️  Nonexistent OID returned #{length(results)} results (unexpected)")
        false
      {:error, _reason} ->
        IO.puts("   ✅ Nonexistent OID returns error (acceptable)")
        true
    end
  end

  defp test_empty_subtree_walk(target) do
    # Walk a subtree that exists but has no children
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1.1.0.1", timeout: @test_timeout) do
      {:ok, []} ->
        IO.puts("   ✅ Empty subtree returns empty list")
        true
      {:ok, results} ->
        IO.puts("   ⚠️  Empty subtree returned #{length(results)} results")
        false
      {:error, _reason} ->
        IO.puts("   ✅ Empty subtree returns error (acceptable)")
        true
    end
  end

  defp test_network_timeout_handling do
    # Test with unreachable target
    case SnmpKit.SNMP.walk("192.0.2.1:161", "1.3.6.1.2.1.1", timeout: 1000) do
      {:error, :timeout} ->
        IO.puts("   ✅ Network timeout properly handled")
        true
      {:error, _other_error} ->
        IO.puts("   ✅ Network error properly handled")
        true
      {:ok, _} ->
        IO.puts("   ❌ Unreachable target unexpectedly succeeded")
        false
    end
  end

  defp test_invalid_target_handling do
    case SnmpKit.SNMP.walk("invalid-target", "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:error, _reason} ->
        IO.puts("   ✅ Invalid target properly handled")
        true
      {:ok, _} ->
        IO.puts("   ❌ Invalid target unexpectedly succeeded")
        false
    end
  end

  defp test_malformed_oid_handling(target) do
    invalid_oids = ["", "invalid", "1.2.3.a", "1..2.3", nil]

    all_handled = Enum.all?(invalid_oids, fn oid ->
      case SnmpKit.SNMP.walk(target, oid, timeout: @test_timeout) do
        {:error, _reason} -> true
        {:ok, _} -> false
      end
    end)

    if all_handled do
      IO.puts("   ✅ Malformed OIDs properly handled")
      true
    else
      IO.puts("   ❌ Some malformed OIDs not handled properly")
      false
    end
  end

  defp test_end_of_mib_handling(target) do
    # Walk from a high OID that should reach end of MIB
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.999", timeout: @test_timeout) do
      {:ok, []} ->
        IO.puts("   ✅ End of MIB handled (empty result)")
        true
      {:error, :end_of_mib_view} ->
        IO.puts("   ✅ End of MIB handled (error result)")
        true
      {:error, _other} ->
        IO.puts("   ✅ End of MIB handled (other error)")
        true
      {:ok, results} ->
        IO.puts("   ⚠️  End of MIB returned #{length(results)} results")
        false
    end
  end

  defp test_version_mismatch_handling(target) do
    # Test operations that don't make sense for specific versions
    v1_bulk_test = case SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v1, timeout: @test_timeout) do
      {:error, _reason} ->
        IO.puts("   ✅ v1 GET_BULK properly rejected")
        true
      {:ok, _} ->
        IO.puts("   ❌ v1 GET_BULK unexpectedly succeeded")
        false
    end

    v1_bulk_test
  end

  # ============================================================================
  # VERSION COMPATIBILITY TESTS
  # ============================================================================

  defp test_version_compatibility do
    IO.puts("\n🧪 Testing Version Compatibility...")

    test_data = %{
      "1.3.6.1.2.1.1.1.0" => "Version Test Device",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.999",
      "1.3.6.1.2.1.1.3.0" => 99999
    }

    with_test_device(test_data, @test_port_base + 4, fn target ->
      tests = [
        test_default_version_behavior(target),
        test_explicit_version_parameters(target),
        test_version_specific_features(target),
        test_parameter_compatibility(target),
        test_response_format_consistency(target)
      ]

      %{
        total: length(tests),
        passed: Enum.count(tests, & &1),
        failed: Enum.count(tests, &(not &1)),
        details: tests
      }
    end)
  end

  defp test_default_version_behavior(target) do
    # Test that default version produces reasonable results
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} when length(results) > 0 ->
        IO.puts("   ✅ Default version works (#{length(results)} results)")
        true
      {:ok, []} ->
        IO.puts("   ❌ Default version returns empty results")
        false
      {:error, reason} ->
        IO.puts("   ❌ Default version failed: #{inspect(reason)}")
        false
    end
  end

  defp test_explicit_version_parameters(target) do
    versions_to_test = [:v1, :v2c]

    results = Enum.map(versions_to_test, fn version ->
      case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: version, timeout: @test_timeout) do
        {:ok, results} ->
          {version, :ok, length(results)}
        {:error, reason} ->
          {version, :error, reason}
      end
    end)

    working_versions = Enum.count(results, fn {_v, status, _} -> status == :ok end)

    if working_versions > 0 do
      IO.puts("   ✅ #{working_versions}/#{length(versions_to_test)} versions work")
      true
    else
      IO.puts("   ❌ No versions work")
      false
    end
  end

  defp test_version_specific_features(target) do
    # Test that v2c can use max_repetitions but v1 cannot (or ignores it)
    v2c_bulk_test = case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1",
                                          version: :v2c,
                                          max_repetitions: 5,
                                          timeout: @test_timeout) do
      {:ok, _results} ->
        IO.puts("   ✅ v2c accepts max_repetitions")
        true
      {:error, reason} ->
        IO.puts("   ❌ v2c with max_repetitions failed: #{inspect(reason)}")
        false
    end

    v1_with_max_rep = case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1",
                                            version: :v1,
                                            max_repetitions: 5,
                                            timeout: @test_timeout) do
      {:ok, _results} ->
        IO.puts("   ✅ v1 gracefully handles max_repetitions")
        true
      {:error, reason} ->
        IO.puts("   ⚠️  v1 with max_repetitions failed: #{inspect(reason)}")
        false
    end

    v2c_bulk_test and v1_with_max_rep
  end

  defp test_parameter_compatibility(target) do
    # Test various parameter combinations
    param_tests = [
      [version: :v2c, max_repetitions: 10],
      [version: :v2c, max_repetitions: 1],
      [version: :v1, max_iterations: 10],
      [version: :v1, timeout: 5000],
      [timeout: 10000],
      [community: "public"]
    ]

    working_params = Enum.count(param_tests, fn params ->
      case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", params ++ [timeout: @test_timeout]) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    end)

    if working_params >= length(param_tests) - 1 do  # Allow 1 failure
      IO.puts("   ✅ #{working_params}/#{length(param_tests)} parameter combinations work")
      true
    else
      IO.puts("   ❌ Only #{working_params}/#{length(param_tests)} parameter combinations work")
      false
    end
  end

  defp test_response_format_consistency(target) do
    # Test that different versions return consistent response formats
    v2c_response = SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout)
    default_response = SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout)

    case {v2c_response, default_response} do
      {{:ok, v2c_results}, {:ok, default_results}} ->
        v2c_format = analyze_result_format(v2c_results)
        default_format = analyze_result_format(default_results)

        if v2c_format == default_format do
          IO.puts("   ✅ Response formats consistent between versions")
          true
        else
          IO.puts("   ❌ Response format mismatch: v2c=#{v2c_format}, default=#{default_format}")
          false
        end
      _ ->
        IO.puts("   ⚠️  Cannot compare formats (one version failed)")
        false
    end
  end

  # ============================================================================
  # RESPONSE FORMAT TESTS
  # ============================================================================

  defp test_response_formats do
    IO.puts("\n🧪 Testing Response Formats...")

    test_data = %{
      "1.3.6.1.2.1.1.1.0" => "Format Test Device",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.999.2"
    }

    with_test_device(test_data, @test_port_base + 5, fn target ->
      tests = [
        test_walk_result_format(target),
        test_oid_format_consistency(target),
        test_value_format_consistency(target),
        test_type_format_consistency(target),
        test_tuple_structure_consistency(target)
      ]

      %{
        total: length(tests),
        passed: Enum.count(tests, & &1),
        failed: Enum.count(tests, &(not &1)),
        details: tests
      }
    end)
  end

  defp test_walk_result_format(target) do
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} when is_list(results) ->
        format_issues = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, type, value} when is_binary(oid) and is_atom(type) ->
              acc
            {oid, value} ->
              ["Missing type info for #{inspect(oid)}" | acc]
            other ->
              ["Invalid format: #{inspect(other)}" | acc]
          end
        end)

        if Enum.empty?(format_issues) do
          IO.puts("   ✅ Walk results have correct format (3-tuples)")
          true
        else
          IO.puts("   ❌ Format issues: #{inspect(format_issues)}")
          false
        end
      {:ok, results} ->
        IO.puts("   ❌ Walk
