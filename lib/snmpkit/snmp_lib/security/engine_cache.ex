defmodule SnmpKit.SnmpLib.Security.EngineCache do
  @moduledoc """
  Remembers what the manager has learned about remote SNMPv3 engines: the
  authoritative engine id of each `{host, port}` and its boots/time, so a
  request does not need a discovery round trip and a time synchronisation
  every time.

  Entries are refreshed whenever an agent answers with a
  `usmStatsNotInTimeWindows` or `usmStatsUnknownEngineIDs` report.
  """
  use GenServer

  @table :snmpkit_engine_cache

  @type key :: {:inet.ip_address() | String.t(), :inet.port_number()}
  @type entry :: %{
          engine_id: binary(),
          engine_boots: non_neg_integer(),
          # agent engine_time minus our monotonic seconds when learned
          time_offset: integer(),
          learned_at: integer()
        }

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The cached entry for `{host, port}`, or `nil`."
  @spec lookup(key()) :: entry() | nil
  def lookup(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, entry}] -> entry
      [] -> nil
    end
  end

  @doc "Stores the engine id and current boots/time of `{host, port}`."
  @spec store(key(), binary(), non_neg_integer(), non_neg_integer()) :: :ok
  def store(key, engine_id, engine_boots, engine_time) do
    ensure_table()

    entry = %{
      engine_id: engine_id,
      engine_boots: engine_boots,
      time_offset: engine_time - now_seconds(),
      learned_at: now_seconds()
    }

    :ets.insert(@table, {key, entry})
    :ok
  end

  @doc "The agent's engine time as of now, from a cached entry."
  @spec current_time(entry()) :: non_neg_integer()
  def current_time(%{time_offset: offset}), do: max(now_seconds() + offset, 0)

  @doc "Forgets one engine or, with no argument, every engine."
  @spec clear(key() | nil) :: :ok
  def clear(key \\ nil) do
    ensure_table()
    if key, do: :ets.delete(@table, key), else: :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    ensure_table()
    {:ok, %{}}
  end

  # The table is public so callers can use it without the GenServer when the
  # application is not running (scripts, tests); the GenServer only keeps it
  # alive across callers.
  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  defp now_seconds, do: System.monotonic_time(:second)
end
