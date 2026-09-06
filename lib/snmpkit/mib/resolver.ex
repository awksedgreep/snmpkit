defmodule SnmpKit.MIB.Resolver do
  @moduledoc """
  Pure functions over name->OID and OID->name maps: forward and reverse
  lookups (with instance suffixes), children, subtree walks and normalisation
  of parsed OID representations. `SnmpKit.SnmpMgr.MIB` holds the maps; this
  module never touches process state, so it is safe to call from anywhere.
  """

  def resolve_name(name, name_to_oid_map) do
    cond do
      # Handle nil or invalid names first
      is_nil(name) or not is_binary(name) ->
        {:error, :invalid_name}

      # Direct match
      Map.has_key?(name_to_oid_map, name) ->
        {:ok, Map.get(name_to_oid_map, name)}

      # Name with instance (e.g., "sysDescr.0")
      String.contains?(name, ".") ->
        [base_name | instance_parts] = String.split(name, ".")

        case Map.get(name_to_oid_map, base_name) do
          nil ->
            {:error, :not_found}

          base_oid ->
            case Enum.reduce_while(instance_parts, [], fn part, acc ->
                   case Integer.parse(part) do
                     {int, ""} -> {:cont, [int | acc]}
                     _ -> {:halt, :error}
                   end
                 end) do
              :error -> {:error, :invalid_instance}
              instance_oids -> {:ok, base_oid ++ Enum.reverse(instance_oids)}
            end
        end

      true ->
        {:error, :not_found}
    end
  end

  def reverse_lookup_oid(oid, oid_to_name_map) do
    case Map.get(oid_to_name_map, oid) do
      nil ->
        # Try to find a partial match
        find_partial_reverse_match(oid, oid_to_name_map)

      name ->
        # Exact match - return as-is (already includes any suffix in the map)
        {:ok, name}
    end
  end

  def find_partial_reverse_match(oid, oid_to_name_map) do
    # Handle case where oid might be a string instead of list
    if is_binary(oid) do
      {:error, :invalid_oid_format}
    else
      # Handle empty list case
      if Enum.empty?(oid) do
        {:error, :empty_oid}
      else
        # Try progressively shorter OIDs to find a base match
        find_partial_match(oid, oid_to_name_map, length(oid) - 1)
      end
    end
  end

  def find_partial_match(_oid, _map, length) when length <= 0, do: {:error, :not_found}

  def find_partial_match(oid, oid_to_name_map, length) do
    partial_oid = Enum.take(oid, length)

    case Map.get(oid_to_name_map, partial_oid) do
      nil ->
        find_partial_match(oid, oid_to_name_map, length - 1)

      base_name ->
        # Found a base match - append the remaining OID elements as the index suffix
        base = strip_instance_suffix(base_name)
        suffix = Enum.drop(oid, length)

        case suffix do
          [] -> {:ok, base}
          _ -> {:ok, base <> "." <> Enum.join(suffix, ".")}
        end
    end
  end

  def find_children(parent_oid, name_to_oid_map) do
    normalized_oid =
      cond do
        is_nil(parent_oid) ->
          []

        is_binary(parent_oid) ->
          case SnmpKit.SnmpLib.OID.string_to_list(parent_oid) do
            {:ok, oid_list} -> oid_list
            {:error, _} -> []
          end

        is_list(parent_oid) ->
          parent_oid

        true ->
          []
      end

    # Return error for invalid OIDs
    if normalized_oid == [] and not is_nil(parent_oid) do
      {:error, :invalid_parent_oid}
    else
      children =
        name_to_oid_map
        |> Enum.filter(fn {_name, oid} ->
          is_list(oid) and is_list(normalized_oid) and
            length(oid) == length(normalized_oid) + 1 and
            List.starts_with?(oid, normalized_oid)
        end)
        |> Enum.map(fn {name, _oid} -> name end)
        |> Enum.sort()

      {:ok, children}
    end
  end

  def walk_tree_from_root(root_oid, name_to_oid_map) do
    root_oid =
      cond do
        is_binary(root_oid) ->
          case SnmpKit.SnmpLib.OID.string_to_list(root_oid) do
            {:ok, oid_list} -> oid_list
            {:error, _} -> []
          end

        is_list(root_oid) ->
          root_oid

        is_nil(root_oid) ->
          []

        true ->
          []
      end

    descendants =
      name_to_oid_map
      |> Enum.filter(fn {_name, oid} ->
        is_list(oid) and List.starts_with?(oid, root_oid)
      end)
      |> Enum.map(fn {name, oid} -> {name, oid} end)
      |> Enum.sort_by(fn {_name, oid} -> oid end)

    {:ok, descendants}
  end

  def build_reverse_map(name_to_oid_map) do
    name_to_oid_map
    |> Enum.map(fn {name, oid} -> {oid, name} end)
    |> Enum.into(%{})
  end

  # Normalize any dotted instance suffix from a name like "ifDescr.1" -> "ifDescr"
  def strip_instance_suffix(name) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [base] -> base
      [base, _rest] -> base
    end
  end

  def strip_instance_suffix(other), do: other

  def parse_instance(instance_str) do
    parts = String.split(instance_str, ".")

    try do
      ints =
        Enum.map(parts, fn p ->
          case Integer.parse(p) do
            {i, ""} -> i
            _ -> throw(:bad)
          end
        end)

      {:ok, ints}
    catch
      :bad -> {:error, :invalid_instance}
    end
  end

  # Normalize name->oid map from arbitrary representations
  def normalize_name_to_oid(raw) when is_map(raw) do
    raw
    |> Enum.reduce(%{}, fn {name, oid_any}, acc ->
      case normalize_parsed_oid(oid_any) do
        {:ok, oid_list} -> Map.put(acc, name, oid_list)
        _ -> acc
      end
    end)
  end

  @doc """
  Resolves the OIDs of a MIB's definitions (parsed maps or a compiled
  `symbols` table) to full integer lists.

  Definitions carry either an absolute OID, a `{parent_name, sub_ids}` tuple,
  or (for OBJECT IDENTIFIER assignments) `parent` and `sub_index` fields.
  Parents are looked up in `known` (names already in the registry) and among
  the definitions themselves, iterating until nothing more resolves, so
  definition order does not matter. Returns `%{name => oid_list}`.
  """
  @spec resolve_definition_oids([map()] | %{String.t() => map()}, %{String.t() => [integer()]}) ::
          %{String.t() => [integer()]}
  def resolve_definition_oids(definitions, known \\ %{})

  def resolve_definition_oids(symbols, known) when is_map(symbols),
    do: resolve_definition_oids(Map.values(symbols), known)

  def resolve_definition_oids(definitions, known) when is_list(definitions) do
    pending =
      definitions
      |> Enum.filter(&(is_map(&1) and is_binary(Map.get(&1, :name))))
      |> Enum.map(&{&1.name, definition_oid(&1)})
      |> Enum.reject(fn {_name, oid} -> oid == nil end)

    resolve_pending(pending, known, %{})
  end

  defp resolve_pending([], _known, resolved), do: resolved

  defp resolve_pending(pending, known, resolved) do
    {done, still} =
      Enum.reduce(pending, {resolved, []}, fn {name, oid}, {done, still} ->
        case absolute_oid(oid, known, done) do
          {:ok, list} -> {Map.put(done, name, list), still}
          :pending -> {done, [{name, oid} | still]}
        end
      end)

    if map_size(done) == map_size(resolved), do: done, else: resolve_pending(still, known, done)
  end

  # {:absolute, list} | {:relative, parent_name, sub_ids} | nil
  defp definition_oid(%{parent: parent, sub_index: subs})
       when is_binary(parent) or is_atom(parent),
       do: {:relative, parent, sub_ids(subs)}

  defp definition_oid(%{oid: {parent, subs}}) when is_binary(parent) or is_atom(parent),
    do: {:relative, parent, sub_ids(subs)}

  defp definition_oid(%{oid: oid}) when is_list(oid) do
    case normalize_parsed_oid(oid) do
      {:ok, list} -> {:absolute, list}
      _ -> nil
    end
  end

  defp definition_oid(_), do: nil

  defp sub_ids(subs) when is_list(subs), do: subs
  defp sub_ids(sub) when is_integer(sub), do: [sub]

  defp sub_ids(sub) when is_binary(sub) do
    case Integer.parse(sub) do
      {i, ""} -> [i]
      _ -> :binary.bin_to_list(sub)
    end
  end

  defp sub_ids(_), do: []

  defp absolute_oid({:absolute, list}, _known, _done), do: {:ok, list}
  defp absolute_oid({:relative, :root, subs}, _known, _done), do: {:ok, subs}
  defp absolute_oid({:relative, "root", subs}, _known, _done), do: {:ok, subs}

  defp absolute_oid({:relative, parent, subs}, known, done) do
    parent = to_string(parent)

    case Map.get(done, parent) || Map.get(known, parent) do
      nil -> :pending
      parent_oid when is_list(parent_oid) -> {:ok, parent_oid ++ subs}
    end
  end

  # Convert parsed OID representation to a flat integer list when possible
  def normalize_parsed_oid(oid) when is_list(oid) do
    cond do
      Enum.all?(oid, &is_integer/1) ->
        {:ok, oid}

      true ->
        # Handle lists like [%{value: 1}, %{value: 3}, ...] possibly with names
        vals =
          Enum.map(oid, fn
            %{value: v} when is_integer(v) ->
              {:ok, v}

            %{value: v} when is_binary(v) ->
              case Integer.parse(v) do
                {i, ""} -> {:ok, i}
                _ -> :error
              end

            v when is_integer(v) ->
              {:ok, v}

            _ ->
              :error
          end)

        if Enum.any?(vals, &(&1 == :error)) do
          {:error, :unresolved_oid}
        else
          {:ok, Enum.map(vals, fn {:ok, i} -> i end)}
        end
    end
  end

  def normalize_parsed_oid(_), do: {:error, :invalid_oid}
end
