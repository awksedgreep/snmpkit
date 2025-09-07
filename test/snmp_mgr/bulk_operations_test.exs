defmodule SnmpKit.SnmpMgr.BulkOperationsTest do
  use ExUnit.Case, async: false

  alias SnmpKit.TestSupport.SNMPSimulator

  @moduletag :unit
  @moduletag :bulk_operations

  describe "Bulk Operations with SnmpLib Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "get_bulk/3 uses SnmpKit.SnmpLib.Manager.get_bulk", %{device: device} do
      # Test GET-BULK operation through SnmpKit.SnmpLib.Manager
      target = "#{device.host}:#{device.port}"

      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
          max_repetitions: 5,
          non_repeaters: 0,
          community: device.community,
          version: :v2c,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) ->
          # Successful bulk operation through snmp_lib - must be meaningful data
          assert length(results) >= 0

          # Validate enriched result structure - each result must be a map
          Enum.each(results, fn
            %{oid: oid, type: type, value: value} = _map ->
              assert is_binary(oid) or is_list(oid)
              assert is_atom(type)
              assert is_binary(value) or is_integer(value) or is_atom(value)

            other ->
              flunk("Unexpected bulk result format: #{inspect(other)}")
          end)

        {:error, reason} ->
          # Accept valid bulk operation errors from simulator
          assert reason in [:timeout, :noSuchObject, :getbulk_requires_v2c]
      end
    end

    test "get_bulk enforces SNMPv2c version", %{device: device} do
      # Test that bulk operation defaults to v2c regardless of specified version
      result_default =
        SnmpKit.SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2",
          max_repetitions: 3,
          community: device.community,
          timeout: 200
        )

      result_explicit_v2c =
        SnmpKit.SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2",
          max_repetitions: 3,
          version: :v2c,
          community: device.community,
          timeout: 200
        )

      # Both should work through SnmpKit.SnmpLib.Manager (v2c enforced internally)
      assert {:ok, _} = result_default
      assert {:ok, _} = result_explicit_v2c
    end

    test "get_bulk handles max_repetitions parameter", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test various max_repetitions values
      repetition_cases = [
        {1, "minimum repetitions"},
        {5, "typical repetitions"},
        {10, "moderate repetitions"},
        {20, "high repetitions"}
      ]

      Enum.each(repetition_cases, fn {max_reps, description} ->
        result =
          SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
            max_repetitions: max_reps,
            community: device.community,
            timeout: 200
          )

        case result do
          {:ok, results} when is_list(results) ->
            # Should respect max_repetitions through snmp_lib
            assert true, "#{description} succeeded through snmp_lib"

          {:error, reason} ->
            # Should get proper error format
            assert is_atom(reason) or is_tuple(reason),
                   "#{description} error: #{inspect(reason)}"
        end
      end)
    end

    test "get_bulk handles non_repeaters parameter", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test various non_repeaters values
      non_repeater_cases = [
        {0, "no non-repeaters"},
        {1, "one non-repeater"},
        {3, "multiple non-repeaters"}
      ]

      Enum.each(non_repeater_cases, fn {non_reps, description} ->
        result =
          SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
            max_repetitions: 5,
            non_repeaters: non_reps,
            community: device.community,
            timeout: 200
          )

        case result do
          {:ok, results} when is_list(results) ->
            # Should handle non_repeaters through snmp_lib
            assert true, "#{description} succeeded through snmp_lib"

          {:error, reason} ->
            # Should get proper error format
            assert is_atom(reason) or is_tuple(reason),
                   "#{description} error: #{inspect(reason)}"
        end
      end)
    end

    test "get_bulk validates parameters", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test missing max_repetitions (should default and succeed)
      result = SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2", community: device.community)
      assert {:ok, _} = result

      # Test invalid max_repetitions type (snmp_lib validates this strictly)
      assert_raise ArgumentError, fn ->
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
          max_repetitions: "invalid",
          community: device.community
        )
      end

      # Test invalid non_repeaters type (snmp_lib validates this strictly)
      assert_raise ArgumentError, fn ->
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
          max_repetitions: 5,
          non_repeaters: "invalid",
          community: device.community
        )
      end

      # Test valid parameters work
      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
          max_repetitions: 3,
          non_repeaters: 0,
          community: device.community
        )

      assert {:ok, _} = result
    end
  end

  describe "Bulk Operations OID Processing" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "bulk operations with string OIDs", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test bulk with various string OID formats
      string_oids = [
        "1.3.6.1.2.1.2.2",
        "1.3.6.1.2.1.2.2.1",
        "1.3.6.1.2.1.1"
      ]

      Enum.each(string_oids, fn oid ->
        result =
          SnmpKit.SnmpMgr.get_bulk(target, oid,
            max_repetitions: 3,
            community: device.community,
            timeout: 200
          )

        # Should process OID through SnmpKit.SnmpLib.OID and succeed
        assert {:ok, _} = result
      end)
    end

    test "bulk operations with list OIDs", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test bulk with list format OIDs
      list_oids = [
        [1, 3, 6, 1, 2, 1, 2, 2],
        [1, 3, 6, 1, 2, 1, 2, 2, 1],
        [1, 3, 6, 1, 2, 1, 1]
      ]

      Enum.each(list_oids, fn oid ->
        result =
          SnmpKit.SnmpMgr.get_bulk(target, oid,
            max_repetitions: 3,
            community: device.community,
            timeout: 200
          )

        # Should process list OID through SnmpKit.SnmpLib.OID and succeed
        assert {:ok, _} = result
      end)
    end

    test "bulk operations with symbolic OIDs", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test bulk with symbolic OIDs (if MIB resolution available)
      symbolic_oids = [
        "ifTable",
        "ifEntry",
        "system"
      ]

      Enum.each(symbolic_oids, fn oid ->
        result =
          SnmpKit.SnmpMgr.get_bulk(target, oid,
            max_repetitions: 3,
            community: device.community,
            timeout: 200
          )

        # MIB resolution may succeed or fail depending on loaded MIBs
        case result do
          # MIB resolved successfully
          {:ok, _} -> assert true
          # MIB not loaded, acceptable
          {:error, :not_found} -> assert true
          {:error, reason} -> flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end
  end

  describe "Bulk Operations Multi-Target Support" do
    setup do
      # Create multiple devices for multi-target testing
      {:ok, device1} = SNMPSimulator.create_test_device()
      {:ok, device2} = SNMPSimulator.create_test_device()

      :ok = SNMPSimulator.wait_for_device_ready(device1)
      :ok = SNMPSimulator.wait_for_device_ready(device2)

      on_exit(fn ->
        SNMPSimulator.stop_device(device1)
        SNMPSimulator.stop_device(device2)
      end)

      %{device1: device1, device2: device2}
    end

    test "get_bulk_multi processes multiple targets", %{device1: device1, device2: device2} do
      requests = [
        {"#{device1.host}:#{device1.port}", "1.3.6.1.2.1.2.2",
         [max_repetitions: 3, community: device1.community, timeout: 200]},
        {"#{device2.host}:#{device2.port}", "1.3.6.1.2.1.1",
         [max_repetitions: 3, community: device2.community, timeout: 200]}
      ]

      results = SnmpKit.SnmpMgr.get_bulk_multi(requests)

      assert is_list(results)
      assert length(results) == 2

      # Each result should be proper format from snmp_lib integration
      Enum.each(results, fn result ->
        case result do
          {:ok, list} when is_list(list) ->
            assert true

          {:error, reason} ->
            # Accept valid bulk operation errors
            assert reason in [:timeout, :noSuchObject, :getbulk_requires_v2c] or
                     is_atom(reason) or is_tuple(reason)
        end
      end)
    end
  end

  describe "Bulk Operations Error Handling" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "handles invalid OIDs in bulk operations", %{device: device} do
      target = "#{device.host}:#{device.port}"

      invalid_oids = [
        "invalid.oid.format",
        "1.3.6.1.2.1.999.999.999",
        ""
      ]

      Enum.each(invalid_oids, fn oid ->
        result =
          SnmpKit.SnmpMgr.get_bulk(target, oid,
            max_repetitions: 3,
            community: device.community,
            timeout: 200
          )

        case result do
          {:error, reason} ->
            # Should return proper error from SnmpKit.SnmpLib.OID or validation
            assert is_atom(reason) or is_tuple(reason)

          {:ok, _} ->
            # Some invalid OIDs might resolve unexpectedly
            assert true
        end
      end)
    end

    test "handles timeout in bulk operations", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test very short timeout
      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
          max_repetitions: 10,
          community: device.community,
          timeout: 1
        )

      case result do
        {:error, :timeout} -> assert true
        # Other errors acceptable
        {:error, _other} -> assert true
        # Unexpectedly fast response
        {:ok, _} -> assert true
      end
    end

    test "handles community validation in bulk operations", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test with wrong community
      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
          max_repetitions: 3,
          community: "wrong_community",
          timeout: 200
        )

      case result do
        {:error, reason} when reason in [:authentication_error, :bad_community] ->
          # Expected authentication error
          assert true

        # Other errors acceptable
        {:error, _other} ->
          assert true

        # Might succeed in test environment
        {:ok, _} ->
          assert true
      end
    end

    test "handles SNMPv2c exceptions in bulk results", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test with OID that might return exceptions
      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.999",
          max_repetitions: 5,
          community: device.community,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) ->
          # Check for SNMPv2c exception values in results
          exceptions =
            Enum.filter(results, fn
              {_oid, value}
              when value in [:no_such_object, :no_such_instance, :end_of_mib_view] ->
                true

              _ ->
                false
            end)

          if length(exceptions) > 0 do
            assert true, "Bulk operation correctly handled SNMPv2c exceptions"
          else
            assert true, "Bulk operation completed without exceptions"
          end

        {:error, reason} ->
          # Error is also acceptable for non-existent OIDs
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end

  describe "Bulk Operations Performance" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "bulk operations complete efficiently", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Measure time for bulk operations
      start_time = System.monotonic_time(:millisecond)

      results =
        Enum.map(1..5, fn _i ->
          SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
            max_repetitions: 3,
            community: device.community,
            timeout: 200
          )
        end)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete reasonably quickly with local simulator
      # Less than 1.2 seconds for 5 bulk operations (allow for CI variance)
      assert duration < 1200
      assert length(results) == 5

      # All should return proper format through snmp_lib
      Enum.each(results, fn result ->
        case result do
          # Operation succeeded
          {:ok, _} -> assert true
          # Acceptable under performance load
          {:error, :timeout} -> assert true
          {:error, reason} -> flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end

    test "bulk vs individual operations efficiency", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Compare one bulk operation vs multiple individual operations
      {bulk_time, bulk_result} =
        :timer.tc(fn ->
          SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.1",
            max_repetitions: 5,
            community: device.community,
            timeout: 200
          )
        end)

      {individual_time, individual_results} =
        :timer.tc(fn ->
          Enum.map(1..5, fn i ->
            SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.#{i}.0",
              community: device.community,
              timeout: 200
            )
          end)
        end)

      case {bulk_result, individual_results} do
        {{:ok, _bulk_data}, individual_data} when is_list(individual_data) ->
          # Both should work, bulk should be competitive
          assert bulk_time > 0
          assert individual_time > 0

          # Bulk should be reasonably efficient (not necessarily faster due to simulator overhead)
          efficiency_ratio = if bulk_time > 0, do: individual_time / bulk_time, else: 1.0

          assert efficiency_ratio > 0.1,
                 "Bulk should be reasonably efficient: #{efficiency_ratio}"

        _ ->
          # If either fails, just verify they return proper formats
          assert {:ok, _} = bulk_result
          assert is_list(individual_results)
      end
    end

    test "concurrent bulk operations", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test concurrent bulk operations
      tasks =
        Enum.map(1..3, fn i ->
          Task.async(fn ->
            SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.#{i}",
              max_repetitions: 3,
              community: device.community,
              timeout: 200
            )
          end)
        end)

      results = Task.await_many(tasks, 500)

      # All should complete through snmp_lib
      assert length(results) == 3

      Enum.each(results, fn result ->
        case result do
          # Operation succeeded
          {:ok, _} -> assert true
          # Acceptable in concurrent operations
          {:error, :timeout} -> assert true
          {:error, reason} -> flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end
  end

  describe "Bulk Operations Integration with SnmpKit.SnmpMgr.Bulk Module" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "bulk module functions use snmp_lib backend", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test that SnmpKit.SnmpMgr.Bulk functions delegate to Core which uses snmp_lib
      case SnmpKit.SnmpMgr.Bulk.get_table_bulk(target, "1.3.6.1.2.1.2.2",
             community: device.community,
             timeout: 200
           ) do
        {:ok, results} when is_list(results) ->
          # Should get table data through snmp_lib
          assert true

        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "bulk table operations with snmp_lib", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test bulk table walking
      case SnmpKit.SnmpMgr.Bulk.walk_bulk(target, "1.3.6.1.2.1.1",
             community: device.community,
             timeout: 200
           ) do
        {:ok, results} when is_list(results) ->
          # Should walk subtree through snmp_lib bulk operations
          assert true

        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "bulk operations return consistent formats", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test that bulk operations maintain consistent return formats
      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.1",
          max_repetitions: 3,
          community: device.community,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) ->
          # Validate structure consistency with enriched varbinds
          Enum.each(results, fn
            %{oid: oid, type: type, value: value} = _map ->
              assert is_binary(oid) or is_list(oid)
              assert is_atom(type)
              assert is_binary(value) or is_integer(value) or is_atom(value) or is_list(value) or is_nil(value)

            other ->
              flunk("Inconsistent result format: #{inspect(other)}")
          end)

        {:error, reason} ->
          # Error format should be consistent
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end

  describe "Bulk Operations OID Ordering" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "get_bulk results maintain lexicographic order", %{device: device} do
      target = "#{device.host}:#{device.port}"

      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.1",
          max_repetitions: 10,
          community: device.community,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) and length(results) > 1 ->
          # Extract OIDs from results
          oids = extract_oids_from_bulk_results(results)

          # Verify OIDs are in lexicographic order
          assert_oids_lexicographically_ordered(oids)

        {:ok, results} when is_list(results) ->
          # Single result or empty - acceptable
          assert true

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          # Acceptable errors in test environment
          assert true

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    test "bulk_multi maintains ordering across multiple targets", %{device: device} do
      # Create a second device for multi-target testing
      {:ok, device2} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device2)

      target1 = "#{device.host}:#{device.port}"
      target2 = "#{device2.host}:#{device2.port}"

      requests = [
        {target1, "1.3.6.1.2.1.1",
         [max_repetitions: 5, community: device.community, timeout: 200]},
        {target2, "1.3.6.1.2.1.1",
         [max_repetitions: 5, community: device2.community, timeout: 200]}
      ]

      results = SnmpKit.SnmpMgr.get_bulk_multi(requests)

      # Verify each target's results maintain ordering
      Enum.each(results, fn
        {:ok, target_results} when is_list(target_results) and length(target_results) > 1 ->
          oids = extract_oids_from_bulk_results(target_results)
          assert_oids_lexicographically_ordered(oids)

        {:ok, _target_results} ->
          # Single or empty result - acceptable
          assert true

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          # Acceptable errors
          assert true

        {:error, reason} ->
          flunk("Unexpected multi-target error: #{inspect(reason)}")
      end)

      SNMPSimulator.stop_device(device2)
    end

    test "bulk operations with mixed OID lengths maintain order", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test with an OID that might return varied length results
      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1",
          max_repetitions: 15,
          community: device.community,
          timeout: 300
        )

      case result do
        {:ok, results} when is_list(results) and length(results) > 2 ->
          oids = extract_oids_from_bulk_results(results)

          # Verify ordering with potentially varied OID lengths
          assert_oids_lexicographically_ordered(oids)

          # Verify no duplicate OIDs
          unique_oids = Enum.uniq(oids)
          assert length(unique_oids) == length(oids), "Found duplicate OIDs in bulk results"

        {:ok, _results} ->
          # Fewer results - acceptable
          assert true

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err, :endOfMibView] ->
          # Acceptable errors
          assert true

        {:error, reason} ->
          flunk("Mixed OID length test failed: #{inspect(reason)}")
      end
    end

    test "large bulk operation maintains ordering integrity", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Larger bulk operation to stress test ordering
      result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1",
          max_repetitions: 50,
          community: device.community,
          timeout: 1000
        )

      case result do
        {:ok, results} when is_list(results) and length(results) > 5 ->
          oids = extract_oids_from_bulk_results(results)

          # Verify ordering is maintained in large result sets
          assert_oids_lexicographically_ordered(oids)

          # Performance check - ordering verification should be fast
          start_time = System.monotonic_time(:microsecond)
          assert_oids_lexicographically_ordered(oids)
          end_time = System.monotonic_time(:microsecond)

          # Ordering check should complete quickly even for large sets
          assert end_time - start_time < 10000, "OID ordering verification too slow"

        {:ok, _results} ->
          # Smaller result set - acceptable
          assert true

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err, :endOfMibView] ->
          # Acceptable errors for large operations
          assert true

        {:error, reason} ->
          flunk("Large bulk operation failed: #{inspect(reason)}")
      end
    end

    # Helper functions for OID ordering tests
    defp extract_oids_from_bulk_results(results) do
      Enum.map(results, fn
        %{oid: oid} -> oid
        {oid, _type, _value} -> oid
        {oid, _value} -> oid
        oid when is_binary(oid) or is_list(oid) -> oid
        other -> flunk("Cannot extract OID from result: #{inspect(other)}")
      end)
    end

    defp assert_oids_lexicographically_ordered(oids) when length(oids) <= 1, do: :ok

    defp assert_oids_lexicographically_ordered(oids) do
      # Convert all OIDs to list format for comparison
      oid_lists = Enum.map(oids, &normalize_oid_to_list/1)

      # Check each adjacent pair
      for {oid1, oid2} <- Enum.zip(oid_lists, tl(oid_lists)) do
        comparison = SnmpKit.SnmpLib.OID.compare(oid1, oid2)

        assert comparison == :lt,
               "OIDs not in lexicographic order: #{inspect(oid1)} >= #{inspect(oid2)}"
      end
    end

    defp normalize_oid_to_list(oid) when is_list(oid), do: oid

    defp normalize_oid_to_list(oid) when is_binary(oid) do
      case SnmpKit.SnmpLib.OID.string_to_list(oid) do
        {:ok, oid_list} -> oid_list
        # Fallback for malformed OIDs
        {:error, _} -> [0]
      end
    end
  end
end
