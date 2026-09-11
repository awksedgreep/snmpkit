defmodule SnmpKit.SnmpMgr.Multi do
  @moduledoc """
  High-performance concurrent multi-target SNMP operations.

  This module provides efficient SNMP operations against multiple targets
  using direct UDP sending and centralized response correlation, eliminating
  GenServer bottlenecks while maintaining proper concurrency control.

  ## Timeouts and retries

  `:timeout` is a per-PDU timeout, `:retries` the number of re-sends of a
  timed-out PDU and `:walk_timeout` a cap on a whole walk; the model and the
  defaults are described in `SnmpKit.SnmpMgr.Config`. Options left out fall
  back to `SnmpKit.SnmpMgr.Config.get/1`.
  """

  require Logger

  @type target :: term()
  @type request :: {target(), term()} | {target(), term(), keyword()}
  @type result :: {:ok, term()} | {:error, term()}
  @type results :: [result()] | [{target(), term(), result()}] | %{{target(), term()} => result()}
  @type operation ::
          {:get | :get_bulk | :walk | :walk_table, target(), term()}
          | {:get | :get_bulk | :walk | :walk_table, target(), term(), keyword()}

  @default_max_concurrent 10

  @doc """
  Performs GET operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} or {target, oid, opts} tuples
  - `opts` - Default options applied to all requests
    - `:timeout` - SNMP PDU timeout in milliseconds (default: the `:timeout`
      in `SnmpKit.SnmpMgr.Config`, 5000). How long to wait for each response
    - `:retries` - re-sends of a timed-out PDU (default: the `:retries` in
      `SnmpKit.SnmpMgr.Config`, 1)
    - `:max_concurrent` - Maximum concurrent requests (default: 10)
    - `:return_format` - Format of returned results (default: `:list`)
      - `:list` - Returns list of results in same order as input
      - `:with_targets` - Returns list of {target, oid, result} tuples
      - `:map` - Returns map with {target, oid} keys and result values

  ## Per-Request Options
  Individual requests can override call-level options by providing a third element:
  - `{target, oid, opts}` where opts can include:
    - `:timeout` - Override the default per-PDU timeout for this specific request
    - `:community` - Override SNMP community string
    - `:version` - Override SNMP version (:v1, :v2c)

  ## Examples

      iex> requests = [
      ...>   {"device1", "sysDescr.0"},
      ...>   {"device2", "sysUpTime.0"}
      ...> ]
      iex> SnmpKit.SnmpMgr.Multi.get_multi(requests)
      [
        {:ok, "Device 1 Description"},
        {:ok, 123456}
      ]
  """
  @spec get_multi([request()], keyword()) :: results()
  def get_multi(targets_and_oids, opts \\ []) do
    execute_multi_operation(targets_and_oids, :get, opts)
  end

  @doc """
  Performs GETBULK operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} or {target, oid, opts} tuples
  - `opts` - Default options applied to all requests
    - `:timeout` - SNMP PDU timeout in milliseconds (default: the `:timeout`
      in `SnmpKit.SnmpMgr.Config`, 5000). How long to wait for each response
    - `:retries` - re-sends of a timed-out PDU (default: the `:retries` in
      `SnmpKit.SnmpMgr.Config`, 1)
    - `:max_repetitions` - Maximum repetitions for GetBulk (default: 30)
    - `:max_concurrent` - Maximum concurrent requests (default: 10)

  ## Per-Request Options
  Individual requests can override call-level options:
    - `:timeout` - Override the default per-PDU timeout for this specific request
    - `:max_repetitions` - Override max repetitions for this request

  ## Examples

      iex> requests = [
      ...>   {"switch1", "ifTable"},
      ...>   {"switch2", "ifTable"}
      ...> ]
      iex> SnmpKit.SnmpMgr.Multi.get_bulk_multi(requests, max_repetitions: 20)
      [
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]}
      ]
  """
  @spec get_bulk_multi([request()], keyword()) :: results()
  def get_bulk_multi(targets_and_oids, opts \\ []) do
    execute_multi_operation(targets_and_oids, :get_bulk, opts)
  end

  @doc """
  Performs walk operations against multiple targets concurrently.

  A walk operation retrieves all OIDs under a given root OID by sending
  multiple GETBULK requests until the end of the MIB subtree is reached.

  ## Parameters
  - `targets_and_oids` - List of {target, root_oid} or {target, root_oid, opts} tuples
  - `opts` - Default options applied to all requests
    - `:timeout` - Per-PDU timeout in milliseconds (default: the `:timeout`
      in `SnmpKit.SnmpMgr.Config`, 5000). How long to wait for each GETBULK
      PDU response during the walk. A walk may require many PDUs, so total
      walk time can exceed this value.
    - `:retries` - re-sends of a timed-out PDU (default: the `:retries` in
      `SnmpKit.SnmpMgr.Config`, 1)
    - `:walk_timeout` - Whole-walk safety cap in milliseconds (default:
      `max(timeout * 10, 1_200_000)`, at most 1_800_000)
    - `:max_repetitions` - OIDs requested per GETBULK PDU (default: 30)
    - `:max_concurrent` - Maximum concurrent walk operations (default: 10)

  ## Per-Request Options
  Individual walk requests can override call-level options:
    - `:timeout` - Override per-PDU timeout for this specific walk
    - `:max_repetitions` - Override max repetitions for this walk
    - `:community` - Override SNMP community string

  ## Timeout Behavior
  - Each GETBULK PDU has its own timeout (per-PDU timeout)
  - Large tables may require 50-200+ PDUs to walk completely
  - Total walk time can be substantial: N_pdus × per_PDU_timeout
  - Operations are protected by `:walk_timeout`

  ## Examples

      iex> requests = [
      ...>   {"device1", "system"},
      ...>   {"device2", "interfaces"}
      ...> ]
      iex> SnmpKit.SnmpMgr.Multi.walk_multi(requests)
      [
        {:ok, [{"1.3.6.1.2.1.1.1.0", "Device 1"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.1.0", 24}, ...]}
      ]
  """
  @spec walk_multi([request()], keyword()) :: results()
  def walk_multi(targets_and_oids, opts \\ []) do
    execute_multi_operation(targets_and_oids, :walk, opts)
  end

  @doc """
  Performs table walk operations against multiple targets concurrently.

  Similar to walk_multi but optimized for SNMP table operations.

  ## Parameters
  - `targets_and_tables` - List of {target, table_oid} or {target, table_oid, opts} tuples
  - `opts` - Default options applied to all requests
    - `:timeout` - Per-PDU timeout in milliseconds (default: the `:timeout`
      in `SnmpKit.SnmpMgr.Config`, 5000). How long to wait for each GETBULK
      PDU response during the table walk.
    - `:retries` - re-sends of a timed-out PDU (default: the `:retries` in
      `SnmpKit.SnmpMgr.Config`, 1)
    - `:walk_timeout` - Whole-walk safety cap in milliseconds (default:
      `max(timeout * 10, 1_200_000)`, at most 1_800_000)
    - `:max_repetitions` - Rows requested per GETBULK PDU (default: 30)
    - `:max_concurrent` - Maximum concurrent table walks (default: 10)

  ## Per-Request Options
  Individual table walk requests can override call-level options:
    - `:timeout` - Override per-PDU timeout for this specific table walk
    - `:max_repetitions` - Override max repetitions for this table

  ## Examples

      iex> requests = [
      ...>   {"switch1", "ifTable"},
      ...>   {"switch2", "ifTable"}
      ...> ]
      iex> SnmpKit.SnmpMgr.Multi.walk_table_multi(requests)
      [
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]}
      ]
  """
  @spec walk_table_multi([request()], keyword()) :: results()
  def walk_table_multi(targets_and_tables, opts \\ []) do
    execute_multi_operation(targets_and_tables, :walk_table, opts)
  end

  @doc """
  Executes mixed SNMP operations against multiple targets concurrently.

  ## Parameters
  - `operations` - List of {operation, target, oid_or_args, opts} tuples
    where operation is :get, :get_bulk, :walk, or :walk_table
  - `opts` - Default options
    - `:timeout` - Per-PDU timeout in milliseconds (default: the `:timeout`
      in `SnmpKit.SnmpMgr.Config`, 5000). Applied to all operations. Walk
      operations may require many PDUs.
    - `:retries` - re-sends of a timed-out PDU (default: the `:retries` in
      `SnmpKit.SnmpMgr.Config`, 1)
    - `:max_concurrent` - Maximum concurrent operations (default: 10)

  ## Per-Operation Options
  Each operation tuple can include individual options:
    - `:timeout` - Override per-PDU timeout for this specific operation
    - `:max_repetitions` - Override for bulk/walk operations
    - `:community` - Override SNMP community string

  ## Timeout Behavior
  - GET/GETBULK: Single PDU timeout
  - WALK operations: Per-PDU timeout, may require many PDUs
  - Mixed operations with walks use `:walk_timeout` as the whole-walk cap

  ## Examples

      iex> operations = [
      ...>   {:get, "device1", "sysDescr.0", []},
      ...>   {:get_bulk, "switch1", "ifTable", [max_repetitions: 20]},
      ...>   {:walk, "router1", "system", []}
      ...> ]
      iex> SnmpKit.SnmpMgr.Multi.execute_mixed(operations)
      [
        {:ok, "Device 1 Description"},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.1.1.0", "Router 1"}, ...]}
      ]
  """
  @spec execute_mixed([operation()], keyword()) :: [result()]
  def execute_mixed(operations, opts \\ []) do
    SnmpKit.Telemetry.span(
      :multi,
      %{operation: :mixed, request_count: length(operations)},
      fn -> execute_mixed_unspanned(operations, opts) end,
      &multi_span_extra/1
    )
  end

  defp execute_mixed_unspanned(operations, opts) do
    case ensure_components_started() do
      :ok ->
        timeout = Keyword.get(opts, :timeout, default_timeout())
        max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

        # Normalize mixed operations to standard format
        normalized_operations = normalize_mixed_operations(operations, opts)

        normalized_operations
        |> execute_mixed_without_tasks(timeout, max_concurrent)
        |> Enum.map(&enrich_any_result(&1, opts))

      {:error, reason} ->
        Enum.map(operations, fn _ -> {:error, reason} end)
    end
  end

  # Private functions

  defp execute_multi_operation(targets_and_data, operation_type, opts) do
    SnmpKit.Telemetry.span(
      :multi,
      %{operation: operation_type, request_count: length(targets_and_data)},
      fn -> execute_multi_operation_unspanned(targets_and_data, operation_type, opts) end,
      &multi_span_extra/1
    )
  end

  # ok/error counts regardless of return_format
  defp multi_span_extra(results) when is_map(results), do: multi_span_extra(Map.values(results))

  defp multi_span_extra(results) when is_list(results) do
    Enum.reduce(results, %{ok_count: 0, error_count: 0}, fn
      {_target, _oid, result}, acc -> count_result(acc, result)
      result, acc -> count_result(acc, result)
    end)
  end

  defp multi_span_extra(_), do: %{}

  defp count_result(acc, {:ok, _}), do: Map.update!(acc, :ok_count, &(&1 + 1))
  defp count_result(acc, _), do: Map.update!(acc, :error_count, &(&1 + 1))

  defp execute_multi_operation_unspanned(targets_and_data, operation_type, opts) do
    case {targets_and_data, ensure_components_started()} do
      {[], _} ->
        format_results(targets_and_data, [], opts)

      {_, {:error, reason}} ->
        # Services are down and auto-start is disabled: say so per target
        # instead of exiting with :noproc deep inside the Engine.
        results = Enum.map(targets_and_data, fn _ -> {:error, reason} end)
        format_results(targets_and_data, results, opts)

      {_, :ok} ->
        execute_multi_operation_started(targets_and_data, operation_type, opts)
    end
  end

  defp execute_multi_operation_started(targets_and_data, operation_type, opts) do
    timeout = Keyword.get(opts, :timeout, default_timeout())
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Normalize requests to standard format
    normalized_requests = normalize_requests(targets_and_data, operation_type, opts)
    results = execute_mixed_without_tasks(normalized_requests, timeout, max_concurrent)

    # Format results according to return_format option
    format_results(targets_and_data, results, opts)
  end

  # Community requests share one socket and are correlated through the
  # Engine; SNMPv3 requests need discovery, key localization and report
  # handling per target, so they run through the single-target path in a
  # bounded task pool. Results come back in request order either way.
  defp execute_mixed_without_tasks(requests, timeout, max_concurrent) do
    indexed_requests = Enum.with_index(requests)

    {v3_requests, community_requests} =
      Enum.split_with(indexed_requests, fn {request, _index} -> v3?(request) end)

    {walk_requests, non_walk_requests} =
      Enum.split_with(community_requests, fn {request, _index} ->
        request.type in [:walk, :walk_table]
      end)

    non_walk_results =
      non_walk_requests
      |> Enum.map(&elem(&1, 0))
      |> execute_non_walk_requests(timeout, max_concurrent)

    walk_results =
      case Enum.map(walk_requests, &elem(&1, 0)) do
        [] ->
          []

        walks ->
          SnmpKit.SnmpMgr.V2Walk.walk_multi(walks,
            timeout: timeout,
            max_concurrent: max_concurrent
          )
      end

    v3_results =
      v3_requests
      |> Enum.map(&elem(&1, 0))
      |> execute_v3_requests(timeout, max_concurrent)

    result_map =
      indexed_result_map(non_walk_requests, non_walk_results)
      |> Map.merge(indexed_result_map(walk_requests, walk_results))
      |> Map.merge(indexed_result_map(v3_requests, v3_results))

    ordered_results(requests, result_map)
  end

  defp v3?(%{version: version}), do: version in [:v3, 3]

  defp execute_v3_requests([], _timeout, _max_concurrent), do: []

  defp execute_v3_requests(requests, timeout, max_concurrent) do
    requests
    |> Task.async_stream(&execute_v3_request(&1, timeout),
      max_concurrency: max(max_concurrent, 1),
      timeout: timeout + 5_000,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _reason} -> {:error, :timeout}
    end)
  end

  defp execute_v3_request(%{type: type, target: target, oid: oid, opts: opts}, timeout) do
    opts =
      opts
      |> Keyword.drop([:max_concurrent, :return_format])
      |> Keyword.put_new(:timeout, timeout)

    case type do
      :get ->
        with {:ok, varbinds} <- SnmpKit.SnmpMgr.get(target, oid, opts),
             do: {:ok, List.wrap(varbinds)}

      :get_bulk ->
        SnmpKit.SnmpMgr.get_bulk(target, oid, opts)

      :walk ->
        SnmpKit.SnmpMgr.walk(target, oid, opts)

      :walk_table ->
        SnmpKit.SnmpMgr.walk_table(target, oid, opts)

      other ->
        {:error, {:unsupported_operation, other}}
    end
  end

  defp indexed_result_map(indexed_requests, results) do
    indexed_requests
    |> Enum.zip(results)
    |> Enum.into(%{}, fn {{_request, original_index}, result} -> {original_index, result} end)
  end

  defp ordered_results([], _result_map), do: []

  defp ordered_results(requests, result_map) do
    0..(length(requests) - 1)
    |> Enum.map(fn index -> Map.get(result_map, index, {:error, :timeout}) end)
  end

  # For high-throughput get/get_bulk paths, keep one caller process and one shared UDP socket.
  # Requests are launched up to max_concurrent and correlated back through Engine.
  defp execute_non_walk_requests([], _global_timeout, _max_concurrent), do: []

  defp execute_non_walk_requests(requests, global_timeout, max_concurrent) do
    case SnmpKit.SnmpMgr.Engine.get_socket() do
      {:error, reason} ->
        Enum.map(requests, fn _ -> {:error, reason} end)

      socket ->
        state = %{
          socket: socket,
          queue: :queue.from_list(Enum.with_index(requests)),
          pending: %{},
          results: %{},
          total: length(requests),
          global_timeout: global_timeout,
          max_concurrent: max(1, max_concurrent)
        }

        state
        |> launch_pending_requests()
        |> await_pending_requests()
        |> build_ordered_results()
    end
  end

  defp launch_pending_requests(state) do
    if map_size(state.pending) >= state.max_concurrent or :queue.is_empty(state.queue) do
      state
    else
      {{:value, {request, index}}, queue} = :queue.out(state.queue)
      timeout = request_timeout(request, state.global_timeout)

      case dispatch_request(state.socket, request, timeout) do
        {:ok, request_id} ->
          entry = %{
            index: index,
            request: request,
            timeout: timeout,
            retries_left: request_retries(request),
            deadline_ms: local_deadline(timeout)
          }

          launch_pending_requests(%{
            state
            | queue: queue,
              pending: Map.put(state.pending, request_id, entry)
          })

        {:error, reason} ->
          launch_pending_requests(%{
            state
            | queue: queue,
              results: Map.put(state.results, index, {:error, reason})
          })
      end
    end
  end

  # Engine delivers :snmp_timeout at `timeout`; the local deadline is a
  # safety net one second later in case that message never arrives.
  defp local_deadline(timeout), do: now_ms() + timeout + 1000

  defp await_pending_requests(state) do
    cond do
      map_size(state.results) == state.total ->
        state

      map_size(state.pending) == 0 ->
        state

      true ->
        receive_timeout = pending_receive_timeout(state)

        receive do
          {:snmp_response, request_id, response_data} ->
            state
            |> complete_pending_request(request_id, {:ok, response_data})
            |> launch_pending_requests()
            |> await_pending_requests()

          {:snmp_timeout, request_id} ->
            state
            |> timeout_pending_request(request_id)
            |> launch_pending_requests()
            |> await_pending_requests()
        after
          receive_timeout ->
            state
            |> fail_stuck_pending_requests()
            |> launch_pending_requests()
            |> await_pending_requests()
        end
    end
  end

  defp complete_pending_request(state, request_id, result) do
    case Map.pop(state.pending, request_id) do
      {nil, pending} ->
        %{state | pending: pending}

      {%{index: index}, pending} ->
        %{state | pending: pending, results: Map.put(state.results, index, result)}
    end
  end

  # A timed-out PDU is re-sent under a fresh request id while the request has
  # retries left; only then is {:error, :timeout} recorded.
  defp timeout_pending_request(state, request_id) do
    case Map.pop(state.pending, request_id) do
      {nil, pending} ->
        %{state | pending: pending}

      {%{retries_left: 0, index: index}, pending} ->
        %{state | pending: pending, results: Map.put(state.results, index, {:error, :timeout})}

      {entry, pending} ->
        entry = %{entry | retries_left: entry.retries_left - 1}

        case dispatch_request(state.socket, entry.request, entry.timeout) do
          {:ok, new_id} ->
            entry = %{entry | deadline_ms: local_deadline(entry.timeout)}
            %{state | pending: Map.put(pending, new_id, entry)}

          {:error, reason} ->
            %{
              state
              | pending: pending,
                results: Map.put(state.results, entry.index, {:error, reason})
            }
        end
    end
  end

  # Only the requests whose own deadline has passed are timed out; a single
  # slow peer must not take the rest of the window down with it.
  defp fail_stuck_pending_requests(state) do
    now = now_ms()

    state.pending
    |> Enum.filter(fn {_request_id, entry} -> entry.deadline_ms <= now end)
    |> Enum.reduce(state, fn {request_id, _entry}, acc ->
      SnmpKit.SnmpMgr.Engine.unregister_request(SnmpKit.SnmpMgr.Engine, request_id)
      timeout_pending_request(acc, request_id)
    end)
  end

  defp build_ordered_results(state) do
    if state.total == 0 do
      []
    else
      0..(state.total - 1)
      |> Enum.map(fn index -> Map.get(state.results, index, {:error, :timeout}) end)
    end
  end

  # Wake up when the *earliest* pending deadline expires.
  defp pending_receive_timeout(state) do
    now = now_ms()

    state.pending
    |> Map.values()
    |> Enum.map(&(&1.deadline_ms - now))
    |> Enum.min(fn -> state.global_timeout + 1000 end)
    |> max(0)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  # Registers a fresh request id and sends the PDU under it.
  defp dispatch_request(socket, request, timeout) do
    with {:ok, request_id} <-
           SnmpKit.SnmpMgr.Engine.register_next_request(SnmpKit.SnmpMgr.Engine, self(), timeout) do
      case build_and_send_packet(socket, request, request_id) do
        :ok ->
          {:ok, request_id}

        {:error, reason} ->
          SnmpKit.SnmpMgr.Engine.unregister_request(SnmpKit.SnmpMgr.Engine, request_id)
          {:error, reason}
      end
    end
  end

  defp default_timeout, do: SnmpKit.SnmpMgr.Config.get(:timeout)

  defp request_timeout(request, global_timeout) do
    timeout = Keyword.get(request.opts, :timeout, global_timeout)
    if is_integer(timeout) and timeout > 0, do: timeout, else: global_timeout
  end

  defp request_retries(request) do
    case Keyword.get(request.opts, :retries) do
      retries when is_integer(retries) and retries >= 0 -> retries
      _ -> SnmpKit.SnmpMgr.Config.get(:retries)
    end
  end

  defp normalize_requests(targets_and_data, operation_type, global_opts) do
    targets_and_data
    |> Enum.map(fn
      {target, data, request_opts} ->
        %{
          type: operation_type,
          target: target,
          oid: data,
          community:
            Keyword.get(request_opts, :community, Keyword.get(global_opts, :community, "public")),
          version: Keyword.get(request_opts, :version, Keyword.get(global_opts, :version, :v2c)),
          max_repetitions:
            Keyword.get(
              request_opts,
              :max_repetitions,
              Keyword.get(global_opts, :max_repetitions, 30)
            ),
          opts: Keyword.merge(global_opts, request_opts)
        }

      {target, data} ->
        %{
          type: operation_type,
          target: target,
          oid: data,
          community: Keyword.get(global_opts, :community, "public"),
          version: Keyword.get(global_opts, :version, :v2c),
          max_repetitions: Keyword.get(global_opts, :max_repetitions, 30),
          opts: global_opts
        }
    end)
  end

  defp normalize_mixed_operations(operations, global_opts) do
    operations
    |> Enum.map(fn
      {operation, target, args, request_opts} ->
        %{
          type: operation,
          target: target,
          oid: args,
          community:
            Keyword.get(request_opts, :community, Keyword.get(global_opts, :community, "public")),
          version: Keyword.get(request_opts, :version, Keyword.get(global_opts, :version, :v2c)),
          max_repetitions:
            Keyword.get(
              request_opts,
              :max_repetitions,
              Keyword.get(global_opts, :max_repetitions, 30)
            ),
          opts: Keyword.merge(global_opts, request_opts)
        }

      {operation, target, args} ->
        %{
          type: operation,
          target: target,
          oid: args,
          community: Keyword.get(global_opts, :community, "public"),
          version: Keyword.get(global_opts, :version, :v2c),
          max_repetitions: Keyword.get(global_opts, :max_repetitions, 30),
          opts: global_opts
        }
    end)
  end

  defp build_and_send_packet(socket, request, request_id) do
    try do
      # Resolve target
      target = resolve_target(request.target)

      with {:ok, socket} <- socket_for(socket, target.host),
           {:ok, message} <- build_snmp_message(request, request_id),
           :ok <-
             SnmpKit.SnmpLib.Transport.send_packet(socket, target.host, target.port, message) do
        Logger.debug(
          "Sent SNMP request #{request_id} to #{format_host(target.host)}:#{target.port}"
        )

        :ok
      else
        {:error, reason} ->
          Logger.error("Failed to send SNMP request #{request_id}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error in build_and_send_packet: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  defp build_snmp_message(request, request_id) do
    community = Keyword.get(request.opts, :community, "public")
    version = Keyword.get(request.opts, :version, :v2c)

    # Resolve OID (handles symbolic names like "sysDescr.0")
    case resolve_oids(request.oid) do
      {:ok, [_ | _] = oid_lists} when request.type == :get ->
        varbinds = Enum.map(oid_lists, &{&1, :null, :null})
        pdu = SnmpKit.SnmpLib.PDU.build_get_request_multi(varbinds, request_id)
        message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, version)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      # Only GET carries several varbinds; a GETBULK PDU has one starting OID
      # (SnmpMgr.Bulk refuses the same thing) and an empty list resolves to
      # nothing. Both used to fall through to a CaseClauseError.
      {:ok, [_, _ | _]} ->
        {:error, {:unsupported, :multi_oid_get_bulk}}

      {:ok, []} ->
        {:error, {:invalid_oid, request.oid, :empty_oid}}

      {:ok, [oid_list]} ->
        case request.type do
          :get ->
            pdu = SnmpKit.SnmpLib.PDU.build_get_request(oid_list, request_id)
            message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, version)
            SnmpKit.SnmpLib.PDU.encode_message(message)

          :get_bulk ->
            max_rep = Keyword.get(request.opts, :max_repetitions, 30)
            pdu = SnmpKit.SnmpLib.PDU.build_get_bulk_request(oid_list, request_id, 0, max_rep)
            message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, version)
            SnmpKit.SnmpLib.PDU.encode_message(message)

          # NOTE: :walk and :walk_table operations are handled by V2Walk module
          # and should not reach this function. They are delegated in execute_single_operation.

          _ ->
            {:error, {:unsupported_request_type, request.type}}
        end

      {:error, _} = error ->
        error
    end
  end

  # A request's OID is one OID or, for GET, a list of them (multi-varbind PDU)
  defp resolve_oids([first | _] = oids) when not is_integer(first) do
    Enum.reduce_while(oids, {:ok, []}, fn oid, {:ok, acc} ->
      case resolve_oid(oid) do
        {:ok, list} -> {:cont, {:ok, [list | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp resolve_oids(oid) do
    case resolve_oid(oid) do
      {:ok, list} -> {:ok, [list]}
      error -> error
    end
  end

  # IPv6 targets go out on the engine's IPv6 socket
  defp socket_for(_default, {_, _, _, _, _, _, _, _}) do
    case SnmpKit.SnmpMgr.Engine.get_socket(SnmpKit.SnmpMgr.Engine, :inet6) do
      {:error, reason} -> {:error, {:ipv6_socket, reason}}
      socket -> {:ok, socket}
    end
  end

  defp socket_for(default, _host), do: {:ok, default}

  # Resolve OID from string (symbolic or numeric) to list format. Failures
  # carry the same {:invalid_oid, input, reason} shape as every other path.
  defp resolve_oid(oid) when is_list(oid) and is_integer(hd(oid)), do: {:ok, oid}

  defp resolve_oid(oid) when is_binary(oid) do
    case SnmpKit.SnmpMgr.Core.parse_oid(oid) do
      {:ok, list} -> {:ok, list}
      {:error, reason} -> {:error, {:invalid_oid, oid, reason}}
    end
  end

  defp resolve_oid(oid), do: {:error, {:invalid_oid, oid, :invalid_oid_input}}

  # Target resolution helper - delegates to canonical Target.resolve
  defp resolve_target(target), do: SnmpKit.SnmpMgr.Target.resolve(target)

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

  defp format_results(targets_and_data, results, opts) do
    case Keyword.get(opts, :return_format, :list) do
      :list ->
        Enum.map(results, &enrich_any_result(&1, opts))

      :with_targets ->
        # Normalize targets_and_data to extract target and data parts
        normalized_targets = normalize_targets_and_data(targets_and_data)

        normalized_targets
        |> Enum.zip(results)
        |> Enum.map(fn {{target, data}, result} ->
          {target, data, enrich_any_result(result, opts)}
        end)

      :map ->
        # Normalize targets_and_data to extract target and data parts
        normalized_targets = normalize_targets_and_data(targets_and_data)

        normalized_targets
        |> Enum.zip(results)
        |> Enum.map(fn {{target, data}, result} ->
          {{target, data}, enrich_any_result(result, opts)}
        end)
        |> Enum.into(%{})

      _ ->
        # Unknown format, default to :list
        Enum.map(results, &enrich_any_result(&1, opts))
    end
  end

  # Ensure the V2 components are running; safe to call repeatedly. Honours
  # auto_start_services: when disabled and the services are not running the
  # caller gets an explicit error rather than a :noproc exit.
  defp ensure_components_started() do
    cond do
      SnmpKit.SnmpMgr.services_running?() -> :ok
      SnmpKit.SnmpMgr.Config.get(:auto_start_services) == false -> {:error, :services_not_started}
      true -> SnmpKit.SnmpMgr.ensure_started()
    end
  end

  # Enrich any result to standardized maps, preserving {:ok, ...} | {:error, ...}
  defp enrich_any_result({:ok, %{oid: _}} = result, _opts), do: result
  defp enrich_any_result({:ok, [%{oid: _} | _] = _already} = result, _opts), do: result

  defp enrich_any_result({:ok, {oid, type, value}}, opts),
    do: {:ok, SnmpKit.SnmpMgr.Format.enrich_varbind({oid, type, value}, opts)}

  defp enrich_any_result({:ok, list}, opts) when is_list(list),
    do: {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(list, opts)}

  defp enrich_any_result(other, _opts), do: other

  defp normalize_targets_and_data(targets_and_data) do
    targets_and_data
    |> Enum.map(fn
      {target, data, _opts} -> {target, data}
      {target, data} -> {target, data}
    end)
  end
end
