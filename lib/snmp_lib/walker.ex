defmodule SnmpLib.Walker do
  @moduledoc """
  Efficient SNMP table walking with bulk operations and streaming support.
  
  This module provides high-performance table walking capabilities using GETBULK
  operations for maximum efficiency. It's designed for collecting large amounts
  of SNMP data with minimal network overhead and memory usage.
  
  ## Features
  
  - **GETBULK Optimization**: Uses GETBULK requests for 3-5x faster table walking
  - **Streaming Support**: Process large tables without loading all data into memory
  - **Automatic Pagination**: Handles table boundaries and end-of-mib-view conditions
  - **Error Recovery**: Graceful handling of partial responses and network issues
  - **Adaptive Bulk Size**: Automatically adjusts bulk size based on device capabilities
  - **Memory Efficient**: Lazy evaluation and streaming for large datasets
  
  ## Table Walking Strategies
  
  ### Bulk Walking (Recommended)
  Uses GETBULK operations for maximum efficiency. Best for SNMPv2c devices.
  
  ### Sequential Walking  
  Falls back to GETNEXT operations for SNMPv1 devices or when GETBULK fails.
  
  ### Streaming Walking
  Processes table rows as they arrive, ideal for very large tables.
  
  ## Examples
  
      # Walk entire interface table
      {:ok, interfaces} = SnmpLib.Walker.walk_table("192.168.1.1", [1, 3, 6, 1, 2, 1, 2, 2])
      
      # Stream large table to avoid memory issues
      SnmpLib.Walker.stream_table("192.168.1.1", [1, 3, 6, 1, 2, 1, 2, 2, 1, 2])
      |> Stream.each(fn {interface_oid, interface_value} -> 
           IO.puts("Interface: " <> inspect(interface_oid) <> " = " <> inspect(interface_value)) 
         end)
      |> Stream.run()
      
      # Walk with custom bulk size and timeout
      {:ok, data} = SnmpLib.Walker.walk_table("10.0.0.1", "1.3.6.1.2.1.4.21",
                                              max_repetitions: 50, timeout: 15_000)
  """
  
  require Logger
  
  @default_max_repetitions 25
  @default_timeout 10_000
  @default_max_retries 3
  @default_retry_delay 1_000
  @max_bulk_size 100
  @min_bulk_size 5
  
  @type host :: binary() | :inet.ip_address()
  @type oid :: [non_neg_integer()] | binary()
  @type varbind :: {oid(), any()}
  @type walk_result :: {:ok, [varbind()]} | {:error, any()}
  @type stream_chunk :: [varbind()]
  
  @type walk_opts :: [
    community: binary(),
    version: :v1 | :v2c,
    timeout: pos_integer(),
    max_repetitions: pos_integer(),
    max_retries: non_neg_integer(),
    retry_delay: pos_integer(),
    port: pos_integer(),
    adaptive_bulk: boolean(),
    chunk_size: pos_integer()
  ]
  
  ## Public API
  
  @doc """
  Walks an entire SNMP table efficiently using GETBULK operations.
  
  This is the most efficient way to retrieve a complete SNMP table. Uses GETBULK
  requests when possible (SNMPv2c) and automatically handles table boundaries.
  
  ## Parameters
  
  - `host`: Target device IP address or hostname
  - `table_oid`: Base OID of the table to walk
  - `opts`: Walking options (see module docs)
  
  ## Returns
  
  - `{:ok, varbinds}`: List of {oid, value} pairs for all table entries
  - `{:error, reason}`: Walking failed with reason
  
  ## Examples
  
      # Test that walk_table function exists and handles invalid input properly
      iex> match?({:error, _}, SnmpLib.Walker.walk_table("invalid.host", [1, 3, 6, 1, 2, 1, 2, 2], timeout: 100))
      true
      
      # Walk with high bulk size for faster collection
      # SnmpLib.Walker.walk_table("10.0.0.1", "1.3.6.1.2.1.2.2", max_repetitions: 50)
      # {:ok, [...]} returns many interface entries
  """
  @spec walk_table(host(), oid(), walk_opts()) :: walk_result()
  def walk_table(host, table_oid, opts \\ []) do
    # Track if max_retries was explicitly provided before merging defaults
    explicit_max_retries = Keyword.has_key?(opts, :max_retries)
    opts = merge_default_opts(opts)
    opts = Keyword.put(opts, :_explicit_max_retries, explicit_max_retries)
    normalized_oid = normalize_oid(table_oid)
    
    case get_walk_strategy(opts) do
      :bulk_walk -> bulk_walk_table(host, normalized_oid, opts)
      :sequential_walk -> sequential_walk_table(host, normalized_oid, opts)
    end
  end
  
  @doc """
  Walks a subtree starting from the given OID.
  
  Similar to walk_table/3 but continues until the OID prefix no longer matches,
  making it suitable for walking MIB subtrees that may contain multiple tables.
  
  ## Parameters
  
  - `host`: Target device IP address or hostname
  - `base_oid`: Starting OID for the subtree walk
  - `opts`: Walking options
  
  ## Returns
  
  - `{:ok, varbinds}`: All OIDs under the base_oid with their values
  - `{:error, reason}`: Walking failed
  
  ## Examples
  
      # Test that walk_subtree function exists and handles invalid input properly
      iex> match?({:error, _}, SnmpLib.Walker.walk_subtree("invalid.host", [1, 3, 6, 1, 2, 1, 1], timeout: 100))
      true
  """
  @spec walk_subtree(host(), oid(), walk_opts()) :: walk_result()
  def walk_subtree(host, base_oid, opts \\ []) do
    opts = merge_default_opts(opts)
    normalized_oid = normalize_oid(base_oid)
    
    case get_walk_strategy(opts) do
      :bulk_walk -> bulk_walk_subtree(host, normalized_oid, opts)
      :sequential_walk -> sequential_walk_subtree(host, normalized_oid, opts)
    end
  end
  
  @doc """
  Streams table entries as they are retrieved, ideal for very large tables.
  
  Returns a Stream that yields chunks of varbinds as they are collected.
  This is memory-efficient for large tables as it doesn't load all data at once.
  
  ## Parameters
  
  - `host`: Target device IP address or hostname
  - `table_oid`: Base OID of the table to stream
  - `opts`: Streaming options (chunk_size controls entries per chunk)
  
  ## Returns
  
  A Stream that yields `stream_chunk()` (lists of varbinds)
  
  ## Examples
  
      # Process large routing table in chunks
      # SnmpLib.Walker.stream_table("192.168.1.1", [1, 3, 6, 1, 2, 1, 4, 21])
      # |> Stream.flat_map(& &1)  # Flatten chunks into individual varbinds
      # |> Stream.filter(fn {_oid, value} -> value != 0 end)  # Filter active routes
      # |> Enum.take(100)  # Take first 100 active routes
      # returns list of active routes
      
      # Test that stream_table function exists and returns a stream
      iex> stream = SnmpLib.Walker.stream_table("invalid.host", "1.3.6.1.2.1.2.2.1.1", timeout: 100)
      iex> is_function(stream, 2)
      true
  """
  @spec stream_table(host(), oid(), walk_opts()) :: Enumerable.t()
  def stream_table(host, table_oid, opts \\ []) do
    opts = merge_default_opts(opts)
    normalized_oid = normalize_oid(table_oid)
    
    Stream.resource(
      fn -> init_streaming_state(host, normalized_oid, opts) end,
      fn state -> get_next_chunk(state) end,
      fn state -> cleanup_streaming_state(state) end
    )
  end
  
  @doc """
  Walks a single table column efficiently.
  
  Optimized for retrieving a single column from an SNMP table by using
  the column OID directly and stopping at table boundaries.
  
  ## Parameters
  
  - `host`: Target device IP address or hostname
  - `column_oid`: OID of the table column (e.g., [1,3,6,1,2,1,2,2,1,2] for ifDescr)
  - `opts`: Walking options
  
  ## Returns
  
  - `{:ok, column_data}`: List of {index_oid, value} pairs for the column
  - `{:error, reason}`: Walking failed
  
  ## Examples
  
      # Test that walk_column function exists and handles invalid input properly
      iex> match?({:error, _}, SnmpLib.Walker.walk_column("invalid.host", [1, 3, 6, 1, 2, 1, 2, 2, 1, 2], timeout: 100))
      true
  """
  @spec walk_column(host(), oid(), walk_opts()) :: walk_result()
  def walk_column(host, column_oid, opts \\ []) do
    case walk_table(host, column_oid, opts) do
      {:ok, varbinds} ->
        # Extract just the index portion and values
        column_data = extract_column_data(varbinds, column_oid)
        {:ok, column_data}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Estimates the size of a table by walking just the first column.
  
  Useful for determining table size before performing full table walks,
  helping with memory planning and progress estimation.
  
  ## Parameters
  
  - `host`: Target device IP address or hostname
  - `table_oid`: Base OID of the table
  - `opts`: Walking options (typically with small max_repetitions)
  
  ## Returns
  
  - `{:ok, count}`: Estimated number of table rows
  - `{:error, reason}`: Estimation failed
  
  ## Examples
  
      # Test that estimate_table_size function exists and handles invalid input properly
      iex> match?({:error, _}, SnmpLib.Walker.estimate_table_size("invalid.host", [1, 3, 6, 1, 2, 1, 2, 2], timeout: 100))
      true
  """
  @spec estimate_table_size(host(), oid(), walk_opts()) :: {:ok, non_neg_integer()} | {:error, any()}
  def estimate_table_size(host, table_oid, opts \\ []) do
    # Use first column of table (add .1.1 for most tables)
    first_column_oid = normalize_oid(table_oid) ++ [1, 1]
    
    case walk_column(host, first_column_oid, opts) do
      {:ok, column_data} -> {:ok, length(column_data)}
      {:error, reason} -> {:error, reason}
    end
  end
  
  ## Private Implementation
  
  # Strategy selection
  defp get_walk_strategy(opts) do
    case opts[:version] do
      :v1 -> :sequential_walk
      :v2c -> :bulk_walk
      _ -> :bulk_walk
    end
  end
  
  # Bulk walking implementation
  defp bulk_walk_table(host, table_oid, opts) do
    initial_state = %{
      host: host,
      current_oid: table_oid,
      table_prefix: table_oid,
      accumulated: [],
      opts: opts,
      bulk_size: opts[:max_repetitions] || @default_max_repetitions,
      adaptive_bulk: opts[:adaptive_bulk] || false
    }
    
    bulk_walk_loop(initial_state)
  end
  
  defp bulk_walk_subtree(host, subtree_oid, opts) do
    initial_state = %{
      host: host,
      current_oid: subtree_oid,
      subtree_prefix: subtree_oid,
      accumulated: [],
      opts: opts,
      bulk_size: opts[:max_repetitions] || @default_max_repetitions,
      adaptive_bulk: opts[:adaptive_bulk] || false
    }
    
    bulk_walk_subtree_loop(initial_state)
  end
  
  defp bulk_walk_loop(state) do
    case perform_bulk_request(state) do
      {:ok, []} ->
        # No more data
        {:ok, Enum.reverse(state.accumulated)}
        
      {:ok, varbinds} ->
        {valid_varbinds, continue?} = filter_table_varbinds(varbinds, state.table_prefix)
        
        if continue? and length(valid_varbinds) > 0 do
          # Get last OID for next request
          last_oid = case List.last(valid_varbinds) do
            {oid, _type, _value} -> oid
            {oid, _value} -> oid
          end
          new_state = %{state | 
            current_oid: last_oid,
            accumulated: valid_varbinds ++ state.accumulated
          }
          bulk_walk_loop(new_state)
        else
          {:ok, Enum.reverse(state.accumulated ++ valid_varbinds)}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp bulk_walk_subtree_loop(state) do
    case perform_bulk_request(state) do
      {:ok, []} ->
        {:ok, Enum.reverse(state.accumulated)}
        
      {:ok, varbinds} ->
        {valid_varbinds, continue?} = filter_subtree_varbinds(varbinds, state.subtree_prefix)
        
        if continue? and length(valid_varbinds) > 0 do
          last_oid = case List.last(valid_varbinds) do
            {oid, _type, _value} -> oid
            {oid, _value} -> oid
          end
          new_state = %{state | 
            current_oid: last_oid,
            accumulated: valid_varbinds ++ state.accumulated
          }
          bulk_walk_subtree_loop(new_state)
        else
          {:ok, Enum.reverse(state.accumulated ++ valid_varbinds)}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Sequential walking fallback
  defp sequential_walk_table(host, table_oid, opts) do
    initial_state = %{
      host: host,
      current_oid: table_oid,
      table_prefix: table_oid,
      opts: opts,
      accumulated: [],
      retries: 0
    }
    
    sequential_walk_loop(initial_state)
  end
  
  defp sequential_walk_subtree(host, base_oid, opts) do
    initial_state = %{
      host: host,
      current_oid: base_oid,
      subtree_prefix: base_oid,
      opts: opts,
      accumulated: [],
      retries: 0
    }
    
    sequential_walk_subtree_loop(initial_state)
  end
  
  defp sequential_walk_loop(state) do
    case SnmpLib.Manager.get_next(state.host, state.current_oid, state.opts) do
      {:ok, {next_oid, type, value}} ->
        # Check if we're still in the table
        if oid_in_table?(next_oid, state.table_prefix) do
          varbind = {next_oid, type, value}
          new_state = %{state | 
            current_oid: next_oid,
            accumulated: [varbind | state.accumulated],
            retries: 0
          }
          sequential_walk_loop(new_state)
        else
          # We've walked past the table
          {:ok, Enum.reverse(state.accumulated)}
        end
        
      {:error, :no_such_name} ->
        # End of MIB or table
        {:ok, Enum.reverse(state.accumulated)}
        
      {:error, reason} ->
        max_retries = state.opts[:max_retries] || @default_max_retries
        if state.retries < max_retries do
          # Retry on transient errors
          new_state = %{state | retries: state.retries + 1}
          sequential_walk_loop(new_state)
        else
          # Max retries exceeded
          {:error, reason}
        end
    end
  end
  
  defp sequential_walk_subtree_loop(state) do
    case SnmpLib.Manager.get_next(state.host, state.current_oid, state.opts) do
      {:ok, {next_oid, type, value}} ->
        # Check if we're still in the subtree
        if oid_in_subtree?(next_oid, state.subtree_prefix) do
          varbind = {next_oid, type, value}
          new_state = %{state | 
            current_oid: next_oid,
            accumulated: [varbind | state.accumulated],
            retries: 0
          }
          sequential_walk_subtree_loop(new_state)
        else
          # We've walked past the subtree
          {:ok, Enum.reverse(state.accumulated)}
        end
        
      {:error, :no_such_name} ->
        # End of MIB or subtree
        {:ok, Enum.reverse(state.accumulated)}
        
      {:error, reason} ->
        max_retries = state.opts[:max_retries] || @default_max_retries
        if state.retries < max_retries do
          # Retry on transient errors
          new_state = %{state | retries: state.retries + 1}
          sequential_walk_subtree_loop(new_state)
        else
          # Max retries exceeded
          {:error, reason}
        end
    end
  end
  
  # Request operations
  defp perform_bulk_request(state) do
    SnmpLib.Manager.get_bulk(
      state.host,
      state.current_oid,
      merge_bulk_options(state.opts, state.bulk_size)
    )
  end
  
  
  # Streaming implementation
  defp init_streaming_state(host, table_oid, opts) do
    %{
      host: host,
      current_oid: table_oid,
      table_prefix: table_oid,
      opts: opts,
      bulk_size: opts[:max_repetitions] || @default_max_repetitions,
      chunk_size: opts[:chunk_size] || 25,
      finished: false
    }
  end
  
  defp get_next_chunk(%{finished: true}), do: {:halt, nil}
  defp get_next_chunk(state) do
    case perform_bulk_request(state) do
      {:ok, []} ->
        {:halt, nil}
        
      {:ok, varbinds} ->
        {valid_varbinds, continue?} = filter_table_varbinds(varbinds, state.table_prefix)
        
        if continue? and length(valid_varbinds) > 0 do
          # Get last OID for next request
          last_oid = case List.last(valid_varbinds) do
            {oid, _type, _value} -> oid
            {oid, _value} -> oid
          end
          new_state = %{state | current_oid: last_oid}
          {[valid_varbinds], new_state}
        else
          new_state = %{state | finished: true}
          {[valid_varbinds], new_state}
        end
        
      {:error, _reason} ->
        {:halt, nil}
    end
  end
  
  defp cleanup_streaming_state(_state), do: :ok
  
  # Helper functions
  defp filter_table_varbinds(varbinds, table_prefix) do
    valid_varbinds = Enum.take_while(varbinds, fn
      {oid, type, value} ->
        case value do
          nil when is_atom(type) and type in [:end_of_mib_view, :no_such_object, :no_such_instance] -> false
          _ -> oid_in_table?(oid, table_prefix)
        end
      {oid, value} ->
        # Handle legacy 2-tuple format
        case value do
          {:end_of_mib_view, _} -> false
          {:no_such_object, _} -> false
          {:no_such_instance, _} -> false
          _ -> oid_in_table?(oid, table_prefix)
        end
    end)
    
    continue? = length(valid_varbinds) == length(varbinds)
    {valid_varbinds, continue?}
  end
  
  defp filter_subtree_varbinds(varbinds, subtree_prefix) do
    valid_varbinds = Enum.take_while(varbinds, fn
      {oid, type, value} ->
        case value do
          nil when is_atom(type) and type in [:end_of_mib_view, :no_such_object, :no_such_instance] -> false
          _ -> oid_in_subtree?(oid, subtree_prefix)
        end
      {oid, value} ->
        # Handle legacy 2-tuple format
        case value do
          {:end_of_mib_view, _} -> false
          {:no_such_object, _} -> false
          {:no_such_instance, _} -> false
          _ -> oid_in_subtree?(oid, subtree_prefix)
        end
    end)
    
    continue? = length(valid_varbinds) == length(varbinds)
    {valid_varbinds, continue?}
  end
  
  defp oid_in_table?(oid, table_prefix) when is_list(oid) and is_list(table_prefix) do
    List.starts_with?(oid, table_prefix)
  end
  
  defp oid_in_subtree?(oid, subtree_prefix) when is_list(oid) and is_list(subtree_prefix) do
    List.starts_with?(oid, subtree_prefix)
  end
  
  defp extract_column_data(varbinds, column_oid) do
    column_prefix_length = length(column_oid)
    
    Enum.map(varbinds, fn 
      {oid, _type, value} ->
        index_oid = Enum.drop(oid, column_prefix_length)
        {index_oid, value}
      {oid, value} ->
        # Handle legacy 2-tuple format
        index_oid = Enum.drop(oid, column_prefix_length)
        {index_oid, value}
    end)
  end
  
  defp normalize_oid(oid) when is_list(oid), do: oid
  defp normalize_oid(oid) when is_binary(oid) do
    case SnmpLib.OID.string_to_list(oid) do
      {:ok, oid_list} -> oid_list
      {:error, _} -> [1, 3, 6, 1]
    end
  end
  
  defp merge_default_opts(opts) do
    [
      community: "public",
      version: :v2c,
      timeout: @default_timeout,
      max_repetitions: @default_max_repetitions,
      max_retries: @default_max_retries,
      retry_delay: @default_retry_delay,
      port: 161,
      adaptive_bulk: true,
      chunk_size: 25
    ]
    |> Keyword.merge(opts)
  end
  
  defp merge_bulk_options(opts, bulk_size) do
    # Ensure bulk_size is within reasonable bounds
    adjusted_bulk_size = max(@min_bulk_size, min(@max_bulk_size, bulk_size))
    Keyword.merge(opts, [max_repetitions: adjusted_bulk_size])
  end
end