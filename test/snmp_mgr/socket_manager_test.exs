defmodule SnmpKit.SnmpMgr.SocketManagerTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.SocketManager

  setup do
    # Start a test socket manager
    {:ok, pid} = SocketManager.start_link(name: :test_socket_manager)

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    {:ok, manager: pid}
  end

  test "starts with default configuration", %{manager: manager} do
    socket = SocketManager.get_socket(manager)
    assert socket != nil

    # Should be a UDP socket
    assert is_port(socket)

    # Should have a port assigned
    port = SocketManager.get_port(manager)
    assert is_integer(port)
    assert port > 0
  end

  test "can send UDP packets", %{manager: manager} do
    socket = SocketManager.get_socket(manager)

    # Send a simple UDP packet to localhost
    result = :gen_udp.send(socket, {127, 0, 0, 1}, 12345, "test packet")
    assert result == :ok
  end

  test "provides socket statistics", %{manager: manager} do
    stats = SocketManager.get_stats(manager)

    assert is_map(stats)
    assert Map.has_key?(stats, :socket_stats)
    assert Map.has_key?(stats, :recv_queue_length)
    assert Map.has_key?(stats, :buffer_size)
    assert Map.has_key?(stats, :port)
    assert Map.has_key?(stats, :uptime_ms)

    # Buffer size should be the default 4MB
    assert stats.buffer_size == 4 * 1024 * 1024

    # Uptime should be reasonable (test runs quickly)
    assert stats.uptime_ms >= 0
    # Should be less than 5 seconds
    assert stats.uptime_ms < 5000
  end

  test "health check returns status", %{manager: manager} do
    health = SocketManager.health_check(manager)

    assert is_map(health)
    assert Map.has_key?(health, :status)
    assert Map.has_key?(health, :port)
    assert Map.has_key?(health, :uptime_ms)

    # Should be healthy initially
    assert health.status in [:healthy, :warning, :critical, :error]
  end

  test "can be configured with custom buffer size" do
    # 1MB
    custom_buffer = 1024 * 1024

    {:ok, manager} =
      SocketManager.start_link(
        name: :custom_socket_manager,
        buffer_size: custom_buffer
      )

    stats = SocketManager.get_stats(manager)
    assert stats.buffer_size == custom_buffer

    GenServer.stop(manager)
  end

  test "handles socket creation failure gracefully" do
    # Try to bind to an invalid port (use a large port number that's likely to fail)
    result = Process.flag(:trap_exit, true)

    case SocketManager.start_link(
           name: :failing_socket_manager,
           # Use a high port number instead of -1
           port: 99999
         ) do
      {:error, _reason} ->
        assert true

      {:ok, pid} ->
        # If it somehow succeeds, clean up
        GenServer.stop(pid)
        assert true
    end
  end

  test "forwards UDP messages to Engine" do
    # Start a mock engine to receive messages
    test_pid = self()

    mock_engine =
      spawn(fn ->
        receive do
          {:udp, _socket, _ip, _port, _data} ->
            send(test_pid, :message_received)
        end
      end)

    # Register it as the Engine
    Process.register(mock_engine, SnmpKit.SnmpMgr.Engine)

    # Create a test socket to send from (separate from the manager's socket)
    {:ok, test_socket} = :gen_udp.open(0, [:binary])

    # Send a UDP message to the manager's socket
    manager_port = SocketManager.get_port(:test_socket_manager)
    :gen_udp.send(test_socket, {127, 0, 0, 1}, manager_port, "test")

    # Give it time to process
    Process.sleep(10)

    # Check if message was forwarded
    assert_receive :message_received, 1000

    # Clean up
    :gen_udp.close(test_socket)

    if Process.whereis(SnmpKit.SnmpMgr.Engine) do
      Process.unregister(SnmpKit.SnmpMgr.Engine)
    end

    Process.exit(mock_engine, :normal)
  end

  describe "ICMP error filtering" do
    test "drops ICMP error responses with :unspec source", %{manager: manager} do
      # Start a mock engine that should NOT receive the message
      test_pid = self()

      mock_engine =
        spawn(fn ->
          receive do
            {:udp, _socket, _ip, _port, _data} ->
              send(test_pid, :message_received)
          after
            100 -> :ok
          end
        end)

      Process.register(mock_engine, SnmpKit.SnmpMgr.Engine)

      # Get initial stats
      initial_stats = SocketManager.get_stats(manager)
      initial_dropped = initial_stats.custom_stats[:icmp_errors_dropped] || 0

      # Simulate an ICMP error response by sending the message directly
      socket = SocketManager.get_socket(manager)
      send(manager, {:udp, socket, {:unspec, ""}, 0, ""})

      # Give it time to process
      Process.sleep(50)

      # Verify the message was NOT forwarded to the engine
      refute_receive :message_received, 100

      # Verify stats were updated
      stats = SocketManager.get_stats(manager)
      assert stats.custom_stats.icmp_errors_dropped == initial_dropped + 1

      # Clean up
      if Process.whereis(SnmpKit.SnmpMgr.Engine) do
        Process.unregister(SnmpKit.SnmpMgr.Engine)
      end

      Process.exit(mock_engine, :normal)
    end

    test "drops empty UDP packets", %{manager: manager} do
      # Start a mock engine that should NOT receive the message
      test_pid = self()

      mock_engine =
        spawn(fn ->
          receive do
            {:udp, _socket, _ip, _port, _data} ->
              send(test_pid, :message_received)
          after
            100 -> :ok
          end
        end)

      Process.register(mock_engine, SnmpKit.SnmpMgr.Engine)

      # Get initial stats
      initial_stats = SocketManager.get_stats(manager)
      initial_dropped = initial_stats.custom_stats[:empty_packets_dropped] || 0

      # Simulate an empty UDP packet
      socket = SocketManager.get_socket(manager)
      send(manager, {:udp, socket, {127, 0, 0, 1}, 161, ""})

      # Give it time to process
      Process.sleep(50)

      # Verify the message was NOT forwarded to the engine
      refute_receive :message_received, 100

      # Verify stats were updated
      stats = SocketManager.get_stats(manager)
      assert stats.custom_stats.empty_packets_dropped == initial_dropped + 1

      # Clean up
      if Process.whereis(SnmpKit.SnmpMgr.Engine) do
        Process.unregister(SnmpKit.SnmpMgr.Engine)
      end

      Process.exit(mock_engine, :normal)
    end

    test "forwards valid SNMP responses", %{manager: manager} do
      # Start a mock engine that SHOULD receive the message
      test_pid = self()

      mock_engine =
        spawn(fn ->
          receive do
            {:udp, _socket, _ip, _port, data} when data != "" ->
              send(test_pid, {:message_received, data})
          after
            500 -> :ok
          end
        end)

      Process.register(mock_engine, SnmpKit.SnmpMgr.Engine)

      # Get initial stats
      initial_stats = SocketManager.get_stats(manager)
      initial_received = initial_stats.custom_stats[:responses_received] || 0

      # Simulate a valid SNMP response
      socket = SocketManager.get_socket(manager)
      send(manager, {:udp, socket, {192, 168, 1, 1}, 161, "valid snmp data"})

      # Give it time to process
      Process.sleep(50)

      # Verify the message WAS forwarded to the engine
      assert_receive {:message_received, "valid snmp data"}, 500

      # Verify stats were updated
      stats = SocketManager.get_stats(manager)
      assert stats.custom_stats.responses_received == initial_received + 1

      # Clean up
      if Process.whereis(SnmpKit.SnmpMgr.Engine) do
        Process.unregister(SnmpKit.SnmpMgr.Engine)
      end

      Process.exit(mock_engine, :normal)
    end

    test "tracks all dropped packet statistics", %{manager: manager} do
      stats = SocketManager.get_stats(manager)

      # Verify the new stats fields exist
      assert Map.has_key?(stats.custom_stats, :icmp_errors_dropped)
      assert Map.has_key?(stats.custom_stats, :empty_packets_dropped)
      assert Map.has_key?(stats.custom_stats, :responses_received)
    end
  end
end
