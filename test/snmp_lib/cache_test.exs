defmodule SnmpKit.SnmpLib.CacheTest do
  use ExUnit.Case, async: false
  doctest SnmpKit.SnmpLib.Cache

  alias SnmpKit.SnmpLib.Cache

  @moduletag :cache_test

  setup do
    # Ensure cache process is stopped before each test
    if Process.whereis(Cache) do
      try do
        GenServer.stop(Cache, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end

    :timer.sleep(10)
    :ok
  end

  describe "Cache.start_link/1" do
    test "starts with default configuration" do
      assert {:ok, pid} = Cache.start_link()
      assert Process.alive?(pid)

      try do
        GenServer.stop(Cache)
      catch
        :exit, _ -> :ok
      end
    end

    test "starts with custom configuration" do
      opts = [
        max_size: 50_000,
        compression_enabled: true,
        adaptive_ttl_enabled: true
      ]

      assert {:ok, pid} = Cache.start_link(opts)
      assert Process.alive?(pid)

      try do
        GenServer.stop(Cache)
      catch
        :exit, _ -> :ok
      end
    end
  end

  describe "Cache.put/3 and Cache.get/1" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "stores and retrieves simple values" do
      key = "test_key"
      value = "test_value"

      :ok = Cache.put(key, value)
      assert {:ok, ^value} = Cache.get(key)
    end

    test "returns miss for non-existent keys" do
      assert :miss = Cache.get("non_existent_key")
    end

    test "handles complex data structures" do
      key = "complex_data"

      value = %{
        device: "192.168.1.1",
        oids: [1, 3, 6, 1, 2, 1, 1, 1, 0],
        response: {:string, "Cisco Router"},
        timestamp: System.system_time(:millisecond)
      }

      :ok = Cache.put(key, value)
      assert {:ok, ^value} = Cache.get(key)
    end

    test "respects TTL expiration" do
      key = "ttl_test"
      value = "expires_soon"

      # Set very short TTL
      :ok = Cache.put(key, value, ttl: 50)
      assert {:ok, ^value} = Cache.get(key)

      # Wait for expiration
      :timer.sleep(100)
      assert :miss = Cache.get(key)
    end

    test "handles compression for large values" do
      key = "large_data"
      # Create a large value that should trigger compression
      large_value = String.duplicate("A", 2000)

      :ok = Cache.put(key, large_value, compress: true)
      assert {:ok, ^large_value} = Cache.get(key)
    end
  end

  describe "Cache.put_adaptive/4" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "stores values with adaptive TTL" do
      key = "adaptive_test"
      value = "adaptive_value"

      :ok = Cache.put_adaptive(key, value, 1000, :medium)
      assert {:ok, ^value} = Cache.get(key)
    end

    test "adjusts TTL based on volatility" do
      # Low volatility should have longer TTL
      :ok = Cache.put_adaptive("low_volatility", "stable_data", 1000, :low)

      # High volatility should have shorter TTL
      :ok = Cache.put_adaptive("high_volatility", "changing_data", 1000, :high)

      # Both should be retrievable immediately
      assert {:ok, "stable_data"} = Cache.get("low_volatility")
      assert {:ok, "changing_data"} = Cache.get("high_volatility")
    end
  end

  describe "Cache.delete/1" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "deletes specific cache entries" do
      key = "delete_test"
      value = "to_be_deleted"

      :ok = Cache.put(key, value)
      assert {:ok, ^value} = Cache.get(key)

      :ok = Cache.delete(key)
      assert :miss = Cache.get(key)
    end
  end

  describe "Cache.invalidate_pattern/1" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "invalidates entries matching pattern" do
      # Store entries with common prefix
      Cache.put("device_1:sysDescr", "Router 1")
      Cache.put("device_1:sysName", "R1")
      Cache.put("device_2:sysDescr", "Router 2")

      # Verify they exist
      assert {:ok, "Router 1"} = Cache.get("device_1:sysDescr")
      assert {:ok, "R1"} = Cache.get("device_1:sysName")
      assert {:ok, "Router 2"} = Cache.get("device_2:sysDescr")

      # Invalidate device_1 entries
      :ok = Cache.invalidate_pattern("device_1:*")

      # device_1 entries should be gone
      assert :miss = Cache.get("device_1:sysDescr")
      assert :miss = Cache.get("device_1:sysName")

      # device_2 entries should remain
      assert {:ok, "Router 2"} = Cache.get("device_2:sysDescr")
    end
  end

  describe "Cache.invalidate_by_tag/1" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "invalidates entries by tag" do
      # Store entries with tags
      Cache.put("entry1", "data1", tags: [:interface_data])
      Cache.put("entry2", "data2", tags: [:interface_data, :statistics])
      Cache.put("entry3", "data3", tags: [:system_data])

      # Verify they exist
      assert {:ok, "data1"} = Cache.get("entry1")
      assert {:ok, "data2"} = Cache.get("entry2")
      assert {:ok, "data3"} = Cache.get("entry3")

      # Invalidate by tag
      :ok = Cache.invalidate_by_tag(:interface_data)

      # Interface data entries should be gone
      assert :miss = Cache.get("entry1")
      assert :miss = Cache.get("entry2")

      # System data should remain
      assert {:ok, "data3"} = Cache.get("entry3")
    end
  end

  describe "Cache.warm_cache/3" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "performs immediate cache warming" do
      device_id = "192.168.1.1"
      oids = ["1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.3.0"]

      :ok = Cache.warm_cache(device_id, oids, strategy: :immediate)

      # Allow time for async processing
      :timer.sleep(10)
    end

    test "performs predictive cache warming" do
      device_id = "192.168.1.1"

      :ok = Cache.warm_cache(device_id, :auto, strategy: :predictive)

      # Allow time for async processing
      :timer.sleep(10)
    end

    test "schedules cache warming" do
      device_id = "192.168.1.1"
      oids = ["1.3.6.1.2.1.1.1.0"]

      :ok = Cache.warm_cache(device_id, oids, strategy: :scheduled)

      # Allow time for async processing
      :timer.sleep(10)
    end
  end

  describe "Cache.get_stats/0" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "returns cache statistics" do
      # Perform some cache operations to generate stats
      Cache.put("test1", "value1")
      Cache.put("test2", "value2")
      # Hit
      Cache.get("test1")
      # Miss
      Cache.get("test3")

      stats = Cache.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_entries)
      assert Map.has_key?(stats, :hit_rate)
      assert Map.has_key?(stats, :miss_rate)
      assert Map.has_key?(stats, :eviction_count)
      assert Map.has_key?(stats, :memory_usage_mb)
      assert Map.has_key?(stats, :compression_ratio)

      assert is_integer(stats.total_entries)
      assert is_float(stats.hit_rate)
      assert is_float(stats.miss_rate)
      assert is_integer(stats.eviction_count)
      assert is_float(stats.memory_usage_mb)
      assert is_float(stats.compression_ratio)

      # Should have some entries
      assert stats.total_entries > 0
    end
  end

  describe "Cache.clear/0" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "clears all cached data" do
      # Add some entries
      Cache.put("test1", "value1")
      Cache.put("test2", "value2")

      # Verify they exist
      assert {:ok, "value1"} = Cache.get("test1")
      assert {:ok, "value2"} = Cache.get("test2")

      # Clear cache
      :ok = Cache.clear()

      # All entries should be gone
      assert :miss = Cache.get("test1")
      assert :miss = Cache.get("test2")

      # Stats should be reset
      stats = Cache.get_stats()
      assert stats.total_entries == 0
    end
  end

  describe "SNMP-specific caching patterns" do
    setup do
      {:ok, _pid} = Cache.start_link()

      on_exit(fn ->
        if Process.whereis(Cache) do
          try do
            GenServer.stop(Cache, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "caches SNMP responses by device and OID" do
      device = "192.168.1.1"
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      response = {:string, "Cisco 2960 Switch"}

      key = "#{device}:#{Enum.join(oid, ".")}"

      :ok = Cache.put(key, response, ttl: 300_000)
      assert {:ok, ^response} = Cache.get(key)
    end

    test "caches table walk results" do
      device = "192.168.1.1"
      table_oid = [1, 3, 6, 1, 2, 1, 2, 2]

      table_data = [
        {[1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1], {:integer, 1}},
        {[1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 2], {:integer, 2}},
        {[1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 3], {:integer, 3}}
      ]

      key = "#{device}:walk:#{Enum.join(table_oid, ".")}"

      :ok = Cache.put_adaptive(key, table_data, 60_000, :medium)
      assert {:ok, ^table_data} = Cache.get(key)
    end

    test "uses device-specific cache invalidation" do
      device1 = "192.168.1.1"
      device2 = "192.168.1.2"

      # Cache data for both devices
      Cache.put("#{device1}:sysDescr", "Router 1")
      Cache.put("#{device1}:sysName", "R1")
      Cache.put("#{device2}:sysDescr", "Router 2")

      # Invalidate all data for device1
      :ok = Cache.invalidate_pattern("#{device1}:*")

      # Device1 data should be gone
      assert :miss = Cache.get("#{device1}:sysDescr")
      assert :miss = Cache.get("#{device1}:sysName")

      # Device2 data should remain
      assert {:ok, "Router 2"} = Cache.get("#{device2}:sysDescr")
    end
  end
end
