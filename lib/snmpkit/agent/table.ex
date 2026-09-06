defmodule SnmpKit.Agent.Table do
  @moduledoc """
  Serves a conceptual table from rows produced by a function.

  Register it at the table's *entry* OID (`ifEntry`, not `ifTable`):

      SnmpKit.Agent.register(agent, "ifEntry", SnmpKit.Agent.Table,
        columns: [{1, :integer}, {2, :octet_string}, {5, :gauge32}, {8, :integer}],
        index: [:integer],
        rows: fn ->
          for {port, i} <- Enum.with_index(MyApp.Ports.all(), 1) do
            {i, %{1 => i, 2 => port.name, 5 => port.speed, 8 => if(port.up?, do: 1, else: 2)}}
          end
        end
      )

  ## Options

  - `:columns` - the column numbers and their types, as a list of
    `{column, type}` or a map
  - `:index` - the INDEX objects' kinds, in order (default `[:integer]`):
    `:integer`, `:string` (length-prefixed), `:implied_string`,
    `:ip_address`, `:oid`, `:implied_oid`
  - `:rows` - a zero-arity function returning `[{index, values}]` where
    `index` is the index value (or a list of values, one per INDEX object)
    and `values` maps column numbers to values; a missing column is
    `noSuchInstance`
  - `:set` - optional `fun(index, column, {type, value}) :: :ok | {:error, reason}`
    making the table writable; the row must already exist

  Rows are fetched once per request, so a GETBULK or a walk step sees a
  consistent snapshot. Tables with tens of thousands of rows are better
  served by a handler of their own that can seek directly.
  """
  @behaviour SnmpKit.Agent.Handler

  @type index_kind :: :integer | :string | :implied_string | :ip_address | :oid | :implied_oid

  @impl true
  def init(opts) do
    columns =
      opts
      |> Keyword.get(:columns, [])
      |> Map.new()

    with true <- is_function(Keyword.get(opts, :rows), 0) || {:error, :rows_function_required},
         true <- map_size(columns) > 0 || {:error, :columns_required} do
      {:ok,
       %{
         columns: columns,
         index: Keyword.get(opts, :index, [:integer]),
         rows: Keyword.fetch!(opts, :rows),
         set: Keyword.get(opts, :set),
         ref: make_ref()
       }}
    end
  end

  @impl true
  def get([column | index_oid], ctx) do
    with {:ok, type} <- column_type(column, ctx),
         {:ok, {_index, values}} <- find_row(index_oid, ctx),
         {:ok, value} <- Map.fetch(values, column) do
      {:ok, {type, value}}
    else
      {:error, :no_such_object} -> {:error, :no_such_object}
      _ -> {:error, :no_such_instance}
    end
  end

  def get(_suffix, _ctx), do: {:error, :no_such_object}

  @impl true
  def get_next(suffix, ctx) do
    case Enum.find(entries(ctx), fn {s, _type, _value} -> s > suffix end) do
      {s, type, value} -> {:ok, {s, {type, value}}}
      nil -> :end_of_subtree
    end
  end

  @impl true
  def check_set([column | index_oid], {type, _value}, ctx) do
    cond do
      is_nil(ctx.set) -> {:error, :not_writable}
      not Map.has_key?(ctx.columns, column) -> {:error, :no_creation}
      not same_type?(ctx.columns[column], type) -> {:error, :wrong_type}
      match?({:error, _}, find_row(index_oid, ctx)) -> {:error, :no_creation}
      true -> :ok
    end
  end

  def check_set(_suffix, _value, _ctx), do: {:error, :no_creation}

  @impl true
  def set([column | index_oid] = suffix, value, ctx) do
    with :ok <- check_set(suffix, value, ctx),
         {:ok, {index, _values}} <- find_row(index_oid, ctx) do
      ctx.set.(index, column, value)
    end
  end

  @doc """
  Encodes index values as instance sub-identifiers (RFC 2578 section 7.7).

      iex> SnmpKit.Agent.Table.encode_index([{10, 0, 0, 1}, "eth0"], [:ip_address, :string])
      [10, 0, 0, 1, 4, ?e, ?t, ?h, ?0]
  """
  @spec encode_index(term() | [term()], [index_kind()]) :: [non_neg_integer()]
  def encode_index(values, kinds) when is_list(kinds) do
    values = if length(kinds) == 1, do: [single(values)], else: values

    kinds
    |> Enum.zip(values)
    |> Enum.flat_map(fn {kind, value} -> encode_one(kind, value) end)
  end

  defp single([v]), do: v
  defp single(v), do: v

  defp encode_one(:integer, n) when is_integer(n), do: [n]
  defp encode_one(:string, s) when is_binary(s), do: [byte_size(s) | :binary.bin_to_list(s)]
  defp encode_one(:implied_string, s) when is_binary(s), do: :binary.bin_to_list(s)
  defp encode_one(:ip_address, {a, b, c, d}), do: [a, b, c, d]
  defp encode_one(:ip_address, <<a, b, c, d>>), do: [a, b, c, d]
  defp encode_one(:oid, oid) when is_list(oid), do: [length(oid) | oid]
  defp encode_one(:implied_oid, oid) when is_list(oid), do: oid
  defp encode_one(_kind, oid) when is_list(oid), do: oid

  defp encode_one(kind, value),
    do: raise(ArgumentError, "cannot encode #{inspect(value)} as a #{inspect(kind)} index")

  ## internals

  defp column_type(column, ctx) do
    case Map.fetch(ctx.columns, column) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, :no_such_object}
    end
  end

  defp find_row(index_oid, ctx) do
    case Enum.find(rows(ctx), fn {index, _values} ->
           encode_index(index, ctx.index) == index_oid
         end) do
      nil -> {:error, :no_such_instance}
      row -> {:ok, row}
    end
  end

  # One request is handled by one worker process, so the process dictionary
  # holds the snapshot for the duration of the request only.
  defp rows(ctx) do
    case Process.get({__MODULE__, ctx.ref, :rows}) do
      nil ->
        rows = ctx.rows.()
        Process.put({__MODULE__, ctx.ref, :rows}, rows)
        rows

      rows ->
        rows
    end
  end

  defp entries(ctx) do
    case Process.get({__MODULE__, ctx.ref, :entries}) do
      nil ->
        entries =
          for {index, values} <- rows(ctx),
              index_oid = encode_index(index, ctx.index),
              {column, type} <- ctx.columns,
              {:ok, value} <- [Map.fetch(values, column)] do
            {[column | index_oid], type, value}
          end
          |> Enum.sort()

        Process.put({__MODULE__, ctx.ref, :entries}, entries)
        entries

      entries ->
        entries
    end
  end

  @string_types [:octet_string, :string]
  @unsigned_types [:gauge32, :unsigned32]
  @oid_types [:object_identifier, :oid]

  defp same_type?(a, b) when a == b, do: true
  defp same_type?(a, b) when a in @string_types and b in @string_types, do: true
  defp same_type?(a, b) when a in @unsigned_types and b in @unsigned_types, do: true
  defp same_type?(a, b) when a in @oid_types and b in @oid_types, do: true
  defp same_type?(_, _), do: false
end
