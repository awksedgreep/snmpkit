defmodule SnmpKit.MIB.TableIndex do
  @moduledoc """
  Decodes the instance sub-identifiers of a conceptual row into the values
  of the table's INDEX objects (RFC 2578 section 7.7).

  Each index object is described by `%{name, base, size, implied}`:

  - integer-like bases (`:integer`, `:gauge32`, `:counter32`, `:timeticks`)
    take one sub-identifier;
  - `:ip_address` takes four and yields a tuple;
  - `:octet_string` with a fixed size takes that many, otherwise a length
    sub-identifier followed by the octets (or the rest when `implied`);
  - `:object_identifier` likewise takes a length then the sub-identifiers
    (or the rest when `implied`).

      iex> SnmpKit.MIB.TableIndex.decode([10, 0, 0, 1, 7], [
      ...>   %{name: "ipAdEntAddr", base: :ip_address},
      ...>   %{name: "slot", base: :integer}
      ...> ])
      {:ok, %{"ipAdEntAddr" => {10, 0, 0, 1}, "slot" => 7}}
  """

  @type index_spec :: %{
          required(:name) => String.t(),
          required(:base) => atom() | nil,
          optional(:size) => {non_neg_integer(), non_neg_integer()} | nil,
          optional(:implied) => boolean()
        }

  @integer_bases [:integer, :gauge32, :counter32, :counter64, :timeticks, :unsigned32, :bits]

  @doc "Decodes `sub_ids` with `specs`; `{:error, reason}` when they do not fit."
  @spec decode([non_neg_integer()], [index_spec()]) ::
          {:ok, %{String.t() => term()}} | {:error, term()}
  def decode(sub_ids, specs) when is_list(sub_ids) and is_list(specs) do
    decode(sub_ids, specs, %{})
  end

  defp decode([], [], acc), do: {:ok, acc}
  defp decode(_rest, [], _acc), do: {:error, :trailing_sub_identifiers}
  defp decode([], [_ | _], _acc), do: {:error, :missing_sub_identifiers}

  defp decode(sub_ids, [spec | specs], acc) do
    with {:ok, value, rest} <- take(spec, sub_ids, specs == []) do
      decode(rest, specs, Map.put(acc, spec.name, value))
    end
  end

  defp take(%{base: base}, [value | rest], _last) when base in @integer_bases,
    do: {:ok, value, rest}

  defp take(%{base: :ip_address}, [a, b, c, d | rest], _last), do: {:ok, {a, b, c, d}, rest}
  defp take(%{base: :ip_address}, _short, _last), do: {:error, :missing_sub_identifiers}

  defp take(%{base: :octet_string} = spec, sub_ids, last) do
    case fixed_size(spec) do
      n when is_integer(n) ->
        split_octets(sub_ids, n)

      nil ->
        if Map.get(spec, :implied, false) or (last and not length_prefixed?(sub_ids)) do
          {:ok, :binary.list_to_bin(sub_ids), []}
        else
          with [len | more] <- sub_ids, do: split_octets(more, len)
        end
    end
  end

  defp take(%{base: :object_identifier} = spec, sub_ids, last) do
    if Map.get(spec, :implied, false) or (last and not length_prefixed?(sub_ids)) do
      {:ok, sub_ids, []}
    else
      case sub_ids do
        [len | more] when length(more) >= len -> {:ok, Enum.take(more, len), Enum.drop(more, len)}
        _ -> {:error, :invalid_object_identifier_index}
      end
    end
  end

  defp take(%{base: nil} = spec, sub_ids, last), do: take(%{spec | base: :integer}, sub_ids, last)
  defp take(_spec, _sub_ids, _last), do: {:error, :undecodable_index}

  defp split_octets(sub_ids, n) when length(sub_ids) >= n do
    {octets, rest} = Enum.split(sub_ids, n)

    if Enum.all?(octets, &(&1 in 0..255)),
      do: {:ok, :binary.list_to_bin(octets), rest},
      else: {:error, :invalid_octet_index}
  end

  defp split_octets(_sub_ids, _n), do: {:error, :missing_sub_identifiers}

  defp fixed_size(%{size: {n, n}}) when is_integer(n), do: n
  defp fixed_size(_), do: nil

  defp length_prefixed?([len | rest]), do: length(rest) == len
  defp length_prefixed?(_), do: false
end
