defmodule SnmpKit.SnmpMgr.MultiV2 do
  @moduledoc """
  High-performance concurrent multi-target SNMP operations.

  This module provides efficient SNMP operations against multiple targets
  using direct UDP sending and centralized response correlation, eliminating
  GenServer bottlenecks while maintaining proper concurrency control.
  """

  require Logger

  @default_timeout 10_000
  @default_max_concurrent 10

  @doc """
  Performs GET operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} or {target, oid, opts} tuples
  - `opts` - Global options applied to all requests
    - `:timeout` - SNMP PDU timeout in milliseconds (default: 10000)
      How long to wait for each individual SNMP response
    - `:max_concurrent` - Maximum concurrent requests (default: 10)
    - `:return_format` - Format of returned results (default: `:list`)
      - `:list` - Returns list of results in same order as input
      - `:with_targets` - Returns list of {target, oid, result} tuples
      - `:map` - Returns map with {target, oid} keys and result values

  ## Per-Request Options
  Individual requests can override global options by providing a third element:
  - `{target, oid, opts}` where opts can include:
    - `:timeout` - Override global timeout for this specific request
    - `:community` - Override SNMP community string
    - `:version` - Override SNMP version (:v1, :v2c)

  ## Examples

      iex> requests = [
      ...>   {"device1", "sysDescr.0"},
      ...>   {"device2", "sysUpTime.0"}
      ...> ]
      iex> SnmpKit.SnmpMgr.MultiV2.get_multi(requests)
      [
        {:ok, "Device 1 Description"},
        {:ok, 123456}
      ]
  """
  def get_multi(targets_and_oids, opts \\ []) do
    execute_multi_operation(targets_and_oids, :get, opts)
  end

  @doc """
  Performs GETBULK operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} or {target, oid, opts} tuples
  - `opts` - Global options applied to all requests
    - `:timeout` - SNMP PDU timeout in milliseconds (default: 10000)
      How long to wait for each individual SNMP response
    - `:max_repetitions` - Maximum repetitions for GetBulk (default: 30)
    - `:max_concurrent` - Maximum concurrent requests (default: 10)

  ## Per-Request Options
  Individual requests can override global options:
    - `:timeout` - Override global timeout for this specific request
    - `:max_repetitions` - Override max repetitions for this request

  ## Examples

      iex> requests = [
      ...>   {"switch1", "ifTable"},
      ...>   {"switch2", "ifTable"}
      ...> ]
      iex> SnmpKit.SnmpMgr.MultiV2.get_bulk_multi(requests, max_repetitions: 20)
      [
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]}
      ]
  """
  def get_bulk_multi(targets_and_oids, opts \\ []) do
    execute_multi_operation(targets_and_oids, :get_bulk, opts)
  end

  @doc """
  Performs walk operations against multiple targets concurrently.

  A walk operation retrieves all OIDs under a given root OID by sending
  multiple GETBULK requests until the end of the MIB subtree is reached.

  ## Parameters
  - `targets_and_oids` - List of {target, root_oid} or {target, root_oid, opts} tuples
  - `opts` - Global options applied to all requests
    - `:timeout` - Per-PDU timeout in milliseconds (default: 30000)
      How long to wait for each GETBULK PDU response during the walk.
      A walk may require many PDUs, so total walk time = N_pdus × timeout.
      Task timeout is capped at 20 minutes to prevent infinite hangs.
    - `:max_repetitions` - OIDs requested per GETBULK PDU (default: 30)
    - `:max_concurrent` - Maximum concurrent walk operations (default: 10)

  ## Per-Request Options
  Individual walk requests can override global options:
    - `:timeout` - Override per-PDU timeout for this specific walk
    - `:max_repetitions` - Override max repetitions for this walk
    - `:community` - Override SNMP community string

  ## Timeout Behavior
  - Each GETBULK PDU has its own timeout (per-PDU timeout)
  - Large tables may require 50-200+ PDUs to walk completely
  - Total walk time can be substantial: N_pdus × per_PDU_timeout
  - Operations are protected by 20-minute maximum task timeout

  ## Examples

      iex> requests = [
      ...>   {"device1", "system"},
      ...>   {"device2", "interfaces"}
      ...> ]
      iex> SnmpKit.SnmpMgr.MultiV2.walk_multi(requests)
      [
        {:ok, [{"1.3.6.1.2.1.1.1.0", "Device 1"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.1.0", 24}, ...]}
      ]
  """
  def walk_multi(targets_and_oids, opts \\ []) do
    # Walks take longer by default
    opts = Keyword.put_new(opts, :timeout, @default_timeout * 3)
    execute_multi_operation(targets_and_oids, :walk, opts)
  end

  @doc """
  Performs table walk operations against multiple targets concurrently.

  Similar to walk_multi but optimized for SNMP table operations.

  ## Parameters
  - `targets_and_tables` - List of {target, table_oid} or {target, table_oid, opts} tuples
  - `opts` - Global options applied to all requests
    - `:timeout` - Per-PDU timeout in milliseconds (default: 50000)
      How long to wait for each GETBULK PDU response during table walk.
      Table walks often require more PDUs than regular walks.
    - `:max_repetitions` - Rows requested per GETBULK PDU (default: 30)
    - `:max_concurrent` - Maximum concurrent table walks (default: 10)

  ## Per-Request Options
  Individual table walk requests can override global options:
    - `:timeout` - Override per-PDU timeout for this specific table walk
    - `:max_repetitions` - Override max repetitions for this table

  ## Examples

      iex> requests = [
      ...>   {"switch1", "ifTable"},
      ...>   {"switch2", "ifTable"}
      ...> ]
      iex> SnmpKit.SnmpMgr.MultiV2.walk_table_multi(requests)
      [
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]}
      ]
  """
  def walk_table_multi(targets_and_tables, opts \\ []) do
    # Table walks take longer by default
    opts = Keyword.put_new(opts, :timeout, @default_timeout * 5)
    execute_multi_operation(targets_and_tables, :walk_table, opts)
  end

  @doc """
  Executes mixed SNMP operations against multiple targets concurrently.

  ## Parameters
  - `operations` - List of {operation, target, oid_or_args, opts} tuples
    where operation is :get, :get_bulk, :walk, or :walk_table
  - `opts` - Global options
    - `:timeout` - Per-PDU timeout in milliseconds (default: 30000)
      Applied to all operations. Walk operations may require many PDUs.
    - `:max_concurrent` - Maximum concurrent operations (default: 10)

  ## Per-Operation Options
  Each operation tuple can include individual options:
    - `:timeout` - Override per-PDU timeout for this specific operation
    - `:max_repetitions` - Override for bulk/walk operations
    - `:community` - Override SNMP community string

  ## Timeout Behavior
  - GET/GETBULK: Single PDU timeout
  - WALK operations: Per-PDU timeout, may require many PDUs
  - Mixed operations with walks use 20-minute task timeout cap
  - Operations without walks use shorter task timeout protection

  ## Examples

      iex> operations = [
      ...>   {:get, "device1", "sysDescr.0", []},
      ...>   {:get_bulk, "switch1", "ifTable", [max_repetitions: 20]},
      ...>   {:walk, "router1", "system", []}
      ...> ]
      iex> SnmpKit.SnmpMgr.MultiV2.execute_mixed(operations)
      [
        {:ok, "Device 1 Description"},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.1.1.0", "Router 1"}, ...]}
      ]
  """
  def execute_mixed(operations, opts \\ []) do
    # Ensure required components are running (idempotent)
    ensure_components_started()

    timeout = Keyword.get(opts, :timeout, @default_timeout * 3)
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Normalize mixed operations to standard format
    normalized_operations = normalize_mixed_operations(operations, opts)

    execute_mixed_without_tasks(normalized_operations, timeout, max_concurrent)
  end

  # Private functions

  defp execute_multi_operation(targets_and_data, operation_type, opts) do
    if targets_and_data == [] do
      ensure_components_started()
      format_results(targets_and_data, [], opts)
    else
      # Ensure required components are running (idempotent)
      ensure_components_started()

      timeout = Keyword.get(opts, :timeout, @default_timeout)
      max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

      # Normalize requests to standard format
      normalized_requests = normalize_requests(targets_and_data, operation_type, opts)

      results =
        if operation_type in [:walk, :walk_table] do
          SnmpKit.SnmpMgr.V2Walk.walk_multi(normalized_requests,
            timeout: timeout,
            max_concurrent: max_concurrent
          )
        else
          execute_non_walk_requests(normalized_requests, timeout, max_concurrent)
        end

      # Format results according to return_format option
      format_results(targets_and_data, results, opts)
    end
  end

  defp execute_mixed_without_tasks(requests, timeout, max_concurrent) do
    indexed_requests = Enum.with_index(requests)

    {walk_requests, non_walk_requests} =
      Enum.split_with(indexed_requests, fn {request, _index} ->
        request.type in [:walk, :walk_table]
      end)

    non_walk_results =
      non_walk_requests
      |> Enum.map(&elem(&1, 0))
      |> execute_non_walk_requests(timeout, max_concurrent)

    walk_results =
      walk_requests
      |> Enum.map(&elem(&1, 0))
      |> SnmpKit.SnmpMgr.V2Walk.walk_multi(timeout: timeout, max_concurrent: max_concurrent)

    result_map =
      indexed_result_map(non_walk_requests, non_walk_results)
      |> Map.merge(indexed_result_map(walk_requests, walk_results))

    ordered_results(requests, result_map)
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
  # Requests are launched up to max_concurrent and correlated back through EngineV2.
  defp execute_non_walk_requests(requests, global_timeout, max_concurrent) do
    socket = SnmpKit.SnmpMgr.SocketManager.get_socket()
    queue = :queue.from_list(Enum.with_index(requests))

    state = %{
      socket: socket,
      queue: queue,
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

  defp launch_pending_requests(state) do
    if map_size(state.pending) >= state.max_concurrent or :queue.is_empty(state.queue) do
      state
    else
      {{:value, {request, index}}, queue} = :queue.out(state.queue)
      timeout = request_timeout(request, state.global_timeout)
      request_id = SnmpKit.SnmpMgr.RequestIdGenerator.next_id()

      pending_entry = %{index: index, timeout: timeout}

      case dispatch_request(state.socket, request, request_id, timeout) do
        :ok ->
          launch_pending_requests(%{
            state
            | queue: queue,
              pending: Map.put(state.pending, request_id, pending_entry)
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

  defp await_pending_requests(state) do
    cond do
      map_size(state.results) == state.total ->
        state

      map_size(state.pending) == 0 ->
        state

      true ->
        receive_timeout = pending_receive_timeout(state.pending)

        receive do
          {:snmp_response, request_id, response_data} ->
            state
            |> complete_pending_request(request_id, {:ok, response_data})
            |> launch_pending_requests()
            |> await_pending_requests()

          {:snmp_timeout, request_id} ->
            state
            |> complete_pending_request(request_id, {:error, :timeout})
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

  defp fail_stuck_pending_requests(state) do
    Enum.reduce(state.pending, %{state | pending: %{}}, fn {request_id, %{index: index}}, acc ->
      SnmpKit.SnmpMgr.EngineV2.unregister_request(SnmpKit.SnmpMgr.EngineV2, request_id)
      %{acc | results: Map.put(acc.results, index, {:error, :timeout})}
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

  defp pending_receive_timeout(pending) do
    pending
    |> Map.values()
    |> Enum.map(& &1.timeout)
    |> Enum.max(fn -> @default_timeout end)
    |> Kernel.+(1000)
  end

  defp dispatch_request(socket, request, request_id, timeout) do
    SnmpKit.SnmpMgr.EngineV2.register_request(
      SnmpKit.SnmpMgr.EngineV2,
      request_id,
      self(),
      timeout
    )

    case build_and_send_packet(socket, request, request_id) do
      :ok ->
        :ok

      {:error, reason} ->
        SnmpKit.SnmpMgr.EngineV2.unregister_request(SnmpKit.SnmpMgr.EngineV2, request_id)
        {:error, reason}
    end
  end

  defp request_timeout(request, global_timeout) do
    timeout = Keyword.get(request.opts, :timeout, global_timeout)
    if is_integer(timeout) and timeout > 0, do: timeout, else: global_timeout
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

      # Build SNMP message
      case build_snmp_message(request, request_id) do
        {:ok, message} ->
          # Send packet
          case SnmpKit.SnmpLib.Transport.send_packet(socket, target.host, target.port, message) do
            :ok ->
              Logger.debug(
                "Sent SNMP request #{request_id} to #{format_host(target.host)}:#{target.port}"
              )

              :ok

            {:error, reason} ->
              Logger.error("Failed to send SNMP request: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Failed to build SNMP message: #{inspect(reason)}")
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
    case resolve_oid(request.oid) do
      {:ok, oid_list} ->
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

      {:error, reason} ->
        {:error, {:oid_resolution_failed, reason}}
    end
  end

  # Resolve OID from string (symbolic or numeric) to list format
  defp resolve_oid(oid) when is_list(oid) and is_integer(hd(oid)), do: {:ok, oid}

  defp resolve_oid(oid) when is_binary(oid) do
    SnmpKit.SnmpMgr.Core.parse_oid(oid)
  end

  defp resolve_oid(oid), do: {:error, {:invalid_oid, oid}}

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

  # Ensure the V2 components are running; safe to call repeatedly
  defp ensure_components_started() do
    # Honor auto_start_services toggle; if disabled, do nothing.
    case SnmpKit.SnmpMgr.Config.get(:auto_start_services) do
      false ->
        :ok

      _true ->
        # RequestIdGenerator
        unless Process.whereis(SnmpKit.SnmpMgr.RequestIdGenerator) do
          _ =
            SnmpKit.SnmpMgr.RequestIdGenerator.start_link(
              name: SnmpKit.SnmpMgr.RequestIdGenerator
            )
        end

        # SocketManager
        unless Process.whereis(SnmpKit.SnmpMgr.SocketManager) do
          _ = SnmpKit.SnmpMgr.SocketManager.start_link(name: SnmpKit.SnmpMgr.SocketManager)
        end

        # EngineV2
        unless Process.whereis(SnmpKit.SnmpMgr.EngineV2) do
          _ = SnmpKit.SnmpMgr.EngineV2.start_link(name: SnmpKit.SnmpMgr.EngineV2)
        end

        :ok
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
