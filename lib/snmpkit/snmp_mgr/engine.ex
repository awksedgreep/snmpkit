defmodule SnmpKit.SnmpKit.SnmpMgr.Engine do
  @moduledoc """
  High-performance streaming PDU engine with request routing and connection pooling.

  This module provides the core infrastructure for handling large volumes of SNMP
  requests efficiently through connection pooling, request batching, and intelligent
  routing strategies.
  """

  use GenServer
  require Logger

  @default_pool_size 10
  @default_max_requests_per_second 100
  @default_request_timeout 5000
  @default_batch_size 50
  @default_batch_timeout 100

  defstruct [
    :name,
    :pool_size,
    :max_rps,
    :request_timeout,
    :batch_size,
    :batch_timeout,
    :connections,
    :request_queue,
    :batch_timer,
    :metrics,
    :circuit_breakers,
    :routes
  ]

  @doc """
  Starts the streaming PDU engine.

  ## Options
  - `:pool_size` - Number of UDP socket connections to maintain (default: 10)
  - `:max_rps` - Maximum requests per second (default: 100)
  - `:request_timeout` - Individual request timeout in ms (default: 5000)
  - `:batch_size` - Maximum requests per batch (default: 50)
  - `:batch_timeout` - Maximum time to wait for batch in ms (default: 100)

  ## Examples

      {:ok, engine} = SnmpKit.SnmpKit.SnmpMgr.Engine.start_link(
        pool_size: 20,
        max_rps: 200,
        batch_size: 100
      )
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Submits a request to the engine for processing.

  ## Parameters
  - `engine` - Engine PID or name
  - `request` - Request specification map
  - `opts` - Request options

  ## Examples

      request = %{
        type: :get,
        target: "192.168.1.1",
        oid: "1.3.6.1.2.1.1.1.0",
        community: "public"
      }

      {:ok, ref} = SnmpKit.SnmpKit.SnmpMgr.Engine.submit_request(engine, request)
  """
  def submit_request(engine, request, opts \\ []) do
    GenServer.call(engine, {:submit_request, request, opts})
  end

  @doc """
  Submits multiple requests as a batch.

  ## Parameters
  - `engine` - Engine PID or name
  - `requests` - List of request specification maps
  - `opts` - Batch options

  ## Examples

      requests = [
        %{type: :get, target: "device1", oid: "sysDescr.0"},
        %{type: :get, target: "device2", oid: "sysDescr.0"}
      ]

      {:ok, batch_ref} = SnmpKit.SnmpKit.SnmpMgr.Engine.submit_batch(engine, requests)
  """
  def submit_batch(engine, requests, opts \\ []) do
    GenServer.call(engine, {:submit_batch, requests, opts})
  end

  @doc """
  Gets engine statistics and metrics.
  """
  def get_stats(engine) do
    GenServer.call(engine, :get_stats)
  end

  @doc """
  Gets connection pool status.
  """
  def get_pool_status(engine) do
    GenServer.call(engine, :get_pool_status)
  end

  @doc """
  Gracefully shuts down the engine.
  """
  def stop(engine) do
    GenServer.call(engine, :stop)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    max_rps = Keyword.get(opts, :max_requests_per_second, @default_max_requests_per_second)
    request_timeout = Keyword.get(opts, :request_timeout, @default_request_timeout)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    batch_timeout = Keyword.get(opts, :batch_timeout, @default_batch_timeout)

    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__),
      pool_size: pool_size,
      max_rps: max_rps,
      request_timeout: request_timeout,
      batch_size: batch_size,
      batch_timeout: batch_timeout,
      connections: initialize_connection_pool(pool_size),
      request_queue: :queue.new(),
      batch_timer: nil,
      metrics: initialize_metrics(),
      circuit_breakers: %{},
      routes: %{}
    }

    Logger.info("SnmpMgr Engine started with pool_size=#{pool_size}, max_rps=#{max_rps}")

    {:ok, state}
  end

  @impl true
  def handle_call({:submit_request, request, opts}, from, state) do
    request_id = generate_request_id()

    enriched_request =
      Map.merge(request, %{
        request_id: request_id,
        # Keep reference for correlation but use request_id for SNMP
        ref: make_ref(),
        from: from,
        submitted_at: System.monotonic_time(:millisecond),
        opts: opts
      })

    new_queue = :queue.in(enriched_request, state.request_queue)
    new_state = %{state | request_queue: new_queue}

    # Update metrics
    metrics = update_metrics(state.metrics, :requests_submitted, 1)
    new_state = %{new_state | metrics: metrics}

    # Start batch timer if not already running
    new_state = maybe_start_batch_timer(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:submit_batch, requests, opts}, from, state) do
    batch_ref = make_ref()

    enriched_requests =
      requests
      |> Enum.with_index()
      |> Enum.map(fn {request, index} ->
        Map.merge(request, %{
          request_id: generate_request_id(),
          ref: make_ref(),
          batch_ref: batch_ref,
          batch_index: index,
          from: from,
          submitted_at: System.monotonic_time(:millisecond),
          opts: opts
        })
      end)

    new_queue =
      Enum.reduce(enriched_requests, state.request_queue, fn req, queue ->
        :queue.in(req, queue)
      end)

    new_state = %{state | request_queue: new_queue}

    # Update metrics
    metrics = update_metrics(state.metrics, :requests_submitted, length(requests))
    metrics = update_metrics(metrics, :batches_submitted, 1)
    new_state = %{new_state | metrics: metrics}

    # Start batch timer if not already running
    new_state = maybe_start_batch_timer(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      queue_length: :queue.len(state.request_queue),
      active_connections: count_active_connections(state.connections),
      total_connections: map_size(state.connections),
      metrics: state.metrics,
      circuit_breakers: map_size(state.circuit_breakers)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_pool_status, _from, state) do
    pool_status =
      state.connections
      |> Enum.map(fn {id, conn} ->
        %{
          id: id,
          status: conn.status,
          active_requests: length(conn.active_requests),
          last_used: conn.last_used,
          error_count: conn.error_count
        }
      end)

    {:reply, pool_status, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    # Clean up connections
    Enum.each(state.connections, fn {_id, conn} ->
      if conn.socket do
        :gen_udp.close(conn.socket)
      end
    end)

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(:process_batch, state) do
    new_state = %{state | batch_timer: nil}
    new_state = process_queued_requests(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) do
    # Handle incoming UDP responses
    new_state = handle_udp_response(state, socket, ip, port, data)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:request_timeout, ref}, state) do
    # Handle request timeouts
    new_state = handle_request_timeout(state, ref)
    {:noreply, new_state}
  end

  # Private functions

  defp initialize_connection_pool(pool_size) do
    1..pool_size
    |> Enum.map(fn id ->
      {id,
       %{
         id: id,
         socket: nil,
         status: :idle,
         active_requests: [],
         last_used: 0,
         error_count: 0,
         created_at: System.monotonic_time(:millisecond)
       }}
    end)
    |> Enum.into(%{})
  end

  defp initialize_metrics() do
    %{
      requests_submitted: 0,
      requests_processed: 0,
      requests_completed: 0,
      requests_failed: 0,
      requests_timeout: 0,
      batches_submitted: 0,
      batches_processed: 0,
      avg_response_time: 0,
      last_reset: System.monotonic_time(:second)
    }
  end

  defp maybe_start_batch_timer(state) do
    if state.batch_timer == nil and :queue.len(state.request_queue) > 0 do
      timer = Process.send_after(self(), :process_batch, state.batch_timeout)
      %{state | batch_timer: timer}
    else
      state
    end
  end

  defp process_queued_requests(state) do
    queue_length = :queue.len(state.request_queue)

    if queue_length > 0 do
      batch_size = min(queue_length, state.batch_size)
      {requests, remaining_queue} = extract_requests(state.request_queue, batch_size)

      # Route and execute requests
      new_state = %{state | request_queue: remaining_queue}
      new_state = route_and_execute_requests(new_state, requests)

      # Update metrics
      metrics = update_metrics(new_state.metrics, :batches_processed, 1)
      metrics = update_metrics(metrics, :requests_processed, length(requests))
      new_state = %{new_state | metrics: metrics}

      # Schedule next batch if queue is not empty
      if :queue.len(remaining_queue) > 0 do
        maybe_start_batch_timer(new_state)
      else
        new_state
      end
    else
      state
    end
  end

  defp extract_requests(queue, count) do
    extract_requests(queue, count, [])
  end

  defp extract_requests(queue, 0, acc) do
    {Enum.reverse(acc), queue}
  end

  defp extract_requests(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, request}, new_queue} ->
        extract_requests(new_queue, count - 1, [request | acc])

      {:empty, queue} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp route_and_execute_requests(state, requests) do
    # Group requests by target for batching
    grouped_requests = Enum.group_by(requests, fn req -> req.target end)

    Enum.reduce(grouped_requests, state, fn {target, target_requests}, acc_state ->
      execute_target_requests(acc_state, target, target_requests)
    end)
  end

  defp execute_target_requests(state, target, requests) do
    # Check circuit breaker
    if circuit_breaker_allows?(state.circuit_breakers, target) do
      # Get available connection
      case get_available_connection(state.connections, target) do
        {:ok, conn_id, connection} ->
          execute_requests_on_connection(state, conn_id, connection, requests)

        {:error, :no_available_connections} ->
          # Queue requests for retry or fail them
          handle_no_connections(state, requests)
      end
    else
      # Circuit breaker is open, fail requests immediately
      fail_requests(state, requests, {:error, :circuit_breaker_open})
    end
  end

  defp execute_requests_on_connection(state, conn_id, connection, requests) do
    # Ensure socket is open
    {:ok, socket} = ensure_socket_open(connection)

    # Send requests
    updated_connection = %{
      connection
      | # Store the socket in the connection
        socket: socket,
        status: :active,
        active_requests: connection.active_requests ++ requests,
        last_used: System.monotonic_time(:millisecond)
    }

    new_connections = Map.put(state.connections, conn_id, updated_connection)
    new_state = %{state | connections: new_connections}

    # Actually send the SNMP requests
    Enum.each(requests, fn request ->
      send_snmp_request(socket, request)
      schedule_request_timeout(request.ref, state.request_timeout)
    end)

    new_state
  end

  defp get_available_connection(connections, _target) do
    # Simple round-robin selection of idle connections
    idle_connections =
      connections
      |> Enum.filter(fn {_id, conn} -> conn.status == :idle end)
      |> Enum.sort_by(fn {_id, conn} -> conn.last_used end)

    case idle_connections do
      [{conn_id, connection} | _] ->
        {:ok, conn_id, connection}

      [] ->
        # Try to find least busy connection
        case Enum.min_by(connections, fn {_id, conn} -> length(conn.active_requests) end) do
          {conn_id, connection} when length(connection.active_requests) < 10 ->
            {:ok, conn_id, connection}

          _ ->
            {:error, :no_available_connections}
        end
    end
  end

  defp ensure_socket_open(connection) do
    if connection.socket do
      {:ok, connection.socket}
    else
      case :gen_udp.open(0, [:binary, {:active, true}]) do
        {:ok, socket} -> {:ok, socket}
        error -> error
      end
    end
  end

  defp send_snmp_request(socket, request) do
    # This is a simplified version - real implementation would use SnmpKit.SnmpKit.SnmpMgr.Core
    target = resolve_target(request.target)

    case build_snmp_message(request) do
      {:ok, message} ->
        # Ensure host is in the correct format for gen_udp.send
        resolved_host =
          case target.host do
            host when is_binary(host) -> String.to_charlist(host)
            host when is_list(host) -> host
            host when is_tuple(host) -> host
            host -> host
          end

        :gen_udp.send(socket, resolved_host, target.port, message)

      {:error, reason} ->
        Logger.error("Failed to build SNMP message: #{inspect(reason)}")
        GenServer.reply(request.from, {:error, reason})
    end
  end

  defp build_snmp_message(request) do
    # Use existing PDU building functionality
    case request.type do
      :get ->
        pdu = SnmpKit.SnmpLib.PDU.build_get_request(request.oid, request.request_id)
        message = SnmpKit.SnmpLib.PDU.build_message(pdu, request.community || "public", :v2c)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      :get_bulk ->
        max_rep = Map.get(request, :max_repetitions, 10)

        pdu =
          SnmpKit.SnmpLib.PDU.build_get_bulk_request(request.oid, request.request_id, 0, max_rep)

        message = SnmpKit.SnmpLib.PDU.build_message(pdu, request.community || "public", :v2c)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      _ ->
        {:error, {:unsupported_request_type, request.type}}
    end
  end

  defp resolve_target(target) when is_binary(target) do
    case SnmpKit.SnmpKit.SnmpMgr.Target.parse(target) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{host: target, port: 161}
    end
  end

  defp resolve_target(target), do: target

  defp schedule_request_timeout(ref, timeout) do
    Process.send_after(self(), {:request_timeout, ref}, timeout)
  end

  defp handle_udp_response(state, socket, _ip, _port, data) do
    case SnmpKit.SnmpLib.PDU.decode_message(data) do
      {:ok, message} ->
        handle_snmp_response(state, socket, message)

      {:error, reason} ->
        Logger.warning("Failed to decode SNMP response: #{inspect(reason)}")
        state
    end
  end

  defp handle_snmp_response(state, _socket, message) do
    request_id = message.data.request_id

    # Find the connection and request
    case find_request_by_id(state.connections, request_id) do
      {:ok, conn_id, request} ->
        # Send response to caller
        GenServer.reply(request.from, {:ok, message.data})

        # Update connection and metrics
        update_connection_after_response(state, conn_id, request)

      {:error, :not_found} ->
        Logger.warning("Received response for unknown request ID: #{request_id}")
        state
    end
  end

  defp find_request_by_id(connections, request_id) do
    Enum.find_value(connections, fn {conn_id, conn} ->
      case Enum.find(conn.active_requests, fn req -> req.request_id == request_id end) do
        nil -> nil
        request -> {:ok, conn_id, request}
      end
    end) || {:error, :not_found}
  end

  defp update_connection_after_response(state, conn_id, completed_request) do
    connection = Map.get(state.connections, conn_id)
    updated_requests = List.delete(connection.active_requests, completed_request)

    new_status = if Enum.empty?(updated_requests), do: :idle, else: :active

    updated_connection = %{
      connection
      | active_requests: updated_requests,
        status: new_status,
        # Reset error count on successful response
        error_count: 0
    }

    new_connections = Map.put(state.connections, conn_id, updated_connection)

    # Update metrics
    response_time = System.monotonic_time(:millisecond) - completed_request.submitted_at
    metrics = update_metrics(state.metrics, :requests_completed, 1)
    metrics = update_avg_response_time(metrics, response_time)

    %{state | connections: new_connections, metrics: metrics}
  end

  defp handle_request_timeout(state, ref) do
    # Find and fail timed out request
    case find_request_by_id(state.connections, ref) do
      {:ok, conn_id, request} ->
        GenServer.reply(request.from, {:error, :timeout})

        # Update connection
        connection = Map.get(state.connections, conn_id)
        updated_requests = List.delete(connection.active_requests, request)
        new_status = if Enum.empty?(updated_requests), do: :idle, else: :active

        updated_connection = %{
          connection
          | active_requests: updated_requests,
            status: new_status,
            error_count: connection.error_count + 1
        }

        new_connections = Map.put(state.connections, conn_id, updated_connection)

        # Update metrics
        metrics = update_metrics(state.metrics, :requests_timeout, 1)

        %{state | connections: new_connections, metrics: metrics}

      {:error, :not_found} ->
        state
    end
  end

  defp handle_no_connections(state, requests) do
    # Fail all requests due to no available connections
    Enum.each(requests, fn request ->
      GenServer.reply(request.from, {:error, :no_available_connections})
    end)

    # Update metrics
    metrics = update_metrics(state.metrics, :requests_failed, length(requests))
    %{state | metrics: metrics}
  end

  defp fail_requests(state, requests, error) do
    Enum.each(requests, fn request ->
      GenServer.reply(request.from, error)
    end)

    # Update metrics
    metrics = update_metrics(state.metrics, :requests_failed, length(requests))
    %{state | metrics: metrics}
  end

  defp circuit_breaker_allows?(_circuit_breakers, _target) do
    # Simplified - always allow for now
    # Real implementation would check circuit breaker state
    true
  end

  defp count_active_connections(connections) do
    Enum.count(connections, fn {_id, conn} -> conn.status == :active end)
  end

  defp generate_request_id() do
    # Generate a random integer request ID similar to Core module
    :rand.uniform(1_000_000)
  end

  defp update_metrics(metrics, key, value) do
    Map.update(metrics, key, value, fn current -> current + value end)
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
