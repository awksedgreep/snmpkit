defmodule SnmpKit.SnmpMgr.Engine do
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
  @default_circuit_breaker_recovery_timeout 30_000

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
    :routes,
    :shared_socket,
    :pending_requests,
    :pending_batches,
    :request_counter,
    :circuit_breaker_config
  ]

  @doc """
  Starts the streaming PDU engine.

  ## Options
  - `:pool_size` - Number of UDP socket connections to maintain (default: 10)
  - `:max_rps` - Maximum requests per second (default: 100)
  - `:request_timeout` - Individual request timeout in ms (default: 5000)
  - `:batch_size` - Maximum requests per batch (default: 50)
  - `:batch_timeout` - Maximum time to wait for batch in ms (default: 100)
  - `:circuit_breaker` - Per-target circuit breaker, off unless configured.
    `[threshold: n, recovery_timeout: ms]` opens a target after `n`
    consecutive failures (timeouts / send errors) and fails requests to it
    with `{:error, :circuit_breaker_open}` for `recovery_timeout` ms
    (default 30_000) before letting one request through to probe it.

  ## Examples

      {:ok, engine} = SnmpKit.SnmpMgr.Engine.start_link(
        pool_size: 20,
        max_rps: 200,
        batch_size: 100
      )
  """
  @type request :: %{
          required(:type) => atom(),
          required(:target) => term(),
          required(:oid) => term(),
          optional(atom()) => term()
        }
  @type result :: {:ok, term()} | {:error, term()}

  @spec start_link(keyword()) :: GenServer.on_start()
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

      {:ok, ref} = SnmpKit.SnmpMgr.Engine.submit_request(engine, request)
  """
  @spec submit_request(GenServer.server(), request(), keyword()) :: result()
  def submit_request(engine, request, opts \\ []) do
    GenServer.call(engine, {:submit_request, request, opts}, call_timeout(opts))
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

      {:ok, batch_ref} = SnmpKit.SnmpMgr.Engine.submit_batch(engine, requests)
  """
  @spec submit_batch(GenServer.server(), [request()], keyword()) ::
          {:ok, [result()]} | {:error, term()}
  def submit_batch(engine, requests, opts \\ []) do
    GenServer.call(engine, {:submit_batch, requests, opts}, call_timeout(opts))
  end

  # The engine always answers a request by its own `:timeout`; the caller must
  # wait a little longer than that or it exits at the very moment the reply is
  # sent. `:call_timeout` overrides the computed value.
  @call_timeout_margin 1_000

  defp call_timeout(opts) do
    case Keyword.get(opts, :call_timeout) do
      nil ->
        case Keyword.get(opts, :timeout, @default_request_timeout) do
          :infinity -> :infinity
          timeout when is_integer(timeout) -> timeout + @call_timeout_margin
          _ -> @default_request_timeout + @call_timeout_margin
        end

      call_timeout ->
        call_timeout
    end
  end

  @doc """
  Gets engine statistics and metrics.
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(engine) do
    GenServer.call(engine, :get_stats)
  end

  @doc """
  Gets connection pool status.
  """
  @spec get_pool_status(GenServer.server()) :: [map()]
  def get_pool_status(engine) do
    GenServer.call(engine, :get_pool_status)
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
    # Engine init starting
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    max_rps = Keyword.get(opts, :max_requests_per_second, @default_max_requests_per_second)
    request_timeout = Keyword.get(opts, :request_timeout, @default_request_timeout)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    batch_timeout = Keyword.get(opts, :batch_timeout, @default_batch_timeout)

    # Trap exits so terminate/2 runs on supervisor shutdown and the UDP
    # sockets are closed rather than leaked across restarts.
    Process.flag(:trap_exit, true)

    {:ok, shared_socket} = SnmpKit.SnmpLib.Transport.create_client_socket([{:active, true}])

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
      routes: %{},
      shared_socket: shared_socket,
      pending_requests: %{},
      pending_batches: %{},
      request_counter: 0,
      circuit_breaker_config: circuit_breaker_config(Keyword.get(opts, :circuit_breaker))
    }

    Logger.info("SnmpMgr Engine started with pool_size=#{pool_size}, max_rps=#{max_rps}")

    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Fail anything still in flight so callers are not left hanging, then
    # release every socket the engine owns.
    Enum.each(state.pending_requests, fn {_id, request} ->
      cancel_timer(request)

      if not Map.has_key?(request, :batch_ref) do
        safe_reply(request.from, {:error, :engine_stopped})
      end
    end)

    Enum.each(state.pending_batches, fn {_ref, batch} ->
      safe_reply(batch.from, {:error, :engine_stopped})
    end)

    if state.shared_socket, do: SnmpKit.SnmpLib.Transport.close_socket(state.shared_socket)

    Enum.each(state.connections, fn {_id, conn} ->
      if conn.socket, do: :gen_udp.close(conn.socket)
    end)

    :ok
  end

  @impl true
  def handle_call({:submit_request, request, opts}, {caller, _tag} = from, state) do
    {request_id, new_counter} = next_request_id(state.request_counter)
    ref = make_ref()
    timeout = Keyword.get(opts, :timeout, state.request_timeout)

    enriched_request =
      Map.merge(request, %{
        request_id: request_id,
        ref: ref,
        from: from,
        submitted_at: System.monotonic_time(:millisecond),
        opts: opts,
        conn_id: nil,
        # The timer carries request_id + ref so a stale timer for a recycled
        # request id can never complete a newer request.
        timer_ref: Process.send_after(self(), {:request_timeout, request_id, ref}, timeout),
        monitor_ref: Process.monitor(caller)
      })

    state = %{
      state
      | pending_requests: Map.put(state.pending_requests, request_id, enriched_request),
        request_counter: new_counter,
        metrics: update_metrics(state.metrics, :requests_submitted, 1)
    }

    cond do
      not circuit_breaker_allows?(state, request.target) ->
        {:noreply, complete_request(state, request_id, {:error, :circuit_breaker_open})}

      true ->
        # Every exit path goes through complete_request/3, which removes the
        # pending entry before replying, so a caller is answered exactly once.
        case send_snmp_request_shared(state.shared_socket, enriched_request) do
          :ok -> {:noreply, state}
          {:error, reason} -> {:noreply, complete_request(state, request_id, {:error, reason})}
        end
    end
  end

  @impl true
  def handle_call({:submit_batch, requests, opts}, {caller, _tag} = from, state) do
    if requests == [] do
      {:reply, {:ok, []}, state}
    else
      batch_ref = make_ref()
      submitted_at = System.monotonic_time(:millisecond)

      {enriched_requests, new_counter} =
        requests
        |> Enum.with_index()
        |> Enum.map_reduce(state.request_counter, fn {request, index}, counter ->
          {request_id, next_counter} = next_request_id(counter)

          enriched_request =
            Map.merge(request, %{
              request_id: request_id,
              ref: make_ref(),
              batch_ref: batch_ref,
              batch_index: index,
              from: from,
              submitted_at: submitted_at,
              opts: opts,
              conn_id: nil,
              timer_ref: nil,
              monitor_ref: nil
            })

          {enriched_request, next_counter}
        end)

      new_queue =
        Enum.reduce(enriched_requests, state.request_queue, fn req, queue ->
          :queue.in(req, queue)
        end)

      pending_requests =
        Enum.reduce(enriched_requests, state.pending_requests, fn req, acc ->
          Map.put(acc, req.request_id, req)
        end)

      pending_batches =
        Map.put(state.pending_batches, batch_ref, %{
          from: from,
          total: length(enriched_requests),
          results: %{},
          monitor_ref: Process.monitor(caller)
        })

      new_state = %{
        state
        | request_queue: new_queue,
          pending_requests: pending_requests,
          pending_batches: pending_batches,
          request_counter: new_counter
      }

      metrics = update_metrics(state.metrics, :requests_submitted, length(requests))
      metrics = update_metrics(metrics, :batches_submitted, 1)
      new_state = %{new_state | metrics: metrics}
      new_state = maybe_start_batch_timer(new_state)

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      queue_length: :queue.len(state.request_queue),
      active_connections: count_active_connections(state.connections),
      total_connections: map_size(state.connections),
      metrics: state.metrics,
      circuit_breakers: map_size(state.circuit_breakers),
      open_circuit_breakers:
        Enum.count(state.circuit_breakers, fn {_t, cb} -> cb.opened_at != nil end)
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
    # Sockets and pending callers are cleaned up in terminate/2
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
    # Handle incoming UDP responses on shared socket
    Logger.debug(
      "Engine received UDP response from #{:inet.ntoa(ip)}:#{port}, #{byte_size(data)} bytes"
    )

    new_state = handle_udp_response_shared(state, socket, ip, port, data)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:request_timeout, request_id, ref}, state) do
    case Map.get(state.pending_requests, request_id) do
      %{ref: ^ref} -> {:noreply, complete_request(state, request_id, {:error, :timeout})}
      _ -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, pid, _reason}, state) do
    # A caller died: drop everything it was waiting on so the pending map and
    # connection slots do not fill with work nobody will collect.
    dead_requests =
      state.pending_requests
      |> Enum.filter(fn {_id, %{from: {from_pid, _}}} -> from_pid == pid end)
      |> Enum.map(fn {id, _} -> id end)

    state = Enum.reduce(dead_requests, state, &discard_request(&2, &1))

    dead_batches =
      state.pending_batches
      |> Enum.filter(fn {_ref, %{from: {from_pid, _}}} -> from_pid == pid end)
      |> Enum.map(fn {ref, _} -> ref end)

    {:noreply, %{state | pending_batches: Map.drop(state.pending_batches, dead_batches)}}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    # Linked sockets/ports exiting are handled via normal error paths
    {:noreply, state}
  end

  @impl true
  def handle_info({:udp_error, _socket, reason}, state) do
    # ICMP errors (e.g. port unreachable) surface here on an active socket;
    # the affected request will still time out normally.
    Logger.debug("Engine socket reported #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:mock_response, request_id, response_data}, state) do
    {:noreply, complete_request(state, request_id, {:ok, response_data})}
  end

  @impl true
  def handle_info(other, state) do
    Logger.debug("Engine ignoring unexpected message: #{inspect(other)}")
    {:noreply, state}
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
    if circuit_breaker_allows?(state, target) do
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
    case ensure_socket_open(connection) do
      {:ok, socket} ->
        request_ids = Enum.map(requests, & &1.request_id)

        updated_connection = %{
          connection
          | socket: socket,
            status: :active,
            active_requests: connection.active_requests ++ request_ids,
            last_used: System.monotonic_time(:millisecond)
        }

        state = %{state | connections: Map.put(state.connections, conn_id, updated_connection)}

        Enum.reduce(requests, state, fn request, acc ->
          # Requests may have completed (e.g. caller died) while queued
          case Map.get(acc.pending_requests, request.request_id) do
            nil ->
              release_connection(acc, conn_id, request.request_id, :ok)

            pending ->
              timeout = Keyword.get(pending.opts, :timeout, acc.request_timeout)

              pending = %{
                pending
                | conn_id: conn_id,
                  timer_ref:
                    Process.send_after(
                      self(),
                      {:request_timeout, pending.request_id, pending.ref},
                      timeout
                    )
              }

              acc = %{
                acc
                | pending_requests: Map.put(acc.pending_requests, pending.request_id, pending)
              }

              case send_snmp_request(socket, pending) do
                :ok -> acc
                {:error, reason} -> complete_request(acc, pending.request_id, {:error, reason})
              end
          end
        end)

      {:error, reason} ->
        Logger.error("Failed to open pool socket #{conn_id}: #{inspect(reason)}")
        state = bump_connection_errors(state, conn_id)
        fail_requests(state, requests, {:error, {:socket_error, reason}})
    end
  end

  # Return a request's slot to its pool connection and update the connection's
  # bookkeeping so the pool can be reused instead of saturating.
  defp release_connection(state, nil, _request_id, _result), do: state

  defp release_connection(state, conn_id, request_id, result) do
    case Map.get(state.connections, conn_id) do
      nil ->
        state

      conn ->
        remaining = List.delete(conn.active_requests, request_id)

        conn = %{
          conn
          | active_requests: remaining,
            status: if(remaining == [], do: :idle, else: :active),
            error_count:
              case result do
                {:error, _} -> conn.error_count + 1
                _ -> conn.error_count
              end
        }

        %{state | connections: Map.put(state.connections, conn_id, conn)}
    end
  end

  defp bump_connection_errors(state, conn_id) do
    case Map.get(state.connections, conn_id) do
      nil ->
        state

      conn ->
        %{
          state
          | connections:
              Map.put(state.connections, conn_id, %{conn | error_count: conn.error_count + 1})
        }
    end
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

  defp send_snmp_request_shared(socket, request) do
    # Send SNMP request using shared socket
    Logger.debug("Preparing to send SNMP request #{request.request_id} to #{request.target}")
    target = resolve_target(request.target)
    Logger.debug("Resolved target: #{inspect(target)}")

    case build_snmp_message(request) do
      {:ok, message} ->
        host_str = format_host(target.host)
        Logger.debug("Built SNMP message successfully, sending to #{host_str}:#{target.port}")

        case SnmpKit.SnmpLib.Transport.send_packet(socket, target.host, target.port, message) do
          :ok ->
            Logger.debug("Sent SNMP request #{request.request_id} to #{host_str}:#{target.port}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to send SNMP request: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to build SNMP message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp send_snmp_request(socket, request) do
    # Legacy function - kept for compatibility
    send_snmp_request_shared(socket, request)
  end

  defp build_snmp_message(request) do
    # Extract community from opts or use default
    community = Keyword.get(request.opts, :community, "public")

    # Use existing PDU building functionality
    case request.type do
      :get ->
        pdu = SnmpKit.SnmpLib.PDU.build_get_request(request.oid, request.request_id)
        message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, :v2c)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      :get_bulk ->
        max_rep = Keyword.get(request.opts, :max_repetitions, 10)

        pdu =
          SnmpKit.SnmpLib.PDU.build_get_bulk_request(request.oid, request.request_id, 0, max_rep)

        message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, :v2c)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      :walk ->
        # For walk operations, start with get_next
        pdu = SnmpKit.SnmpLib.PDU.build_get_next_request(request.oid, request.request_id)
        message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, :v2c)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      :walk_table ->
        # For table walks, start with get_next
        pdu = SnmpKit.SnmpLib.PDU.build_get_next_request(request.oid, request.request_id)
        message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, :v2c)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      _ ->
        {:error, {:unsupported_request_type, request.type}}
    end
  end

  # Target resolution helper - delegates to canonical Target.resolve
  defp resolve_target(target), do: SnmpKit.SnmpMgr.Target.resolve(target)

  defp handle_udp_response_shared(state, socket, _ip, _port, data) do
    case SnmpKit.SnmpLib.PDU.decode_message(data) do
      {:ok, message} ->
        handle_snmp_response_shared(state, socket, message)

      {:error, reason} ->
        Logger.warning("Failed to decode SNMP response: #{inspect(reason)}")
        state
    end
  end

  defp handle_snmp_response_shared(state, _socket, message) do
    request_id = message.pdu.request_id

    case Map.get(state.pending_requests, request_id) do
      nil ->
        Logger.warning("Received response for unknown request ID: #{request_id}")
        state

      request ->
        response_data = extract_response_data(message.pdu, request.type)
        complete_request(state, request_id, {:ok, response_data})
    end
  end

  defp handle_no_connections(state, requests) do
    Enum.reduce(requests, state, fn request, acc ->
      complete_request(acc, request.request_id, {:error, :no_available_connections})
    end)
  end

  defp fail_requests(state, requests, error) do
    Enum.reduce(requests, state, fn request, acc ->
      complete_request(acc, request.request_id, error)
    end)
  end

  # Per-target circuit breaker (opt-in via the :circuit_breaker option).
  defp circuit_breaker_config(nil), do: nil

  defp circuit_breaker_config(opts) when is_list(opts) do
    case Keyword.get(opts, :threshold) do
      threshold when is_integer(threshold) and threshold > 0 ->
        %{
          threshold: threshold,
          recovery_timeout:
            Keyword.get(opts, :recovery_timeout, @default_circuit_breaker_recovery_timeout)
        }

      _ ->
        nil
    end
  end

  defp circuit_breaker_config(_), do: nil

  defp circuit_breaker_allows?(%{circuit_breaker_config: nil}, _target), do: true

  defp circuit_breaker_allows?(state, target) do
    case Map.get(state.circuit_breakers, target) do
      %{opened_at: opened_at} when is_integer(opened_at) ->
        # Open: block until the recovery timeout passes, then allow one probe
        System.monotonic_time(:millisecond) - opened_at >=
          state.circuit_breaker_config.recovery_timeout

      _ ->
        true
    end
  end

  defp record_circuit_breaker_result(%{circuit_breaker_config: nil} = state, _target, _result),
    do: state

  defp record_circuit_breaker_result(state, target, {:ok, _}) do
    %{state | circuit_breakers: Map.delete(state.circuit_breakers, target)}
  end

  defp record_circuit_breaker_result(state, _target, {:error, :circuit_breaker_open}), do: state

  defp record_circuit_breaker_result(state, target, {:error, _reason}) do
    cb = Map.get(state.circuit_breakers, target, %{failures: 0, opened_at: nil})
    failures = cb.failures + 1

    cb =
      if failures >= state.circuit_breaker_config.threshold do
        if cb.opened_at == nil,
          do: Logger.warning("Circuit breaker opened for #{inspect(target)}")

        %{failures: failures, opened_at: System.monotonic_time(:millisecond)}
      else
        %{cb | failures: failures}
      end

    %{state | circuit_breakers: Map.put(state.circuit_breakers, target, cb)}
  end

  defp count_active_connections(connections) do
    Enum.count(connections, fn {_id, conn} -> conn.status == :active end)
  end

  defp next_request_id(counter) do
    # Generate sequential request IDs for better correlation
    new_counter = rem(counter + 1, 1_000_000)
    {new_counter, new_counter}
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

  defp complete_request(state, request_id, result) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        state

      {request, pending_requests} ->
        cancel_timer(request)
        demonitor(request)

        state =
          %{state | pending_requests: pending_requests}
          |> release_connection(request.conn_id, request_id, result)
          |> record_circuit_breaker_result(request.target, result)
          |> update_completion_metrics(request, result)

        if Map.has_key?(request, :batch_ref) do
          complete_batch_member(state, request, result)
        else
          safe_reply(request.from, result)
          state
        end
    end
  end

  # Drop a request whose caller is gone: no reply, no batch accounting.
  defp discard_request(state, request_id) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        state

      {request, pending_requests} ->
        cancel_timer(request)
        demonitor(request)

        %{state | pending_requests: pending_requests}
        |> release_connection(request.conn_id, request_id, :ok)
    end
  end

  defp cancel_timer(%{timer_ref: ref}) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_timer(_), do: :ok

  defp demonitor(%{monitor_ref: ref}) when is_reference(ref),
    do: Process.demonitor(ref, [:flush])

  defp demonitor(_), do: :ok

  defp safe_reply(from, reply) do
    GenServer.reply(from, reply)
  catch
    _, _ -> :ok
  end

  defp complete_batch_member(state, request, result) do
    case Map.get(state.pending_batches, request.batch_ref) do
      nil -> state
      batch -> complete_batch_member(state, request, result, batch)
    end
  end

  defp complete_batch_member(state, request, result, batch) do
    results = Map.put(batch.results, request.batch_index, result)

    if map_size(results) == batch.total do
      ordered_results =
        0..(batch.total - 1)
        |> Enum.map(fn index -> Map.fetch!(results, index) end)

      demonitor(batch)
      safe_reply(batch.from, {:ok, ordered_results})
      %{state | pending_batches: Map.delete(state.pending_batches, request.batch_ref)}
    else
      pending_batches =
        Map.put(state.pending_batches, request.batch_ref, %{batch | results: results})

      %{state | pending_batches: pending_batches}
    end
  end

  defp update_completion_metrics(state, request, {:ok, _result}) do
    response_time = System.monotonic_time(:millisecond) - request.submitted_at
    metrics = update_metrics(state.metrics, :requests_completed, 1)
    metrics = update_avg_response_time(metrics, response_time)
    %{state | metrics: metrics}
  end

  defp update_completion_metrics(state, _request, {:error, :timeout}) do
    metrics = update_metrics(state.metrics, :requests_timeout, 1)
    %{state | metrics: metrics}
  end

  defp update_completion_metrics(state, _request, {:error, _reason}) do
    metrics = update_metrics(state.metrics, :requests_failed, 1)
    %{state | metrics: metrics}
  end

  defp extract_response_data(response_data, request_type) do
    # Extract and format response data based on request type
    case request_type do
      :get ->
        # For GET requests, extract the single value
        case response_data do
          %{varbinds: [varbind | _]} -> format_varbind(varbind)
          %{"varbinds" => [varbind | _]} -> format_varbind(varbind)
          _ -> response_data
        end

      :get_bulk ->
        # For GET_BULK requests, extract all varbinds
        case response_data do
          %{varbinds: varbinds} -> Enum.map(varbinds, &format_varbind/1)
          %{"varbinds" => varbinds} -> Enum.map(varbinds, &format_varbind/1)
          _ -> response_data
        end

      :walk ->
        # For WALK requests, format as walk results
        case response_data do
          %{varbinds: varbinds} -> Enum.map(varbinds, &format_varbind/1)
          %{"varbinds" => varbinds} -> Enum.map(varbinds, &format_varbind/1)
          _ -> response_data
        end

      _ ->
        response_data
    end
  end

  defp format_varbind(varbind) do
    case varbind do
      {oid, type, value} -> {oid, type, value}
      %{oid: oid, type: type, value: value} -> {oid, type, value}
      _ -> varbind
    end
  end

  defp format_host(host) do
    case host do
      {a, b, c, d} when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) ->
        "#{a}.#{b}.#{c}.#{d}"

      host when is_binary(host) ->
        host

      _ ->
        to_string(host)
    end
  end
end
