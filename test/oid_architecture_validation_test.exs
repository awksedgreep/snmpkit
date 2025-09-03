defmodule SnmpKit.OidArchitectureValidationTest do
  use ExUnit.Case
  doctest SnmpKit

  @moduledoc """
  Tests to validate that the OID handling architecture follows the established principles:

  1. All internal OID handling uses lists of integers [1,3,6,1,2,1,1,1,0]
  2. All external APIs accept both string "1.3.6.1.2.1.1.1.0" and list [1,3,6,1,2,1,1,1,0] formats
  3. Conversion happens only at API boundaries
  4. No unnecessary string/list conversions in internal operations
  """

  describe "Core API Entry Points" do
    test "parse_oid function always returns lists" do
      # Test string input
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} =
               SnmpKit.SnmpMgr.Core.parse_oid("1.3.6.1.2.1.1.1.0")

      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} =
               SnmpKit.SnmpMgr.Core.parse_oid(".1.3.6.1.2.1.1.1.0")

      # Test list input - should validate and return same list
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} =
               SnmpKit.SnmpMgr.Core.parse_oid([1, 3, 6, 1, 2, 1, 1, 1, 0])

      # Test empty cases get proper fallbacks
      assert {:ok, [1, 3]} = SnmpKit.SnmpMgr.Core.parse_oid("")
      assert {:ok, [1, 3]} = SnmpKit.SnmpMgr.Core.parse_oid([])

      # Test invalid cases
      assert {:error, :invalid_oid_input} = SnmpKit.SnmpMgr.Core.parse_oid(123)
      assert {:error, :invalid_oid_input} = SnmpKit.SnmpMgr.Core.parse_oid(nil)
    end

    test "API functions accept both string and list OID formats" do
      # These would normally make network calls, but we're testing the input validation
      # The functions should not crash on valid OID formats

      string_oid = "1.3.6.1.2.1.1.1.0"
      list_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # Test that both formats are accepted (they will fail with network errors, but not format errors)
      result1 = SnmpKit.SnmpMgr.get("invalid.host", string_oid, timeout: 100)
      result2 = SnmpKit.SnmpMgr.get("invalid.host", list_oid, timeout: 100)

      # Both should fail with network errors, not format errors
      assert match?({:error, _}, result1)
      assert match?({:error, _}, result2)

      # Neither should fail with format-specific errors
      refute match?({:error, :invalid_oid_format}, result1)
      refute match?({:error, :invalid_oid_format}, result2)
      refute match?({:error, :invalid_oid_input}, result1)
      refute match?({:error, :invalid_oid_input}, result2)
    end
  end

  describe "Internal Consistency" do
    test "OID validation uses list format internally" do
      # Test the OID validation functions work with lists
      assert :ok = SnmpKit.SnmpLib.OID.valid_oid?([1, 3, 6, 1, 2, 1, 1, 1, 0])
      assert {:error, :empty_oid} = SnmpKit.SnmpLib.OID.valid_oid?([])
      assert {:error, :invalid_component} = SnmpKit.SnmpLib.OID.valid_oid?([1, -1, 3])
      assert {:error, :invalid_input} = SnmpKit.SnmpLib.OID.valid_oid?("string")
    end

    test "OID normalization returns lists consistently" do
      # Test the normalize function in OID module
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} =
               SnmpKit.SnmpLib.OID.normalize("1.3.6.1.2.1.1.1.0")

      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} =
               SnmpKit.SnmpLib.OID.normalize([1, 3, 6, 1, 2, 1, 1, 1, 0])

      # Empty cases return error for OID module (but get fallback in parse_oid)
      assert {:error, :empty_oid} = SnmpKit.SnmpLib.OID.normalize("")
      assert {:error, :empty_oid} = SnmpKit.SnmpLib.OID.normalize([])
    end

    test "bulk operations maintain list format internally" do
      # Test that bulk resolve_oid function returns lists
      test_cases = [
        {"1.3.6.1.2.1.1.1.0", [1, 3, 6, 1, 2, 1, 1, 1, 0]},
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 1, 0]},
        {"", [1, 3]},
        {[], [1, 3]}
      ]

      Enum.each(test_cases, fn {input, expected} ->
        # Access the private resolve_oid function through a test helper pattern
        # This validates internal consistency without exposing private APIs
        case SnmpKit.SnmpMgr.Core.parse_oid(input) do
          {:ok, result} ->
            assert result == expected,
                   "resolve_oid(#{inspect(input)}) should return #{inspect(expected)}, got #{inspect(result)}"

          error ->
            flunk("resolve_oid(#{inspect(input)}) returned error: #{inspect(error)}")
        end
      end)
    end
  end

  describe "API Boundaries and Conversion" do
    test "string-to-list conversion happens at entry points" do
      # Test OID string parsing
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} =
               SnmpKit.SnmpLib.OID.string_to_list("1.3.6.1.2.1.1.1.0")

      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} =
               SnmpKit.SnmpLib.OID.string_to_list(".1.3.6.1.2.1.1.1.0")

      # Test edge cases
      assert {:error, :empty_oid} = SnmpKit.SnmpLib.OID.string_to_list("")
      assert {:error, :invalid_oid_string} = SnmpKit.SnmpLib.OID.string_to_list("1.3.6.x")
      assert {:error, :invalid_input} = SnmpKit.SnmpLib.OID.string_to_list(123)
    end

    test "list-to-string conversion for output only" do
      # Test OID list to string conversion
      assert {:ok, "1.3.6.1.2.1.1.1.0"} =
               SnmpKit.SnmpLib.OID.list_to_string([1, 3, 6, 1, 2, 1, 1, 1, 0])

      # Test edge cases
      assert {:error, :empty_oid} = SnmpKit.SnmpLib.OID.list_to_string([])
      assert {:error, :invalid_component} = SnmpKit.SnmpLib.OID.list_to_string([1, -1, 3])
      assert {:error, :invalid_input} = SnmpKit.SnmpLib.OID.list_to_string("string")
    end

    test "format functions handle mixed OID value types correctly" do
      # Test that format functions handle object_identifier values correctly
      # Note: pretty_print expects string OIDs as input (final output format)

      test_cases = [
        {{"1.3.6.1.2.1.1.1.0", :object_identifier, [1, 3, 6, 1, 4, 1, 9]}, "1.3.6.1.4.1.9"},
        {{"1.3.6.1.2.1.1.2.0", :object_identifier, "1.3.6.1.4.1.9"}, "1.3.6.1.4.1.9"},
        {{"1.3.6.1.2.1.1.3.0", :integer, 12345}, "12345"}
      ]

      Enum.each(test_cases, fn {input_tuple, expected_formatted_value} ->
        {oid_string, type, formatted_value} = SnmpKit.SnmpMgr.Format.pretty_print(input_tuple)

        # OID should be string in output
        assert is_binary(oid_string), "OID in output should be string format"

        # Type should be preserved
        {_, original_type, _} = input_tuple
        assert type == original_type, "Type should be preserved"

        # Value formatting should handle both list and string object identifiers
        if original_type == :object_identifier do
          assert formatted_value == expected_formatted_value,
                 "Object identifier should be formatted as string: #{inspect(formatted_value)}"
        end
      end)
    end
  end

  describe "Error Handling and Validation" do
    test "invalid OID inputs are properly rejected" do
      invalid_inputs = [
        "1.3.6.invalid",
        "1.3.6.-1",
        [1, 3, -1],
        [1, 3, "invalid"],
        123,
        nil,
        %{},
        {:invalid}
      ]

      Enum.each(invalid_inputs, fn invalid_input ->
        result = SnmpKit.SnmpMgr.Core.parse_oid(invalid_input)

        assert match?({:error, _}, result),
               "Invalid input #{inspect(invalid_input)} should be rejected"
      end)
    end

    test "empty OID cases have consistent fallbacks" do
      # Only test cases that actually get fallback treatment in parse_oid
      empty_cases = ["", [], "   "]

      Enum.each(empty_cases, fn empty_input ->
        case SnmpKit.SnmpMgr.Core.parse_oid(empty_input) do
          {:ok, [1, 3]} ->
            # Expected fallback
            :ok

          {:ok, other} ->
            flunk(
              "Empty input #{inspect(empty_input)} should fallback to [1, 3], got #{inspect(other)}"
            )

          {:error, reason} ->
            flunk("Empty input #{inspect(empty_input)} should not error, got #{inspect(reason)}")
        end
      end)

      # "." is treated as an invalid OID string, not empty
      assert {:error, _} = SnmpKit.SnmpMgr.Core.parse_oid(".")
    end

    test "type information is preserved throughout operations" do
      # This test validates that our architecture preserves SNMP type information
      # Note: Format functions expect string OIDs (final output format)

      mock_snmp_results = [
        {"1.3.6.1.2.1.1.1.0", :octet_string, "System Description"},
        {"1.3.6.1.2.1.1.2.0", :object_identifier, [1, 3, 6, 1, 4, 1, 9]},
        {"1.3.6.1.2.1.1.3.0", :timeticks, 123_456}
      ]

      # Test that formatting preserves type information
      formatted_results =
        Enum.map(mock_snmp_results, fn result ->
          SnmpKit.SnmpMgr.Format.pretty_print(result)
        end)

      # Every result should have 3-tuple format with preserved type
      Enum.zip(mock_snmp_results, formatted_results)
      |> Enum.each(fn {{_, original_type, _}, {_, formatted_type, _}} ->
        assert formatted_type == original_type,
               "Type information should be preserved: #{original_type} != #{formatted_type}"
      end)

      # OIDs should be converted to strings in final output
      Enum.each(formatted_results, fn {oid_string, _type, _value} ->
        assert is_binary(oid_string), "Final output OID should be string format"

        assert String.match?(oid_string, ~r/^\d+(\.\d+)*$/),
               "OID string should be valid dotted decimal format"
      end)
    end
  end

  describe "Performance and Efficiency" do
    test "no unnecessary conversions in processing chain" do
      # Test that we don't do redundant string<->list conversions
      # This is more of a design validation than a direct test

      list_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # If we start with a list, parse_oid should not do unnecessary conversions
      assert {:ok, result} = SnmpKit.SnmpMgr.Core.parse_oid(list_oid)
      assert result == list_oid, "List input should return same list without conversion"

      # The result should be the same object (no unnecessary copying)
      # Note: This is more about design efficiency than strict object identity
    end
  end

  describe "Integration Consistency" do
    test "MIB operations maintain OID list format" do
      # Test MIB reverse lookup expects lists
      test_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # This will return an error since no MIBs are loaded, but should not fail on format
      result = SnmpKit.SnmpMgr.MIB.reverse_lookup(test_oid)

      # Should not fail with format errors
      refute match?({:error, :invalid_oid_format}, result)

      # String version should convert to list internally
      string_result = SnmpKit.SnmpMgr.MIB.reverse_lookup("1.3.6.1.2.1.1.1.0")
      refute match?({:error, :invalid_oid_format}, string_result)
    end

    test "walk operations use consistent OID formats" do
      # Test that internal walk functions expect list OIDs
      # We can't test actual walks without network, but we can test OID resolution

      walk_test_cases = [
        "1.3.6.1.2.1.1",
        "system",
        [1, 3, 6, 1, 2, 1, 1],
        ""
      ]

      Enum.each(walk_test_cases, fn test_input ->
        # All these should be resolved to lists internally
        case SnmpKit.SnmpMgr.Core.parse_oid(test_input) do
          {:ok, result} ->
            assert is_list(result),
                   "Walk OID resolution should return lists: #{inspect(test_input)} -> #{inspect(result)}"

            assert Enum.all?(result, &is_integer/1),
                   "All OID components should be integers: #{inspect(result)}"

          {:error, _} ->
            # Some inputs may be invalid, that's expected
            :ok
        end
      end)
    end
  end
end
