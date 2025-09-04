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
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Use direct SNMP get_bulk operations instead of Engine
    requests = normalize_bulk_requests(targets_and_oids, opts)

    # Submit batch using get_bulk directly
    results = submit_bulk_batch(requests, timeout, max_concurrent)

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

    # Use SnmpKit.SnmpMgr.Walk.walk for proper iterative walk behavior
    requests = normalize_walk_requests(targets_and_oids, opts)

    # Submit batch using Walk.walk directly
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
        results

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
          {target, data, result}
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
          {{target, data}, result}
        end)
        |> Enum.into(%{})

      _ ->
        # Unknown format, default to :list
        results
    end
  end

  # Walk-specific request normalization for V2Walk
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

  # Submit walk requests using Walk.walk directly
  defp submit_walk_batch(requests, timeout, max_concurrent) do
    # Use Task.async_stream for concurrent walks with proper Walk.walk execution
    requests
    |> Task.async_stream(
      fn request ->
        # Call Walk.walk directly for each request
        SnmpKit.SnmpMgr.Walk.walk(request.target, request.oid, request.opts)
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

  # Bulk-specific request normalization for direct get_bulk calls
  defp normalize_bulk_requests(targets_and_data, global_opts) do
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

  # Submit bulk requests using get_bulk directly
  defp submit_bulk_batch(requests, timeout, max_concurrent) do
    # Use Task.async_stream for concurrent bulk operations with proper get_bulk execution
    requests
    |> Task.async_stream(
      fn request ->
        # Call get_bulk directly for each request
        SnmpKit.SnmpMgr.Bulk.get_bulk(request.target, request.oid, request.opts)
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
end
