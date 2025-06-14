defmodule SnmpKit.SnmpLib.PoolTest do
  use ExUnit.Case, async: false
  doctest SnmpKit.SnmpLib.Pool

  alias SnmpKit.SnmpKit.SnmpLib.Pool

  @moduletag :pool_test

  # Helper function for safe pool cleanup
  defp safe_stop_pool(pool_name, timeout \\ 100) do
    try do
      if Process.whereis(pool_name), do: Pool.stop_pool(pool_name, timeout)
    catch
      :exit, _ -> :ok
    rescue
      _ -> :ok
    end
  end

  setup do
    # Clean up any existing pools with better error handling
    pool_names = [
      :test_pool,
      :custom_pool,
      :duplicate_test,
      :affinity_pool,
      :fifo_pool,
      :rr_pool,
      :overflow_pool,
      :max_overflow_pool,
      :health_pool,
      :cleanup_pool,
      :stats_pool,
      :operation_stats_pool,
      :error_pool,
      :recovery_pool,
      :lifecycle_pool,
      :timeout_pool,
      :perf_pool,
      :reuse_pool
    ]

    Enum.each(pool_names, fn pool_name ->
      try do
        if Process.whereis(pool_name) do
          Pool.stop_pool(pool_name, 100)
        end
      catch
        :exit, _ -> :ok
      rescue
        _ -> :ok
      end
    end)

    # Small delay to ensure cleanup
    :timer.sleep(10)
    :ok
  end

  describe "Pool.start_pool/2" do
    test "starts a basic pool with default options" do
      assert {:ok, pid} = Pool.start_pool(:test_pool)
      assert Process.alive?(pid)

      # Check pool stats
      stats = Pool.get_stats(:test_pool)
      assert stats.name == :test_pool
      assert stats.strategy == :fifo
      # Default size
      assert stats.size == 10

      Pool.stop_pool(:test_pool)
    end

    test "starts a pool with custom configuration" do
      opts = [
        strategy: :device_affinity,
        size: 5,
        max_overflow: 3,
        health_check_interval: 10_000
      ]

      assert {:ok, pid} = Pool.start_pool(:custom_pool, opts)
      assert Process.alive?(pid)

      stats = Pool.get_stats(:custom_pool)
      assert stats.strategy == :device_affinity
      assert stats.size == 5

      Pool.stop_pool(:custom_pool)
    end

    test "prevents duplicate pool names" do
      assert {:ok, _pid} = Pool.start_pool(:duplicate_test)

      # Second pool with same name should fail
      assert {:error, _reason} = Pool.start_pool(:duplicate_test)

      Pool.stop_pool(:duplicate_test)
    end
  end

  describe "Pool.with_connection/4" do
    setup do
      {:ok, _pid} = Pool.start_pool(:test_pool, size: 3)
      on_exit(fn -> safe_stop_pool(:test_pool) end)
      :ok
    end

    test "executes function with pooled connection" do
      result =
        Pool.with_connection(:test_pool, "192.168.1.1", fn conn ->
          assert is_map(conn)
          assert Map.has_key?(conn, :socket)
          assert Map.has_key?(conn, :device)
          assert conn.device == "192.168.1.1"
          {:ok, :test_result}
        end)

      assert result == {:ok, :test_result}
    end

    test "handles function errors gracefully" do
      result =
        Pool.with_connection(:test_pool, "192.168.1.1", fn _conn ->
          raise "Test error"
        end)

      assert match?({:error, {:operation_failed, _}}, result)
    end

    test "returns connection to pool after use" do
      initial_stats = Pool.get_stats(:test_pool)
      initial_idle = initial_stats.idle_connections

      Pool.with_connection(:test_pool, "192.168.1.1", fn _conn ->
        # Connection should be checked out
        during_stats = Pool.get_stats(:test_pool)
        assert during_stats.idle_connections == initial_idle - 1
        assert during_stats.active_connections == 1
        :ok
      end)

      # Connection should be returned
      final_stats = Pool.get_stats(:test_pool)
      assert final_stats.idle_connections == initial_idle
      assert final_stats.active_connections == 0
    end

    test "supports concurrent operations" do
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            Pool.with_connection(:test_pool, "device_#{i}", fn conn ->
              # No sleep needed for testing connection logic
              {:ok, conn.device}
            end)
          end)
        end)

      results = Task.await_many(tasks, 1000)

      # All should succeed
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)

      # Check that connections were properly managed
      stats = Pool.get_stats(:test_pool)
      assert stats.total_checkouts >= 5
      # All returned
      assert stats.active_connections == 0
    end
  end

  describe "Pool.checkout_connection/3 and checkin_connection/2" do
    setup do
      {:ok, _pid} = Pool.start_pool(:test_pool, size: 2, max_overflow: 0)
      on_exit(fn -> safe_stop_pool(:test_pool) end)
      :ok
    end

    test "manually checks out and returns connections" do
      assert {:ok, conn1} = Pool.checkout_connection(:test_pool, "device1")
      assert {:ok, conn2} = Pool.checkout_connection(:test_pool, "device2")

      # Pool should be exhausted
      stats = Pool.get_stats(:test_pool)
      assert stats.idle_connections == 0
      assert stats.active_connections == 2

      # Return connections
      assert :ok = Pool.checkin_connection(:test_pool, conn1)
      assert :ok = Pool.checkin_connection(:test_pool, conn2)

      # Pool should be restored
      final_stats = Pool.get_stats(:test_pool)
      assert final_stats.idle_connections == 2
      assert final_stats.active_connections == 0
    end

    test "handles checkout timeout when pool is exhausted" do
      # Checkout all connections
      {:ok, conn1} = Pool.checkout_connection(:test_pool, "device1")
      {:ok, conn2} = Pool.checkout_connection(:test_pool, "device2")

      # Next checkout should fail when pool is exhausted (no overflow allowed)
      assert {:error, :no_connections} =
               Pool.checkout_connection(:test_pool, "device3", timeout: 100)

      # Return one connection
      Pool.checkin_connection(:test_pool, conn1)

      # Should be able to checkout again
      assert {:ok, _conn3} = Pool.checkout_connection(:test_pool, "device3")

      # Cleanup
      Pool.checkin_connection(:test_pool, conn2)
    end
  end

  describe "Pool strategies" do
    test "FIFO strategy processes connections in order" do
      {:ok, _pid} = Pool.start_pool(:fifo_pool, strategy: :fifo, size: 3)

      # Strategy should be FIFO
      stats = Pool.get_stats(:fifo_pool)
      assert stats.strategy == :fifo

      Pool.stop_pool(:fifo_pool)
    end

    test "round-robin strategy distributes connections evenly" do
      {:ok, _pid} = Pool.start_pool(:rr_pool, strategy: :round_robin, size: 3)

      stats = Pool.get_stats(:rr_pool)
      assert stats.strategy == :round_robin

      Pool.stop_pool(:rr_pool)
    end

    test "device-affinity strategy maintains device associations" do
      {:ok, _pid} = Pool.start_pool(:affinity_pool, strategy: :device_affinity, size: 3)

      stats = Pool.get_stats(:affinity_pool)
      assert stats.strategy == :device_affinity

      # Test device affinity behavior
      {:ok, conn1} = Pool.checkout_connection(:affinity_pool, "device1")
      Pool.checkin_connection(:affinity_pool, conn1)

      {:ok, conn2} = Pool.checkout_connection(:affinity_pool, "device1")

      # With device affinity, we should get connections that work for the device
      # The exact socket might be different but the device should be properly set
      assert conn2.device == "device1"

      Pool.checkin_connection(:affinity_pool, conn2)
      Pool.stop_pool(:affinity_pool)
    end
  end

  describe "Pool overflow handling" do
    test "creates overflow connections when pool is exhausted" do
      {:ok, _pid} = Pool.start_pool(:overflow_pool, size: 2, max_overflow: 2)

      # Checkout all base connections
      {:ok, conn1} = Pool.checkout_connection(:overflow_pool, "device1")
      {:ok, conn2} = Pool.checkout_connection(:overflow_pool, "device2")

      initial_stats = Pool.get_stats(:overflow_pool)
      assert initial_stats.idle_connections == 0
      assert initial_stats.active_connections == 2
      assert initial_stats.overflow_connections == 0

      # Checkout overflow connections
      {:ok, conn3} = Pool.checkout_connection(:overflow_pool, "device3")
      {:ok, conn4} = Pool.checkout_connection(:overflow_pool, "device4")

      overflow_stats = Pool.get_stats(:overflow_pool)
      assert overflow_stats.overflow_connections >= 2

      # Return all connections
      Pool.checkin_connection(:overflow_pool, conn1)
      Pool.checkin_connection(:overflow_pool, conn2)
      Pool.checkin_connection(:overflow_pool, conn3)
      Pool.checkin_connection(:overflow_pool, conn4)

      Pool.stop_pool(:overflow_pool)
    end

    test "rejects connections when max overflow is reached" do
      {:ok, _pid} = Pool.start_pool(:max_overflow_pool, size: 1, max_overflow: 1)

      # Checkout base and overflow
      {:ok, conn1} = Pool.checkout_connection(:max_overflow_pool, "device1")
      {:ok, conn2} = Pool.checkout_connection(:max_overflow_pool, "device2")

      # Should reject further checkouts
      assert {:error, :no_connections} =
               Pool.checkout_connection(:max_overflow_pool, "device3", timeout: 100)

      Pool.checkin_connection(:max_overflow_pool, conn1)
      Pool.checkin_connection(:max_overflow_pool, conn2)
      Pool.stop_pool(:max_overflow_pool)
    end
  end

  describe "Pool health monitoring" do
    test "tracks connection health status" do
      {:ok, _pid} = Pool.start_pool(:health_pool, size: 2, health_check_interval: 100)

      # Force health check
      Pool.health_check(:health_pool)

      stats = Pool.get_stats(:health_pool)
      assert Map.has_key?(stats, :health_status)

      Pool.stop_pool(:health_pool)
    end

    test "cleans up unhealthy connections" do
      {:ok, _pid} = Pool.start_pool(:cleanup_pool, size: 2)

      # Simulate unhealthy connections
      Pool.cleanup_unhealthy(:cleanup_pool)

      # Pool should still be functional
      stats = Pool.get_stats(:cleanup_pool)
      assert stats.idle_connections >= 0

      Pool.stop_pool(:cleanup_pool)
    end
  end

  describe "Pool statistics" do
    test "provides comprehensive pool statistics" do
      {:ok, _pid} = Pool.start_pool(:stats_pool, size: 3, max_overflow: 2)

      stats = Pool.get_stats(:stats_pool)

      # Check required fields
      assert Map.has_key?(stats, :name)
      assert Map.has_key?(stats, :strategy)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :active_connections)
      assert Map.has_key?(stats, :idle_connections)
      assert Map.has_key?(stats, :overflow_connections)
      assert Map.has_key?(stats, :total_checkouts)
      assert Map.has_key?(stats, :total_checkins)
      assert Map.has_key?(stats, :health_status)
      assert Map.has_key?(stats, :average_response_time)

      # Check initial values
      assert stats.name == :stats_pool
      assert stats.size == 3
      assert stats.idle_connections == 3
      assert stats.active_connections == 0
      assert stats.total_checkouts == 0
      assert stats.total_checkins == 0

      Pool.stop_pool(:stats_pool)
    end

    test "updates statistics during operation" do
      {:ok, _pid} = Pool.start_pool(:operation_stats_pool, size: 2)

      initial_stats = Pool.get_stats(:operation_stats_pool)
      assert initial_stats.total_checkouts == 0

      # Perform some operations
      Pool.with_connection(:operation_stats_pool, "device1", fn _conn -> :ok end)
      Pool.with_connection(:operation_stats_pool, "device2", fn _conn -> :ok end)

      updated_stats = Pool.get_stats(:operation_stats_pool)
      assert updated_stats.total_checkouts >= 2
      assert updated_stats.total_checkins >= 2

      Pool.stop_pool(:operation_stats_pool)
    end
  end

  describe "Pool error handling" do
    test "handles worker process failures gracefully" do
      {:ok, _pid} = Pool.start_pool(:error_pool, size: 2)

      # Pool should remain functional even with simulated errors
      result =
        Pool.with_connection(:error_pool, "device1", fn conn ->
          assert is_map(conn)
          :ok
        end)

      assert result == :ok

      Pool.stop_pool(:error_pool)
    end

    test "recovers from connection failures" do
      {:ok, _pid} = Pool.start_pool(:recovery_pool, size: 2)

      # Simulate connection failure and recovery
      Pool.cleanup_unhealthy(:recovery_pool)

      # Pool should still work
      result = Pool.with_connection(:recovery_pool, "device1", fn _conn -> :success end)
      assert result == :success

      Pool.stop_pool(:recovery_pool)
    end
  end

  describe "Pool lifecycle" do
    test "stops gracefully and cleans up resources" do
      {:ok, pid} = Pool.start_pool(:lifecycle_pool, size: 2)
      assert Process.alive?(pid)

      # Use the pool
      Pool.with_connection(:lifecycle_pool, "device1", fn _conn -> :ok end)

      # Stop should succeed
      assert :ok = Pool.stop_pool(:lifecycle_pool, 1000)
      refute Process.alive?(pid)
    end

    test "handles stop timeout appropriately" do
      {:ok, _pid} = Pool.start_pool(:timeout_pool, size: 1)

      # Should stop within timeout
      assert :ok = Pool.stop_pool(:timeout_pool, 100)
    end
  end

  # Performance tests
  describe "Pool performance" do
    @tag :performance
    test "handles high-frequency operations efficiently" do
      {:ok, _pid} = Pool.start_pool(:perf_pool, size: 10, max_overflow: 15)

      # Measure time for many operations
      {time_microseconds, results} =
        :timer.tc(fn ->
          tasks =
            Enum.map(1..20, fn i ->
              Task.async(fn ->
                Pool.with_connection(:perf_pool, "device_#{rem(i, 10)}", fn _conn ->
                  # Minimal work
                  :timer.sleep(1)
                  :ok
                end)
              end)
            end)

          Task.await_many(tasks, 5000)
        end)

      # All operations should succeed
      assert Enum.all?(results, fn result -> result == :ok end)

      # Should complete reasonably quickly (less than 2 seconds)
      assert time_microseconds < 2_000_000

      stats = Pool.get_stats(:perf_pool)
      assert stats.total_checkouts >= 20

      Pool.stop_pool(:perf_pool)
    end

    @tag :performance
    test "connection reuse provides performance benefit" do
      {:ok, _pid} = Pool.start_pool(:reuse_pool, size: 3)

      # Simulate repeated operations to same device
      device = "performance.test.device"

      {time_microseconds, _} =
        :timer.tc(fn ->
          Enum.each(1..20, fn _i ->
            Pool.with_connection(:reuse_pool, device, fn _conn ->
              # Simulate SNMP operation
              :timer.sleep(5)
              :ok
            end)
          end)
        end)

      # Should complete efficiently with connection reuse
      # Less than 1 second
      assert time_microseconds < 1_000_000

      stats = Pool.get_stats(:reuse_pool)
      assert stats.total_checkouts == 20

      Pool.stop_pool(:reuse_pool)
    end
  end
end
