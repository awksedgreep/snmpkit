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

  ## Cost

  Rows are fetched once per request (every PDU, including each GETBULK of
  a walk), so one request sees a consistent snapshot. Within that request
  the first GET or SET encodes every row's index once (O(rows)) and each
  further lookup is a map lookup; the first GETNEXT encodes and sorts
  every cell once (O(cells log cells)) and each further step is a binary
  search. A walk therefore costs one rows call and one sort per PDU, not
  per object. Tables with tens of thousands of rows are still better
  served by a handler of their own that can seek directly.
  """
  @behaviour SnmpKit.Agent.Handler

  alias SnmpKit.Agent.Types

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
    entries = entries(ctx)

    case first_after(entries, suffix, 0, tuple_size(entries)) do
      {s, type, value} -> {:ok, {s, {type, value}}}
      nil -> :end_of_subtree
    end
  end

  @impl true
  def check_set([column | index_oid], {type, _value}, ctx) do
    cond do
      is_nil(ctx.set) -> {:error, :not_writable}
      not Map.has_key?(ctx.columns, column) -> {:error, :no_creation}
      not Types.same_type?(ctx.columns[column], type) -> {:error, :wrong_type}
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
    case Map.fetch(row_index(ctx), index_oid) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, :no_such_instance}
    end
  end

  # the first entry whose suffix is greater than `suffix`, in `entries[lo, hi)`
  defp first_after(entries, suffix, lo, hi) when lo < hi do
    mid = div(lo + hi, 2)

    if elem(elem(entries, mid), 0) > suffix,
      do: first_after(entries, suffix, lo, mid),
      else: first_after(entries, suffix, mid + 1, hi)
  end

  defp first_after(entries, _suffix, lo, _hi) when lo < tuple_size(entries), do: elem(entries, lo)
  defp first_after(_entries, _suffix, _lo, _hi), do: nil

  # One request is handled by one worker process, so the process dictionary
  # holds the snapshot, and what is derived from it, for that request only.
  defp rows(ctx), do: cached(ctx, :rows, fn -> ctx.rows.() end)

  # rows keyed by their encoded index; the first row wins a duplicate index
  defp row_index(ctx) do
    cached(ctx, :row_index, fn ->
      Enum.reduce(rows(ctx), %{}, fn {index, _values} = row, acc ->
        Map.put_new(acc, encode_index(index, ctx.index), row)
      end)
    end)
  end

  # every cell as {suffix, type, value}, sorted, in a tuple for binary search
  defp entries(ctx) do
    cached(ctx, :entries, fn ->
      for {index, values} <- rows(ctx),
          index_oid = encode_index(index, ctx.index),
          {column, type} <- ctx.columns,
          {:ok, value} <- [Map.fetch(values, column)] do
        {[column | index_oid], type, value}
      end
      |> Enum.sort()
      |> List.to_tuple()
    end)
  end

  defp cached(ctx, what, build) do
    key = {__MODULE__, ctx.ref, what}

    case Process.get(key) do
      nil ->
        value = build.()
        Process.put(key, value)
        value

      value ->
        value
    end
  end
end
