defmodule SnmpKit.SnmpMgr.Engine do
  @moduledoc """
  The manager's shared UDP socket and response correlator.

  The engine owns one UDP socket. Callers (`SnmpKit.SnmpMgr.Multi`,
  `SnmpKit.SnmpMgr.V2Walk`) register a request id, send their PDU themselves
  on the socket from `get_socket/1`, and receive `{:snmp_response, id, data}`
  or `{:snmp_timeout, id}` in their mailbox. Responses arrive straight in the
  engine's mailbox; there is no forwarding hop.

  Datagrams from `{:unspec, _}` sources (ICMP errors surfaced by the socket)
  and empty datagrams are dropped and counted.

  ## Options
  - `:name` - process name (default: `SnmpKit.SnmpMgr.Engine`)
  - `:port` - local UDP port (default 0, ephemeral)
  - `:buffer_size` - socket receive buffer in bytes (default 4 MiB)
  - `:max_queue_depth` - mailbox depth treated as 100% for `health_check/1`
  """

  use GenServer
  require Logger

  @default_buffer_size 4 * 1024 * 1024
  @default_port 0
  @default_max_queue_depth 10_000

  defstruct [
    :name,
    :pending_requests,
    :metrics,
    :timeout_refs,
    :socket,
    :socket6,
    :port,
    :buffer_size,
    :max_queue_depth,
    :created_at
  ]

  @doc """
  Starts the Engine response correlator.

  ## Options
  - `:name` - Process name (default: __MODULE__)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a request for response correlation.

  ## Parameters
  - `engine` - Engine PID or name
  - `request_id` - Unique request identifier
  - `caller_pid` - Process to send response to
  - `timeout_ms` - Timeout in milliseconds (optional)

  ## Examples

      SnmpKit.SnmpMgr.Engine.register_request(engine, 12345, self(), 5000)
  """
  @spec register_request(GenServer.server(), integer(), pid(), non_neg_integer()) :: :ok
  def register_request(engine, request_id, caller_pid, timeout_ms \\ 5000) do
    GenServer.call(engine, {:register_request, request_id, caller_pid, timeout_ms})
  end

  @doc """
  Unregisters a request (used when caller times out locally).

  ## Parameters  
  - `engine` - Engine PID or name
  - `request_id` - Request identifier to unregister
  """
  @spec unregister_request(GenServer.server(), integer()) :: :ok
  def unregister_request(engine, request_id) do
    GenServer.cast(engine, {:unregister_request, request_id})
  end

  @doc """
  Gets engine statistics: pending request count, correlation metrics, socket
  counters (`:socket_stats`), the local `:port` and `:recv_queue_length`.
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(engine \\ __MODULE__) do
    GenServer.call(engine, :get_stats)
  end

  @doc "The shared UDP socket. Send request PDUs on it after `register_request/4`."
  @spec get_socket(GenServer.server(), :inet | :inet6) :: :gen_udp.socket() | {:error, term()}
  def get_socket(engine \\ __MODULE__, family \\ :inet)

  def get_socket(engine, :inet6) do
    GenServer.call(engine, {:get_socket, :inet6})
  end

  def get_socket(engine, :inet) do
    GenServer.call(engine, :get_socket)
  end

  @doc "The local UDP port the shared socket is bound to."
  @spec get_port(GenServer.server()) :: :inet.port_number()
  def get_port(engine \\ __MODULE__) do
    GenServer.call(engine, :get_port)
  end

  @doc "Socket buffer statistics: largest datagram seen relative to the receive buffer, mailbox depth."
  @spec get_buffer_stats(GenServer.server()) :: map()
  def get_buffer_stats(engine \\ __MODULE__) do
    GenServer.call(engine, :get_buffer_stats)
  end

  @doc """
  Health based on how many datagrams are waiting in the engine's mailbox
  relative to `:max_queue_depth`: `:healthy` (< 50%), `:warning` (< 80%),
  `:critical`, or `:error` if the socket is gone.
  """
  @spec health_check(GenServer.server()) :: :healthy | :warning | :critical | :error
  def health_check(engine \\ __MODULE__) do
    GenServer.call(engine, :health_check)
  end

  @doc """
  Gets the number of pending requests.
  """
  @spec pending_count(GenServer.server()) :: non_neg_integer()
  def pending_count(engine) do
    GenServer.call(engine, :pending_count)
  end

  @doc """
  Gracefully shuts down the engine.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(engine) do
    GenServer.call(engine, :stop)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    port = Keyword.get(opts, :port, @default_port)

    case create_socket(buffer_size, port) do
      {:ok, socket} ->
        {:ok, actual_port} = :inet.port(socket)
        Logger.info("Engine started on UDP port #{actual_port} (#{buffer_size} byte buffer)")

        {:ok,
         %__MODULE__{
           name: Keyword.get(opts, :name, __MODULE__),
           pending_requests: %{},
           metrics: initialize_metrics(),
           timeout_refs: %{},
           socket: socket,
           port: actual_port,
           buffer_size: buffer_size,
           max_queue_depth: Keyword.get(opts, :max_queue_depth, @default_max_queue_depth),
           created_at: System.monotonic_time(:millisecond)
         }}

      {:error, reason} ->
        Logger.error("Failed to open engine UDP socket on port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.timeout_refs, fn {_id, ref} -> Process.cancel_timer(ref) end)
    if state.socket, do: :gen_udp.close(state.socket)
    if state.socket6, do: :gen_udp.close(state.socket6)
    :ok
  end

  @impl true
  def handle_call({:register_request, request_id, caller_pid, timeout_ms}, _from, state) do
    # Register the request for correlation. The caller is monitored so a crash
    # releases its registrations instead of leaving them until timeout.
    pending_requests =
      Map.put(state.pending_requests, request_id, %{
        caller_pid: caller_pid,
        monitor_ref: Process.monitor(caller_pid),
        registered_at: System.monotonic_time(:millisecond)
      })

    # Schedule timeout
    timeout_ref = Process.send_after(self(), {:request_timeout, request_id}, timeout_ms)
    timeout_refs = Map.put(state.timeout_refs, request_id, timeout_ref)

    # Update metrics
    metrics = update_metrics(state.metrics, :requests_registered, 1)

    new_state = %{
      state
      | pending_requests: pending_requests,
        timeout_refs: timeout_refs,
        metrics: metrics
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    socket_stats =
      case :inet.getstat(state.socket, [:recv_cnt, :recv_oct, :send_cnt, :send_oct]) do
        {:ok, stats} -> stats
        {:error, _} -> []
      end

    stats = %{
      pending_requests: map_size(state.pending_requests),
      metrics: state.metrics,
      socket_stats: socket_stats,
      recv_queue_length: mailbox_depth(self()),
      buffer_size: state.buffer_size,
      port: state.port,
      uptime_ms: System.monotonic_time(:millisecond) - state.created_at
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_socket, _from, state), do: {:reply, state.socket, state}

  # The IPv6 socket is opened on first use so IPv4-only hosts never need one.
  @impl true
  def handle_call({:get_socket, :inet6}, _from, %{socket6: nil} = state) do
    case :gen_udp.open(0, [
           :binary,
           :inet6,
           {:ipv6_v6only, true},
           {:active, true},
           {:recbuf, state.buffer_size}
         ]) do
      {:ok, socket6} ->
        {:reply, socket6, %{state | socket6: socket6}}

      {:error, reason} ->
        Logger.error("Failed to open engine IPv6 UDP socket: #{inspect(reason)}")
        {:reply, nil, state}
    end
  end

  @impl true
  def handle_call({:get_socket, :inet6}, _from, state), do: {:reply, state.socket6, state}

  @impl true
  def handle_call(:get_port, _from, state), do: {:reply, state.port, state}

  @impl true
  def handle_call(:get_buffer_stats, _from, state) do
    buffer_stats =
      case :inet.getstat(state.socket, [:recv_max, :send_max, :recv_oct, :send_oct]) do
        {:ok, stats} -> stats
        {:error, _} -> []
      end

    recv_max = Keyword.get(buffer_stats, :recv_max, 0)
    utilization = if state.buffer_size > 0, do: recv_max / state.buffer_size * 100, else: 0

    {:reply,
     %{
       buffer_size: state.buffer_size,
       recv_queue_length: mailbox_depth(self()),
       recv_utilization_percent: utilization,
       max_queue_depth: state.max_queue_depth,
       buffer_stats: buffer_stats,
       port: state.port,
       uptime_ms: System.monotonic_time(:millisecond) - state.created_at
     }, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    depth = mailbox_depth(self())
    ratio = if state.max_queue_depth > 0, do: depth / state.max_queue_depth, else: 0

    status =
      cond do
        Port.info(state.socket) == nil -> :error
        ratio < 0.5 -> :healthy
        ratio < 0.8 -> :warning
        true -> :critical
      end

    {:reply,
     %{
       status: status,
       port: state.port,
       queue_depth: depth,
       max_queue_depth: state.max_queue_depth,
       uptime_ms: System.monotonic_time(:millisecond) - state.created_at
     }, state}
  end

  @impl true
  def handle_call(:pending_count, _from, state) do
    count = map_size(state.pending_requests)
    {:reply, count, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    # terminate/2 cancels timers and closes the socket
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:unregister_request, request_id}, state) do
    new_state = remove_request(state, request_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:udp, _socket, {:unspec, _}, _port, _data}, state) do
    # ICMP errors (unreachable hosts) surface as datagrams from :unspec
    {:noreply, %{state | metrics: update_metrics(state.metrics, :icmp_errors_dropped, 1)}}
  end

  @impl true
  def handle_info({:udp, _socket, _ip, _port, ""}, state) do
    {:noreply, %{state | metrics: update_metrics(state.metrics, :empty_packets_dropped, 1)}}
  end

  @impl true
  def handle_info({:udp_error, _socket, reason}, state) do
    Logger.debug("Engine socket reported #{inspect(reason)}")
    {:noreply, %{state | metrics: update_metrics(state.metrics, :icmp_errors_dropped, 1)}}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def handle_info({:udp, _socket, ip, port, data}, state) do
    # Handle incoming UDP responses
    Logger.debug(
      "Engine received UDP response from #{:inet.ntoa(ip)}:#{port}, #{byte_size(data)} bytes"
    )

    state = %{state | metrics: update_metrics(state.metrics, :responses_received, 1)}

    case decode_snmp_response(data) do
      {:ok, request_id, response_data} ->
        new_state = handle_correlated_response(state, request_id, response_data)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Failed to decode SNMP response: #{inspect(reason)}")
        metrics = update_metrics(state.metrics, :decode_failures, 1)
        {:noreply, %{state | metrics: metrics}}
    end
  end

  @impl true
  def handle_info({:request_timeout, request_id}, state) do
    # Handle request timeout
    case Map.get(state.pending_requests, request_id) do
      nil ->
        # Request already completed
        {:noreply, state}

      request_info ->
        # Send timeout to caller
        send(request_info.caller_pid, {:snmp_timeout, request_id})

        SnmpKit.Telemetry.execute([:engine, :timeout], %{count: 1}, %{
          request_id: request_id,
          target: Map.get(request_info, :target)
        })

        # Remove the request
        new_state = remove_request(state, request_id)

        # Update metrics
        metrics = update_metrics(new_state.metrics, :requests_timeout, 1)
        new_state = %{new_state | metrics: metrics}

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    dead =
      state.pending_requests
      |> Enum.filter(fn {_id, info} -> info.caller_pid == pid end)
      |> Enum.map(fn {id, _} -> id end)

    {:noreply, Enum.reduce(dead, state, &remove_request(&2, &1))}
  end

  @impl true
  def handle_info({:mock_response, request_id, response_data}, state) do
    # Handle mock response for testing
    new_state = handle_correlated_response(state, request_id, response_data)
    {:noreply, new_state}
  end

  # Private functions

  defp initialize_metrics() do
    %{
      requests_registered: 0,
      requests_completed: 0,
      requests_timeout: 0,
      decode_failures: 0,
      unknown_responses: 0,
      responses_received: 0,
      icmp_errors_dropped: 0,
      empty_packets_dropped: 0,
      avg_response_time: 0,
      last_reset: System.monotonic_time(:second)
    }
  end

  defp handle_correlated_response(state, request_id, response_data) do
    case Map.get(state.pending_requests, request_id) do
      nil ->
        Logger.warning("Received response for unknown request ID: #{request_id}")
        metrics = update_metrics(state.metrics, :unknown_responses, 1)
        %{state | metrics: metrics}

      request_info ->
        # Send response to caller
        send(request_info.caller_pid, {:snmp_response, request_id, response_data})

        # Calculate response time
        response_time = System.monotonic_time(:millisecond) - request_info.registered_at

        # Remove the request
        new_state = remove_request(state, request_id)

        # Update metrics
        metrics = update_metrics(new_state.metrics, :requests_completed, 1)
        metrics = update_avg_response_time(metrics, response_time)

        %{new_state | metrics: metrics}
    end
  end

  defp remove_request(state, request_id) do
    {info, pending_requests} = Map.pop(state.pending_requests, request_id)

    case info do
      %{monitor_ref: ref} when is_reference(ref) -> Process.demonitor(ref, [:flush])
      _ -> :ok
    end

    # Cancel and remove timeout
    case Map.get(state.timeout_refs, request_id) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    timeout_refs = Map.delete(state.timeout_refs, request_id)

    %{state | pending_requests: pending_requests, timeout_refs: timeout_refs}
  end

  defp decode_snmp_response(data) do
    case SnmpKit.SnmpLib.PDU.decode_message(data) do
      {:ok, %{pdu: %{type: :get_response} = pdu}} ->
        {:ok, pdu.request_id, extract_response_data(pdu)}

      {:ok, _not_a_response} ->
        {:error, :not_a_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_response_data(%{varbinds: varbinds}), do: Enum.map(varbinds, &format_varbind/1)

  defp format_varbind(varbind) do
    case varbind do
      {oid, type, value} -> {oid, type, value}
      %{oid: oid, type: type, value: value} -> {oid, type, value}
      _ -> varbind
    end
  end

  defp create_socket(buffer_size, port) do
    case :gen_udp.open(port, [
           :binary,
           {:active, true},
           {:recbuf, buffer_size},
           {:reuseaddr, true}
         ]) do
      {:ok, socket} ->
        case :inet.getopts(socket, [:recbuf]) do
          {:ok, [{:recbuf, actual}]} when actual < buffer_size ->
            Logger.warning("Requested UDP buffer size #{buffer_size}, got #{actual}")

          _ ->
            :ok
        end

        {:ok, socket}

      error ->
        error
    end
  end

  defp mailbox_depth(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, n} -> n
      nil -> 0
    end
  end

  defp update_metrics(metrics, key, increment) do
    Map.update(metrics, key, increment, fn current -> current + increment end)
  end

  defp update_avg_response_time(metrics, new_time) do
    current_avg = metrics.avg_response_time
    completed = metrics.requests_completed

    new_avg =
      if completed <= 1 do
        new_time
      else
        (current_avg * (completed - 1) + new_time) / completed
      end

    Map.put(metrics, :avg_response_time, new_avg)
  end
end
