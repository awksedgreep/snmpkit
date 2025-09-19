defmodule SnmpKit.SnmpSim.LazyDevicePoolTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.LazyDevicePool
  alias SnmpKit.SnmpSim.TestHelpers.PortHelper

  # Helper function to get unique port for each test using PortHelper
  defp get_test_port(_test_name, offset \\ 0) do
    PortHelper.get_port() + offset
  end

  setup %{test: test_name} do
    # Start a fresh LazyDevicePool for each test
    {:ok, pool_pid} =
      LazyDevicePool.start_link(
        # Short timeout for testing
        idle_timeout_ms: 1000,
        max_devices: 100
      )

    # Ensure clean state
    LazyDevicePool.shutdown_all_devices()

    on_exit(fn ->
      if Process.alive?(pool_pid) do
        Process.exit(pool_pid, :normal)
      end
    end)

    # Provide unique port for this test
    test_port = get_test_port(test_name)
    {:ok, pool_pid: pool_pid, test_port: test_port}
  end

  describe "device creation" do
    test "creates device on first access", %{test_port: test_port} do
      port = test_port

      # Device shouldn't exist initially
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 0

      # Create device
      assert {:ok, device_pid} = LazyDevicePool.get_or_create_device(port)
      assert is_pid(device_pid)
      assert Process.alive?(device_pid)

      # Stats should reflect new device
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 1
      assert stats.devices_created == 1
    end

    test "reuses existing device on subsequent access", %{test_port: test_port} do
      port = test_port

      # Create device first time
      assert {:ok, device_pid1} = LazyDevicePool.get_or_create_device(port)

      # Get same device second time
      assert {:ok, device_pid2} = LazyDevicePool.get_or_create_device(port)

      # Should be the same PID
      assert device_pid1 == device_pid2

      # Only one device created
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 1
      assert stats.devices_created == 1
    end

    test "creates different devices for different ports", %{test_port: test_port} do
      port1 = test_port
      port2 = test_port + 1

      assert {:ok, device_pid1} = LazyDevicePool.get_or_create_device(port1)
      assert {:ok, device_pid2} = LazyDevicePool.get_or_create_device(port2)

      assert device_pid1 != device_pid2

      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 2
      assert stats.devices_created == 2
    end

    test "determines device type based on port range", %{test_port: _test_port} do
      # Cable modem port (30,000-37,999)
      cable_modem_port = 30_005
      assert {:ok, cable_modem_pid} = LazyDevicePool.get_or_create_device(cable_modem_port)

      # Switch port (39,500-39,899)
      switch_port = 39_505
      assert {:ok, switch_pid} = LazyDevicePool.get_or_create_device(switch_port)

      # Verify they're different devices
      assert cable_modem_pid != switch_pid
    end

    test "respects max device limit", %{test_port: test_port} do
      # Stop the existing pool and start a new one with limited devices
      existing_pool = Process.whereis(LazyDevicePool)

      if existing_pool && Process.alive?(existing_pool) do
        GenServer.stop(existing_pool)
      end

      {:ok, _} = LazyDevicePool.start_link(max_devices: 2)

      # Create devices up to limit
      assert {:ok, _} = LazyDevicePool.get_or_create_device(test_port)
      assert {:ok, _} = LazyDevicePool.get_or_create_device(test_port + 1)

      # Should fail to create beyond limit
      assert {:error, :max_devices_reached} = LazyDevicePool.get_or_create_device(test_port + 2)
    end

    test "handles unknown port ranges", %{test_port: _test_port} do
      # Port outside any known range
      unknown_port = 99_999

      assert {:error, :unknown_port_range} = LazyDevicePool.get_or_create_device(unknown_port)
    end
  end

  describe "device lifecycle management" do
    test "recreates device if it dies", %{test_port: test_port} do
      # Trap exits to prevent test from crashing when device dies
      Process.flag(:trap_exit, true)

      port = test_port

      # Create device
      assert {:ok, device_pid1} = LazyDevicePool.get_or_create_device(port)

      # Monitor the LazyDevicePool to debug crashes
      pool_pid = Process.whereis(LazyDevicePool)
      pool_ref = Process.monitor(pool_pid)

      # Kill the device normally (not with :kill which is brutal)
      GenServer.stop(device_pid1, :normal)

      # Wait for the DOWN message to be processed
      :timer.sleep(200)

      # Check if pool is still alive
      receive do
        {:DOWN, ^pool_ref, :process, ^pool_pid, reason} ->
          flunk("LazyDevicePool died with reason: #{inspect(reason)}")
      after
        # Pool is still alive
        0 -> :ok
      end

      # Verify pool is responsive
      assert Process.alive?(pool_pid)
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 0

      # Request device again - should create new one
      assert {:ok, device_pid2} = LazyDevicePool.get_or_create_device(port)
      assert device_pid1 != device_pid2
      assert Process.alive?(device_pid2)

      # Clean up monitor
      Process.demonitor(pool_ref, [:flush])
    end

    @tag :slow
    test "cleans up idle devices after timeout", %{test_port: test_port} do
      port = test_port

      # Create device
      assert {:ok, device_pid} = LazyDevicePool.get_or_create_device(port)

      # Should exist initially
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 1

      # Force cleanup (idle timeout is 1000ms in test setup)
      :timer.sleep(1100)
      LazyDevicePool.cleanup_idle_devices()

      # Device should be cleaned up
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 0
      assert stats.devices_cleaned_up == 1

      # Device process should be dead
      refute Process.alive?(device_pid)
    end

    @tag :slow
    test "updates last access time to prevent cleanup", %{test_port: test_port} do
      port = test_port

      # Create device
      assert {:ok, device_pid} = LazyDevicePool.get_or_create_device(port)

      # Wait half the timeout period
      :timer.sleep(500)

      # Access device again to update timestamp
      assert {:ok, ^device_pid} = LazyDevicePool.get_or_create_device(port)

      # Wait another half timeout period
      :timer.sleep(600)
      LazyDevicePool.cleanup_idle_devices()

      # Device should still be alive (total time > timeout but last access < timeout)
      assert Process.alive?(device_pid)
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 1
    end
  end

  describe "device shutdown" do
    test "shuts down specific device", %{test_port: test_port} do
      port = test_port

      # Create device
      assert {:ok, device_pid} = LazyDevicePool.get_or_create_device(port)

      # Shutdown specific device
      assert :ok = LazyDevicePool.shutdown_device(port)

      # Device should be gone
      refute Process.alive?(device_pid)
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 0
    end

    test "handles shutdown of non-existent device", %{test_port: test_port} do
      port = test_port

      assert {:error, :not_found} = LazyDevicePool.shutdown_device(port)
    end

    test "shuts down all devices", %{test_port: test_port} do
      # Create multiple devices
      ports = [test_port, test_port + 1, test_port + 2]

      device_pids =
        Enum.map(ports, fn port ->
          {:ok, pid} = LazyDevicePool.get_or_create_device(port)
          pid
        end)

      # Verify all created
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 3

      # Shutdown all
      assert :ok = LazyDevicePool.shutdown_all_devices()

      # All should be gone
      Enum.each(device_pids, fn pid ->
        refute Process.alive?(pid)
      end)

      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 0
    end
  end

  describe "port assignment configuration" do
    test "configures custom port assignments", %{test_port: test_port} do
      custom_assignments = %{
        test_device: test_port..(test_port + 99)
      }

      assert :ok = LazyDevicePool.configure_port_assignments(custom_assignments)

      # Should be able to create device in custom range
      assert {:ok, _} = LazyDevicePool.get_or_create_device(test_port + 50)

      # Should fail outside custom range
      assert {:error, :unknown_port_range} = LazyDevicePool.get_or_create_device(test_port + 200)
    end
  end

  describe "statistics tracking" do
    test "tracks device creation statistics", %{test_port: test_port} do
      ports = [test_port, test_port + 1, test_port + 2]

      # Create devices
      Enum.each(ports, fn port ->
        {:ok, _} = LazyDevicePool.get_or_create_device(port)
      end)

      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 3
      assert stats.devices_created == 3
      assert stats.peak_count == 3
      assert stats.devices_cleaned_up == 0
    end

    test "tracks peak device count", %{test_port: test_port} do
      # Create devices
      {:ok, _} = LazyDevicePool.get_or_create_device(test_port)
      {:ok, _} = LazyDevicePool.get_or_create_device(test_port + 1)

      # Remove one
      LazyDevicePool.shutdown_device(test_port)

      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 1
      # Peak should remain at 2
      assert stats.peak_count == 2
    end
  end

  describe "concurrent access" do
    test "handles concurrent device creation safely", %{test_port: test_port} do
      port = test_port

      # Create multiple tasks trying to create same device
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            LazyDevicePool.get_or_create_device(port)
          end)
        end

      # Wait for all tasks
      results = Enum.map(tasks, &Task.await/1)

      # All should succeed and return same PID
      assert Enum.all?(results, &match?({:ok, _}, &1))

      device_pids = Enum.map(results, fn {:ok, pid} -> pid end)
      unique_pids = Enum.uniq(device_pids)

      # Should only have one unique PID
      assert length(unique_pids) == 1

      # Only one device should be created
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == 1
      assert stats.devices_created == 1
    end

    test "handles concurrent access to different ports", %{test_port: test_port} do
      ports = test_port..(test_port + 10) |> Enum.to_list()

      # Create tasks for different ports
      tasks =
        Enum.map(ports, fn port ->
          Task.async(fn ->
            LazyDevicePool.get_or_create_device(port)
          end)
        end)

      # Wait for all tasks
      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Should have created all devices
      stats = LazyDevicePool.get_stats()
      assert stats.active_count == length(ports)
      assert stats.devices_created == length(ports)
    end
  end
end
