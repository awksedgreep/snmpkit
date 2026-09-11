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

  Uses atomic ETS operations for thread-safe counter increment. Wraps around
  at #{@max_request_id}; `SnmpKit.SnmpMgr.Engine` refuses to register an id
  that is still pending, so a wrapped id is never reused while its earlier
  request is in flight.

  Raises `ArgumentError` when the generator is not running; `fetch_next_id/0`
  is the non-raising form.

  ## Examples

      iex> SnmpKit.SnmpMgr.RequestIdGenerator.next_id()
      1

      iex> SnmpKit.SnmpMgr.RequestIdGenerator.next_id()
      2
  """
  @spec next_id() :: pos_integer()
  def next_id() do
    case fetch_next_id() do
      {:ok, id} ->
        id

      {:error, :services_not_started} ->
        raise ArgumentError,
              "#{inspect(__MODULE__)} is not running (ETS table #{inspect(@table_name)} " <>
                "is missing); call SnmpKit.SnmpMgr.ensure_started/0 first"
    end
  end

  @doc """
  Like `next_id/0`, but returns `{:error, :services_not_started}` instead of
  raising when the generator is not running. There is no fallback id: a random
  one could collide with a request already in flight.
  """
  @spec fetch_next_id() :: {:ok, pos_integer()} | {:error, :services_not_started}
  def fetch_next_id() do
    {:ok, :ets.update_counter(@table_name, :counter, {2, 1, @max_request_id, 1})}
  rescue
    ArgumentError -> {:error, :services_not_started}
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
    #
    # The table may already exist (another generator instance owns it, or a
    # previous owner is still shutting down); in that case it is shared rather
    # than crashing this process with a badarg.
    owner? =
      case :ets.whereis(table_name) do
        :undefined ->
          ^table_name =
            :ets.new(table_name, [
              :public,
              :set,
              :named_table,
              {:read_concurrency, true},
              {:write_concurrency, true}
            ])

          # Initialize counter to 0
          :ets.insert(table_name, {:counter, 0})
          true

        _existing ->
          :ets.insert_new(table_name, {:counter, 0})
          false
      end

    Logger.info("RequestIdGenerator started with table: #{table_name}")

    {:ok, %{table_name: table_name, owner?: owner?}}
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

  # Only the instance that created the table deletes it; a generator sharing
  # another instance's table must not take that table down with it.
  @impl true
  def terminate(_reason, %{owner?: true, table_name: table_name}) do
    if :ets.info(table_name) != :undefined do
      :ets.delete(table_name)
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok
end
