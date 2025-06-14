defmodule SnmpMgr.Stream do
  @moduledoc """
  High-performance streaming SNMP operations for memory-efficient processing.
  
  This module provides streaming APIs that allow processing of large SNMP datasets
  without loading everything into memory at once. Perfect for large tables and
  real-time monitoring scenarios.
  """

  @default_chunk_size 50
  @default_buffer_size 1000

  @doc """
  Creates a stream for walking large SNMP trees without memory overhead.

  The stream lazily fetches data in chunks, allowing processing of arbitrarily
  large SNMP trees with constant memory usage.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :chunk_size, :version, :adaptive

  ## Examples

      # Process a large table efficiently
      "switch.local"
      |> SnmpMgr.Stream.walk_stream("ifTable")
      |> Stream.filter(fn {_oid, value} -> String.contains?(value, "Gigabit") end)
      |> Stream.map(&extract_interface_info/1)
      |> Enum.to_list()

      # Real-time processing with backpressure
      "router.local"
      |> SnmpMgr.Stream.walk_stream("ipRouteTable", chunk_size: 100)
      |> Stream.each(&update_routing_database/1)
      |> Stream.run()
  """
  def walk_stream(target, root_oid, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    adaptive = Keyword.get(opts, :adaptive, true)
    
    Stream.resource(
      fn -> initialize_walk_stream(target, root_oid, chunk_size, adaptive, opts) end,
      fn state -> fetch_next_chunk(state, opts) end,
      fn state -> cleanup_walk_stream(state) end
    )
  end

  @doc """
  Creates a stream for processing large SNMP tables.

  Optimized for table structures with intelligent chunking based on
  table columns and indexes.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to stream
  - `opts` - Options including :chunk_size, :columns, :indexes

  ## Examples

      # Stream interface table with column filtering
      "switch.local"
      |> SnmpMgr.Stream.table_stream("ifTable", columns: [:ifDescr, :ifOperStatus])
      |> Stream.filter(fn {_index, data} -> data[:ifOperStatus] == 1 end)
      |> Stream.map(fn {index, data} -> {index, data[:ifDescr]} end)
      |> Enum.to_list()

      # Process table with custom chunk size
      "device.local"
      |> SnmpMgr.Stream.table_stream("ipRouteTable", chunk_size: 200)
      |> Stream.each(&process_route_entry/1)
      |> Stream.run()
  """
  def table_stream(target, table_oid, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    columns = Keyword.get(opts, :columns)
    
    Stream.resource(
      fn -> initialize_table_stream(target, table_oid, chunk_size, columns, opts) end,
      fn state -> fetch_next_table_chunk(state, opts) end,
      fn state -> cleanup_table_stream(state) end
    )
  end

  @doc """
  Creates a real-time monitoring stream that polls devices at intervals.

  Provides a continuous stream of SNMP data for real-time monitoring
  and alerting applications.

  ## Parameters
  - `targets` - List of {target, oid} tuples to monitor
  - `opts` - Options including :interval, :buffer_size, :error_handling

  ## Examples

      # Monitor multiple devices
      targets = [
        {"switch1", "ifInOctets.1"},
        {"switch2", "ifInOctets.1"},
        {"router1", "sysUpTime.0"}
      ]
      
      targets
      |> SnmpMgr.Stream.monitor_stream(interval: 30_000)
      |> Stream.each(&send_to_metrics_system/1)
      |> Stream.run()

      # Monitor with error handling
      targets
      |> SnmpMgr.Stream.monitor_stream(
           interval: 10_000, 
           error_handling: :skip_errors
         )
      |> Stream.filter(&is_successful_reading/1)
      |> Stream.each(&update_dashboard/1)
      |> Stream.run()
  """
  def monitor_stream(targets, opts \\ []) do
    interval = Keyword.get(opts, :interval, 30_000)
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    error_handling = Keyword.get(opts, :error_handling, :include_errors)
    
    Stream.resource(
      fn -> initialize_monitor_stream(targets, interval, buffer_size, error_handling, opts) end,
      fn state -> fetch_next_monitor_data(state, opts) end,
      fn state -> cleanup_monitor_stream(state) end
    )
  end

  @doc """
  Creates a concurrent stream that processes multiple devices in parallel.

  Combines results from multiple devices into a single stream with
  configurable concurrency and ordering.

  ## Parameters
  - `device_operations` - List of {target, operation, oid, opts} tuples
  - `opts` - Options including :max_concurrent, :ordered, :timeout

  ## Examples

      # Concurrent table walks
      operations = [
        {"switch1", :walk_table, "ifTable", []},
        {"switch2", :walk_table, "ifTable", []},
        {"router1", :walk, "ipRouteTable", []}
      ]
      
      operations
      |> SnmpMgr.Stream.concurrent_stream(max_concurrent: 3)
      |> Stream.each(&process_device_data/1)
      |> Stream.run()
  """
  def concurrent_stream(device_operations, opts \\ []) do
    max_concurrent = Keyword.get(opts, :max_concurrent, 5)
    ordered = Keyword.get(opts, :ordered, false)
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    Stream.resource(
      fn -> initialize_concurrent_stream(device_operations, max_concurrent, ordered, timeout, opts) end,
      fn state -> fetch_next_concurrent_data(state, opts) end,
      fn state -> cleanup_concurrent_stream(state) end
    )
  end

  @doc """
  Creates a filtered stream that applies predicates during data fetching.

  This is more efficient than Stream.filter/2 for large datasets as it
  can skip unnecessary network requests based on OID patterns.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID
  - `filter_fn` - Function to filter OIDs and values
  - `opts` - Stream options

  ## Examples

      # Only fetch interface names (column 2)
      filter_fn = fn {oid, _type, _value} ->
        case SnmpLib.OID.string_to_list(oid) do
          {:ok, oid_list} -> List.last(oid_list, 2) |> hd() == 2
          _ -> false
        end
      end
      
      "switch.local"
      |> SnmpMgr.Stream.filtered_stream("ifTable", filter_fn)
      |> Enum.to_list()
  """
  def filtered_stream(target, root_oid, filter_fn, opts \\ []) do
    walk_stream(target, root_oid, opts)
    |> Stream.filter(filter_fn)
  end

  # Private functions for stream resource management

  defp initialize_walk_stream(target, root_oid, chunk_size, adaptive, opts) do
    case resolve_oid(root_oid) do
      {:ok, start_oid} ->
        %{
          target: target,
          current_oid: start_oid,
          root_oid: start_oid,
          chunk_size: chunk_size,
          adaptive: adaptive,
          adaptive_state: if(adaptive, do: init_adaptive_state(chunk_size), else: nil),
          finished: false,
          opts: opts
        }
      {:error, reason} ->
        %{error: reason, finished: true}
    end
  end

  defp fetch_next_chunk(%{finished: true} = state, _opts), do: {:halt, state}
  defp fetch_next_chunk(%{error: reason}, _opts), do: {[{:error, reason}], %{finished: true}}

  defp fetch_next_chunk(state, opts) do
    chunk_size = if state.adaptive and state.adaptive_state do
      state.adaptive_state.current_size
    else
      state.chunk_size
    end
    
    bulk_opts = opts
    |> Keyword.put(:max_repetitions, chunk_size)
    |> Keyword.put(:version, :v2c)
    
    start_time = if state.adaptive, do: System.monotonic_time(:millisecond), else: nil
    
    case SnmpMgr.Core.send_get_bulk_request(state.target, state.current_oid, bulk_opts) do
      {:ok, results} ->
        end_time = if state.adaptive, do: System.monotonic_time(:millisecond), else: nil
        
        # Filter results within scope
        {in_scope, next_oid} = filter_stream_results(results, state.root_oid)
        
        if Enum.empty?(in_scope) or next_oid == nil do
          {in_scope, %{state | finished: true}}
        else
          new_state = if state.adaptive and start_time != nil and end_time != nil do
            response_time = end_time - start_time
            adaptive_state = update_stream_adaptive_state(state.adaptive_state, response_time, length(in_scope))
            %{state | current_oid: next_oid, adaptive_state: adaptive_state}
          else
            %{state | current_oid: next_oid}
          end
          
          {in_scope, new_state}
        end
      
      {:error, reason} ->
        if state.adaptive and state.adaptive_state.current_size > 1 do
          # Try reducing chunk size
          new_adaptive_state = %{state.adaptive_state | current_size: div(state.adaptive_state.current_size, 2)}
          new_state = %{state | adaptive_state: new_adaptive_state}
          fetch_next_chunk(new_state, opts)
        else
          {[{:error, reason}], %{state | finished: true}}
        end
    end
  end

  defp cleanup_walk_stream(_state), do: :ok

  defp initialize_table_stream(target, table_oid, chunk_size, columns, opts) do
    case resolve_oid(table_oid) do
      {:ok, start_oid} ->
        %{
          target: target,
          current_oid: start_oid,
          table_oid: start_oid,
          chunk_size: chunk_size,
          columns: columns,
          finished: false,
          opts: opts,
          row_buffer: %{}
        }
      {:error, reason} ->
        %{error: reason, finished: true}
    end
  end

  defp fetch_next_table_chunk(%{finished: true} = state, _opts), do: {:halt, state}
  defp fetch_next_table_chunk(%{error: reason}, _opts), do: {[{:error, reason}], %{finished: true}}

  defp fetch_next_table_chunk(state, opts) do
    bulk_opts = opts
    |> Keyword.put(:max_repetitions, state.chunk_size)
    |> Keyword.put(:version, :v2c)
    
    case SnmpMgr.Core.send_get_bulk_request(state.target, state.current_oid, bulk_opts) do
      {:ok, results} ->
        # Filter and organize table results
        {table_entries, next_oid} = process_table_results(results, state.table_oid, state.columns)
        
        if Enum.empty?(table_entries) or next_oid == nil do
          # Return any remaining buffered rows
          remaining_rows = Map.values(state.row_buffer)
          {remaining_rows, %{state | finished: true}}
        else
          # Update row buffer and return complete rows
          {complete_rows, new_buffer} = update_table_buffer(state.row_buffer, table_entries)
          new_state = %{state | current_oid: next_oid, row_buffer: new_buffer}
          {complete_rows, new_state}
        end
      
      {:error, reason} ->
        {[{:error, reason}], %{state | finished: true}}
    end
  end

  defp cleanup_table_stream(_state), do: :ok

  defp initialize_monitor_stream(targets, interval, buffer_size, error_handling, opts) do
    %{
      targets: targets,
      interval: interval,
      buffer_size: buffer_size,
      error_handling: error_handling,
      last_poll: 0,
      buffer: :queue.new(),
      opts: opts
    }
  end

  defp fetch_next_monitor_data(state, opts) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time - state.last_poll >= state.interval do
      # Time for next poll
      poll_results = poll_targets(state.targets, state.error_handling, opts)
      new_buffer = Enum.reduce(poll_results, state.buffer, fn result, acc ->
        :queue.in(result, acc)
      end)
      
      # Return buffered items
      {items, remaining_buffer} = extract_buffer_items(new_buffer, state.buffer_size)
      new_state = %{state | last_poll: current_time, buffer: remaining_buffer}
      {items, new_state}
    else
      # Return buffered items if available
      {items, new_buffer} = extract_buffer_items(state.buffer, min(10, state.buffer_size))
      if Enum.empty?(items) do
        # Sleep until next poll time
        sleep_time = state.interval - (current_time - state.last_poll)
        Process.sleep(max(100, sleep_time))
        fetch_next_monitor_data(state, opts)
      else
        {items, %{state | buffer: new_buffer}}
      end
    end
  end

  defp cleanup_monitor_stream(_state), do: :ok

  defp initialize_concurrent_stream(device_operations, max_concurrent, ordered, timeout, opts) do
    %{
      operations: device_operations,
      max_concurrent: max_concurrent,
      ordered: ordered,
      timeout: timeout,
      active_tasks: [],
      completed_results: :queue.new(),
      operation_index: 0,
      opts: opts
    }
  end

  defp fetch_next_concurrent_data(state, opts) do
    # Start new tasks up to max_concurrent limit
    new_state = start_concurrent_tasks(state, opts)
    
    # Check for completed tasks
    {completed, still_active} = check_completed_tasks(new_state.active_tasks, new_state.timeout)
    
    # Add completed results to queue
    updated_results = Enum.reduce(completed, new_state.completed_results, fn result, acc ->
      :queue.in(result, acc)
    end)
    
    # Extract available results
    {items, remaining_results} = extract_buffer_items(updated_results, 10)
    
    final_state = %{new_state | 
      active_tasks: still_active,
      completed_results: remaining_results
    }
    
    if Enum.empty?(items) and Enum.empty?(still_active) and final_state.operation_index >= length(final_state.operations) do
      {:halt, final_state}
    else
      {items, final_state}
    end
  end

  defp cleanup_concurrent_stream(state) do
    # Clean up any remaining tasks
    Enum.each(state.active_tasks, fn {task, _index} ->
      Task.shutdown(task, 1000)
    end)
    :ok
  end

  defp poll_targets(targets, error_handling, opts) do
    SnmpMgr.Multi.get_multi(targets, opts)
    |> Enum.zip(targets)
    |> Enum.map(fn {result, {target, oid}} ->
      case result do
        {:ok, value} -> {:ok, %{target: target, oid: oid, value: value, timestamp: System.system_time(:second)}}
        {:error, reason} when error_handling == :include_errors -> {:error, %{target: target, oid: oid, error: reason, timestamp: System.system_time(:second)}}
        {:error, _reason} -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp extract_buffer_items(queue, max_items) do
    extract_items(queue, max_items, [])
  end

  defp extract_items(queue, 0, acc), do: {Enum.reverse(acc), queue}
  defp extract_items(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} -> 
        extract_items(new_queue, count - 1, [item | acc])
      {:empty, queue} -> 
        {Enum.reverse(acc), queue}
    end
  end

  defp start_concurrent_tasks(state, opts) do
    available_slots = state.max_concurrent - length(state.active_tasks)
    operations_to_start = Enum.drop(state.operations, state.operation_index) |> Enum.take(available_slots)
    
    new_tasks = 
      operations_to_start
      |> Enum.with_index(state.operation_index)
      |> Enum.map(fn {{target, operation, oid, op_opts}, index} ->
        task = Task.async(fn ->
          merged_opts = Keyword.merge(opts, op_opts)
          result = execute_stream_operation(operation, target, oid, merged_opts)
          {index, target, result}
        end)
        {task, index}
      end)
    
    %{state | 
      active_tasks: state.active_tasks ++ new_tasks,
      operation_index: state.operation_index + length(operations_to_start)
    }
  end

  defp check_completed_tasks(tasks, timeout) do
    Task.yield_many(Enum.map(tasks, fn {task, _} -> task end), timeout)
    |> Enum.zip(tasks)
    |> Enum.split_with(fn {{_task, result}, {_task_ref, _index}} -> result != nil end)
    |> case do
      {completed, still_running} ->
        completed_results = Enum.map(completed, fn {{_task, {:ok, result}}, {_task_ref, index}} -> {index, result} end)
        active_tasks = Enum.map(still_running, fn {_yield_result, task_info} -> task_info end)
        {completed_results, active_tasks}
    end
  end

  defp execute_stream_operation(:walk, target, oid, opts), do: SnmpMgr.walk(target, oid, opts)
  defp execute_stream_operation(:walk_table, target, oid, opts), do: SnmpMgr.walk_table(target, oid, opts)
  defp execute_stream_operation(:get, target, oid, opts), do: SnmpMgr.get(target, oid, opts)
  defp execute_stream_operation(:get_bulk, target, oid, opts), do: SnmpMgr.get_bulk(target, oid, opts)
  defp execute_stream_operation(_, _, _, _), do: {:error, :unsupported_operation}

  defp resolve_oid(oid) when is_binary(oid) do
    case SnmpLib.OID.string_to_list(oid) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, _} ->
        case SnmpMgr.MIB.resolve(oid) do
          {:ok, resolved_oid} -> {:ok, resolved_oid}
          error -> error
        end
    end
  end
  defp resolve_oid(oid) when is_list(oid), do: {:ok, oid}
  defp resolve_oid(_), do: {:error, :invalid_oid_format}

  # Helper functions

  defp init_adaptive_state(initial_size) do
    %{
      current_size: initial_size,
      consecutive_successes: 0,
      consecutive_errors: 0,
      avg_response_time: nil
    }
  end

  defp update_stream_adaptive_state(state, response_time, result_count) do
    new_avg = if state.avg_response_time do
      (state.avg_response_time + response_time) / 2
    else
      response_time
    end
    
    cond do
      # Too slow, reduce size
      response_time > 200 and state.current_size > 5 ->
        %{state | current_size: max(5, state.current_size - 5), avg_response_time: new_avg}
      
      # Fast and full results, increase size
      response_time < 50 and result_count == state.current_size and state.current_size < 100 ->
        %{state | current_size: min(100, state.current_size + 10), avg_response_time: new_avg}
      
      # Stable
      true ->
        %{state | avg_response_time: new_avg}
    end
  end

  defp filter_stream_results(results, root_oid) do
    in_scope_results = 
      results
      |> Enum.filter(fn 
        # Handle 3-tuple format (preferred)
        {oid_string, _type, _value} ->
          case SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
            _ -> false
          end
        # Handle 2-tuple format (backward compatibility)
        {oid_string, _value} ->
          case SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
            _ -> false
          end
      end)
    
    next_oid = case List.last(results) do
      {oid_string, _type, _value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} -> oid_list
          _ -> nil
        end
      {oid_string, _value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} -> oid_list
          _ -> nil
        end
      _ -> nil
    end
    
    {in_scope_results, next_oid}
  end

  defp process_table_results(results, _table_oid, _columns) do
    # Process results into table entries
    # This is a simplified version - real implementation would be more sophisticated
    {results, List.last(results) |> elem(0) |> SnmpLib.OID.string_to_list() |> elem(1)}
  end

  defp update_table_buffer(buffer, entries) do
    # Update row buffer and return complete rows
    # Simplified implementation
    {[], Map.merge(buffer, Enum.into(entries, %{}))}
  end
end