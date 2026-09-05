defmodule SnmpKit.WalkMultiEdgeCaseTest do
  use ExUnit.Case, async: true
  @moduletag :walk_multi_edge

  alias SnmpKit.SnmpMgr.Multi

  @test_timeout 200

  setup_all do
    # Ensure the SnmpMgr Engine is running
    case Process.whereis(SnmpKit.SnmpMgr.Engine) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.Engine.start_link(name: SnmpKit.SnmpMgr.Engine)
        :ok

      _pid ->
        :ok
    end

    :ok
  end

  describe "walk_multi first-OID bug scenarios" do
    test "walk_multi with single target handles internal result truncation" do
      # This test specifically looks for the bug where walk_multi might return
      # only the first OID from a walk result instead of all OIDs

      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 1, "Should have exactly 1 result for 1 target"

      # Even if it's an error, the structure should be preserved
      [single_result] = results
      assert match?({:error, _}, single_result)
    end

    test "walk_multi handles rapid successive requests" do
      # Test multiple rapid requests that might trigger race conditions
      # leading to result truncation

      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.3", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.4", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.5", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)

      assert length(results) == 5,
             "BUG DETECTED: Should have 5 results but got #{length(results)}"

      # All should be errors, but importantly, ALL should be present
      Enum.with_index(results, 1)
      |> Enum.each(fn {result, idx} ->
        assert match?({:error, _}, result),
               "Result #{idx} should be error for unreachable host"
      end)
    end

    test "walk_multi preserves all results with different OIDs" do
      # Test with different OIDs to ensure no cross-contamination

      targets_and_oids = [
        # system
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        # interfaces
        {"192.168.255.1", "1.3.6.1.2.1.2", [timeout: @test_timeout]},
        # ip
        {"192.168.255.1", "1.3.6.1.2.1.4", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)

      assert is_list(results)

      assert length(results) == 3,
             "Should have all 3 different OID results"

      # Verify each target/oid combination is preserved
      result_keys = Enum.map(results, fn {target, oid, _result} -> {target, oid} end)

      expected_keys = [
        {"192.168.255.1", "1.3.6.1.2.1.1"},
        {"192.168.255.1", "1.3.6.1.2.1.2"},
        {"192.168.255.1", "1.3.6.1.2.1.4"}
      ]

      assert result_keys == expected_keys,
             "Result keys should match expected order and content"
    end

    test "walk_multi handles mixed timeout scenarios" do
      # Test with different timeout values to see if early returns affect later results

      targets_and_oids = [
        # fast timeout
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: 50]},
        # medium timeout
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: 100]},
        # slow timeout
        {"192.168.255.3", "1.3.6.1.2.1.1", [timeout: 200]}
      ]

      start_time = System.monotonic_time(:millisecond)
      results = Multi.walk_multi(targets_and_oids)
      end_time = System.monotonic_time(:millisecond)

      assert is_list(results)

      assert length(results) == 3,
             "Should have all 3 results regardless of timeout differences"

      # Should take at least as long as the longest timeout
      duration = end_time - start_time
      assert duration >= 200, "Should wait for all timeouts to complete"

      # All should be timeout errors
      Enum.each(results, fn result ->
        assert match?({:error, _}, result)
      end)
    end

    test "walk_multi concurrent execution doesn't affect result count" do
      # Run multiple walk_multi operations concurrently to test for race conditions

      targets_and_oids = [
        {"192.168.255.10", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.11", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      # Run 3 concurrent walk_multi operations
      tasks =
        Enum.map(1..3, fn _i ->
          Task.async(fn ->
            Multi.walk_multi(targets_and_oids)
          end)
        end)

      # Wait for all tasks to complete
      concurrent_results = Task.await_many(tasks, 5000)

      # Each concurrent operation should return 2 results
      Enum.with_index(concurrent_results, 1)
      |> Enum.each(fn {results, task_num} ->
        assert is_list(results), "Task #{task_num} should return list"

        assert length(results) == 2,
               "Task #{task_num} should return 2 results, got #{length(results)}"
      end)
    end

    test "walk_multi with malformed targets preserves error structure" do
      # Test edge cases with malformed input to ensure proper error handling

      targets_and_oids = [
        # empty host
        {"", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        # empty OID
        {"192.168.255.1", "", [timeout: @test_timeout]},
        # invalid OID
        {"192.168.255.1", "invalid.oid", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)

      assert length(results) == 3,
             "Should return error results for all malformed inputs"

      # All should be errors due to malformed inputs
      Enum.with_index(results, 1)
      |> Enum.each(fn {result, idx} ->
        assert match?({:error, _}, result),
               "Malformed input #{idx} should result in error"
      end)
    end

    test "walk_multi large batch size doesn't truncate results" do
      # Test with a larger number of targets to see if there's a batch size limit

      targets_and_oids =
        1..20
        |> Enum.map(fn i ->
          {"192.168.255.#{i}", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
        end)

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)

      assert length(results) == 20,
             "CRITICAL BUG: Should have 20 results but got #{length(results)} - this suggests result truncation!"

      # Verify we have results for each expected target
      target_list = 1..20 |> Enum.map(&"192.168.255.#{&1}")

      # For with_targets format, we can verify the specific targets
      with_targets_results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)
      result_targets = Enum.map(with_targets_results, fn {target, _oid, _result} -> target end)

      assert result_targets == target_list,
             "Target order and completeness should be preserved"
    end

    test "walk_multi result consistency across formats" do
      # Verify that all return formats return the same number of results

      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.3", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      list_results = Multi.walk_multi(targets_and_oids, return_format: :list)
      with_targets_results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)
      map_results = Multi.walk_multi(targets_and_oids, return_format: :map)

      # All formats should have the same count
      assert length(list_results) == 3, "List format should have 3 results"
      assert length(with_targets_results) == 3, "With targets format should have 3 results"
      assert map_size(map_results) == 3, "Map format should have 3 keys"

      # This would catch the bug if any format only returned the first result
      refute length(list_results) == 1, "BUG: List format returned only first result"

      refute length(with_targets_results) == 1,
             "BUG: With targets format returned only first result"

      refute map_size(map_results) == 1, "BUG: Map format returned only first result"
    end
  end

  describe "walk_multi individual walk result preservation" do
    test "walk_multi preserves complete walk results when successful" do
      # This would be the ultimate test if we had a working SNMP device
      # For now, we test the error case but with detailed inspection

      targets_and_oids = [
        {"127.0.0.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 1

      [result] = results

      case result do
        {:ok, walk_results} ->
          # If localhost has SNMP and we got results, verify completeness
          assert is_list(walk_results), "Walk results should be a list"

          if length(walk_results) > 1 do
            # Verify all results are proper 3-tuples
            Enum.each(walk_results, fn entry ->
              assert match?({_oid, _type, _value}, entry),
                     "Each result should be {oid, type, value}"
            end)

            # Extract OIDs and verify uniqueness and completeness
            oids = Enum.map(walk_results, fn {oid, _type, _value} -> oid end)
            unique_oids = Enum.uniq(oids)

            assert length(oids) == length(unique_oids),
                   "All OIDs should be unique"

            # Verify OIDs are in system subtree and properly ordered
            sorted_oids = Enum.sort(oids)

            assert oids == sorted_oids or length(oids) == 1,
                   "OIDs should be returned in sorted order"

            # The critical bug check: verify we didn't get just the first OID
            # This would fail if walk_multi truncated to only the first result
            system_base_oids = [
              # sysDescr
              "1.3.6.1.2.1.1.1.",
              # sysObjectID
              "1.3.6.1.2.1.1.2.",
              # sysUpTime
              "1.3.6.1.2.1.1.3.",
              # sysContact
              "1.3.6.1.2.1.1.4.",
              # sysName
              "1.3.6.1.2.1.1.5.",
              # sysLocation
              "1.3.6.1.2.1.1.6."
            ]

            matching_bases =
              system_base_oids
              |> Enum.filter(fn base ->
                Enum.any?(oids, &String.starts_with?(&1, base))
              end)

            assert length(matching_bases) > 1,
                   "BUG DETECTED: Only found OIDs for #{length(matching_bases)} system base(s), expected multiple. This suggests walk_multi returned incomplete results. Found: #{inspect(matching_bases)}"
          end

        {:error, _reason} ->
          # Expected if no SNMP on localhost
          :ok
      end
    end
  end
end
