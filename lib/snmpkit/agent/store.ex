defmodule SnmpKit.Agent.Store do
  @moduledoc """
  Scalars kept in an ETS table: the handler behind `SnmpKit.Agent.put/4`.

  Every agent has one store covering the whole tree; objects put into it
  are served unless a handler registered at a more specific prefix shadows
  them. A value may be a zero-arity function, which is called on every read,
  so a live gauge is just:

      SnmpKit.Agent.put(agent, "hrSystemNumUsers.0", :gauge32, fn -> MyApp.Sessions.count() end)

  Objects are read-only unless put with `writable: true`, in which case a
  SET of a value with the same type replaces it (type aliases such as
  `:string`/`:octet_string` are treated as equal). A store can also be
  registered on its own at a prefix, with `table:` naming an ETS
  `ordered_set` you own.
  """
  @behaviour SnmpKit.Agent.Handler

  @type table :: :ets.tid() | atom()

  @doc "Creates the ETS table a store uses (a public `ordered_set`)."
  @spec new_table() :: :ets.tid()
  def new_table do
    :ets.new(:snmpkit_agent_store, [:ordered_set, :public, read_concurrency: true])
  end

  @doc "Puts `{type, value}` at `oid`; `writable: true` lets SET replace the value."
  @spec put(table(), [non_neg_integer()], atom(), term(), keyword()) :: :ok
  def put(table, oid, type, value, opts \\ []) when is_list(oid) do
    :ets.insert(table, {oid, type, value, Keyword.get(opts, :writable, false)})
    :ok
  end

  @doc "Removes the object at `oid`."
  @spec delete(table(), [non_neg_integer()]) :: :ok
  def delete(table, oid) when is_list(oid) do
    :ets.delete(table, oid)
    :ok
  end

  @doc "Reads the object at `oid`, calling a function value."
  @spec fetch(table(), [non_neg_integer()]) :: {:ok, {atom(), term()}} | :error
  def fetch(table, oid) when is_list(oid) do
    case :ets.lookup(table, oid) do
      [{^oid, type, value, _writable}] -> {:ok, {type, materialize(value)}}
      [] -> :error
    end
  end

  @doc "Every object in the store as `{oid, type, value}`, in OID order."
  @spec to_list(table()) :: [{[non_neg_integer()], atom(), term()}]
  def to_list(table) do
    table
    |> :ets.tab2list()
    |> Enum.sort()
    |> Enum.map(fn {oid, type, value, _} -> {oid, type, materialize(value)} end)
  end

  ## Handler callbacks

  @impl true
  def init(opts) do
    case Keyword.get(opts, :table) do
      nil -> {:ok, %{table: new_table()}}
      table -> {:ok, %{table: table}}
    end
  end

  @impl true
  def get(suffix, %{table: table}) do
    case fetch(table, suffix) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :no_such_object}
    end
  end

  @impl true
  def get_next(suffix, %{table: table}) do
    case :ets.next(table, suffix) do
      :"$end_of_table" ->
        :end_of_subtree

      next ->
        case fetch(table, next) do
          {:ok, value} -> {:ok, {next, value}}
          :error -> get_next(next, %{table: table})
        end
    end
  end

  @impl true
  def check_set(suffix, {type, _value}, %{table: table}) do
    case :ets.lookup(table, suffix) do
      [{_, _type, _value, false}] ->
        {:error, :not_writable}

      [{_, current, _value, true}] ->
        if same_type?(current, type), do: :ok, else: {:error, :wrong_type}

      [] ->
        {:error, :no_creation}
    end
  end

  @impl true
  def set(suffix, {_type, value} = typed, %{table: table} = ctx) do
    with :ok <- check_set(suffix, typed, ctx) do
      [{_, current_type, _old, writable}] = :ets.lookup(table, suffix)
      :ets.insert(table, {suffix, current_type, value, writable})
      :ok
    end
  end

  defp materialize(fun) when is_function(fun, 0), do: fun.()
  defp materialize(value), do: value

  @string_types [:octet_string, :string]
  @unsigned_types [:gauge32, :unsigned32]
  @oid_types [:object_identifier, :oid]

  defp same_type?(a, b) when a == b, do: true
  defp same_type?(a, b) when a in @string_types and b in @string_types, do: true
  defp same_type?(a, b) when a in @unsigned_types and b in @unsigned_types, do: true
  defp same_type?(a, b) when a in @oid_types and b in @oid_types, do: true
  defp same_type?(_, _), do: false
end
