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
    - `:timeout` - Request timeout in milliseconds (default: 10000)
    - `:max_concurrent` - Maximum concurrent requests (default: 10)
    - `:return_format` - Format of returned results (default: `:list`)
      - `:list` - Returns list of results in same order as input
      - `:with_targets` - Returns list of {target, oid, result} tuples
      - `:map` - Returns map with {target, oid} keys and result values

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
    - `:max_repetitions` - Maximum repetitions for GetBulk (default: 10)

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

  ## Parameters
  - `targets_and_oids` - List of {target, root_oid} or {target, root_oid, opts} tuples
  - `opts` - Global options applied to all requests

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

  ## Parameters
  - `targets_and_tables` - List of {target, table_oid} or {target, table_oid, opts} tuples
  - `opts` - Global options applied to all requests

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
  - `opts` - Global options

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
        timeout: timeout + 1000,
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
        timeout: timeout + 1000,
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
              Keyword.get(global_opts, :max_repetitions, 10)
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
          max_repetitions: Keyword.get(global_opts, :max_repetitions, 10),
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
              Keyword.get(global_opts, :max_repetitions, 10)
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
          max_repetitions: Keyword.get(global_opts, :max_repetitions, 10),
          opts: global_opts
        }
    end)
  end

  defp execute_single_operation(request, timeout) do
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

  defp execute_single_request(request, timeout) do
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
        max_rep = Keyword.get(request.opts, :max_repetitions, 10)
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
        results

      :with_targets ->
        # Normalize targets_and_data to extract target and data parts
        normalized_targets = normalize_targets_and_data(targets_and_data)

        normalized_targets
        |> Enum.zip(results)
        |> Enum.map(fn {{target, data}, result} ->
          {target, data, result}
        end)

      :map ->
        # Normalize targets_and_data to extract target and data parts
        normalized_targets = normalize_targets_and_data(targets_and_data)

        normalized_targets
        |> Enum.zip(results)
        |> Enum.map(fn {{target, data}, result} ->
          {{target, data}, result}
        end)
        |> Enum.into(%{})

      _ ->
        # Unknown format, default to :list
        results
    end
  end

  defp normalize_targets_and_data(targets_and_data) do
    targets_and_data
    |> Enum.map(fn
      {target, data, _opts} -> {target, data}
      {target, data} -> {target, data}
    end)
  end
end
