defmodule SnmpMgr.Multi do
  @moduledoc """
  Concurrent multi-target SNMP operations.
  
  Provides functions to perform SNMP operations against multiple targets
  concurrently, with configurable timeouts and error handling.
  """

  @default_timeout 10_000
  @default_max_concurrent 10

  @doc """
  Performs GET operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} or {target, oid, opts} tuples
  - `opts` - Global options applied to all requests

  ## Examples

      iex> requests = [
      ...>   {"device1", "sysDescr.0"},
      ...>   {"device2", "sysUpTime.0"},
      ...>   {"device3", "ifNumber.0"}
      ...> ]
      iex> SnmpMgr.Multi.get_multi(requests)
      [
        {:ok, "Device 1 Description"},
        {:ok, 123456},
        {:error, :timeout}
      ]
  """
  def get_multi(targets_and_oids, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    
    execute_concurrent_requests(targets_and_oids, timeout, max_concurrent, fn {target, oid, request_opts} ->
      merged_opts = Keyword.merge(opts, request_opts)
      SnmpMgr.get(target, oid, merged_opts)
    end)
  end

  @doc """
  Performs GETBULK operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} or {target, oid, opts} tuples
  - `opts` - Global options applied to all requests

  ## Examples

      iex> requests = [
      ...>   {"switch1", "ifTable"},
      ...>   {"switch2", "ifTable"},
      ...>   {"router1", "ipRouteTable"}
      ...> ]
      iex> SnmpMgr.Multi.get_bulk_multi(requests, max_repetitions: 20)
      [
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]},
        {:error, :timeout}
      ]
  """
  def get_bulk_multi(targets_and_oids, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    
    execute_concurrent_requests(targets_and_oids, timeout, max_concurrent, fn {target, oid, request_opts} ->
      merged_opts = Keyword.merge(opts, request_opts)
      SnmpMgr.get_bulk(target, oid, merged_opts)
    end)
  end

  @doc """
  Performs walk operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_oids` - List of {target, root_oid} or {target, root_oid, opts} tuples
  - `opts` - Global options applied to all requests

  ## Examples

      iex> requests = [
      ...>   {"device1", "system"},
      ...>   {"device2", "interfaces"},
      ...>   {"device3", [1, 3, 6, 1, 2, 1, 4]}
      ...> ]
      iex> SnmpMgr.Multi.walk_multi(requests, version: :v2c)
      [
        {:ok, [{"1.3.6.1.2.1.1.1.0", "Device 1"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.1.0", 24}, ...]},
        {:error, :timeout}
      ]
  """
  def walk_multi(targets_and_oids, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout * 3) # Walks take longer
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    
    execute_concurrent_requests(targets_and_oids, timeout, max_concurrent, fn {target, oid, request_opts} ->
      merged_opts = Keyword.merge(opts, request_opts)
      SnmpMgr.walk(target, oid, merged_opts)
    end)
  end

  @doc """
  Performs table walk operations against multiple targets concurrently.

  ## Parameters
  - `targets_and_tables` - List of {target, table_oid} or {target, table_oid, opts} tuples
  - `opts` - Global options applied to all requests

  ## Examples

      iex> requests = [
      ...>   {"switch1", "ifTable"},
      ...>   {"switch2", "ifTable"},
      ...>   {"router1", "ipRouteTable"}
      ...> ]
      iex> SnmpMgr.Multi.walk_table_multi(requests, version: :v2c)
      [
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "GigE0/1"}, ...]},
        {:error, :host_unreachable}
      ]
  """
  def walk_table_multi(targets_and_tables, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout * 5) # Table walks take longer
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    
    execute_concurrent_requests(targets_and_tables, timeout, max_concurrent, fn {target, table_oid, request_opts} ->
      merged_opts = Keyword.merge(opts, request_opts)
      SnmpMgr.walk_table(target, table_oid, merged_opts)
    end)
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
      iex> SnmpMgr.Multi.execute_mixed(operations)
      [
        {:ok, "Device 1 Description"},
        {:ok, [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]},
        {:ok, [{"1.3.6.1.2.1.1.1.0", "Router 1"}, ...]}
      ]
  """
  def execute_mixed(operations, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout * 3)
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    
    # Convert operations to normalized format
    normalized_ops = 
      operations
      |> Enum.map(fn
        {operation, target, args, request_opts} ->
          {operation, target, args, request_opts}
        {operation, target, args} ->
          {operation, target, args, []}
      end)
    
    execute_concurrent_operations(normalized_ops, timeout, max_concurrent, opts)
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
      {:ok, monitor_pid} = SnmpMgr.Multi.monitor(targets, callback, interval: 30_000)
  """
  def monitor(targets_and_oids, callback, opts \\ []) do
    interval = Keyword.get(opts, :interval, 30_000)
    initial_poll = Keyword.get(opts, :initial_poll, true)
    
    {:ok, spawn_link(fn -> 
      monitor_loop(targets_and_oids, callback, opts, %{}, initial_poll, interval)
    end)}
  end

  # Private functions

  defp execute_concurrent_requests(targets_and_data, timeout, max_concurrent, operation_fn) do
    # Normalize input format
    normalized = 
      targets_and_data
      |> Enum.map(fn
        {target, data, opts} -> {target, data, opts}
        {target, data} -> {target, data, []}
      end)
    
    # Execute in chunks to limit concurrency
    normalized
    |> Enum.chunk_every(max_concurrent)
    |> Enum.flat_map(fn chunk ->
      tasks = 
        chunk
        |> Enum.map(fn request ->
          Task.async(fn -> operation_fn.(request) end)
        end)
      
      tasks
      |> Task.yield_many(timeout)
      |> Enum.map(fn {_task, result} ->
        case result do
          {:ok, value} -> value
          nil -> {:error, :timeout}
          {:exit, reason} -> {:error, {:task_failed, reason}}
        end
      end)
    end)
  end

  defp execute_concurrent_operations(operations, timeout, max_concurrent, global_opts) do
    operations
    |> Enum.chunk_every(max_concurrent)
    |> Enum.flat_map(fn chunk ->
      tasks = 
        chunk
        |> Enum.map(fn {operation, target, args, request_opts} ->
          Task.async(fn -> 
            merged_opts = Keyword.merge(global_opts, request_opts)
            execute_operation(operation, target, args, merged_opts)
          end)
        end)
      
      tasks
      |> Task.yield_many(timeout)
      |> Enum.map(fn {_task, result} ->
        case result do
          {:ok, value} -> value
          nil -> {:error, :timeout}
          {:exit, reason} -> {:error, {:task_failed, reason}}
        end
      end)
    end)
  end

  defp execute_operation(:get, target, oid, opts) do
    SnmpMgr.get(target, oid, opts)
  end

  defp execute_operation(:get_next, target, oid, opts) do
    SnmpMgr.get_next(target, oid, opts)
  end

  defp execute_operation(:set, target, {oid, value}, opts) do
    SnmpMgr.set(target, oid, value, opts)
  end

  defp execute_operation(:get_bulk, target, oid, opts) do
    SnmpMgr.get_bulk(target, oid, opts)
  end

  defp execute_operation(:walk, target, root_oid, opts) do
    SnmpMgr.walk(target, root_oid, opts)
  end

  defp execute_operation(:walk_table, target, table_oid, opts) do
    SnmpMgr.walk_table(target, table_oid, opts)
  end

  defp execute_operation(operation, target, args, _opts) do
    {:error, {:unsupported_operation, operation, target, args}}
  end

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
end