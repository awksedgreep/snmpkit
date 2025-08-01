defmodule SnmpKit.SnmpMgr.RequestIdGenerator do
  @moduledoc """
  Atomic request ID generator using ETS for thread-safe counter operations.
  
  Provides unique request IDs for SNMP operations without requiring
  GenServer synchronization, eliminating serialization bottlenecks.
  """
  
  use GenServer
  require Logger
  
  @table_name :snmp_request_id_counter
  @max_request_id 1_000_000
  
  @doc """
  Starts the RequestIdGenerator GenServer.
  
  Creates the ETS table for atomic counter operations.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Generates the next unique request ID.
  
  Uses atomic ETS operations for thread-safe counter increment.
  Wraps around at #{@max_request_id} to prevent overflow.
  
  ## Examples
  
      iex> SnmpKit.SnmpMgr.RequestIdGenerator.next_id()
      1
      
      iex> SnmpKit.SnmpMgr.RequestIdGenerator.next_id()
      2
  """
  def next_id() do
    try do
      :ets.update_counter(@table_name, :counter, {2, 1, @max_request_id, 1})
    rescue
      ArgumentError ->
        # Table doesn't exist, start the GenServer
        Logger.warning("RequestIdGenerator not started, using fallback")
        :rand.uniform(@max_request_id)
    end
  end
  
  @doc """
  Gets the current counter value without incrementing.
  
  Useful for debugging and monitoring.
  """
  def current_value() do
    try do
      [{:counter, value}] = :ets.lookup(@table_name, :counter)
      value
    rescue
      ArgumentError ->
        Logger.warning("RequestIdGenerator not started")
        0
    end
  end
  
  @doc """
  Resets the counter to 0.
  
  Primarily used for testing.
  """
  def reset() do
    try do
      :ets.insert(@table_name, {:counter, 0})
      :ok
    rescue
      ArgumentError ->
        Logger.warning("RequestIdGenerator not started")
        :error
    end
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, @table_name)
    
    # Create ETS table for atomic counter operations
    # :public allows other processes to access directly
    # :set ensures single counter entry
    # :named_table allows access by atom name
    ^table_name = :ets.new(table_name, [
      :public,
      :set,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Initialize counter to 0
    :ets.insert(table_name, {:counter, 0})
    
    Logger.info("RequestIdGenerator started with table: #{table_name}")
    
    {:ok, %{table_name: table_name}}
  end
  
  @impl true
  def handle_call(:current_value, _from, state) do
    [{:counter, value}] = :ets.lookup(state.table_name, :counter)
    {:reply, value, state}
  end
  
  @impl true
  def handle_call(:reset, _from, state) do
    :ets.insert(state.table_name, {:counter, 0})
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:next_id, count}, _from, state) when count > 0 do
    # Batch ID generation for testing
    ids = for _ <- 1..count, do: next_id()
    {:reply, ids, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Clean up ETS table
    if :ets.info(state.table_name) != :undefined do
      :ets.delete(state.table_name)
    end
    :ok
  end
end