defmodule SnmpKit.SnmpMgr.SocketManager do
  @moduledoc """
  Manages shared UDP sockets for SNMP operations.

  Provides centralized socket lifecycle management with configurable
  buffer sizes and health monitoring. Eliminates the need for individual
  processes to manage their own sockets.
  """

  use GenServer
  require Logger

  # 4MB
  @default_buffer_size 4 * 1024 * 1024
  # Let OS assign port
  @default_port 0

  defstruct [
    :socket,
    :buffer_size,
    :port,
    :stats,
    :created_at,
    :engine_pid,
    :engine_monitor,
    :max_queue_depth
  ]

  # Datagrams are forwarded to the engine only while its mailbox is below this
  # depth; beyond it they are dropped (and counted) rather than queued forever.
  @default_max_queue_depth 10_000

  @doc """
  Starts the SocketManager GenServer.

  ## Options
  - `:buffer_size` - UDP receive buffer size in bytes (default: 4MB)
  - `:port` - Local port to bind (default: 0 for OS assignment)
  - `:name` - Process name (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the shared UDP socket.

  Returns the socket reference that can be used for sending
  SNMP packets. The socket is configured with appropriate
  buffer sizes and options.

  ## Examples

      iex> socket = SnmpKit.SnmpMgr.SocketManager.get_socket()
      iex> :gen_udp.send(socket, {192, 168, 1, 1}, 161, packet)
  """
  def get_socket(manager \\ __MODULE__) do
    GenServer.call(manager, :get_socket)
  end

  @doc """
  Gets socket statistics and health information.

  Returns information about buffer usage, packet counts,
  and socket health metrics.
  """
  def get_stats(manager \\ __MODULE__) do
    GenServer.call(manager, :get_stats)
  end

  @doc """
  Gets detailed UDP buffer utilization metrics.

  Returns buffer usage, queue lengths, and utilization percentages.
  """
  def get_buffer_stats(manager \\ __MODULE__) do
    GenServer.call(manager, :get_buffer_stats)
  end

  @doc """
  Gets the local port the socket is bound to.
  """
  def get_port(manager \\ __MODULE__) do
    GenServer.call(manager, :get_port)
  end

  @doc """
  Checks if the socket is healthy and operational.
  """
  def health_check(manager \\ __MODULE__) do
    GenServer.call(manager, :health_check)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    port = Keyword.get(opts, :port, @default_port)
    max_queue_depth = Keyword.get(opts, :max_queue_depth, @default_max_queue_depth)

    case create_socket(buffer_size, port) do
      {:ok, socket} ->
        {:ok, actual_port} = :inet.port(socket)

        Logger.info(
          "SocketManager started on port #{actual_port} with #{buffer_size} byte buffer"
        )

        state = %__MODULE__{
          socket: socket,
          buffer_size: buffer_size,
          port: actual_port,
          stats: initialize_stats(),
          created_at: System.monotonic_time(:millisecond),
          engine_pid: nil,
          engine_monitor: nil,
          max_queue_depth: max_queue_depth
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to create UDP socket: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_socket, _from, state) do
    {:reply, state.socket, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Get current socket statistics
    socket_stats =
      case :inet.getstat(state.socket, [:recv_cnt, :recv_oct, :send_cnt, :send_oct]) do
        {:ok, stats} -> stats
        {:error, _} -> []
      end

    # Datagrams received but not yet forwarded (:recv_q is not a valid
    # inet:getstat/2 option; the mailbox depth is the real queue here)
    recv_queue = mailbox_depth(self())

    stats = %{
      socket_stats: socket_stats,
      recv_queue_length: recv_queue,
      buffer_size: state.buffer_size,
      port: state.port,
      uptime_ms: System.monotonic_time(:millisecond) - state.created_at,
      custom_stats: state.stats
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_buffer_stats, _from, state) do
    # Get detailed buffer statistics
    buffer_stats =
      case :inet.getstat(state.socket, [:recv_max, :send_max, :recv_oct, :send_oct]) do
        {:ok, stats} -> stats
        {:error, _} -> []
      end

    recv_queue = mailbox_depth(self())
    send_queue = 0

    # Largest datagram seen relative to the socket buffer: bytes against bytes
    recv_max = Keyword.get(buffer_stats, :recv_max, 0)
    recv_utilization = if state.buffer_size > 0, do: recv_max / state.buffer_size * 100, else: 0

    detailed_stats = %{
      buffer_size: state.buffer_size,
      recv_queue_length: recv_queue,
      send_queue_length: send_queue,
      recv_utilization_percent: recv_utilization,
      max_queue_depth: state.max_queue_depth,
      engine_queue_length: mailbox_depth(state.engine_pid),
      buffer_stats: buffer_stats,
      port: state.port,
      uptime_ms: System.monotonic_time(:millisecond) - state.created_at
    }

    {:reply, detailed_stats, state}
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    # Health is the number of datagrams waiting (here and in the engine)
    # relative to the configured queue depth: like units on both sides.
    queue_depth = mailbox_depth(self()) + mailbox_depth(state.engine_pid)
    queue_ratio = if state.max_queue_depth > 0, do: queue_depth / state.max_queue_depth, else: 0

    health =
      cond do
        Port.info(state.socket) == nil -> :error
        queue_ratio < 0.5 -> :healthy
        queue_ratio < 0.8 -> :warning
        true -> :critical
      end

    result = %{
      status: health,
      port: state.port,
      queue_depth: queue_depth,
      max_queue_depth: state.max_queue_depth,
      uptime_ms: System.monotonic_time(:millisecond) - state.created_at
    }

    {:reply, result, state}
  end

  @impl true
  def handle_info({:udp, _socket, {:unspec, _}, _port, _data}, state) do
    # Drop ICMP error responses (unreachable hosts return these)
    # These have :unspec as the source and would flood the Engine's mailbox
    updated_stats = update_stats(state.stats, :icmp_errors_dropped, 1)
    {:noreply, %{state | stats: updated_stats}}
  end

  @impl true
  def handle_info({:udp, _socket, _ip, _port, ""}, state) do
    # Drop empty UDP packets - these are invalid SNMP responses
    updated_stats = update_stats(state.stats, :empty_packets_dropped, 1)
    {:noreply, %{state | stats: updated_stats}}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) do
    # Forward datagrams to the engine for response correlation. The engine pid
    # is cached and monitored instead of looked up per packet, and forwarding
    # sheds load once the engine's mailbox is past max_queue_depth.
    state = %{state | stats: update_stats(state.stats, :responses_received, 1)}
    {state, engine_pid} = resolve_engine(state)

    stats =
      cond do
        engine_pid == nil ->
          Logger.warning("Engine not found, dropping UDP response from #{:inet.ntoa(ip)}:#{port}")
          update_stats(state.stats, :dropped_no_engine, 1)

        mailbox_depth(engine_pid) >= state.max_queue_depth ->
          Logger.debug("Engine mailbox over #{state.max_queue_depth}, shedding datagram")
          update_stats(state.stats, :dropped_overload, 1)

        true ->
          send(engine_pid, {:udp, socket, ip, port, data})
          state.stats
      end

    {:noreply, %{state | stats: stats}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{engine_monitor: ref} = state) do
    {:noreply, %{state | engine_pid: nil, engine_monitor: nil}}
  end

  @impl true
  def handle_info({:udp_error, _socket, reason}, state) do
    Logger.debug("SocketManager socket reported #{inspect(reason)}")
    {:noreply, %{state | stats: update_stats(state.stats, :icmp_errors_dropped, 1)}}
  end

  @impl true
  def handle_info(_other, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SocketManager terminating: #{inspect(reason)}")

    if state.socket do
      :gen_udp.close(state.socket)
    end

    :ok
  end

  # Private functions

  defp create_socket(buffer_size, port) do
    socket_opts = [
      :binary,
      {:active, true},
      {:recbuf, buffer_size},
      {:reuseaddr, true}
    ]

    case :gen_udp.open(port, socket_opts) do
      {:ok, socket} ->
        # Verify actual buffer size
        case :inet.getopts(socket, [:recbuf]) do
          {:ok, [{:recbuf, actual_size}]} ->
            if actual_size < buffer_size do
              Logger.warning("Requested buffer size #{buffer_size}, got #{actual_size}")
            end

            {:ok, socket}

          {:error, reason} ->
            Logger.warning("Could not verify buffer size: #{inspect(reason)}")
            {:ok, socket}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp initialize_stats() do
    %{
      responses_received: 0,
      icmp_errors_dropped: 0,
      empty_packets_dropped: 0,
      dropped_no_engine: 0,
      dropped_overload: 0,
      last_reset: System.monotonic_time(:second)
    }
  end

  # EngineV2 (new) first, Engine (old) as fallback; cached until it goes down.
  defp resolve_engine(%{engine_pid: pid} = state) when is_pid(pid), do: {state, pid}

  defp resolve_engine(state) do
    case Process.whereis(SnmpKit.SnmpMgr.EngineV2) || Process.whereis(SnmpKit.SnmpMgr.Engine) do
      nil -> {state, nil}
      pid -> {%{state | engine_pid: pid, engine_monitor: Process.monitor(pid)}, pid}
    end
  end

  defp mailbox_depth(nil), do: 0

  defp mailbox_depth(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, n} -> n
      nil -> 0
    end
  end

  defp update_stats(stats, key, increment) do
    Map.update(stats, key, increment, fn current -> current + increment end)
  end
end
