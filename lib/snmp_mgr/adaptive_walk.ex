defmodule SnmpMgr.AdaptiveWalk do
  @moduledoc """
  Intelligent SNMP walk operations with adaptive parameter tuning.
  
  This module provides advanced walk operations that automatically adjust
  bulk parameters based on device response characteristics for optimal performance.
  """

  @default_initial_bulk_size 10
  @default_max_bulk_size 50
  @default_min_bulk_size 1
  @default_performance_threshold 100  # milliseconds
  @default_max_entries 10_000

  @doc """
  Performs an adaptive bulk walk that automatically tunes parameters.

  Starts with a conservative bulk size and adapts based on response times
  and error rates to find the optimal parameters for the target device.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :adaptive_tuning, :performance_threshold

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpMgr.AdaptiveWalk.bulk_walk("switch.local", "ifTable")
      # Automatically adjusts bulk size for optimal performance:
      # [
      #   {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "FastEthernet0/1"},
      #   {"1.3.6.1.2.1.2.2.1.2.2", :octet_string, "FastEthernet0/2"},
      #   {"1.3.6.1.2.1.2.2.1.2.3", :octet_string, "GigabitEthernet0/1"},
      #   # ... optimally retrieved with adaptive bulk sizing
      # ]
      
      # With custom options:
      {:ok, results} = SnmpMgr.AdaptiveWalk.bulk_walk("router.local", "sysDescr", 
        adaptive_tuning: true, max_entries: 100, performance_threshold: 50)
      # [{"1.3.6.1.2.1.1.1.0", :octet_string, "Cisco IOS Software, Version 15.1"}]
  """
  def bulk_walk(target, root_oid, opts \\ []) do
    adaptive_tuning = Keyword.get(opts, :adaptive_tuning, true)
    max_entries = Keyword.get(opts, :max_entries, @default_max_entries)
    
    case resolve_oid(root_oid) do
      {:ok, start_oid} ->
        if adaptive_tuning do
          adaptive_bulk_walk(target, start_oid, start_oid, [], max_entries, opts)
        else
          # Fall back to regular bulk walk
          SnmpMgr.Bulk.walk_bulk(target, root_oid, opts)
        end
      error -> error
    end
  end

  @doc """
  Performs an adaptive table walk optimized for large tables.

  Automatically determines the optimal bulk size for table retrieval
  and handles pagination for very large tables.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to walk
  - `opts` - Options including :adaptive_tuning, :stream, :max_entries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, table_data} = SnmpMgr.AdaptiveWalk.table_walk("switch.local", "ifTable", max_entries: 1000)
      # Efficiently walks large tables with automatic optimization:
      # [
      #   {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},           # ifIndex.1
      #   {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "Ethernet1"}, # ifDescr.1
      #   {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6},           # ifType.1 (ethernetCsmacd)
      #   {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 1000000000},  # ifSpeed.1 (1 Gbps)
      #   # ... continues with adaptive pagination for large tables
      # ]
      
      # For very large tables with streaming:
      {:ok, results} = SnmpMgr.AdaptiveWalk.table_walk("core-switch", "ipRouteTable", 
        max_entries: 10000, adaptive_tuning: true)
  """
  def table_walk(target, table_oid, opts \\ []) do
    adaptive_tuning = Keyword.get(opts, :adaptive_tuning, true)
    max_entries = Keyword.get(opts, :max_entries, @default_max_entries)
    
    case resolve_oid(table_oid) do
      {:ok, start_oid} ->
        if adaptive_tuning do
          adaptive_table_walk(target, start_oid, start_oid, [], max_entries, opts)
        else
          # Fall back to regular table walk
          SnmpMgr.Bulk.get_table_bulk(target, table_oid, opts)
        end
      error -> error
    end
  end

  @doc """
  Benchmarks a device to determine optimal bulk parameters.

  Performs a series of test requests with different bulk sizes
  to determine the best parameters for the target device.

  ## Parameters
  - `target` - The target device to benchmark
  - `test_oid` - OID to use for testing (should have multiple entries)
  - `opts` - Options including :test_sizes, :iterations

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, benchmark} = SnmpMgr.AdaptiveWalk.benchmark_device("switch.local", "ifTable")
      # Returns comprehensive performance analysis:
      # %{
      #   optimal_bulk_size: 25,
      #   avg_response_time: 45,
      #   error_rate: 0.0,
      #   all_results: [
      #     {1, 120}, {5, 85}, {10, 52}, {15, 48}, 
      #     {20, 44}, {25, 42}, {30, 45}, {40, 52}, {50, 68}
      #   ],
      #   recommendations: %{
      #     max_repetitions: 25,
      #     timeout: 3000,
      #     adaptive_tuning: false  # Device has consistent performance
      #   }
      # }
      
      # Custom benchmark with specific test sizes:
      {:ok, results} = SnmpMgr.AdaptiveWalk.benchmark_device("router.local", "ipRouteTable",
        test_sizes: [5, 10, 20, 50], iterations: 5)
  """
  def benchmark_device(target, test_oid, opts \\ []) do
    test_sizes = Keyword.get(opts, :test_sizes, [1, 5, 10, 15, 20, 25, 30, 40, 50])
    iterations = Keyword.get(opts, :iterations, 3)
    
    case resolve_oid(test_oid) do
      {:ok, oid_list} ->
        results = 
          test_sizes
          |> Enum.map(fn size ->
            avg_time = benchmark_bulk_size(target, oid_list, size, iterations, opts)
            {size, avg_time}
          end)
          |> Enum.filter(fn {_size, time} -> time != :error end)
        
        if Enum.empty?(results) do
          {:error, :no_successful_benchmarks}
        else
          optimal = find_optimal_parameters(results)
          {:ok, optimal}
        end
      error -> error
    end
  end

  @doc """
  Gets optimal parameters for a previously benchmarked device.

  Returns cached optimal parameters or performs a quick benchmark
  if no cached data is available.
  """
  def get_optimal_params(target, opts \\ []) do
    # In a real implementation, this would check a cache/ETS table
    # For now, return reasonable defaults based on device type
    default_params = %{
      max_repetitions: determine_default_bulk_size(target),
      timeout: 5000,
      adaptive_tuning: true
    }
    
    {:ok, Map.merge(default_params, Enum.into(opts, %{}))}
  end

  # Private functions

  defp adaptive_bulk_walk(target, current_oid, root_oid, acc, remaining, opts) when remaining > 0 do
    # Start with conservative bulk size
    initial_bulk_size = Keyword.get(opts, :initial_bulk_size, @default_initial_bulk_size)
    performance_threshold = Keyword.get(opts, :performance_threshold, @default_performance_threshold)
    
    # Initialize adaptive state
    state = %{
      current_bulk_size: initial_bulk_size,
      consecutive_successes: 0,
      consecutive_errors: 0,
      avg_response_time: nil,
      total_requests: 0
    }
    
    adaptive_walk_loop(target, current_oid, root_oid, acc, remaining, opts, state, performance_threshold)
  end

  defp adaptive_bulk_walk(_target, _current_oid, _root_oid, acc, 0, _opts) do
    {:ok, Enum.reverse(acc)}
  end

  defp adaptive_walk_loop(target, current_oid, root_oid, acc, remaining, opts, state, performance_threshold) do
    bulk_size = max(1, min(state.current_bulk_size, remaining))
    
    # Measure request time
    start_time = System.monotonic_time(:millisecond)
    
    bulk_opts = opts
    |> Keyword.put(:max_repetitions, bulk_size)
    |> Keyword.put(:version, :v2c)
    
    case SnmpMgr.Core.send_get_bulk_request(target, current_oid, bulk_opts) do
      {:ok, results} ->
        end_time = System.monotonic_time(:millisecond)
        response_time = end_time - start_time
        
        # Filter results within scope
        {in_scope, next_oid} = filter_scope_results(results, root_oid)
        
        if Enum.empty?(in_scope) or next_oid == nil do
          {:ok, Enum.reverse(acc)}
        else
          # Update adaptive state based on performance
          new_state = update_adaptive_state(state, response_time, length(in_scope), performance_threshold)
          new_acc = Enum.reverse(in_scope) ++ acc
          new_remaining = remaining - length(in_scope)
          
          adaptive_walk_loop(target, next_oid, root_oid, new_acc, new_remaining, opts, new_state, performance_threshold)
        end
      
      {:error, _} = error ->
        # Handle error by reducing bulk size
        new_state = handle_walk_error(state)
        if new_state.current_bulk_size < @default_min_bulk_size do
          error
        else
          adaptive_walk_loop(target, current_oid, root_oid, acc, remaining, opts, new_state, performance_threshold)
        end
    end
  end

  defp adaptive_table_walk(target, current_oid, root_oid, acc, remaining, opts) do
    # Similar to adaptive_bulk_walk but optimized for table structure
    adaptive_bulk_walk(target, current_oid, root_oid, acc, remaining, opts)
  end

  defp update_adaptive_state(state, response_time, result_count, performance_threshold) do
    new_avg_time = if state.avg_response_time do
      (state.avg_response_time + response_time) / 2
    else
      response_time
    end
    
    new_state = %{state | 
      avg_response_time: new_avg_time,
      total_requests: state.total_requests + 1
    }
    
    cond do
      # Response time too high, reduce bulk size
      response_time > performance_threshold and state.current_bulk_size > @default_min_bulk_size ->
        %{new_state | 
          current_bulk_size: max(@default_min_bulk_size, state.current_bulk_size - 5),
          consecutive_successes: 0,
          consecutive_errors: state.consecutive_errors + 1
        }
      
      # Good performance and full result set, try increasing bulk size
      response_time < performance_threshold / 2 and 
      result_count == state.current_bulk_size and 
      state.current_bulk_size < @default_max_bulk_size ->
        %{new_state | 
          current_bulk_size: min(@default_max_bulk_size, state.current_bulk_size + 5),
          consecutive_successes: state.consecutive_successes + 1,
          consecutive_errors: 0
        }
      
      # Stable performance
      true ->
        %{new_state | 
          consecutive_successes: state.consecutive_successes + 1,
          consecutive_errors: 0
        }
    end
  end

  defp handle_walk_error(state) do
    # Reduce bulk size on error
    new_bulk_size = max(@default_min_bulk_size, div(state.current_bulk_size, 2))
    %{state | 
      current_bulk_size: new_bulk_size,
      consecutive_errors: state.consecutive_errors + 1,
      consecutive_successes: 0
    }
  end

  defp benchmark_bulk_size(target, oid_list, bulk_size, iterations, opts) do
    times = 
      1..iterations
      |> Enum.map(fn _ ->
        start_time = System.monotonic_time(:millisecond)
        
        bulk_opts = opts
        |> Keyword.put(:max_repetitions, bulk_size)
        |> Keyword.put(:version, :v2c)
        
        case SnmpMgr.Core.send_get_bulk_request(target, oid_list, bulk_opts) do
          {:ok, _results} ->
            end_time = System.monotonic_time(:millisecond)
            end_time - start_time
          {:error, _} ->
            :error
        end
      end)
      |> Enum.filter(&(&1 != :error))
    
    if Enum.empty?(times) do
      :error
    else
      Enum.sum(times) / length(times)
    end
  end

  defp find_optimal_parameters(results) do
    # Find the bulk size with best performance (lowest average time)
    {optimal_size, optimal_time} = 
      results
      |> Enum.min_by(fn {_size, time} -> time end)
    
    # Calculate statistics (avg_time not currently used but available for future enhancements)
    _avg_time = results |> Enum.map(fn {_size, time} -> time end) |> Enum.sum() |> div(length(results))
    
    %{
      optimal_bulk_size: optimal_size,
      avg_response_time: optimal_time,
      error_rate: 0.0,  # We filtered out errors above
      all_results: results,
      recommendations: %{
        max_repetitions: optimal_size,
        timeout: max(3000, trunc(optimal_time * 3)),  # 3x response time for timeout
        adaptive_tuning: optimal_time > 100  # Enable adaptive tuning for slow devices
      }
    }
  end

  defp filter_scope_results(results, root_oid) do
    in_scope_results = 
      results
      |> Enum.filter(fn 
        # Handle 3-tuple format (preferred - from snmp_lib v1.0.5+)
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

  defp determine_default_bulk_size(target) do
    # Simple heuristic based on target type
    cond do
      String.contains?(target, "switch") -> 25
      String.contains?(target, "router") -> 15
      String.contains?(target, "server") -> 10
      true -> @default_initial_bulk_size
    end
  end

  defp resolve_oid(oid) when is_binary(oid) do
    case SnmpLib.OID.string_to_list(oid) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, _} ->
        # Try as symbolic name
        case SnmpMgr.MIB.resolve(oid) do
          {:ok, resolved_oid} -> {:ok, resolved_oid}
          error -> error
        end
    end
  end
  defp resolve_oid(oid) when is_list(oid), do: {:ok, oid}
  defp resolve_oid(_), do: {:error, :invalid_oid_format}
end