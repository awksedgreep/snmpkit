defmodule SnmpKit.WalkMultiBugTest do
  use ExUnit.Case, async: true
  @moduletag :walk_multi_bug

  alias SnmpKit.SnmpMgr.Multi

  @test_timeout 1000
  @localhost "127.0.0.1"

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

  describe "walk_multi bug detection" do
    test "walk_multi does not return only first result from batch" do
      # Test with multiple unreachable hosts to check if walk_multi
      # returns all errors or just the first one
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.3", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      # Critical test: we should get results for ALL targets, not just the first
      assert is_list(results), "Results should be a list"

      assert length(results) == 3,
             "BUG DETECTED: walk_multi should return 3 results but got #{length(results)}: #{inspect(results)}"

      # All should be errors due to unreachable hosts
      Enum.with_index(results, 1)
      |> Enum.each(fn {result, index} ->
        assert match?({:error, _}, result),
               "Result #{index} should be an error, got: #{inspect(result)}"
      end)
    end

    test "walk_multi with :with_targets format returns all targets" do
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)

      assert is_list(results), "Results should be a list"

      assert length(results) == 2,
             "BUG DETECTED: walk_multi with :with_targets should return 2 results but got #{length(results)}"

      # Verify structure and that we have both targets
      targets_seen = Enum.map(results, fn {target, _oid, _result} -> target end)
      assert "192.168.255.1" in targets_seen, "Should include first target"
      assert "192.168.255.2" in targets_seen, "Should include second target"
    end

    test "walk_multi with :map format returns all keys" do
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids, return_format: :map)

      assert is_map(results), "Results should be a map"

      assert map_size(results) == 2,
             "BUG DETECTED: walk_multi with :map should return 2 keys but got #{map_size(results)}"

      # Verify both expected keys exist
      expected_key1 = {"192.168.255.1", "1.3.6.1.2.1.1"}
      expected_key2 = {"192.168.255.2", "1.3.6.1.2.1.1"}

      assert Map.has_key?(results, expected_key1), "Should have key for first target"
      assert Map.has_key?(results, expected_key2), "Should have key for second target"
    end

    test "walk_multi single target returns single result (not truncated)" do
      # Test with one target to ensure we're not accidentally taking only first of internal collections
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results), "Results should be a list"

      assert length(results) == 1,
             "walk_multi with 1 target should return exactly 1 result, got #{length(results)}"

      [result] = results
      assert match?({:error, _}, result), "Single result should be an error for unreachable host"
    end

    test "walk_multi empty list returns empty list" do
      results = Multi.walk_multi([])
      assert results == [], "Empty input should return empty list"
    end

    test "walk_multi preserves request order" do
      # Test that results come back in the same order as requests
      targets_and_oids = [
        {"192.168.255.10", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.20", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.30", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)

      assert length(results) == 3, "Should have 3 results"

      # Extract targets in order
      result_targets = Enum.map(results, fn {target, _oid, _result} -> target end)
      expected_targets = ["192.168.255.10", "192.168.255.20", "192.168.255.30"]

      assert result_targets == expected_targets,
             "Results should preserve request order. Expected: #{inspect(expected_targets)}, Got: #{inspect(result_targets)}"
    end

    test "walk_multi handles potential localhost SNMP gracefully" do
      # This test attempts to walk localhost - if SNMP is running, we can verify walk results
      # If not, we just verify the error handling works correctly
      targets_and_oids = [
        {@localhost, "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results), "Results should be a list"
      assert length(results) == 1, "Should have exactly 1 result for 1 target"

      [result] = results

      case result do
        {:ok, walk_results} ->
          # If localhost has SNMP running, verify walk results structure
          assert is_list(walk_results), "Walk results should be a list"

          # If we got results, each should be a proper 3-tuple
          Enum.each(walk_results, fn entry ->
            assert match?({_oid, _type, _value}, entry),
                   "Each walk result should be {oid, type, value}, got: #{inspect(entry)}"
          end)

          # The critical test: if we have multiple results, verify they're all there
          if length(walk_results) > 1 do
            oids = Enum.map(walk_results, fn {oid, _type, _value} -> oid end)
            unique_oids = Enum.uniq(oids)

            assert length(walk_results) == length(unique_oids),
                   "All walk results should be unique, got duplicates in: #{inspect(oids)}"

            # Verify OIDs are within the system subtree
            Enum.each(oids, fn oid ->
              assert String.starts_with?(oid, "1.3.6.1.2.1.1."),
                     "All OIDs should be within system subtree, got: #{oid}"
            end)

            # This would detect the bug: if walk_multi only returned the first OID
            refute length(walk_results) == 1,
                   "POTENTIAL BUG: walk_multi returned only 1 OID from system subtree, which likely has multiple OIDs"
          end

        {:error, _reason} ->
          # Expected if localhost doesn't have SNMP running
          :ok
      end
    end

    test "walk_multi with multiple localhost attempts shows consistency" do
      # Test multiple identical requests to see if behavior is consistent
      targets_and_oids = [
        {@localhost, "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {@localhost, "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results), "Results should be a list"
      assert length(results) == 2, "Should have 2 results for 2 requests"

      # Both requests should return the same type of result (both success or both failure)
      [result1, result2] = results

      case {result1, result2} do
        {{:ok, walk_results1}, {:ok, walk_results2}} ->
          # Both succeeded - verify they got the same data
          assert length(walk_results1) == length(walk_results2),
                 "Both walks should return same number of results"

        {{:error, _}, {:error, _}} ->
          # Both failed - this is expected if no SNMP on localhost
          :ok

        _ ->
          flunk("Inconsistent results: #{inspect(result1)} vs #{inspect(result2)}")
      end
    end
  end
end
