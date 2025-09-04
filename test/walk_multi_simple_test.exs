defmodule SnmpKit.WalkMultiSimpleTest do
  use ExUnit.Case, async: true
  @moduletag :walk_multi_simple

  alias SnmpKit.SnmpMgr.Multi

  @test_timeout 500

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

  describe "walk_multi basic functionality" do
    test "walk_multi returns correct number of results" do
      # Simple test with 2 unreachable targets
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)

      assert length(results) == 2,
             "walk_multi should return 2 results for 2 targets, got #{length(results)}"

      # Both should be errors
      Enum.each(results, fn result ->
        assert match?({:error, _}, result)
      end)
    end

    test "walk_multi with single target returns single result" do
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 1, "Should return exactly 1 result"

      [result] = results
      assert match?({:error, _}, result)
    end

    test "walk_multi with empty list returns empty list" do
      results = Multi.walk_multi([])
      assert results == []
    end

    test "walk_multi with :with_targets format preserves count" do
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)

      assert is_list(results)
      assert length(results) == 2, "Should return 2 results with :with_targets format"

      # Verify structure
      Enum.each(results, fn result ->
        assert match?({_target, _oid, {:error, _}}, result)
      end)
    end

    test "walk_multi with :map format preserves count" do
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids, return_format: :map)

      assert is_map(results)
      assert map_size(results) == 2, "Should return 2 keys with :map format"

      # Verify expected keys exist
      expected_keys = [
        {"192.168.255.1", "1.3.6.1.2.1.1"},
        {"192.168.255.2", "1.3.6.1.2.1.1"}
      ]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(results, key), "Should have key #{inspect(key)}"
        assert match?({:error, _}, results[key])
      end)
    end
  end

  describe "walk_multi potential first-OID bug detection" do
    test "walk_multi does not truncate to only first result" do
      # This is the key test for the reported bug
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.3", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      # The critical assertion: we should NOT get only 1 result when we requested 3
      refute length(results) == 1,
             "POTENTIAL BUG: walk_multi returned only 1 result when 3 were expected. This could indicate the first-OID bug."

      # We should get exactly 3 results
      assert length(results) == 3,
             "walk_multi should return all 3 requested results, got #{length(results)}"
    end

    test "walk_multi format consistency check" do
      # Verify all formats return the same count
      targets_and_oids = [
        {"192.168.255.1", "1.3.6.1.2.1.1", [timeout: @test_timeout]},
        {"192.168.255.2", "1.3.6.1.2.1.1", [timeout: @test_timeout]}
      ]

      list_results = Multi.walk_multi(targets_and_oids, return_format: :list)
      with_targets_results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)
      map_results = Multi.walk_multi(targets_and_oids, return_format: :map)

      # All should return 2 results
      assert length(list_results) == 2
      assert length(with_targets_results) == 2
      assert map_size(map_results) == 2

      # None should return only 1 (which would indicate the bug)
      refute length(list_results) == 1, "List format should not truncate to 1 result"

      refute length(with_targets_results) == 1,
             "With_targets format should not truncate to 1 result"

      refute map_size(map_results) == 1, "Map format should not truncate to 1 result"
    end
  end
end
