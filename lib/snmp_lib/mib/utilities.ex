defmodule SnmpKit.SnmpLib.MIB.Utilities do
  @moduledoc """
  Direct port of Erlang snmpc_lib.erl utility functions to Elixir.

  This is a 1:1 port of the utility functions from the official Erlang SNMP compiler
  from OTP lib/snmp/src/compile/snmpc_lib.erl

  Original copyright: Ericsson AB 1996-2025 (Apache License 2.0)
  """

  @type oid() :: [integer()]
  @type oid_status() :: :resolved | :unresolved
  @type verbosity() :: :silent | :warning | :info | :debug

  # OID and Name Resolution

  @doc """
  Register an OID entry in the OID table.
  Port of register_oid/4 from snmpc_lib.erl
  """
  @spec register_oid(binary(), oid(), atom(), map()) :: map()
  def register_oid(name, oid, status, oid_table) do
    entry = %{
      name: name,
      oid: oid,
      status: status,
      parent: get_parent_oid(oid),
      children: []
    }

    Map.put(oid_table, name, entry)
  end

  @doc """
  Resolve symbolic OID references to numeric OIDs.
  Port of resolve_oids/1 from snmpc_lib.erl
  """
  @spec resolve_oids(map()) :: {:ok, map()} | {:error, [binary()]}
  def resolve_oids(oid_table) do
    # Start with root OIDs (those without parents)
    root_oids = find_root_oids(oid_table)

    case resolve_oid_tree(root_oids, oid_table, MapSet.new()) do
      {:ok, resolved_table} -> {:ok, resolved_table}
      {:error, unresolved} -> {:error, MapSet.to_list(unresolved)}
    end
  end

  @doc """
  Translate symbolic name to numeric OID.
  Port of tr_oid/2 from snmpc_lib.erl
  """
  @spec tr_oid(binary(), map()) :: {:ok, oid()} | {:error, :not_found}
  def tr_oid(name, oid_table) do
    case Map.get(oid_table, name) do
      %{oid: oid, status: :resolved} -> {:ok, oid}
      %{status: :unresolved} -> {:error, :unresolved}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Update MIB entries with resolved OIDs.
  Port of update_me_oids/3 from snmpc_lib.erl
  """
  @spec update_me_oids([map()], map(), verbosity()) :: [map()]
  def update_me_oids(mib_entries, oid_table, verbosity) do
    Enum.map(mib_entries, fn entry ->
      update_single_entry_oid(entry, oid_table, verbosity)
    end)
  end

  # Type Checking and Validation

  @doc """
  Validate and transform ASN.1 type definition.
  Port of make_ASN1type/1 from snmpc_lib.erl
  """
  @spec make_asn1_type(term()) :: {:ok, map()} | {:error, binary()}
  def make_asn1_type(type_def) do
    case normalize_type(type_def) do
      {:ok, normalized} -> validate_type_constraints(normalized)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate bit definitions for BITS syntax.
  Port of test_kibbles/2 from snmpc_lib.erl
  """
  @spec test_kibbles([map()], verbosity()) :: :ok | {:error, binary()}
  def test_kibbles(bit_definitions, verbosity) do
    case validate_bit_names(bit_definitions) do
      :ok -> validate_bit_values(bit_definitions, verbosity)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if size constraint is allowed for given type (RFC 1902 compliance).
  Port of allow_size_rfc1902/1 from snmpc_lib.erl
  """
  @spec allow_size_rfc1902(atom()) :: boolean()
  def allow_size_rfc1902(type) do
    case type do
      :octet_string -> true
      :object_identifier -> false
      :integer -> false
      :counter32 -> false
      :counter64 -> false
      :gauge32 -> false
      :time_ticks -> false
      :ip_address -> false
      _ -> false
    end
  end

  @doc """
  Validate sub-identifier ranges.
  Port of check_sub_ids/3 from snmpc_lib.erl
  """
  @spec check_sub_ids(oid(), integer(), integer()) :: :ok | {:error, binary()}
  def check_sub_ids(oid, min_value, max_value) do
    case Enum.find(oid, &(&1 < min_value or &1 > max_value)) do
      nil ->
        :ok

      invalid_id ->
        {:error, "Sub-identifier #{invalid_id} out of range [#{min_value}..#{max_value}]"}
    end
  end

  # Error Handling and Reporting

  @doc """
  Print error message with formatting.
  Port of print_error/2 and print_error/3 from snmpc_lib.erl
  """
  @spec print_error(binary(), verbosity()) :: :ok
  def print_error(message, verbosity) when verbosity != :silent do
    IO.puts("❌ Error: #{message}")
  end

  def print_error(_message, :silent), do: :ok

  @spec print_error(binary(), term(), verbosity()) :: :ok
  def print_error(format, args, verbosity) when verbosity != :silent do
    message = :io_lib.format(format, args) |> IO.iodata_to_binary()
    print_error(message, verbosity)
  end

  def print_error(_format, _args, :silent), do: :ok

  @doc """
  Terminate compilation with error.
  Port of error/2 and error/3 from snmpc_lib.erl
  """
  @spec compilation_error(binary()) :: no_return()
  def compilation_error(message) do
    throw({:error, message})
  end

  @spec compilation_error(binary(), term()) :: no_return()
  def compilation_error(format, args) do
    message = :io_lib.format(format, args) |> IO.iodata_to_binary()
    compilation_error(message)
  end

  # Debugging Utilities

  @doc """
  Configurable verbose printing.
  Port of vprint/6 from snmpc_lib.erl
  """
  @spec vprint(verbosity(), verbosity(), binary(), binary(), binary(), [term()]) :: :ok
  def vprint(current_verbosity, required_verbosity, module, function, format, args) do
    if printable?(current_verbosity, required_verbosity) do
      message = :io_lib.format(format, args) |> IO.iodata_to_binary()
      IO.puts("[#{module}:#{function}] #{message}")
    end
  end

  @doc """
  Determine if message should be printed based on verbosity.
  Port of printable/2 from snmpc_lib.erl
  """
  @spec printable?(verbosity(), verbosity()) :: boolean()
  def printable?(current_verbosity, required_verbosity) do
    verbosity_level(current_verbosity) >= verbosity_level(required_verbosity)
  end

  @doc """
  Validate verbosity level.
  Port of vvalidate/1 from snmpc_lib.erl
  """
  @spec vvalidate(term()) :: {:ok, verbosity()} | {:error, binary()}
  def vvalidate(verbosity) when verbosity in [:silent, :warning, :info, :debug] do
    {:ok, verbosity}
  end

  def vvalidate(invalid) do
    {:error, "Invalid verbosity level: #{inspect(invalid)}"}
  end

  # Miscellaneous Helpers

  @doc """
  Safe key lookup in list of tuples/maps.
  Port of key1search/2 and key1search/3 from snmpc_lib.erl
  """
  @spec key1search(term(), [tuple()]) :: {:value, term()} | false
  def key1search(key, list) do
    case Enum.find(list, &(elem(&1, 0) == key)) do
      nil -> false
      tuple -> {:value, tuple}
    end
  end

  @spec key1search(term(), [tuple()], term()) :: term()
  def key1search(key, list, default) do
    case key1search(key, list) do
      {:value, tuple} -> tuple
      false -> default
    end
  end

  @doc """
  Set directory path helper.
  Port of set_dir/2 from snmpc_lib.erl
  """
  @spec set_dir(binary(), binary()) :: binary()
  def set_dir(filename, directory) do
    case Path.dirname(filename) do
      "." -> Path.join(directory, Path.basename(filename))
      _ -> filename
    end
  end

  @doc """
  Generic lookup function with multiple criteria.
  Port of lookup/2 from snmpc_lib.erl
  """
  @spec lookup(term(), [term()]) :: {:ok, term()} | {:error, :not_found}
  def lookup(key, list) when is_list(list) do
    case Enum.find(list, &match_lookup_criteria(key, &1)) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  # Private helper functions

  defp get_parent_oid([]), do: nil
  defp get_parent_oid(oid) when length(oid) == 1, do: nil

  defp get_parent_oid(oid) do
    oid |> Enum.drop(-1)
  end

  defp find_root_oids(oid_table) do
    oid_table
    |> Enum.filter(fn {_name, entry} -> entry.parent == nil end)
    |> Enum.map(fn {name, _entry} -> name end)
  end

  defp resolve_oid_tree([], oid_table, _visited), do: {:ok, oid_table}

  defp resolve_oid_tree([name | rest], oid_table, visited) do
    if MapSet.member?(visited, name) do
      resolve_oid_tree(rest, oid_table, visited)
    else
      case resolve_single_oid(name, oid_table) do
        {:ok, updated_table} ->
          new_visited = MapSet.put(visited, name)
          resolve_oid_tree(rest, updated_table, new_visited)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp resolve_single_oid(name, oid_table) do
    case Map.get(oid_table, name) do
      %{status: :resolved} = _entry ->
        {:ok, oid_table}

      %{status: :unresolved, oid: symbolic_oid} = entry ->
        case resolve_symbolic_oid(symbolic_oid, oid_table) do
          {:ok, numeric_oid} ->
            updated_entry = %{entry | oid: numeric_oid, status: :resolved}
            updated_table = Map.put(oid_table, name, updated_entry)
            {:ok, updated_table}

          {:error, reason} ->
            {:error, reason}
        end

      nil ->
        {:error, "OID not found: #{name}"}
    end
  end

  defp resolve_symbolic_oid(oid, oid_table) when is_list(oid) do
    # Convert symbolic OID elements to numeric
    case resolve_oid_elements(oid, oid_table, []) do
      {:ok, numeric_oid} -> {:ok, numeric_oid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_oid_elements([], _oid_table, acc), do: {:ok, Enum.reverse(acc)}

  defp resolve_oid_elements([element | rest], oid_table, acc) do
    case resolve_oid_element(element, oid_table) do
      {:ok, numeric_value} ->
        resolve_oid_elements(rest, oid_table, [numeric_value | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_oid_element(%{name: _name, value: value}, _oid_table) when is_integer(value) do
    {:ok, value}
  end

  defp resolve_oid_element(%{name: name}, oid_table) do
    case tr_oid(name, oid_table) do
      {:ok, [numeric_value]} -> {:ok, numeric_value}
      {:ok, oid} when length(oid) > 1 -> {:error, "Invalid OID reference: #{name}"}
      {:error, reason} -> {:error, "Cannot resolve OID reference: #{name} (#{reason})"}
    end
  end

  defp resolve_oid_element(%{value: value}, _oid_table) when is_integer(value) do
    {:ok, value}
  end

  defp update_single_entry_oid(entry, oid_table, verbosity) do
    case Map.get(entry, :oid) do
      nil ->
        entry

      symbolic_oid ->
        case tr_oid(symbolic_oid, oid_table) do
          {:ok, numeric_oid} ->
            vprint(verbosity, :debug, "Utilities", "update_oid", "Resolved ~s -> ~w", [
              symbolic_oid,
              numeric_oid
            ])

            %{entry | oid: numeric_oid}

          {:error, reason} ->
            print_error("Cannot resolve OID for #{entry.name}: #{reason}", verbosity)
            entry
        end
    end
  end

  defp normalize_type({:integer, constraints}),
    do: {:ok, %{type: :integer, constraints: constraints}}

  defp normalize_type({:octet_string, constraints}),
    do: {:ok, %{type: :octet_string, constraints: constraints}}

  defp normalize_type({:object_identifier}),
    do: {:ok, %{type: :object_identifier, constraints: []}}

  defp normalize_type({:named_type, name}),
    do: {:ok, %{type: :named_type, name: name, constraints: []}}

  defp normalize_type(type) when is_atom(type), do: {:ok, %{type: type, constraints: []}}
  defp normalize_type(invalid), do: {:error, "Invalid type definition: #{inspect(invalid)}"}

  defp validate_type_constraints(%{type: :integer, constraints: constraints} = type_def) do
    case validate_integer_constraints(constraints) do
      :ok -> {:ok, type_def}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_type_constraints(%{type: :octet_string, constraints: constraints} = type_def) do
    case validate_size_constraints(constraints) do
      :ok -> {:ok, type_def}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_type_constraints(type_def), do: {:ok, type_def}

  defp validate_integer_constraints([]), do: :ok

  defp validate_integer_constraints([{:range, min, max} | rest])
       when is_integer(min) and is_integer(max) and min <= max do
    validate_integer_constraints(rest)
  end

  defp validate_integer_constraints([{:enum, _values} | rest]) do
    # TODO: Validate enum values
    validate_integer_constraints(rest)
  end

  defp validate_integer_constraints([invalid | _]) do
    {:error, "Invalid integer constraint: #{inspect(invalid)}"}
  end

  defp validate_size_constraints([]), do: :ok

  defp validate_size_constraints([size | rest]) when is_integer(size) and size >= 0 do
    validate_size_constraints(rest)
  end

  defp validate_size_constraints([{:range, min, max} | rest])
       when is_integer(min) and is_integer(max) and min <= max and min >= 0 do
    validate_size_constraints(rest)
  end

  defp validate_size_constraints([invalid | _]) do
    {:error, "Invalid size constraint: #{inspect(invalid)}"}
  end

  defp validate_bit_names(bit_definitions) do
    names = Enum.map(bit_definitions, & &1.name)

    case length(names) == length(Enum.uniq(names)) do
      true -> :ok
      false -> {:error, "Duplicate bit names found"}
    end
  end

  defp validate_bit_values(bit_definitions, verbosity) do
    values = Enum.map(bit_definitions, & &1.value)

    case length(values) == length(Enum.uniq(values)) do
      true ->
        vprint(verbosity, :debug, "Utilities", "validate_bits", "Bit validation successful", [])
        :ok

      false ->
        {:error, "Duplicate bit values found"}
    end
  end

  defp verbosity_level(:silent), do: 0
  defp verbosity_level(:warning), do: 1
  defp verbosity_level(:info), do: 2
  defp verbosity_level(:debug), do: 3

  defp match_lookup_criteria(key, {key, _value}), do: true
  defp match_lookup_criteria(key, %{name: key}), do: true
  defp match_lookup_criteria(key, %{id: key}), do: true
  defp match_lookup_criteria(_key, _item), do: false
end
