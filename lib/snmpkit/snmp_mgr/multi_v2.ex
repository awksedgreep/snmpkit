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

    # Execute using Task.async_stream for concurrency control
    results =
      normalized_operations
      |> Task.async_stream(
        fn operation -> execute_single_operation(operation, timeout) end,
        max_concurrency: max_concurrent,
        timeout:
          if(Enum.any?(normalized_operations, fn op -> op.type in [:walk, :walk_table] end),
            do: 1_200_000,
            else: timeout + 1000
          ),
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:task_failed, reason}}
      end)

    results
  end

  # Private functions

  defp execute_multi_operation(targets_and_data, operation_type, opts) do
    # Ensure required components are running (idempotent)
    ensure_components_started()

    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Normalize requests to standard format
    normalized_requests = normalize_requests(targets_and_data, operation_type, opts)

    # Execute using Task.async_stream for proper concurrency control
    results =
      normalized_requests
      |> Task.async_stream(
        fn request -> execute_single_operation(request, timeout) end,
        max_concurrency: max_concurrent,
        timeout: if(operation_type in [:walk, :walk_table], do: 1_200_000, else: timeout + 1000),
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:task_failed, reason}}
      end)

    # Format results according to return_format option
    format_results(targets_and_data, results, opts)
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

  defp execute_single_operation(request, global_timeout) do
    # Use per-request timeout if specified, otherwise use global timeout
    timeout = Keyword.get(request.opts, :timeout, global_timeout)

    # Validate timeout is a positive integer
    timeout = if is_integer(timeout) and timeout > 0, do: timeout, else: global_timeout

    try do
      case request.type do
        :walk ->
          # Use the proper walk implementation for walk operations
          SnmpKit.SnmpMgr.V2Walk.walk(request, timeout)

        :walk_table ->
          # Use the proper walk implementation for table walks
          SnmpKit.SnmpMgr.V2Walk.walk(request, timeout)

        _ ->
          # Handle single-request operations (get, get_bulk)
          execute_single_request(request, timeout)
      end
    rescue
      error ->
        Logger.error("Error in execute_single_operation: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  defp execute_single_request(request, global_timeout) do
    # Use per-request timeout if specified, otherwise use global timeout
    timeout = Keyword.get(request.opts, :timeout, global_timeout)

    # Validate timeout is a positive integer
    timeout = if is_integer(timeout) and timeout > 0, do: timeout, else: global_timeout

    try do
      # Generate unique request ID
      request_id = SnmpKit.SnmpMgr.RequestIdGenerator.next_id()

      # Get shared socket
      socket = SnmpKit.SnmpMgr.SocketManager.get_socket()

      # Register for response correlation
      SnmpKit.SnmpMgr.EngineV2.register_request(
        SnmpKit.SnmpMgr.EngineV2,
        request_id,
        self(),
        timeout
      )

      # Build and send SNMP packet
      case build_and_send_packet(socket, request, request_id) do
        :ok ->
          # Wait for response
          receive do
            {:snmp_response, ^request_id, response_data} ->
              {:ok, response_data}

            {:snmp_timeout, ^request_id} ->
              {:error, :timeout}
          after
            timeout ->
              # Unregister if we timeout locally
              SnmpKit.SnmpMgr.EngineV2.unregister_request(SnmpKit.SnmpMgr.EngineV2, request_id)
              {:error, :timeout}
          end

        {:error, reason} ->
          # Unregister if send fails
          SnmpKit.SnmpMgr.EngineV2.unregister_request(SnmpKit.SnmpMgr.EngineV2, request_id)
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error in execute_single_request: #{inspect(error)}")
        {:error, {:exception, error}}
    end
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

    case request.type do
      :get ->
        pdu = SnmpKit.SnmpLib.PDU.build_get_request(request.oid, request_id)
        message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, version)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      :get_bulk ->
        max_rep = Keyword.get(request.opts, :max_repetitions, 30)
        pdu = SnmpKit.SnmpLib.PDU.build_get_bulk_request(request.oid, request_id, 0, max_rep)
        message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, version)
        SnmpKit.SnmpLib.PDU.encode_message(message)

      # NOTE: :walk and :walk_table operations are handled by V2Walk module
      # and should not reach this function. They are delegated in execute_single_operation.

      _ ->
        {:error, {:unsupported_request_type, request.type}}
    end
  end

  defp resolve_target(target) when is_binary(target) do
    case SnmpKit.SnmpMgr.Target.parse(target) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{host: target, port: 161}
    end
  end

  defp resolve_target(target), do: target

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
