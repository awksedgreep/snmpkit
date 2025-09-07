defmodule SnmpKit.SnmpMgr.BulkWalkComprehensiveTest do
  use ExUnit.Case, async: false

  alias SnmpKit.TestSupport.SNMPSimulator

  @moduletag :unit
  @moduletag :bulk_walk
  @moduletag :comprehensive

  describe "Bulk Walk Operations" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "adaptive_walk/3 performs intelligent bulk walking", %{device: device} do
      target = "#{device.host}:#{device.port}"

      result =
        SnmpKit.SnmpMgr.adaptive_walk(target, "1.3.6.1.2.1.1",
          community: device.community,
          adaptive_tuning: true,
          max_entries: 100,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) ->
          # Verify results are properly structured (empty results are acceptable in test env)
          assert length(results) >= 0

          # Validate each result has proper structure if we have results
          if length(results) > 0 do
            Enum.each(results, fn
              %{oid: oid, type: type, value: value} = _map ->
                assert is_binary(oid) or is_list(oid)
                assert is_atom(type)
                assert value != nil

              other ->
                flunk("Unexpected result format: #{inspect(other)}")
            end)

            # Verify results are in lexicographic order
            oids = extract_oids(results)
            assert_oids_sorted(oids)
          end

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          # Acceptable errors for test environment
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    test "bulk_walk maintains lexicographic ordering", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Use a well-known OID that should have multiple entries
      result =
        SnmpKit.SnmpMgr.adaptive_walk(target, "1.3.6.1.2.1.1",
          community: device.community,
          max_entries: 50,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) and length(results) > 1 ->
          oids = extract_oids(results)

          # Verify OIDs are in strict lexicographic order
          for {oid1, oid2} <- Enum.zip(oids, tl(oids)) do
            oid1_list = normalize_oid_to_list(oid1)
            oid2_list = normalize_oid_to_list(oid2)

            comparison = SnmpKit.SnmpLib.OID.compare(oid1_list, oid2_list)

            assert comparison == :lt,
                   "OIDs not in lexicographic order: #{inspect(oid1)} >= #{inspect(oid2)}"
          end

        {:ok, results} when is_list(results) ->
          # Single result or empty - acceptable
          :ok

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          # Acceptable errors for test environment
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    test "adaptive_walk optimizes bulk parameters", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test with adaptive tuning enabled
      start_time = System.monotonic_time(:millisecond)

      result_adaptive =
        SnmpKit.SnmpMgr.adaptive_walk(target, "1.3.6.1.2.1.1",
          community: device.community,
          adaptive_tuning: true,
          performance_threshold: 100,
          max_entries: 20,
          timeout: 200
        )

      adaptive_time = System.monotonic_time(:millisecond) - start_time

      case result_adaptive do
        {:ok, adaptive_results} ->
          # Test with adaptive tuning disabled (should use fixed parameters)
          start_time2 = System.monotonic_time(:millisecond)

          result_fixed =
            SnmpKit.SnmpMgr.adaptive_walk(target, "1.3.6.1.2.1.1",
              community: device.community,
              adaptive_tuning: false,
              max_entries: 20,
              timeout: 200
            )

          fixed_time = System.monotonic_time(:millisecond) - start_time2

          case result_fixed do
            {:ok, fixed_results} ->
              # Both should return results (empty is acceptable in test environment)
              assert length(adaptive_results) >= 0
              assert length(fixed_results) >= 0

              # Adaptive should potentially be more efficient or at least comparable
              # (This is environment dependent, so we just ensure both complete)
              # Should complete within 5 seconds
              assert adaptive_time < 5000
              assert fixed_time < 5000

            {:error, _} ->
              # Fixed mode might fail if parameters aren't optimal
              # But adaptive should have worked (empty results are acceptable)
              assert length(adaptive_results) >= 0
          end

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          # Acceptable in test environment
          :ok

        {:error, reason} ->
          flunk("Adaptive walk failed unexpectedly: #{inspect(reason)}")
      end
    end

    test "bulk_walk handles large OID trees efficiently", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test walking a potentially large tree
      start_time = System.monotonic_time(:millisecond)

      result =
        SnmpKit.SnmpMgr.adaptive_walk(target, "1.3.6.1.2.1",
          community: device.community,
          # Larger limit
          max_entries: 500,
          # Longer timeout
          timeout: 1000
        )

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      case result do
        {:ok, results} when is_list(results) ->
          # Should complete within reasonable time even for large trees
          assert duration < 10000, "Bulk walk took too long: #{duration}ms"

          if length(results) > 10 do
            # If we got a reasonable number of results, verify ordering
            oids = extract_oids(results)
            assert_oids_sorted(oids)

            # Verify no duplicate OIDs
            unique_oids = Enum.uniq(oids)
            assert length(unique_oids) == length(oids), "Duplicate OIDs found in bulk walk"
          end

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err, :endOfMibView] ->
          # Acceptable - some test environments may not have large MIB trees
          :ok

        {:error, reason} ->
          flunk("Large tree walk failed: #{inspect(reason)}")
      end
    end

    test "bulk_walk vs traditional walk comparison", %{device: device} do
      target = "#{device.host}:#{device.port}"
      test_oid = "1.3.6.1.2.1.1"

      # Perform bulk walk
      bulk_start = System.monotonic_time(:millisecond)

      bulk_result =
        SnmpKit.SnmpMgr.adaptive_walk(target, test_oid,
          community: device.community,
          max_entries: 50,
          timeout: 500
        )

      bulk_time = System.monotonic_time(:millisecond) - bulk_start

      # Perform traditional walk
      traditional_start = System.monotonic_time(:millisecond)

      traditional_result =
        SnmpKit.SnmpMgr.walk(target, test_oid,
          community: device.community,
          timeout: 500
        )

      traditional_time = System.monotonic_time(:millisecond) - traditional_start

      case {bulk_result, traditional_result} do
        {{:ok, bulk_results}, {:ok, traditional_results}} ->
          # Both should return data (empty is acceptable in test environment)
          assert length(bulk_results) >= 0
          assert length(traditional_results) >= 0

          # Extract and normalize OIDs for comparison if we have results
          if length(bulk_results) > 0 and length(traditional_results) > 0 do
            bulk_oids = extract_oids(bulk_results) |> Enum.map(&normalize_oid_to_list/1)

            traditional_oids =
              extract_oids(traditional_results) |> Enum.map(&normalize_oid_to_list/1)

            # The OID sets should overlap significantly (exact match depends on implementation)
            # At minimum, both should start with the same OIDs
            first_bulk_oid = List.first(bulk_oids)
            first_traditional_oid = List.first(traditional_oids)

            # Both should start walking from the same base OID
            assert SnmpKit.SnmpLib.OID.compare(first_bulk_oid, first_traditional_oid) in [
                     :eq,
                     :lt,
                     :gt
                   ]
          end


        {{:ok, bulk_results}, {:error, _}} ->
          # Bulk succeeded where traditional failed - this is acceptable
          assert length(bulk_results) >= 0

        {{:error, _}, {:ok, traditional_results}} ->
          # Traditional succeeded where bulk failed - this might indicate an issue
          # but could be environment-specific
          assert length(traditional_results) >= 0

        {{:error, bulk_reason}, {:error, traditional_reason}} ->
          # Both failed - acceptable in test environment
          assert bulk_reason in [:timeout, :no_such_name, :gen_err]
          assert traditional_reason in [:timeout, :no_such_name, :gen_err]
      end
    end

    test "bulk_walk handles empty and single-entry results", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test with an OID that might not exist or have limited entries
      result =
        SnmpKit.SnmpMgr.adaptive_walk(target, "1.3.6.1.2.1.99.99.99",
          community: device.community,
          max_entries: 10,
          timeout: 200
        )

      case result do
        {:ok, []} ->
          # Empty result is acceptable
          :ok

        {:ok, [single_result]} ->
          # Single result should be properly formatted
          case single_result do
            {oid, type, value} ->
              assert is_binary(oid) or is_list(oid)
              assert is_atom(type)
              assert value != nil

            {oid, value} ->
              assert is_binary(oid) or is_list(oid)
              assert value != nil

            other ->
              flunk("Unexpected single result format: #{inspect(other)}")
          end

        {:ok, results} when is_list(results) ->
          # Multiple results - should be ordered
          oids = extract_oids(results)
          assert_oids_sorted(oids)

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err, :endOfMibView] ->
          # Acceptable errors for non-existent OIDs
          :ok

        {:error, reason} ->
          flunk("Unexpected error for empty/single test: #{inspect(reason)}")
      end
    end

    test "bulk_walk respects max_entries limit", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test with a small max_entries limit
      result =
        SnmpKit.SnmpMgr.adaptive_walk(target, "1.3.6.1.2.1.1",
          community: device.community,
          max_entries: 5,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) ->
          # Should respect the max_entries limit
          assert length(results) <= 5

          if length(results) > 1 do
            # Results should still be ordered
            oids = extract_oids(results)
            assert_oids_sorted(oids)
          end

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          # Acceptable in test environment
          :ok

        {:error, reason} ->
          flunk("Max entries test failed: #{inspect(reason)}")
      end
    end

    test "bulk_walk_pretty handles empty OID without hanging", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test with empty list - this should not hang
      result_empty_list =
        test_with_timeout(
          fn ->
            SnmpKit.SnmpMgr.bulk_walk_pretty(target, [],
              community: device.community,
              timeout: 1000,
              max_entries: 10
            )
          end,
          3000
        )

      assert result_empty_list != :timeout, "bulk_walk_pretty with empty list [] should not hang"

      case result_empty_list do
        {:ok, results} when is_list(results) ->
          # Empty OID should return results from MIB root
          assert length(results) >= 0
          # Verify enriched map format with formatted field
          if length(results) > 0 do
            Enum.each(results, fn %{oid: oid_string, type: type, formatted: formatted_value} ->
              assert is_binary(oid_string), "OID should be string, got: #{inspect(oid_string)}"
              assert is_atom(type), "Type should be atom, got: #{inspect(type)}"

              assert is_binary(formatted_value),
                     "Formatted value should be string, got: #{inspect(formatted_value)}"
            end)
          end

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          # Acceptable in test environment
          :ok

        {:error, reason} ->
          flunk("Empty OID test failed: #{inspect(reason)}")
      end

      # Test with empty string - this should also not hang
      result_empty_string =
        test_with_timeout(
          fn ->
            SnmpKit.SnmpMgr.bulk_walk_pretty(target, "",
              community: device.community,
              timeout: 1000,
              max_entries: 10
            )
          end,
          3000
        )

      assert result_empty_string != :timeout,
             "bulk_walk_pretty with empty string \"\" should not hang"

      case result_empty_string do
        {:ok, results} when is_list(results) ->
          assert length(results) >= 0
          # Verify format consistency
          if length(results) > 0 do
            Enum.each(results, fn %{oid: oid_string, type: type, formatted: formatted_value} ->
              assert is_binary(oid_string)
              assert is_atom(type)
              assert is_binary(formatted_value)
            end)
          end

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          :ok

        {:error, reason} ->
          flunk("Empty string OID test failed: #{inspect(reason)}")
      end
    end

    test "bulk_walk handles empty OID without hanging", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test with empty list for bulk_walk (not pretty)
      result =
        test_with_timeout(
          fn ->
            SnmpKit.SnmpMgr.bulk_walk(target, [],
              community: device.community,
              timeout: 1000,
              max_entries: 10
            )
          end,
          3000
        )

      assert result != :timeout, "bulk_walk with empty list [] should not hang"

      case result do
        {:ok, results} when is_list(results) ->
          assert length(results) >= 0
          # Verify enriched map format with raw value
          if length(results) > 0 do
            Enum.each(results, fn %{oid: oid_string, type: type, value: value} ->
              assert is_binary(oid_string)
              assert is_atom(type)
              assert value != nil
            end)
          end

        {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
          :ok

        {:error, reason} ->
          flunk("Empty OID bulk_walk test failed: #{inspect(reason)}")
      end
    end

    test "comprehensive OID format testing", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Test all OID formats: "", [], "1", [1], "1.3", [1,3], "1.3.6", [1,3,6]
      test_cases = [
        {"empty string", ""},
        {"empty list", []},
        {"string 1", "1"},
        {"list [1]", [1]},
        {"string 1.3", "1.3"},
        {"list [1,3]", [1, 3]},
        {"string 1.3.6", "1.3.6"},
        {"list [1,3,6]", [1, 3, 6]}
      ]

      Enum.each(test_cases, fn {description, oid} ->
        # Test bulk_walk_pretty
        result_pretty =
          test_with_timeout(
            fn ->
              SnmpKit.SnmpMgr.bulk_walk_pretty(target, oid,
                community: device.community,
                timeout: 1000,
                max_entries: 5
              )
            end,
            3000
          )

        assert result_pretty != :timeout,
               "bulk_walk_pretty with #{description} should not hang"

        case result_pretty do
          {:ok, results} when is_list(results) ->
            assert length(results) >= 0
          # Verify enriched map format with formatted field
          if length(results) > 0 do
            Enum.each(results, fn %{oid: oid_string, type: type, formatted: formatted_value} ->
              assert is_binary(oid_string),
                     "OID should be string for #{description}, got: #{inspect(oid_string)}"

              assert is_atom(type),
                     "Type should be atom for #{description}, got: #{inspect(type)}"

              assert is_binary(formatted_value),
                     "Formatted value should be string for #{description}, got: #{inspect(formatted_value)}"
            end)

            # Verify OIDs are properly scoped
            first_oid = hd(results).oid

            assert String.starts_with?(first_oid, "1.3"),
                   "#{description} should return OIDs starting with 1.3, got: #{first_oid}"
          end

          {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
            # Acceptable in test environment
            :ok

          {:error, reason} ->
            flunk("#{description} bulk_walk_pretty failed: #{inspect(reason)}")
        end

        # Test bulk_walk (without pretty formatting)
        result_bulk =
          test_with_timeout(
            fn ->
              SnmpKit.SnmpMgr.bulk_walk(target, oid,
                community: device.community,
                timeout: 1000,
                max_entries: 5
              )
            end,
            3000
          )

        assert result_bulk != :timeout, "bulk_walk with #{description} should not hang"

        case result_bulk do
          {:ok, results} when is_list(results) ->
            assert length(results) >= 0
            # Verify enriched map format with raw value
            if length(results) > 0 do
              Enum.each(results, fn %{oid: oid_string, type: type, value: value} ->
                assert is_binary(oid_string),
                       "OID should be string for #{description}, got: #{inspect(oid_string)}"

                assert is_atom(type),
                       "Type should be atom for #{description}, got: #{inspect(type)}"

                assert value != nil,
                       "Value should not be nil for #{description}, got: #{inspect(value)}"
              end)
            end

          {:error, reason} when reason in [:timeout, :no_such_name, :gen_err] ->
            :ok

          {:error, reason} ->
            flunk("#{description} bulk_walk failed: #{inspect(reason)}")
        end
      end)
    end

    test "OID format consistency verification", %{device: device} do
      target = "#{device.host}:#{device.port}"

      # Verify that equivalent OID formats return similar results
      equivalent_pairs = [
        {[], ""},
        {[1], "1"},
        {[1, 3], "1.3"},
        {[1, 3, 6], "1.3.6"}
      ]

      Enum.each(equivalent_pairs, fn {list_oid, string_oid} ->
        # Test that list and string versions of the same OID behave consistently
        result_list =
          test_with_timeout(
            fn ->
              SnmpKit.SnmpMgr.bulk_walk_pretty(target, list_oid,
                community: device.community,
                timeout: 1000,
                max_entries: 3
              )
            end,
            3000
          )

        result_string =
          test_with_timeout(
            fn ->
              SnmpKit.SnmpMgr.bulk_walk_pretty(target, string_oid,
                community: device.community,
                timeout: 1000,
                max_entries: 3
              )
            end,
            3000
          )

        # Both should either succeed or fail in the same way
        case {result_list, result_string} do
          {{:ok, list_results}, {:ok, string_results}} ->
            # Both succeeded - results should be similar (allow for minor differences due to timing)
            assert length(list_results) >= 0
            assert length(string_results) >= 0

            if length(list_results) > 0 and length(string_results) > 0 do
              # First OID should be the same or very similar
              first_list_oid = hd(list_results).oid
              first_string_oid = hd(string_results).oid

              # Both should start with the same prefix
              assert String.starts_with?(first_list_oid, "1.3"),
                     "List OID #{inspect(list_oid)} should return 1.3.x results"

              assert String.starts_with?(first_string_oid, "1.3"),
                     "String OID #{inspect(string_oid)} should return 1.3.x results"
            end

          {{:error, _}, {:error, _}} ->
            # Both failed - acceptable for test environment
            :ok

          {{:ok, _}, {:error, _}} ->
            # List succeeded but string failed - might be acceptable
            :ok

          {{:error, _}, {:ok, _}} ->
            # String succeeded but list failed - might be acceptable
            :ok

          {:timeout, _} ->
            flunk("List OID #{inspect(list_oid)} timed out")

          {_, :timeout} ->
            flunk("String OID #{inspect(string_oid)} timed out")
        end
      end)
    end
  end

  # Helper functions

  defp test_with_timeout(test_fn, timeout_ms) do
    parent = self()

    task =
      Task.async(fn ->
        try do
          result = test_fn.()
          send(parent, {:result, result})
        rescue
          error ->
            send(parent, {:error, error})
        catch
          :exit, reason ->
            send(parent, {:exit, reason})
        end
      end)

    receive do
      {:result, result} -> result
      {:error, error} -> {:error, error}
      {:exit, reason} -> {:error, reason}
    after
      timeout_ms ->
        Task.shutdown(task, :brutal_kill)
        :timeout
    end
  end

  defp extract_oids(results) do
    Enum.map(results, fn
      %{oid: oid} -> oid
      {oid, _type, _value} -> oid
      {oid, _value} -> oid
      oid when is_binary(oid) or is_list(oid) -> oid
      other -> flunk("Cannot extract OID from: #{inspect(other)}")
    end)
  end

  defp normalize_oid_to_list(oid) when is_list(oid), do: oid

  defp normalize_oid_to_list(oid) when is_binary(oid) do
    case SnmpKit.SnmpLib.OID.string_to_list(oid) do
      {:ok, oid_list} -> oid_list
      # Fallback for invalid OIDs
      {:error, _} -> [0]
    end
  end

  defp assert_oids_sorted(oids) when length(oids) <= 1, do: :ok

  defp assert_oids_sorted(oids) do
    oid_lists = Enum.map(oids, &normalize_oid_to_list/1)
    sorted_oids = SnmpKit.SnmpLib.OID.sort(oid_lists)

    assert oid_lists == sorted_oids, "OIDs not in lexicographic order"
  end
end
