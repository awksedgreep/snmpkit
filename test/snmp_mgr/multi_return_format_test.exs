defmodule SnmpKit.SnmpMgr.MultiReturnFormatTest do
  use ExUnit.Case, async: true
  @moduletag :performance
  alias SnmpKit.SnmpMgr.Multi

  setup_all do
    # Ensure the SnmpMgr Engine is running for these tests
    case Process.whereis(SnmpKit.SnmpMgr.Engine) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.Engine.start_link(name: SnmpKit.SnmpMgr.Engine)

        on_exit(fn ->
          case Process.whereis(SnmpKit.SnmpMgr.Engine) do
            nil -> :ok
            pid when is_pid(pid) -> GenServer.stop(pid)
          end
        end)

        :ok

      _pid ->
        :ok
    end
  end

  describe "return_format option with simulated network calls" do
    test "default behavior returns list format" do
      # Use invalid hosts to ensure we get consistent error responses
      targets_and_oids = [
        {"192.168.255.251", "1.3.6.1.2.1.1.1.0", [timeout: 50]},
        {"192.168.255.252", "1.3.6.1.2.1.1.3.0", [timeout: 50]},
        {"192.168.255.250", "1.3.6.1.2.1.1.5.0", [timeout: 50]}
      ]

      results = Multi.get_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 3

      # All should be errors due to invalid hosts
      Enum.each(results, fn result ->
        assert match?({:error, _}, result)
      end)
    end

    test "return_format: :list returns same as default" do
      targets_and_oids = [
        {"192.168.255.254", "1.3.6.1.2.1.1.1.0", [timeout: 50]},
        {"192.168.255.253", "1.3.6.1.2.1.1.3.0", [timeout: 50]}
      ]

      default_results = Multi.get_multi(targets_and_oids)
      list_results = Multi.get_multi(targets_and_oids, return_format: :list)

      assert default_results == list_results
      assert is_list(list_results)
      assert length(list_results) == 2
    end

    test "return_format: :with_targets returns target/oid/result tuples" do
      targets_and_oids = [
        {"192.168.255.254", "1.3.6.1.2.1.1.1.0", [timeout: 50]},
        {"192.168.255.253", "1.3.6.1.2.1.1.3.0", [timeout: 50]}
      ]

      results = Multi.get_multi(targets_and_oids, return_format: :with_targets)

      assert is_list(results)
      assert length(results) == 2

      # Check structure: {target, oid, result}
      {target1, oid1, result1} = Enum.at(results, 0)
      {target2, oid2, result2} = Enum.at(results, 1)

      assert target1 == "192.168.255.254"
      assert oid1 == "1.3.6.1.2.1.1.1.0"
      assert match?({:error, _}, result1)

      assert target2 == "192.168.255.253"
      assert oid2 == "1.3.6.1.2.1.1.3.0"
      assert match?({:error, _}, result2)
    end

    test "return_format: :map returns map with target/oid keys" do
      targets_and_oids = [
        {"192.168.255.254", "1.3.6.1.2.1.1.1.0", [timeout: 50]},
        {"192.168.255.253", "1.3.6.1.2.1.1.3.0", [timeout: 50]}
      ]

      results = Multi.get_multi(targets_and_oids, return_format: :map)

      assert is_map(results)
      assert map_size(results) == 2

      key1 = {"192.168.255.254", "1.3.6.1.2.1.1.1.0"}
      key2 = {"192.168.255.253", "1.3.6.1.2.1.1.3.0"}

      assert Map.has_key?(results, key1)
      assert Map.has_key?(results, key2)
      assert match?({:error, _}, results[key1])
      assert match?({:error, _}, results[key2])
    end

    test "unknown return_format defaults to :list" do
      targets_and_oids = [
        {"192.168.255.254", "1.3.6.1.2.1.1.1.0", [timeout: 50]}
      ]

      results = Multi.get_multi(targets_and_oids, return_format: :unknown_format)

      # Should default to list format
      assert is_list(results)
      assert length(results) == 1
      assert match?({:error, _}, Enum.at(results, 0))
    end

    test "handles 2-tuple input format correctly" do
      targets_and_oids = [
        {"192.168.255.254", "1.3.6.1.2.1.1.1.0"},
        {"192.168.255.253", "1.3.6.1.2.1.1.3.0"}
      ]

      # Test with_targets format
      results = Multi.get_multi(targets_and_oids, return_format: :with_targets, timeout: 50)

      assert is_list(results)
      assert length(results) == 2

      {target1, oid1, result1} = Enum.at(results, 0)
      {target2, oid2, result2} = Enum.at(results, 1)

      assert target1 == "192.168.255.254"
      assert oid1 == "1.3.6.1.2.1.1.1.0"
      assert match?({:error, _}, result1)

      assert target2 == "192.168.255.253"
      assert oid2 == "1.3.6.1.2.1.1.3.0"
      assert match?({:error, _}, result2)
    end

    test "get_bulk_multi supports return_format options" do
      targets_and_oids = [
        {"192.168.255.254", "1.3.6.1.2.1.2.2", [timeout: 50]},
        {"192.168.255.253", "1.3.6.1.2.1.2.2", [timeout: 50]}
      ]

      # Test :with_targets format
      results = Multi.get_bulk_multi(targets_and_oids, return_format: :with_targets)

      assert is_list(results)
      assert length(results) == 2

      {target1, oid1, result1} = Enum.at(results, 0)
      assert target1 == "192.168.255.254"
      assert oid1 == "1.3.6.1.2.1.2.2"
      assert match?({:error, _}, result1)

      # Test :map format
      map_results = Multi.get_bulk_multi(targets_and_oids, return_format: :map)

      assert is_map(map_results)
      assert map_size(map_results) == 2

      key1 = {"192.168.255.254", "1.3.6.1.2.1.2.2"}
      assert Map.has_key?(map_results, key1)
      assert match?({:error, _}, map_results[key1])
    end

    test "walk_multi supports return_format options" do
      targets_and_oids = [
        {"192.168.255.254", "1.3.6.1.2.1.1", [timeout: 50]},
        {"192.168.255.253", "1.3.6.1.2.1.2", [timeout: 50]}
      ]

      # Test :with_targets format
      results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)

      assert is_list(results)
      assert length(results) == 2

      {target1, oid1, result1} = Enum.at(results, 0)
      assert target1 == "192.168.255.254"
      assert oid1 == "1.3.6.1.2.1.1"
      assert match?({:error, _}, result1)

      # Test :map format
      map_results = Multi.walk_multi(targets_and_oids, return_format: :map)

      assert is_map(map_results)
      assert map_size(map_results) == 2
    end

    test "walk_table_multi supports return_format options" do
      targets_and_oids = [
        {"192.168.255.254", "ifTable", [timeout: 50]},
        {"192.168.255.253", "ifTable", [timeout: 50]}
      ]

      # Test :with_targets format
      results = Multi.walk_table_multi(targets_and_oids, return_format: :with_targets)

      assert is_list(results)
      assert length(results) == 2

      {target1, oid1, result1} = Enum.at(results, 0)
      assert target1 == "192.168.255.254"
      assert oid1 == "ifTable"
      assert match?({:error, _}, result1)

      # Test :map format
      map_results = Multi.walk_table_multi(targets_and_oids, return_format: :map)

      assert is_map(map_results)
      assert map_size(map_results) == 2
    end
  end

  describe "return_format ordering and consistency" do
    test "all formats maintain same ordering as input" do
      targets_and_oids = [
        {"192.168.255.1", "oid.1", [timeout: 50]},
        {"192.168.255.2", "oid.2", [timeout: 50]},
        {"192.168.255.3", "oid.3", [timeout: 50]}
      ]

      list_results = Multi.get_multi(targets_and_oids, return_format: :list)
      with_targets_results = Multi.get_multi(targets_and_oids, return_format: :with_targets)
      map_results = Multi.get_multi(targets_and_oids, return_format: :map)

      # Verify ordering in with_targets format matches input
      assert length(with_targets_results) == 3
      {target1, oid1, _} = Enum.at(with_targets_results, 0)
      {target2, oid2, _} = Enum.at(with_targets_results, 1)
      {target3, oid3, _} = Enum.at(with_targets_results, 2)

      assert target1 == "192.168.255.1"
      assert oid1 == "oid.1"
      assert target2 == "192.168.255.2"
      assert oid2 == "oid.2"
      assert target3 == "192.168.255.3"
      assert oid3 == "oid.3"

      # Verify map contains all expected keys
      assert Map.has_key?(map_results, {"192.168.255.1", "oid.1"})
      assert Map.has_key?(map_results, {"192.168.255.2", "oid.2"})
      assert Map.has_key?(map_results, {"192.168.255.3", "oid.3"})

      # Verify list has correct length
      assert length(list_results) == 3
    end

    test "empty input list handled correctly for all formats" do
      empty_targets = []

      list_results = Multi.get_multi(empty_targets, return_format: :list)
      with_targets_results = Multi.get_multi(empty_targets, return_format: :with_targets)
      map_results = Multi.get_multi(empty_targets, return_format: :map)

      assert list_results == []
      assert with_targets_results == []
      assert map_results == %{}
    end
  end
end
