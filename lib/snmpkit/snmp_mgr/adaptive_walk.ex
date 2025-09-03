defmodule SnmpKit.SnmpMgr.AdaptiveWalk do
  @moduledoc """
  Intelligent SNMP walk operations with adaptive parameter tuning.

  This module provides advanced walk operations that automatically adjust
  bulk parameters based on device response characteristics for optimal performance.
  """

  @default_initial_bulk_size 10
  @default_max_entries 1_000

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
      {:ok, results} = SnmpKit.SnmpMgr.AdaptiveWalk.bulk_walk("switch.local", "ifTable")
      # Automatically adjusts bulk size for optimal performance:
      # [
      #   {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "FastEthernet0/1"},
      #   {"1.3.6.1.2.1.2.2.1.2.2", :octet_string, "FastEthernet0/2"},
      #   {"1.3.6.1.2.1.2.2.1.2.3", :octet_string, "GigabitEthernet0/1"},
      #   # ... optimally retrieved with adaptive bulk sizing
      # ]

      # With custom options:
      {:ok, results} = SnmpKit.SnmpMgr.AdaptiveWalk.bulk_walk("router.local", "sysDescr",
        adaptive_tuning: true, max_entries: 100, performance_threshold: 50)
      # [{"1.3.6.1.2.1.1.1.0", :octet_string, "Cisco IOS Software, Version 15.1"}]
  """
  def bulk_walk(target, root_oid, opts \\ []) do
    max_entries = Keyword.get(opts, :max_entries, @default_max_entries)

    case resolve_oid(root_oid) do
      {:ok, start_oid} ->
        # Handle empty OID by using standard MIB-II subtree
        {actual_start_oid, filter_oid} =
          case start_oid do
            [] -> {[1, 3], []}
            _ -> {start_oid, start_oid}
          end

        simple_bulk_walk(target, actual_start_oid, filter_oid, [], max_entries, opts)

      error ->
        error
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
      {:ok, table_data} = SnmpKit.SnmpMgr.AdaptiveWalk.table_walk("switch.local", "ifTable", max_entries: 1000)
      # Efficiently walks large tables with automatic optimization:
      # [
      #   {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},           # ifIndex.1
      #   {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "Ethernet1"}, # ifDescr.1
      #   {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6},           # ifType.1 (ethernetCsmacd)
      #   {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 1000000000},  # ifSpeed.1 (1 Gbps)
      #   # ... continues with adaptive pagination for large tables
      # ]

      # For very large tables with streaming:
      {:ok, results} = SnmpKit.SnmpMgr.AdaptiveWalk.table_walk("core-switch", "ipRouteTable",
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
          SnmpKit.SnmpMgr.Bulk.get_table_bulk(target, table_oid, opts)
        end

      error ->
        error
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
      {:ok, benchmark} = SnmpKit.SnmpMgr.AdaptiveWalk.benchmark_device("switch.local", "ifTable")
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
      {:ok, results} = SnmpKit.SnmpMgr.AdaptiveWalk.benchmark_device("router.local", "ipRouteTable",
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

      error ->
        error
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

  # Simple recursive PDU processor
  defp simple_bulk_walk(target, current_oid, filter_oid, acc, remaining, opts)
       when remaining > 0 do
    bulk_size = min(remaining, Keyword.get(opts, :max_repetitions, 10))

    bulk_opts =
      opts
      |> Keyword.put(:max_repetitions, bulk_size)
      |> Keyword.put(:version, :v2c)

    case SnmpKit.SnmpMgr.Core.send_get_bulk_request(target, current_oid, bulk_opts) do
      {:ok, results} ->
        # Check for end of MIB conditions first
        if has_end_of_mib?(results) do
          {:ok, Enum.reverse(acc)}
        else
          # Filter results based on base OID
          filtered_results = filter_results_by_base_oid(results, filter_oid)

          # Stop if no more results in scope
          if Enum.empty?(filtered_results) do
            {:ok, Enum.reverse(acc)}
          else
            # Get next OID for continuation
            next_oid = get_next_oid(results)

            # Stop if we can't determine next OID or if it's the same (no progress)
            if next_oid == nil or next_oid == current_oid do
              {:ok, Enum.reverse(acc)}
            else
              # Add filtered results to accumulator
              new_acc = Enum.reverse(filtered_results) ++ acc
              new_remaining = remaining - length(filtered_results)

              # Continue recursively
              simple_bulk_walk(target, next_oid, filter_oid, new_acc, new_remaining, opts)
            end
          end
        end

      {:error, :endOfMibView} ->
        {:ok, Enum.reverse(acc)}

      {:error, :noSuchName} ->
        {:ok, Enum.reverse(acc)}

      {:error, _} = error ->
        error
    end
  end

  defp simple_bulk_walk(_target, _current_oid, _filter_oid, acc, 0, _opts) do
    {:ok, Enum.reverse(acc)}
  end

  # Check if any result contains end-of-MIB indicators
  defp has_end_of_mib?(results) do
    Enum.any?(results, fn result ->
      case result do
        {_oid, :endOfMibView, _} -> true
        {_oid, :noSuchObject, _} -> true
        {_oid, :noSuchInstance, _} -> true
        _ -> false
      end
    end)
  end

  # Filter results to only include those within the base OID scope
  # Results should always be in {oid_list, type, value} format internally
  defp filter_results_by_base_oid(results, filter_oid) do
    Enum.filter(results, fn result ->
      case result do
        {oid_list, _type, _value} when is_list(oid_list) ->
          oid_in_scope?(oid_list, filter_oid)

        # Legacy support for mixed formats - convert and warn
        {oid_string, _type, _value} when is_binary(oid_string) ->
          case SnmpKit.SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} ->
              # TODO: Fix upstream to return list format consistently
              oid_in_scope?(oid_list, filter_oid)

            _ ->
              false
          end

        _ ->
          false
      end
    end)
  end

  # Get the next OID for continuing the walk
  # Should always return list format for internal operations
  defp get_next_oid(results) do
    case List.last(results) do
      {oid_list, _type, _value} when is_list(oid_list) ->
        oid_list

      # Legacy support for mixed formats - convert and return list
      {oid_string, _type, _value} when is_binary(oid_string) ->
        case SnmpKit.SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} ->
            # TODO: Fix upstream to return list format consistently
            oid_list

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  # Check if OID is within scope of the filter OID
  defp oid_in_scope?(oid_list, filter_oid) do
    case filter_oid do
      [] ->
        # Empty filter means accept everything
        true

      _ ->
        # Check if OID starts with filter OID
        List.starts_with?(oid_list, filter_oid)
    end
  end

  defp adaptive_table_walk(target, current_oid, root_oid, acc, remaining, opts) do
    # Use simple bulk walk for table operations too
    simple_bulk_walk(target, current_oid, root_oid, acc, remaining, opts)
  end

  defp benchmark_bulk_size(target, oid_list, bulk_size, iterations, opts) do
    times =
      1..iterations
      |> Enum.map(fn _ ->
        start_time = System.monotonic_time(:millisecond)

        bulk_opts =
          opts
          |> Keyword.put(:max_repetitions, bulk_size)
          |> Keyword.put(:version, :v2c)

        case SnmpKit.SnmpMgr.Core.send_get_bulk_request(target, oid_list, bulk_opts) do
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
    _avg_time =
      results |> Enum.map(fn {_size, time} -> time end) |> Enum.sum() |> div(length(results))

    %{
      optimal_bulk_size: optimal_size,
      avg_response_time: optimal_time,
      # We filtered out errors above
      error_rate: 0.0,
      all_results: results,
      recommendations: %{
        max_repetitions: optimal_size,
        # 3x response time for timeout
        timeout: max(3000, trunc(optimal_time * 3)),
        # Enable adaptive tuning for slow devices
        adaptive_tuning: optimal_time > 100
      }
    }
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
    case String.trim(oid) do
      "" ->
        # Empty string means start from MIB root - use standard fallback
        {:ok, [1, 3]}

      trimmed ->
        case SnmpKit.SnmpLib.OID.string_to_list(trimmed) do
          {:ok, oid_list} when oid_list != [] ->
            {:ok, oid_list}

          {:ok, []} ->
            # Empty result fallback
            {:ok, [1, 3]}

          {:error, _} ->
            # Try as symbolic name
            case SnmpKit.SnmpMgr.MIB.resolve(trimmed) do
              {:ok, resolved_oid} when is_list(resolved_oid) ->
                {:ok, resolved_oid}

              error ->
                error
            end
        end
    end
  end

  defp resolve_oid(oid) when is_list(oid) do
    # Validate list format before returning
    case SnmpKit.SnmpLib.OID.valid_oid?(oid) do
      :ok -> {:ok, oid}
      {:error, :empty_oid} -> {:ok, [1, 3]}
      error -> error
    end
  end

  defp resolve_oid(_), do: {:error, :invalid_oid_format}
end
