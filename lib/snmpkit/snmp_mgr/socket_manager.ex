defmodule SnmpKit.SnmpMgr.SocketManager do
  @moduledoc """
  Manages shared UDP sockets for SNMP operations.
  
  Provides centralized socket lifecycle management with configurable
  buffer sizes and health monitoring. Eliminates the need for individual
  processes to manage their own sockets.
  """
  
  use GenServer
  require Logger
  
  @default_buffer_size 4 * 1024 * 1024  # 4MB
  @default_port 0  # Let OS assign port
  
  defstruct [
    :socket,
    :buffer_size,
    :port,
    :stats,
    :created_at
  ]
  
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
    
    case create_socket(buffer_size, port) do
      {:ok, socket} ->
        {:ok, actual_port} = :inet.port(socket)
        
        Logger.info("SocketManager started on port #{actual_port} with #{buffer_size} byte buffer")
        
        state = %__MODULE__{
          socket: socket,
          buffer_size: buffer_size,
          port: actual_port,
          stats: initialize_stats(),
          created_at: System.monotonic_time(:millisecond)
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
    socket_stats = case :inet.getstat(state.socket, [:recv_cnt, :recv_oct, :send_cnt, :send_oct]) do
      {:ok, stats} -> stats
      {:error, _} -> []
    end
    
    # Get receive queue length
    recv_queue = case :inet.getstat(state.socket, [:recv_q]) do
      {:ok, [{:recv_q, count}]} -> count
      {:error, _} -> 0
    end
    
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
    buffer_stats = case :inet.getstat(state.socket, [:recv_q, :send_q, :recv_max, :send_max]) do
      {:ok, stats} -> stats
      {:error, _} -> []
    end
    
    recv_queue = Keyword.get(buffer_stats, :recv_q, 0)
    send_queue = Keyword.get(buffer_stats, :send_q, 0)
    
    # Calculate utilization percentages
    recv_utilization = if state.buffer_size > 0, do: (recv_queue / state.buffer_size) * 100, else: 0
    
    detailed_stats = %{
      buffer_size: state.buffer_size,
      recv_queue_length: recv_queue,
      send_queue_length: send_queue,
      recv_utilization_percent: recv_utilization,
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
    health = case :inet.getstat(state.socket, [:recv_q]) do
      {:ok, [{:recv_q, queue_length}]} ->
        # Consider healthy if receive queue is not full
        # (rough heuristic: less than 80% of buffer size)
        queue_ratio = queue_length / state.buffer_size
        
        cond do
          queue_ratio < 0.5 -> :healthy
          queue_ratio < 0.8 -> :warning
          true -> :critical
        end
        
      {:error, reason} ->
        Logger.warning("Socket health check failed: #{inspect(reason)}")
        :error
    end
    
    result = %{
      status: health,
      port: state.port,
      uptime_ms: System.monotonic_time(:millisecond) - state.created_at
    }
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) do
    # Forward UDP messages to the Engine for response correlation
    # This ensures all UDP responses go through the Engine
    # Try both EngineV2 (new) and Engine (old) for compatibility
    engine_pid = Process.whereis(SnmpKit.SnmpMgr.EngineV2) || Process.whereis(SnmpKit.SnmpMgr.Engine)
    
    case engine_pid do
      nil ->
        Logger.warning("Engine not found, dropping UDP response from #{:inet.ntoa(ip)}:#{port}")
        
      pid ->
        send(pid, {:udp, socket, ip, port, data})
    end
    
    # Update stats
    updated_stats = update_stats(state.stats, :responses_received, 1)
    new_state = %{state | stats: updated_stats}
    
    {:noreply, new_state}
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
      last_reset: System.monotonic_time(:second)
    }
  end
  
  defp update_stats(stats, key, increment) do
    Map.update(stats, key, increment, fn current -> current + increment end)
  end
end