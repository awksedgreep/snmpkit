defmodule SnmpKit.SnmpMgr.Multi do
  @moduledoc """
  Concurrent multi-target SNMP operations.

  Provides functions to perform SNMP operations against multiple targets
  concurrently, with configurable timeouts and error handling.
  """

  require Logger

  @default_timeout 10_000
  @default_max_concurrent 10

  @doc """
  Performs GET operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} or {target, oid, opts} tuples
  - `opts` - Global options applied to all requests
    - `:return_format` - Format of returned results (default: `:list`)
      - `:list` - Returns list of results in same order as input
      - `:with_targets` - Returns list of {target, oid, result} tuples
      - `:map` - Returns map with {target, oid} keys and result values

  ## Examples

      iex> requests = [
      ...>   {"device1", "sysDescr.0"},
      ...>   {"device2", "sysUpTime.0"},
      ...>   {"device3", "ifNumber.0"}
      ...> ]

      # Default list format
      iex> SnmpKit.SnmpMgr.Multi.get_multi(requests)
      [
        {:ok, "Device 1 Description"},
        {:ok, 123456},
        {:error, :timeout}
      ]

      # With targets format - includes host/oid association
      iex> SnmpKit.SnmpMgr.Multi.get_multi(requests, return_format: :with_targets)
      [
        {"device1", "sysDescr.0", {:ok, "Device 1 Description"}},
        {"device2", "sysUpTime.0", {:ok, 123456}},
        {"device3", "ifNumber.0", {:error, :timeout}}
      ]

      # Map format - easy result lookup by host/oid
      iex> SnmpKit.SnmpMgr.Multi.get_multi(requests, return_format: :map)
      %{
        {"device1", "sysDescr.0"} => {:ok, "Device 1 Description"},
        {"device2", "sysUpTime.0"} => {:ok, 123456},
        {"device3", "ifNumber.0"} => {:error, :timeout}
      }
  """
  def get_multi(targets_and_oids, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    _max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Use Engine for shared socket operations
    engine = get_or_start_engine(opts)

    # Convert to engine request format
    requests = normalize_requests_for_engine(targets_and_oids, :get, opts)

    # Submit batch to engine
    results = submit_batch_to_engine(engine, requests, timeout)

    format_results(targets_and_oids, results, opts)
  end

  @doc """
  Performs GETBULK operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} or {target, oid, opts} tuples
  - `opts` - Global options applied to all requests
    - `:return_format` - Format of returned results (default: `:list`)
      - `:list` - Returns list of results in same order as input
      - `:with_targets` - Returns list of {target, oid, result} tuples
      - `:map` - Returns map with {target, oid} keys and result values

  ## Examples

      iex> requests = [
      ...>   {"switch1", "ifTable"},
      ...>   {"switch2", "ifTable"},
      ...>   {"router1", "ipRouteTable"}
      ...> ]

      # Default list format
      iex> SnmpKit.SnmpMgr.Multi.get_bulk_multi(requests, max_repetitions: 20)
      [
        {:ok, [{[1,3,6,1,2,1,2,2,1,2,1], :octet_string, "eth0"}, ...]},
        {:ok, [{[1,3,6,1,2,1,2,2,1,2,1], :octet_string, "GigE0/1"}, ...]},
        {:error, :timeout}
      ]

      # With targets format
      iex> SnmpKit.SnmpMgr.Multi.get_bulk_multi(requests, return_format: :with_targets, max_repetitions: 20)
      [
        {"switch1", "ifTable", {:ok, [{[1,3,6,1,2,1,2,2,1,2,1], :octet_string, "eth0"}, ...]}},
        {"switch2", "ifTable", {:ok, [{[1,3,6,1,2,1,2,2,1,2,1], :octet_string, "GigE0/1"}, ...]}},
        {"router1", "ipRouteTable", {:error, :timeout}}
      ]

      # Map format
      iex> SnmpKit.SnmpMgr.Multi.get_bulk_multi(requests, return_format: :map, max_repetitions: 20)
      %{
        {"switch1", "ifTable"} => {:ok, [{[1,3,6,1,2,1,2,2,1,2,1], :octet_string, "eth0"}, ...]},
        {"switch2", "ifTable"} => {:ok, [{[1,3,6,1,2,1,2,2,1,2,1], :octet_string, "GigE0/1"}, ...]},
        {"router1", "ipRouteTable"} => {:error, :timeout}
      }
  """
  def get_bulk_multi(targets_and_oids, opts \\ []) do
    # get_bulk_multi called with #{length(targets_and_oids)} targets
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    _max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Use Engine for shared socket operations
    engine = get_or_start_engine(opts)
    # Engine obtained: #{inspect(engine)}

    # Convert to engine request format
    requests = normalize_requests_for_engine(targets_and_oids, :get_bulk, opts)
    # Normalized #{length(requests)} requests

    # Submit batch to engine
    results = submit_batch_to_engine(engine, requests, timeout)
    # Got results: #{inspect(results)}

    format_results(targets_and_oids, results, opts)
  end

  @doc """
  Performs walk operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, root_oid} or {target, root_oid, opts} tuples
  - `opts` - Global options applied to all requests
    - `:return_format` - Format of returned results (default: `:list`)
      - `:list` - Returns list of results in same order as input
      - `:with_targets` - Returns list of {target, oid, result} tuples
      - `:map` - Returns map with {target, oid} keys and result values

  ## Examples

      iex> requests = [
      ...>   {"device1", "system"},
      ...>   {"device2", "interfaces"},
      ...>   {"device3", [1, 3, 6, 1, 2, 1, 4]}
      ...> ]

      # Default list format
      iex> SnmpKit.SnmpMgr.Multi.walk_multi(requests, version: :v2c)
      [
        {:ok, [{[1,3,6,1,2,1,1,1,0], :octet_string, "Device 1"}, ...]},
        {:ok, [{[1,3,6,1,2,1,2,1,0], :integer, 24}, ...]},
        {:error, :timeout}
      ]

      # With targets format
      iex> SnmpKit.SnmpMgr.Multi.walk_multi(requests, return_format: :with_targets, version: :v2c)
      [
        {"device1", "system", {:ok, [{[1,3,6,1,2,1,1,1,0], :octet_string, "Device 1"}, ...]}},
        {"device2", "interfaces", {:ok, [{[1,3,6,1,2,1,2,1,0], :integer, 24}, ...]}},
        {"device3", [1, 3, 6, 1, 2, 1, 4], {:error, :timeout}}
      ]

      # Map format
      iex> SnmpKit.SnmpMgr.Multi.walk_multi(requests, return_format: :map, version: :v2c)
      %{
        {"device1", "system"} => {:ok, [{[1,3,6,1,2,1,1,1,0], :octet_string, "Device 1"}, ...]},
        {"device2", "interfaces"} => {:ok, [{[1,3,6,1,2,1,2,1,0], :integer, 24}, ...]},
        {"device3", [1, 3, 6, 1, 2, 1, 4]} => {:error, :timeout}
      }
  """
  def walk_multi(targets_and_oids, opts \\ []) do
    # Walks take longer
    timeout = Keyword.get(opts, :timeout, @default_timeout * 3)
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Use direct iterative walks instead of Engine (which only handles single requests)
    requests = normalize_walk_requests(targets_and_oids, opts)

    # Submit batch using proper iterative walk logic
    results = submit_walk_batch(requests, timeout, max_concurrent)

    format_results(targets_and_oids, results, opts)
  end

  @doc """
  Performs table walk operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_tables` - List of {target, table_oid} or {target, table_oid, opts} tuples
  - `opts` - Global options applied to all requests
    - `:return_format` - Format of returned results (default: `:list`)
      - `:list` - Returns list of results in same order as input
      - `:with_targets` - Returns list of {target, oid, result} tuples
      - `:map` - Returns map with {target, oid} keys and result values

  ## Examples

      iex> requests = [
      ...>   {"switch1", "ifTable"},
      ...>   {"switch2", "ifTable"},
      ...>   {"router1", "ipRouteTable"}
      ...> ]

      # Default list format
      iex> SnmpKit.SnmpMgr.Multi.walk_table_multi(requests, version: :v2c)
      [
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]},
        {:error, :host_unreachable}
      ]

      # With targets format
      iex> SnmpKit.SnmpMgr.Multi.walk_table_multi(requests, return_format: :with_targets, version: :v2c)
      [
        {"switch1", "ifTable", {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]}},
        {"switch2", "ifTable", {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]}},
        {"router1", "ipRouteTable", {:error, :host_unreachable}}
      ]

      # Map format
      iex> SnmpKit.SnmpMgr.Multi.walk_table_multi(requests, return_format: :map, version: :v2c)
      %{
        {"switch1", "ifTable"} => {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {"switch2", "ifTable"} => {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]},
        {"router1", "ipRouteTable"} => {:error, :host_unreachable}
      }
  """
  def walk_table_multi(targets_and_tables, opts \\ []) do
    # Table walks take longer
    timeout = Keyword.get(opts, :timeout, @default_timeout * 5)
    _max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Use Engine for shared socket operations
    engine = get_or_start_engine(opts)

    # Convert to engine request format
    requests = normalize_requests_for_engine(targets_and_tables, :walk_table, opts)

    # Submit batch to engine
    results = submit_batch_to_engine(engine, requests, timeout)

    format_results(targets_and_tables, results, opts)
  end

  @doc """
  Executes mixed SNMP operations against multiple targets concurrently.

  Allows different operation types per target for maximum flexibility.

  ## Parameters
  - `operations` - List of {operation, target, oid_or_args, opts} tuples
  - `opts` - Global options

  ## Examples

      iex> operations = [
      ...>   {:get, "device1", "sysDescr.0", []},
      ...>   {:get_bulk, "switch1", "ifTable", [max_repetitions: 20]},
      ...>   {:walk, "router1", "system", [version: :v2c]}
      ...> ]

      # Default list format
      iex> SnmpKit.SnmpMgr.Multi.execute_mixed(operations)
      [
        {:ok, "Device 1 Description"},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.1.1.0", "Router 1"}, ...]}
      ]

      # Note: execute_mixed handles different operation types, so return_format
      # is not applicable here as operations have different target/args structures
  """
  def execute_mixed(operations, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout * 3)
    _max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Use Engine for shared socket operations
    engine = get_or_start_engine(opts)

    # Convert operations to engine request format
    requests = normalize_mixed_operations_for_engine(operations, opts)

    # Submit batch to engine
    submit_batch_to_engine(engine, requests, timeout)
  end

  @doc """
  Monitors multiple devices for changes by polling at regular intervals.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} tuples to monitor
  - `callback` - Function called with {target, oid, old_value, new_value} when changes occur
  - `opts` - Options including :interval, :initial_poll, :max_concurrent

  ## Examples

      targets = [{"device1", "sysUpTime.0"}, {"device2", "ifInOctets.1"}]
      callback = fn change -> IO.inspect(change) end
      {:ok, monitor_pid} = SnmpKit.SnmpMgr.Multi.monitor(targets, callback, interval: 30_000)
  """
  def monitor(targets_and_oids, callback, opts \\ []) do
    interval = Keyword.get(opts, :interval, 30_000)
    initial_poll = Keyword.get(opts, :initial_poll, true)

    {:ok,
     spawn_link(fn ->
       monitor_loop(targets_and_oids, callback, opts, %{}, initial_poll, interval)
     end)}
  end

  # Private functions

  defp get_or_start_engine(_opts) do
    # Get or start the SNMP engine for shared socket operations
    case Process.whereis(SnmpKit.SnmpMgr.Engine) do
      nil ->
        # Start engine if not running
        Logger.debug("Starting new SNMP engine")
        {:ok, engine} = SnmpKit.SnmpMgr.Engine.start_link(name: SnmpKit.SnmpMgr.Engine)
        Logger.debug("Started SNMP engine: #{inspect(engine)}")
        engine

      engine ->
        Logger.debug("Using existing SNMP engine: #{inspect(engine)}")
        engine
    end
  end

  defp normalize_requests_for_engine(targets_and_data, operation_type, global_opts) do
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

  defp normalize_mixed_operations_for_engine(operations, global_opts) do
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

  defp submit_batch_to_engine(engine, requests, timeout) do
    # Submit batch to engine and collect results
    Logger.debug("Submitting batch of #{length(requests)} requests to engine #{inspect(engine)}")

    tasks =
      requests
      |> Enum.with_index()
      |> Enum.map(fn {request, index} ->
        Task.async(fn ->
          Logger.debug("Task #{index}: Calling submit_request with #{inspect(request)}")
          result = SnmpKit.SnmpMgr.Engine.submit_request(engine, request, timeout: :infinity)
          Logger.debug("Task #{index}: submit_request returned #{inspect(result)}")
          result
        end)
      end)

    # Collect all results
    Logger.debug(
      "Waiting for #{length(tasks)} tasks to complete with timeout #{timeout + 1000}ms"
    )

    results =
      tasks
      # Add buffer to engine timeout
      |> Task.yield_many(timeout + 1000)
      |> Enum.map(fn {_task, result} ->
        case result do
          {:ok, value} -> value
          nil -> {:error, :timeout}
          {:exit, reason} -> {:error, {:task_failed, reason}}
        end
      end)

    Logger.debug("Batch completed with results: #{inspect(results)}")
    results
  end

  # Legacy function - now handled by normalize_mixed_operations_for_engine
  # Kept for backwards compatibility if needed elsewhere

  # Legacy execute_operation functions - now handled by Engine
  # Operations are now processed by SnmpKit.SnmpMgr.Engine

  defp monitor_loop(targets_and_oids, callback, opts, previous_values, initial_poll, interval) do
    if initial_poll do
      # Get initial values
      current_values = poll_targets(targets_and_oids, opts)

      # Sleep and start monitoring loop
      Process.sleep(interval)
      monitor_loop(targets_and_oids, callback, opts, current_values, false, interval)
    else
      # Poll for current values
      current_values = poll_targets(targets_and_oids, opts)

      # Check for changes and call callback
      check_for_changes(targets_and_oids, previous_values, current_values, callback)

      # Sleep and continue loop
      Process.sleep(interval)
      monitor_loop(targets_and_oids, callback, opts, current_values, false, interval)
    end
  end

  defp poll_targets(targets_and_oids, opts) do
    # Use updated get_multi with shared socket
    get_multi(targets_and_oids, opts)
    |> Enum.zip(targets_and_oids)
    |> Enum.map(fn {result, {target, oid}} ->
      {{target, oid}, result}
    end)
    |> Enum.into(%{})
  end

  defp check_for_changes(targets_and_oids, previous_values, current_values, callback) do
    targets_and_oids
    |> Enum.each(fn {target, oid} ->
      key = {target, oid}
      old_value = Map.get(previous_values, key)
      new_value = Map.get(current_values, key)

      if old_value != nil and old_value != new_value do
        callback.({target, oid, old_value, new_value})
      end
    end)
  end

  # Format results based on return_format option
  defp format_results(targets_and_data, results, opts) do
    case Keyword.get(opts, :return_format, :list) do
      :list ->
        Enum.map(results, &enrich_any_result(&1, opts))

      :with_targets ->
        # Normalize targets_and_data to extract target and data parts
        normalized_targets =
          targets_and_data
          |> Enum.map(fn
            {target, data, _opts} -> {target, data}
            {target, data} -> {target, data}
          end)

        normalized_targets
        |> Enum.zip(results)
        |> Enum.map(fn {{target, data}, result} ->
          {target, data, enrich_any_result(result, opts)}
        end)

      :map ->
        # Normalize targets_and_data to extract target and data parts
        normalized_targets =
          targets_and_data
          |> Enum.map(fn
            {target, data, _opts} -> {target, data}
            {target, data} -> {target, data}
          end)

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

  # Enrich any engine result into standardized maps while preserving {:ok, ...} | {:error, ...}
  defp enrich_any_result({:ok, %{oid: _}} = result, _opts), do: result
  defp enrich_any_result({:ok, [%{oid: _} | _] = _already_enriched} = result, _opts), do: result

  defp enrich_any_result({:ok, {oid, type, value}}, opts),
    do: {:ok, SnmpKit.SnmpMgr.Format.enrich_varbind({oid, type, value}, opts)}

  defp enrich_any_result({:ok, list}, opts) when is_list(list) do
    {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(list, opts)}
  end

  defp enrich_any_result(other, _opts), do: other

  # Walk-specific request normalization for proper iterative walks
  defp normalize_walk_requests(targets_and_data, global_opts) do
    targets_and_data
    |> Enum.map(fn
      {target, data, request_opts} ->
        %{
          target: target,
          oid: data,
          opts: Keyword.merge(global_opts, request_opts)
        }

      {target, data} ->
        %{
          target: target,
          oid: data,
          opts: global_opts
        }
    end)
  end

  # Submit walk requests using proper iterative walk logic
  defp submit_walk_batch(requests, timeout, max_concurrent) do
    # Use Task.async_stream for concurrent walks with proper iterative walk execution
    requests
    |> Task.async_stream(
      fn request ->
        # Use the bulk walk function directly for proper iterative behavior
        case resolve_oid(request.oid) do
          {:ok, start_oid} ->
            # Call the iterative bulk walk function that handles multiple GETBULK requests
            case bulk_walk_subtree_iterative(
                   request.target,
                   start_oid,
                   start_oid,
                   [],
                   1000,
                   request.opts
                 ) do
              {:ok, results} ->
                # Convert OID lists to strings for final output (matching single walk format)
                formatted_results =
                  Enum.map(results, fn
                    {oid_list, type, value} -> {Enum.join(oid_list, "."), type, value}
                  end)

                {:ok, formatted_results}

              error ->
                error
            end

          error ->
            error
        end
      end,
      max_concurrency: max_concurrent,
      timeout: timeout + 1000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, :timeout}
      {:exit, reason} -> {:error, {:task_failed, reason}}
    end)
  end

  # Proper iterative bulk walk that continues until end of subtree
  defp bulk_walk_subtree_iterative(target, current_oid, root_oid, acc, remaining, opts)
       when remaining > 0 do
    require Logger

    max_repetitions =
      min(remaining, Keyword.get(opts, :max_repetitions, 10))

    bulk_opts =
      opts
      |> Keyword.put(:max_repetitions, max_repetitions)
      |> Keyword.put(:version, :v2c)

    Logger.debug(
      "walk_multi_iterative: target=#{target}, current_oid=#{inspect(current_oid)}, remaining=#{remaining}, max_rep=#{max_repetitions}"
    )

    case SnmpKit.SnmpMgr.Core.send_get_bulk_request(target, current_oid, bulk_opts) do
      {:ok, results} ->
        Logger.debug("walk_multi_iterative: got #{length(results)} raw results from GETBULK")

        # Log first few results for debugging
        results
        |> Enum.take(3)
        |> Enum.with_index()
        |> Enum.each(fn {{oid, type, value}, idx} ->
          Logger.debug(
            "walk_multi_iterative: result[#{idx}] = #{inspect(oid)} (#{type}) = #{inspect(String.slice(to_string(value), 0, 20))}"
          )
        end)

        # Filter results that are still within the subtree scope
        {in_scope, next_oid} = filter_subtree_results_iterative(results, root_oid)

        Logger.debug(
          "walk_multi_iterative: #{length(in_scope)} results in scope, next_oid=#{inspect(next_oid)}"
        )

        Logger.debug("walk_multi_iterative: root_oid=#{inspect(root_oid)}")

        # Log in-scope OIDs
        in_scope
        |> Enum.take(3)
        |> Enum.with_index()
        |> Enum.each(fn {{oid, _type, _value}, idx} ->
          Logger.debug("walk_multi_iterative: in_scope[#{idx}] = #{inspect(oid)}")
        end)

        if Enum.empty?(in_scope) or next_oid == nil do
          Logger.debug(
            "walk_multi_iterative: STOPPING - empty_in_scope=#{Enum.empty?(in_scope)}, next_oid_nil=#{next_oid == nil}"
          )

          Logger.debug("walk_multi_iterative: final result count = #{length(acc)}")
          {:ok, Enum.reverse(acc)}
        else
          new_acc = Enum.reverse(in_scope) ++ acc

          Logger.debug(
            "walk_multi_iterative: CONTINUING - total results so far = #{length(new_acc)}"
          )

          # Continue walking from the next OID
          bulk_walk_subtree_iterative(
            target,
            next_oid,
            root_oid,
            new_acc,
            remaining - length(in_scope),
            opts
          )
        end

      {:error, error} ->
        Logger.debug("walk_multi_iterative: ERROR - #{inspect(error)}")
        {:error, error}
    end
  end

  defp bulk_walk_subtree_iterative(_target, _current_oid, _root_oid, acc, 0, _opts) do
    {:ok, Enum.reverse(acc)}
  end

  # Proper filtering for iterative walks
  defp filter_subtree_results_iterative(results, root_oid) do
    require Logger

    in_scope_results =
      results
      |> Enum.filter(fn
        {oid_list, _type, _value} ->
          starts_with = List.starts_with?(oid_list, root_oid)

          Logger.debug(
            "walk_multi_filter: checking #{inspect(oid_list)} starts_with #{inspect(root_oid)} = #{starts_with}"
          )

          starts_with

        {_oid_list, _value} ->
          Logger.debug("walk_multi_filter: rejecting 2-tuple format")
          false
      end)

    Logger.debug("walk_multi_filter: #{length(in_scope_results)} results passed filtering")

    # Next OID should be from the last in-scope result for continuing the walk
    next_oid =
      case List.last(in_scope_results) do
        {oid_list, _type, _value} ->
          Logger.debug("walk_multi_filter: next_oid = #{inspect(oid_list)}")
          oid_list

        _ ->
          Logger.debug("walk_multi_filter: next_oid = nil (no in_scope results)")
          nil
      end

    {in_scope_results, next_oid}
  end

  # OID resolution helper
  defp resolve_oid(oid) when is_binary(oid) do
    SnmpKit.SnmpLib.OID.string_to_list(oid)
  end

  defp resolve_oid(oid) when is_list(oid) do
    {:ok, oid}
  end

  defp resolve_oid(_), do: {:error, :invalid_oid}
end
