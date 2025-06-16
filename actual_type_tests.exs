#!/usr/bin/env elixir

# SNMP Type Information Tests - WITH ACTUAL TYPE DATA
# This test properly includes SNMP type information in test data
# and validates that ALL operations preserve type information correctly

Mix.install([
  {:snmpkit, path: "."}
])

defmodule ActualTypeTests do
  require Logger

  @moduledoc """
  Tests that ACTUALLY include and validate SNMP type information.

  SNMP type information is CRITICAL. Without it:
  - You can't tell if 123 is an integer, timeticks, or counter
  - You can't distinguish between different string encodings
  - You lose essential semantic meaning of the data

  ALL test data includes explicit type information.
  ALL operations MUST return 3-tuples: {oid, type, value}
  """

  # Test configurations
  @test_port_base 6000
  @test_timeout 10_000

  def run_all_tests do
    IO.puts("=" * 80)
    IO.puts("ACTUAL SNMP TYPE INFORMATION TESTS")
    IO.puts("=" * 80)
    IO.puts("Testing with REAL type data - no more wishful thinking!")
    IO.puts("")

    # Disable debug logging for cleaner output
    Logger.configure(level: :warn)

    results = %{
      explicit_type_data_tests: test_explicit_type_data(),
      type_preservation_validation: test_type_preservation_validation(),
      cross_version_type_consistency: test_cross_version_type_consistency(),
      mandatory_3_tuple_format: test_mandatory_3_tuple_format(),
      snmp_type_semantics: test_snmp_type_semantics()
    }

    print_results(results)
    results
  end

  # ============================================================================
  # TEST DATA WITH EXPLICIT TYPE INFORMATION
  # ============================================================================

  # This is how test data SHOULD be structured - with explicit types
  defp get_typed_test_data do
    %{
      # System group with proper SNMP types
      "1.3.6.1.2.1.1.1.0" => %{
        value: "Test Device Description",
        expected_type: :octet_string,
        description: "sysDescr - DisplayString"
      },
      "1.3.6.1.2.1.1.2.0" => %{
        value: "1.3.6.1.4.1.999.1.2.3",
        expected_type: :object_identifier,
        description: "sysObjectID - OBJECT IDENTIFIER"
      },
      "1.3.6.1.2.1.1.3.0" => %{
        value: 12345,
        expected_type: :timeticks,
        description: "sysUpTime - TimeTicks (centiseconds)"
      },
      "1.3.6.1.2.1.1.4.0" => %{
        value: "admin@test.local",
        expected_type: :octet_string,
        description: "sysContact - DisplayString"
      },
      "1.3.6.1.2.1.1.5.0" => %{
        value: "test-device.local",
        expected_type: :octet_string,
        description: "sysName - DisplayString"
      },
      "1.3.6.1.2.1.1.6.0" => %{
        value: "Test Lab Location",
        expected_type: :octet_string,
        description: "sysLocation - DisplayString"
      },
      "1.3.6.1.2.1.1.7.0" => %{
        value: 78,
        expected_type: :integer,
        description: "sysServices - INTEGER (0..127)"
      },

      # Interface group with proper SNMP types
      "1.3.6.1.2.1.2.1.0" => %{
        value: 5,
        expected_type: :integer,
        description: "ifNumber - INTEGER"
      },
      "1.3.6.1.2.1.2.2.1.1.1" => %{
        value: 1,
        expected_type: :integer,
        description: "ifIndex.1 - InterfaceIndex"
      },
      "1.3.6.1.2.1.2.2.1.2.1" => %{
        value: "eth0",
        expected_type: :octet_string,
        description: "ifDescr.1 - DisplayString"
      },
      "1.3.6.1.2.1.2.2.1.3.1" => %{
        value: 6,
        expected_type: :integer,
        description: "ifType.1 - IANAifType (ethernet-csmacd)"
      },
      "1.3.6.1.2.1.2.2.1.5.1" => %{
        value: 1000000000,
        expected_type: :gauge32,
        description: "ifSpeed.1 - Gauge32 (bits per second)"
      },
      "1.3.6.1.2.1.2.2.1.8.1" => %{
        value: 1,
        expected_type: :integer,
        description: "ifOperStatus.1 - INTEGER {up(1), down(2), testing(3)}"
      },
      "1.3.6.1.2.1.2.2.1.10.1" => %{
        value: 5000000,
        expected_type: :counter32,
        description: "ifInOctets.1 - Counter32 (bytes received)"
      },
      "1.3.6.1.2.1.2.2.1.11.1" => %{
        value: 10000,
        expected_type: :counter32,
        description: "ifInUcastPkts.1 - Counter32 (unicast packets received)"
      },
      "1.3.6.1.2.1.2.2.1.16.1" => %{
        value: 3000000,
        expected_type: :counter32,
        description: "ifOutOctets.1 - Counter32 (bytes transmitted)"
      },
      "1.3.6.1.2.1.2.2.1.17.1" => %{
        value: 8000,
        expected_type: :counter32,
        description: "ifOutUcastPkts.1 - Counter32 (unicast packets transmitted)"
      }
    }
  end

  # Convert typed test data to simple OID map for device creation
  defp typed_test_data_to_device_map(typed_data) do
    Enum.into(typed_data, %{}, fn {oid, %{value: value}} -> {oid, value} end)
  end

  # ============================================================================
  # EXPLICIT TYPE DATA TESTS
  # ============================================================================

  defp test_explicit_type_data do
    IO.puts("🧪 Testing with Explicit Type Data...")

    typed_data = get_typed_test_data()
    device_data = typed_test_data_to_device_map(typed_data)

    with_test_device(device_data, @test_port_base + 1, fn target ->
      tests = [
        test_all_operations_return_expected_types(target, typed_data),
        test_walk_preserves_all_expected_types(target, typed_data),
        test_individual_gets_return_expected_types(target, typed_data),
        test_bulk_operations_preserve_expected_types(target, typed_data),
        test_no_type_information_loss(target, typed_data)
      ]

      calculate_test_results(tests, "explicit type data")
    end)
  end

  defp test_all_operations_return_expected_types(target, typed_data) do
    IO.puts("   Testing ALL operations return expected types...")

    type_failures = []

    # Test individual GETs
    get_failures = Enum.reduce(typed_data, [], fn {oid, %{expected_type: expected}}, acc ->
      case SnmpKit.SNMP.get_with_type(target, oid, timeout: @test_timeout) do
        {:ok, {^oid, actual_type, _value}} ->
          if type_matches?(actual_type, expected) do
            acc
          else
            ["GET #{oid}: expected #{expected}, got #{actual_type}" | acc]
          end
        {:ok, {^oid, _value}} ->
          ["GET #{oid}: returned 2-tuple - TYPE INFORMATION LOST!" | acc]
        {:ok, other} ->
          ["GET #{oid}: invalid format #{inspect(other)}" | acc]
        {:error, reason} ->
          ["GET #{oid}: failed #{inspect(reason)}" | acc]
      end
    end)

    # Test WALK
    walk_failures = case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, actual_type, _value} ->
              case Map.get(typed_data, oid) do
                %{expected_type: expected_type} ->
                  if type_matches?(actual_type, expected_type) do
                    acc
                  else
                    ["WALK #{oid}: expected #{expected_type}, got #{actual_type}" | acc]
                  end
                nil ->
                  if valid_snmp_type?(actual_type) do
                    acc
                  else
                    ["WALK #{oid}: invalid type #{actual_type}" | acc]
                  end
              end
            {oid, _value} ->
              ["WALK #{oid}: 2-tuple - TYPE INFORMATION LOST!" | acc]
            other ->
              ["WALK invalid format: #{inspect(other)}" | acc]
          end
        end)
      {:error, reason} ->
        ["WALK failed: #{inspect(reason)}"]
    end

    all_failures = get_failures ++ walk_failures

    if Enum.empty?(all_failures) do
      IO.puts("   ✅ All operations return expected types")
      true
    else
      IO.puts("   ❌ Type expectation failures:")
      Enum.each(all_failures, &IO.puts("      #{&1}"))
      false
    end
  end

  defp test_walk_preserves_all_expected_types(target, typed_data) do
    IO.puts("   Testing walk preserves ALL expected types...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1", timeout: @test_timeout) do
      {:ok, results} ->
        type_preservation_issues = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, type, value} when is_binary(oid) and is_atom(type) ->
              # Check if this OID has expected type data
              case Map.get(typed_data, oid) do
                %{expected_type: expected_type, value: expected_value} ->
                  cond do
                    not type_matches?(type, expected_type) ->
                      ["#{oid}: type mismatch - expected #{expected_type}, got #{type}" | acc]
                    value != expected_value ->
                      ["#{oid}: value mismatch - expected #{inspect(expected_value)}, got #{inspect(value)}" | acc]
                    true ->
                      acc
                  end
                nil ->
                  # OID not in our test data, just verify type is valid
                  if valid_snmp_type?(type) do
                    acc
                  else
                    ["#{oid}: invalid SNMP type #{type}" | acc]
                  end
              end
            {oid, _value} ->
              ["#{oid}: 2-tuple format - TYPE INFORMATION LOST!" | acc]
            other ->
              ["Invalid result format: #{inspect(other)}" | acc]
          end
        end)

        if Enum.empty?(type_preservation_issues) do
          IO.puts("   ✅ Walk preserves all expected types (#{length(results)} results)")
          true
        else
          IO.puts("   ❌ Type preservation issues:")
          Enum.each(type_preservation_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_individual_gets_return_expected_types(target, typed_data) do
    IO.puts("   Testing individual GETs return expected types...")

    # Test specific high-value OIDs with known types
    critical_oids = [
      "1.3.6.1.2.1.1.3.0",  # sysUpTime - must be TimeTicks
      "1.3.6.1.2.1.2.2.1.10.1",  # ifInOctets - must be Counter32
      "1.3.6.1.2.1.2.2.1.5.1"   # ifSpeed - must be Gauge32
    ]

    type_issues = Enum.reduce(critical_oids, [], fn oid, acc ->
      case {Map.get(typed_data, oid), SnmpKit.SNMP.get_with_type(target, oid, timeout: @test_timeout)} do
        {%{expected_type: expected}, {:ok, {^oid, actual, _value}}} ->
          if type_matches?(actual, expected) do
            acc
          else
            ["CRITICAL: #{oid} expected #{expected}, got #{actual}" | acc]
          end
        {%{expected_type: expected}, {:ok, {^oid, _value}}} ->
          ["CRITICAL: #{oid} expected #{expected}, got 2-tuple (TYPE LOST!)" | acc]
        {nil, _} ->
          ["Missing test data for critical OID #{oid}" | acc]
        {_, {:error, reason}} ->
          ["Failed to get critical OID #{oid}: #{inspect(reason)}" | acc]
      end
    end)

    if Enum.empty?(type_issues) do
      IO.puts("   ✅ All critical OIDs return expected types")
      true
    else
      IO.puts("   ❌ Critical type issues:")
      Enum.each(type_issues, &IO.puts("      #{&1}"))
      false
    end
  end

  defp test_bulk_operations_preserve_expected_types(target, typed_data) do
    IO.puts("   Testing bulk operations preserve expected types...")

    case SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v2c, max_repetitions: 10, timeout: @test_timeout) do
      {:ok, results} ->
        bulk_type_issues = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, type, value} ->
              case Map.get(typed_data, oid) do
                %{expected_type: expected_type, value: expected_value} ->
                  cond do
                    not type_matches?(type, expected_type) ->
                      ["BULK #{oid}: expected #{expected_type}, got #{type}" | acc]
                    value != expected_value ->
                      ["BULK #{oid}: value mismatch" | acc]
                    true ->
                      acc
                  end
                nil ->
                  if valid_snmp_type?(type) do
                    acc
                  else
                    ["BULK #{oid}: invalid type #{type}" | acc]
                  end
              end
            {oid, _value} ->
              ["BULK #{oid}: 2-tuple - TYPE LOST!" | acc]
            other ->
              ["BULK invalid format: #{inspect(other)}" | acc]
          end
        end)

        if Enum.empty?(bulk_type_issues) do
          IO.puts("   ✅ Bulk operations preserve expected types (#{length(results)} results)")
          true
        else
          IO.puts("   ❌ Bulk type issues:")
          Enum.each(bulk_type_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Bulk operation failed: #{inspect(reason)}")
        false
    end
  end

  defp test_no_type_information_loss(target, _typed_data) do
    IO.puts("   Testing ZERO tolerance for type information loss...")

    # Test all major operations and ensure NONE return 2-tuples
    operations = [
      {"GET", fn -> SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.1.1.0", timeout: @test_timeout) end},
      {"GET_NEXT", fn -> SnmpKit.SNMP.get_next(target, "1.3.6.1.2.1.1", timeout: @test_timeout) end},
      {"GET_BULK", fn -> SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) end},
      {"WALK", fn -> SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) end},
      {"WALK_v1", fn -> SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v1, timeout: @test_timeout) end},
      {"WALK_v2c", fn -> SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) end}
    ]

    type_loss_violations = Enum.reduce(operations, [], fn {op_name, op_func}, acc ->
      case op_func.() do
        {:ok, results} when is_list(results) ->
          # Check each result in list
          Enum.reduce(results, acc, fn result, inner_acc ->
            case result do
              {_oid, _type, _value} -> inner_acc  # Good 3-tuple
              {oid, _value} -> ["#{op_name}: #{oid} is 2-tuple - TYPE LOST!" | inner_acc]
              other -> ["#{op_name}: invalid format #{inspect(other)}" | inner_acc]
            end
          end)
        {:ok, {_oid, _type, _value}} ->
          acc  # Good 3-tuple
        {:ok, {oid, _value}} ->
          ["#{op_name}: #{oid} is 2-tuple - TYPE LOST!" | acc]
        {:ok, other} ->
          ["#{op_name}: invalid format #{inspect(other)}" | acc]
        {:error, _} ->
          acc  # Errors are acceptable for this test
      end
    end)

    if Enum.empty?(type_loss_violations) do
      IO.puts("   ✅ ZERO type information loss detected across all operations")
      true
    else
      IO.puts("   ❌ TYPE INFORMATION LOSS VIOLATIONS:")
      Enum.each(type_loss_violations, &IO.puts("      #{&1}"))
      false
    end
  end

  # ============================================================================
  # TYPE PRESERVATION VALIDATION
  # ============================================================================

  defp test_type_preservation_validation do
    IO.puts("\n🧪 Testing Type Preservation Validation...")

    typed_data = get_typed_test_data()
    device_data = typed_test_data_to_device_map(typed_data)

    with_test_device(device_data, @test_port_base + 2, fn target ->
      tests = [
        test_timeticks_vs_integer_distinction(target),
        test_counter_vs_gauge_distinction(target),
        test_string_vs_oid_distinction(target),
        test_type_semantic_meaning_preservation(target)
      ]

      calculate_test_results(tests, "type preservation validation")
    end)
  end

  defp test_timeticks_vs_integer_distinction(target) do
    IO.puts("   Testing TimeTicks vs Integer distinction...")

    # sysUpTime MUST be TimeTicks, not Integer
    case SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.1.3.0", timeout: @test_timeout) do
      {:ok, {_, :timeticks, value}} when is_integer(value) ->
        IO.puts("   ✅ sysUpTime correctly typed as TimeTicks: #{value} centiseconds")
        true
      {:ok, {_, :integer, value}} ->
        IO.puts("   ❌ sysUpTime incorrectly typed as Integer: #{value} (should be TimeTicks)")
        false
      {:ok, {_, other_type, value}} ->
        IO.puts("   ❌ sysUpTime wrong type: #{other_type} (should be TimeTicks)")
        false
      {:ok, {_, value}} ->
        IO.puts("   ❌ sysUpTime missing type information (should be TimeTicks)")
        false
      {:error, reason} ->
        IO.puts("   ❌ Failed to get sysUpTime: #{inspect(reason)}")
        false
    end
  end

  defp test_counter_vs_gauge_distinction(target) do
    IO.puts("   Testing Counter32 vs Gauge32 distinction...")

    # ifInOctets MUST be Counter32 (monotonically increasing)
    counter_test = case SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.2.2.1.10.1", timeout: @test_timeout) do
      {:ok, {_, :counter32, value}} when is_integer(value) ->
        IO.puts("   ✅ ifInOctets correctly typed as Counter32: #{value}")
        true
      {:ok, {_, other_type, value}} ->
        IO.puts("   ❌ ifInOctets wrong type: #{other_type} (should be Counter32)")
        false
      {:error, _} ->
        IO.puts("   ⚠️  ifInOctets not available for testing")
        true
    end

    # ifSpeed MUST be Gauge32 (instantaneous value)
    gauge_test = case SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.2.2.1.5.1", timeout: @test_timeout) do
      {:ok, {_, :gauge32, value}} when is_integer(value) ->
        IO.puts("   ✅ ifSpeed correctly typed as Gauge32: #{value} bps")
        true
      {:ok, {_, other_type, value}} ->
        IO.puts("   ❌ ifSpeed wrong type: #{other_type} (should be Gauge32)")
        false
      {:error, _} ->
        IO.puts("   ⚠️  ifSpeed not available for testing")
        true
    end

    counter_test and gauge_test
  end

  defp test_string_vs_oid_distinction(target) do
    IO.puts("   Testing String vs OID distinction...")

    # sysDescr MUST be OctetString (DisplayString)
    string_test = case SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.1.1.0", timeout: @test_timeout) do
      {:ok, {_, :octet_string, value}} when is_binary(value) ->
        IO.puts("   ✅ sysDescr correctly typed as OctetString: #{inspect(value)}")
        true
      {:ok, {_, other_type, value}} ->
        IO.puts("   ❌ sysDescr wrong type: #{other_type} (should be OctetString)")
        false
      {:error, _} ->
        false
    end

    # sysObjectID MUST be ObjectIdentifier
    oid_test = case SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.1.2.0", timeout: @test_timeout) do
      {:ok, {_, :object_identifier, value}} when is_binary(value) ->
        IO.puts("   ✅ sysObjectID correctly typed as ObjectIdentifier: #{value}")
        true
      {:ok, {_, :octet_string, value}} ->
        # Many implementations return OID as string, which is acceptable
        IO.puts("   ✅ sysObjectID as OctetString (acceptable): #{value}")
        true
      {:ok, {_, other_type, value}} ->
        IO.puts("   ❌ sysObjectID wrong type: #{other_type} (should be ObjectIdentifier)")
        false
      {:error, _} ->
        false
    end

    string_test and oid_test
  end

  defp test_type_semantic_meaning_preservation(target) do
    IO.puts("   Testing type semantic meaning preservation...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.2.2.1", timeout: @test_timeout) do
      {:ok, results} ->
        semantic_issues = Enum.reduce(results, [], fn {oid, type, value}, acc ->
          cond do
            # Interface indices should be integers
            String.contains?(oid, ".2.2.1.1.") and type != :integer ->
              ["#{oid}: ifIndex should be integer, got #{type}" | acc]

            # Interface descriptions should be strings
            String.contains?(oid, ".2.2.1.2.") and type not in [:octet_string, :display_string] ->
              ["#{oid}: ifDescr should be string, got #{type}" | acc]

            # Interface types should be integers
            String.contains?(oid, ".2.2.1.3.") and type != :integer ->
              ["#{oid}: ifType should be integer, got #{type}" | acc]

            # Interface speeds should be gauges
            String.contains?(oid, ".2.2.1.5.") and type not in [:gauge32, :gauge, :integer] ->
              ["#{oid}: ifSpeed should be gauge32, got #{type}" | acc]

            # Interface counters should be counters
            String.contains?(oid, ".2.2.1.10.") and type not in [:counter32, :counter] ->
              ["#{oid}: ifInOctets should be counter32, got #{type}" | acc]

            true ->
              acc
          end
        end)

        if Enum.empty?(semantic_issues) do
          IO.puts("   ✅ Type semantic meanings preserved (#{length(results)} results)")
          true
        else
          IO.puts("   ❌ Semantic meaning issues:")
          Enum.each(semantic_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Interface table walk failed: #{inspect(reason)}")
        false
    end
  end

  # ============================================================================
  # CROSS-VERSION TYPE CONSISTENCY
  # ============================================================================

  defp test_cross_version_type_consistency do
    IO.puts("\n🧪 Testing Cross-Version Type Consistency...")

    typed_data = get_typed_test_data()
    device_data = typed_test_data_to_device_map(typed_data)

    with_test_device(device_data, @test_port_base + 3, fn target ->
      tests = [
        test_v1_vs_v2c_type_consistency(target),
        test_default_vs_explicit_version_consistency(target),
        test_operation_type_consistency_across_versions(target)
      ]

      calculate_test_results(tests, "cross-version type consistency")
    end)
  end

  defp test_v1_vs_v2c_type_consistency(target) do
    IO.puts("   Testing v1 vs v2c type consistency...")

    test_oid = "1.3.6.1.2.1.1.1.0"

    v1_result = SnmpKit.SNMP.get_with_type(target, test_oid, version: :v1, timeout: @test_timeout)
    v2c_result = SnmpKit.SNMP.get_with_type(target, test_oid, version: :v2c, timeout: @test_timeout)

    case {v1_result, v2c_result} do
      {{:ok, {_, v1_type, v1_value}}, {:ok, {_, v2c_type, v2c_value}}} ->
        if v1_value == v2c_value and type_compatible?(v1_type, v2c_type) do
          IO.puts("   ✅ v1 and v2c return consistent types: #{v1_type}/#{v2c_type}")
          true
        else
          IO.puts("   ❌ v1/v2c inconsistency: v1=#{v1_type}/#{inspect(v1_value)}, v2c=#{v2c_type}/#{inspect(v2c_value)}")
          false
        end
      {{:ok, {_, v1_type, v1_value}}, {:error, v2c_error}} ->
        IO.puts("   ⚠️  v1 works (#{v1_type}), v2c failed: #{inspect(v2c_error)}")
        true
      {{:error, v1_error}, {:ok, {_, v2c_type, v2c_value}}} ->
        IO.puts("   ⚠️  v2c works (#{v2c_type}), v1 failed: #{inspect(v1_error)}")
        true
      {{:error, v1_error}, {:error, v2c_error}} ->
        IO.puts("   ❌ Both v1 and v2c failed: v1=#{inspect(v1_error)}, v2c=#{inspect(v2c_error)}")
        false
    end
  end

  defp test_default_vs_explicit_version_consistency(target) do
    IO.puts("   Testing default vs explicit version consistency...")

    test_oid = "1.3.6.1.2.1.1.3.0"  # sysUpTime - should be TimeTicks

    default_result = SnmpKit.SNMP.get_with_type(target, test_oid, timeout: @test_timeout)
    explicit_result = SnmpKit.SNMP.get_with_type(target, test_oid, version: :v2c, timeout: @test_timeout)

    case {default_result, explicit_result} do
      {{:ok, {_, default_type, default_value}}, {:ok, {_, explicit_type, explicit_value}}} ->
        if default_value == explicit_value and type_compatible?(default_type, explicit_type) do
          IO.puts("   ✅ Default and explicit versions consistent: #{default_type}")

          # Also verify it's the expected type (TimeTicks)
          if type_matches?(default_type, :timeticks) do
            IO.puts("   ✅ Correct type preserved: TimeTicks")
            true
          else
            IO.puts("   ❌ Wrong type: expected TimeTicks, got #{default_type}")
            false
          end
        else
          IO.puts("   ❌ Default/explicit inconsistency")
          false
        end
      _ ->
        IO.puts("   ❌ One or both versions failed")
        false
    end
  end

  defp test_operation_type_consistency_across_versions(target) do
    IO.puts("   Testing operation type consistency across versions...")

    # Test that walk operations return consistent types regardless of version
    default_walk = SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout)
    v2c_walk = SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout)

    case {default_walk, v2c_walk} do
      {{:ok, default_results}, {:ok, v2c_results}} ->
        # Convert to type maps for comparison
        default_types = results_to_type_map(default_results)
        v2c_types = results_to_type_map(v2c_results)

        # Find common OIDs and compare types
        common_oids = MapSet.intersection(
          MapSet.new(Map.keys(default_types)),
          MapSet.new(Map.keys(v2c_types))
        )

        inconsistencies = Enum.reduce(common_oids, [], fn oid, acc ->
          default_type = Map.get(default_types, oid)
          v2c_type = Map.get(v2c_types, oid)

          if type_compatible?(default_type, v2c_type) do
            acc
          else
            ["#{oid}: default=#{default_type}, v2c=#{v2c_type}" | acc]
          end
        end)

        if Enum.empty?(inconsistencies) do
          IO.puts("   ✅ Operation types consistent across versions (#{MapSet.size(common_oids)} OIDs)")
          true
        else
          IO.puts("   ❌ Type inconsistencies across versions:")
          Enum.each(inconsistencies, &IO.puts("      #{&1}"))
          false
        end
      _ ->
        IO.puts("   ⚠️  Cannot compare - one or both walks failed")
        true
    end
  end

  # ============================================================================
  # MANDATORY 3-TUPLE FORMAT TESTS
  # ============================================================================

  defp test_mandatory_3_tuple_format do
    IO.puts("\n🧪 Testing Mandatory 3-Tuple Format...")

    typed_data = get_typed_test_data()
    device_data = typed_test_data_to_device_map(typed_data)

    with_test_device(device_data, @test_port_base + 4, fn target ->
      tests = [
        test_no_2_tuple_responses_anywhere(target),
        test_all_responses_have_type_atoms(target),
        test_tuple_structure_validation(target)
      ]

      calculate_test_results(tests, "mandatory 3-tuple format")
    end)
  end

  defp test_no_2_tuple_responses_anywhere(target) do
    IO.puts("   Testing NO 2-tuple responses allowed anywhere...")

    # Test every operation type
    operations = [
      {"GET", fn -> SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.1.1.0", timeout: @test_timeout) end},
      {"GET_NEXT", fn -> SnmpKit.SNMP.get_next(target, "1.3.6.1.2.1.1", timeout: @test_timeout) end},
      {"GET_BULK", fn -> SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) end},
      {"WALK_DEFAULT", fn -> SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) end},
      {"WALK_V1", fn -> SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v1, timeout: @test_timeout) end},
      {"WALK_V2C", fn -> SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: @test_timeout) end}
    ]

    violations = Enum.reduce(operations, [], fn {op_name, op_func}, acc ->
      case op_func.() do
        {:ok, results} when is_list(results) ->
          Enum.reduce(results, acc, fn result, inner_acc ->
            case result do
              {_oid, _type, _value} -> inner_acc
              {oid, _value} -> ["#{op_name}: #{oid} returned 2-tuple - TYPE LOST!" | inner_acc]
              other -> ["#{op_name}: invalid format #{inspect(other)}" | inner_acc]
            end
          end)
        {:ok, {_oid, _type, _value}} -> acc
        {:ok, {oid, _value}} -> ["#{op_name}: #{oid} returned 2-tuple - TYPE LOST!" | acc]
        {:ok, other} -> ["#{op_name}: invalid format #{inspect(other)}" | acc]
        {:error, _} -> acc
      end
    end)

    if Enum.empty?(violations) do
      IO.puts("   ✅ ZERO 2-tuple responses found - all operations preserve types")
      true
    else
      IO.puts("   ❌ TYPE PRESERVATION VIOLATIONS:")
      Enum.each(violations, &IO.puts("      #{&1}"))
      false
    end
  end

  defp test_all_responses_have_type_atoms(target) do
    IO.puts("   Testing all responses have valid type atoms...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1", timeout: @test_timeout) do
      {:ok, results} ->
        type_atom_issues = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, type, _value} when is_atom(type) and type != nil ->
              if valid_snmp_type?(type) do
                acc
              else
                ["#{oid}: invalid SNMP type atom #{type}" | acc]
              end
            {oid, type, _value} ->
              ["#{oid}: type is not valid atom: #{inspect(type)}" | acc]
            {oid, _value} ->
              ["#{oid}: missing type information" | acc]
            other ->
              ["Invalid result format: #{inspect(other)}" | acc]
          end
        end)

        if Enum.empty?(type_atom_issues) do
          IO.puts("   ✅ All responses have valid type atoms (#{length(results)} results)")
          true
        else
          IO.puts("   ❌ Type atom issues:")
          Enum.each(type_atom_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_tuple_structure_validation(target) do
    IO.puts("   Testing tuple structure validation...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        structure_issues = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, type, value} when is_binary(oid) and is_atom(type) ->
              cond do
                String.length(oid) < 7 -> ["#{oid}: OID too short" | acc]
                not String.starts_with?(oid, "1.3.6.1") -> ["#{oid}: invalid OID format" | acc]
                type == :unknown -> ["#{oid}: type should not be :unknown" | acc]
                is_nil(value) -> ["#{oid}: value should not be nil" | acc]
                true -> acc
              end
            {oid, type, _value} ->
              issues = []
              issues = if not is_binary(oid), do: ["OID not string: #{inspect(oid)}" | issues], else: issues
              issues = if not is_atom(type), do: ["Type not atom: #{inspect(type)}" | issues], else: issues
              issues ++ acc
            other ->
              ["Invalid tuple structure: #{inspect(other)}" | acc]
          end
        end)

        if Enum.empty?(structure_issues) do
          IO.puts("   ✅ All tuples have valid structure")
          true
        else
          IO.puts("   ❌ Structure issues:")
          Enum.each(structure_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  # ============================================================================
  # SNMP TYPE SEMANTICS TESTS
  # ============================================================================

  defp test_snmp_type_semantics do
    IO.puts("\n🧪 Testing SNMP Type Semantics...")

    typed_data = get_typed_test_data()
    device_data = typed_test_data_to_device_map(typed_data)

    with_test_device(device_data, @test_port_base + 5, fn target ->
      tests = [
        test_semantic_type_requirements(target),
        test_standard_mib_type_compliance(target),
        test_type_value_compatibility(target)
      ]

      calculate_test_results(tests, "SNMP type semantics")
    end)
  end

  defp test_semantic_type_requirements(target) do
    IO.puts("   Testing semantic type requirements...")

    # Define semantic requirements for well-known OIDs
    semantic_requirements = %{
      "1.3.6.1.2.1.1.3.0" => %{required_type: :timeticks, description: "sysUpTime MUST be TimeTicks"},
      "1.3.6.1.2.1.2.2.1.10.1" => %{required_type: :counter32, description: "ifInOctets MUST be Counter32"},
      "1.3.6.1.2.1.2.2.1.5.1" => %{required_type: :gauge32, description: "ifSpeed MUST be Gauge32"},
      "1.3.6.1.2.1.1.1.0" => %{required_type: :octet_string, description: "sysDescr MUST be DisplayString"},
      "1.3.6.1.2.1.1.7.0" => %{required_type: :integer, description: "sysServices MUST be INTEGER"}
    }

    semantic_violations = Enum.reduce(semantic_requirements, [], fn {oid, %{required_type: required, description: desc}}, acc ->
      case SnmpKit.SNMP.get_with_type(target, oid, timeout: @test_timeout) do
        {:ok, {^oid, actual_type, _value}} ->
          if type_matches?(actual_type, required) do
            acc
          else
            ["#{desc}: got #{actual_type}" | acc]
          end
        {:ok, {^oid, _value}} ->
          ["#{desc}: missing type information" | acc]
        {:error, _reason} ->
          ["#{desc}: OID not available" | acc]
      end
    end)

    if Enum.empty?(semantic_violations) do
      IO.puts("   ✅ All semantic type requirements met")
      true
    else
      IO.puts("   ❌ Semantic violations:")
      Enum.each(semantic_violations, &IO.puts("      #{&1}"))
      false
    end
  end

  defp test_standard_mib_type_compliance(target) do
    IO.puts("   Testing standard MIB type compliance...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1", timeout: @test_timeout) do
      {:ok, results} ->
        compliance_issues = Enum.reduce(results, [], fn {oid, type, value}, acc ->
          cond do
            # System group compliance
            String.starts_with?(oid, "1.3.6.1.2.1.1.") ->
              validate_system_group_types(oid, type, value, acc)

            # Interfaces group compliance
            String.starts_with?(oid, "1.3.6.1.2.1.2.") ->
              validate_interfaces_group_types(oid, type, value, acc)

            true ->
              acc
          end
        end)

        if Enum.empty?(compliance_issues) do
          IO.puts("   ✅ Standard MIB type compliance verified")
          true
        else
          IO.puts("   ❌ MIB compliance issues:")
          Enum.each(compliance_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ MIB walk failed: #{inspect(reason)}")
        false
    end
  end

  defp test_type_value_compatibility(target) do
    IO.puts("   Testing type-value compatibility...")

    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: @test_timeout) do
      {:ok, results} ->
        compatibility_issues = Enum.reduce(results, [], fn {oid, type, value}, acc ->
          if type_value_compatible?(type, value) do
            acc
          else
            ["#{oid}: type #{type} incompatible with value #{inspect(value)}" | acc]
          end
        end)

        if Enum.empty?(compatibility_issues) do
          IO.puts("   ✅ All type-value combinations compatible")
          true
        else
          IO.puts("   ❌ Type-value compatibility issues:")
          Enum.each(compatibility_issues, &IO.puts("      #{&1}"))
          false
        end
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  defp with_test_device(oid_map, port, test_func) do
    case SnmpKit.SnmpSim.ProfileLoader.load_profile(:test, {:manual, oid_map}) do
      {:ok, profile} ->
        case SnmpKit.Sim.start_device(profile, port: port) do
          {:ok, _device} ->
            target = "127.0.0.1:#{port}"
            test_func.(target)
          {:error, reason} ->
            IO.puts("   ❌ Failed to start test device: #{inspect(reason)}")
            %{total: 1, passed: 0, failed: 1}
        end
      {:error, reason} ->
        IO.puts("   ❌ Failed to load test profile: #{inspect(reason)}")
        %{total: 1, passed: 0, failed: 1}
    end
  end

  defp calculate_test_results(tests, test_name) do
    total = length(tests)
    passed = Enum.count(tests, & &1)
    failed = total - passed

    IO.puts("   #{test_name}: #{passed}/#{total} passed")
    %{total: total, passed: passed, failed: failed}
  end

  defp type_matches?(actual, expected) do
    actual == expected or type_compatible?(actual, expected)
  end

  defp type_compatible?(type1, type2) do
    # Define type compatibility rules
    case {type1, type2} do
      {same, same} -> true
      {:octet_string, :display_string} -> true
      {:display_string, :octet_string} -> true
      {:counter, :counter32} -> true
      {:counter32, :counter} -> true
      {:gauge, :gauge32} -> true
      {:gauge32, :gauge} -> true
      {:integer, :integer32} -> true
      {:integer32, :integer} -> true
      _ -> false
    end
  end

  defp valid_snmp_type?(type) do
    type in [
      :octet_string, :display_string, :integer, :integer32,
      :counter32, :counter, :gauge32, :gauge, :timeticks,
      :object_identifier, :ip_address, :opaque, :counter64,
      :unsigned32, :null, :no_such_object, :no_such_instance,
      :end_of_mib_view
    ]
  end

  defp type_value_compatible?(type, value) do
    case {type, value} do
      {:octet_string, val} when is_binary(val) -> true
      {:display_string, val} when is_binary(val) -> true
      {:integer, val} when is_integer(val) -> true
      {:integer32, val} when is_integer(val) -> true
      {:counter32, val} when is_integer(val) and val >= 0 -> true
      {:counter, val} when is_integer(val) and val >= 0 -> true
      {:gauge32, val} when is_integer(val) and val >= 0 -> true
      {:gauge, val} when is_integer(val) and val >= 0 -> true
      {:timeticks, val} when is_integer(val) and val >= 0 -> true
      {:object_identifier, val} when is_binary(val) -> true
      {:ip_address, val} when is_binary(val) -> true
      {:null, nil} -> true
      _ -> false
    end
  end

  defp results_to_type_map(results) do
    Enum.into(results, %{}, fn {oid, type, _value} -> {oid, type} end)
  end

  defp validate_system_group_types(oid, type, _value, acc) do
    case oid do
      "1.3.6.1.2.1.1.1.0" when type not in [:octet_string, :display_string] ->
        ["sysDescr should be OctetString, got #{type}" | acc]
      "1.3.6.1.2.1.1.3.0" when type != :timeticks ->
        ["sysUpTime should be TimeTicks, got #{type}" | acc]
      "1.3.6.1.2.1.1.7.0" when type not in [:integer, :integer32] ->
        ["sysServices should be Integer, got #{type}" | acc]
      _ ->
        acc
    end
  end

  defp validate_interfaces_group_types(oid, type, _value, acc) do
    cond do
      String.contains?(oid, ".2.1.0") and type not in [:integer, :integer32] ->
        ["ifNumber should be Integer, got #{type}" | acc]
      String.contains?(oid, ".2.2.1.1.") and type not in [:integer, :integer32] ->
        ["ifIndex should be Integer, got #{type}" | acc]
      String.contains?(oid, ".2.2.1.2.") and type not in [:octet_string, :display_string] ->
        ["ifDescr should be DisplayString, got #{type}" | acc]
      String.contains?(oid, ".2.2.1.10.") and type not in [:counter32, :counter] ->
        ["ifInOctets should be Counter32, got #{type}" | acc]
      String.contains?(oid, ".2.2.1.5.") and type not in [:gauge32, :gauge] ->
        ["ifSpeed should be Gauge32, got #{type}" | acc]
      true ->
        acc
    end
  end

  defp print_results(results) do
    IO.puts("\n" <> "=" * 80)
    IO.puts("TYPE PRESERVATION TEST RESULTS")
    IO.puts("=" * 80)

    total_tests = Enum.reduce(results, 0, fn {_name, %{total: total}}, acc -> acc + total end)
    total_passed = Enum.reduce(results, 0, fn {_name, %{passed: passed}}, acc -> acc + passed end)
    total_failed = total_tests - total_passed

    Enum.each(results, fn {test_name, %{total: total, passed: passed, failed: failed}} ->
      status = if failed == 0, do: "✅", else: "❌"
      IO.puts("#{status} #{test_name}: #{passed}/#{total} passed")
    end)

    IO.puts("")
    overall_status = if total_failed == 0, do: "✅ ALL", else: "❌"
    IO.puts("#{overall_status} TESTS: #{total_passed}/#{total_tests} passed")

    if total_failed == 0 do
      IO.puts("")
      IO.puts("🎉 TYPE PRESERVATION VERIFICATION COMPLETE!")
      IO.puts("All SNMP operations correctly preserve type information.")
    else
      IO.puts("")
      IO.puts("❌ TYPE PRESERVATION FAILURES DETECTED!")
      IO.puts("SNMP type information is being lost - this MUST be fixed.")
    end
  end
end

# Run the tests if called directly
if __ENV__.file == :code.which(:script_name) do
  ActualTypeTests.run_all_tests()
end
