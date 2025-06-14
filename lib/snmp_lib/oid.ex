defmodule SnmpLib.OID do
  @moduledoc """
  Comprehensive OID (Object Identifier) manipulation utilities for SNMP operations.
  
  Provides string/list conversions, tree operations, table utilities, and validation
  functions needed by both SNMP managers and simulators.
  
  ## Features
  
  - String/list format conversions with validation
  - OID tree operations (parent/child relationships)
  - SNMP table index parsing and construction
  - OID comparison and sorting
  - Enterprise OID utilities
  - Performance-optimized operations
  
  ## Examples
  
      # Basic conversions
      {:ok, oid_list} = SnmpLib.OID.string_to_list("1.3.6.1.2.1.1.1.0")
      {:ok, oid_string} = SnmpLib.OID.list_to_string([1, 3, 6, 1, 2, 1, 1, 1, 0])
      
      # Tree operations
      true = SnmpLib.OID.is_child_of?([1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1])
      {:ok, parent} = SnmpLib.OID.get_parent([1, 3, 6, 1, 2, 1, 1, 1, 0])
      
      # Comparison
      :lt = SnmpLib.OID.compare([1, 3, 6, 1], [1, 3, 6, 2])
      
      # Table operations
      {:ok, index} = SnmpLib.OID.extract_table_index([1, 3, 6, 1, 2, 1, 2, 2, 1, 1], [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1])
  """

  @type oid :: [non_neg_integer()]
  @type oid_string :: String.t()
  @type table_oid :: oid()
  @type index :: [non_neg_integer()]

  # Standard SNMP OID prefixes
  @iso_org_dod_internet [1, 3, 6, 1]
  @mgmt [1, 3, 6, 1, 2]
  @mib_2 [1, 3, 6, 1, 2, 1]
  @enterprises [1, 3, 6, 1, 4, 1]
  @experimental [1, 3, 6, 1, 3]
  @private [1, 3, 6, 1, 4]

  ## String/List Conversions

  @doc """
  Converts an OID string to a list of integers.
  
  Parses a dot-separated OID string into a list of non-negative integers.
  Validates each component and ensures the OID format is correct.
  
  ## Parameters
  
  - `oid_string`: Dot-separated OID string (e.g., "1.3.6.1.2.1.1.1.0")
  
  ## Returns
  
  - `{:ok, oid_list}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      # Standard SNMP OIDs
      iex> SnmpLib.OID.string_to_list("1.3.6.1.2.1.1.1.0")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}
      
      # Short OIDs
      iex> SnmpLib.OID.string_to_list("1.3.6")
      {:ok, [1, 3, 6]}
      
      # Error cases
      iex> SnmpLib.OID.string_to_list("")
      {:error, :empty_oid}
      
      iex> SnmpLib.OID.string_to_list("1.3.6.1.a.2")
      {:error, :invalid_oid_string}
      
      iex> SnmpLib.OID.string_to_list("1.3.6.1.2.-1")
      {:error, :invalid_oid_string}
  """
  @spec string_to_list(oid_string()) :: {:ok, oid()} | {:error, atom()}
  def string_to_list(oid_string) when is_binary(oid_string) do
    case String.trim(oid_string) do
      "" ->
        {:error, :empty_oid}
      
      trimmed_string ->
        parts = String.split(trimmed_string, ".")
        case parse_oid_components(parts) do
          {:ok, oid_list} ->
            case validate_oid_list(oid_list) do
              :ok -> {:ok, oid_list}
              {:error, reason} -> {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
    end
  end
  def string_to_list(_), do: {:error, :invalid_input}

  @doc """
  Converts an OID list to a dot-separated string.
  
  ## Parameters
  
  - `oid_list`: List of non-negative integers
  
  ## Returns
  
  - `{:ok, oid_string}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      {:ok, "1.3.6.1.2.1.1.1.0"} = SnmpLib.OID.list_to_string([1, 3, 6, 1, 2, 1, 1, 1, 0])
      {:error, :invalid_oid_list} = SnmpLib.OID.list_to_string([1, 3, -1, 4])
      {:error, :empty_oid} = SnmpLib.OID.list_to_string([])
  """
  @spec list_to_string(oid()) :: {:ok, oid_string()} | {:error, atom()}
  def list_to_string(oid_list) when is_list(oid_list) do
    case validate_oid_list(oid_list) do
      :ok ->
        oid_string = Enum.join(oid_list, ".")
        {:ok, oid_string}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def list_to_string(_), do: {:error, :invalid_input}

  ## Tree Operations

  @doc """
  Checks if one OID is a child of another.
  
  ## Parameters
  
  - `child_oid`: Potential child OID
  - `parent_oid`: Potential parent OID
  
  ## Returns
  
  - `true` if child_oid is a child of parent_oid
  - `false` otherwise
  
  ## Examples
  
      true = SnmpLib.OID.is_child_of?([1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1])
      false = SnmpLib.OID.is_child_of?([1, 3, 6, 1], [1, 3, 6, 1, 2, 1])
      false = SnmpLib.OID.is_child_of?([1, 3, 6, 2], [1, 3, 6, 1])
  """
  @spec is_child_of?(oid(), oid()) :: boolean()
  def is_child_of?(child_oid, parent_oid) when is_list(child_oid) and is_list(parent_oid) do
    child_length = length(child_oid)
    parent_length = length(parent_oid)
    
    child_length > parent_length and 
      Enum.take(child_oid, parent_length) == parent_oid
  end
  def is_child_of?(_, _), do: false

  @doc """
  Checks if one OID is a parent of another.
  """
  @spec is_parent_of?(oid(), oid()) :: boolean()
  def is_parent_of?(parent_oid, child_oid), do: is_child_of?(child_oid, parent_oid)

  @doc """
  Gets the parent OID by removing the last component.
  
  ## Examples
  
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1]} = SnmpLib.OID.get_parent([1, 3, 6, 1, 2, 1, 1, 1, 0])
      {:error, :root_oid} = SnmpLib.OID.get_parent([])
      {:error, :root_oid} = SnmpLib.OID.get_parent([1])
  """
  @spec get_parent(oid()) :: {:ok, oid()} | {:error, atom()}
  def get_parent(oid) when is_list(oid) and length(oid) > 1 do
    parent = Enum.drop(oid, -1)
    {:ok, parent}
  end
  def get_parent(oid) when is_list(oid), do: {:error, :root_oid}
  def get_parent(_), do: {:error, :invalid_input}

  @doc """
  Gets the immediate children prefix for an OID in a given set.
  
  ## Parameters
  
  - `parent_oid`: The parent OID
  - `oid_set`: Set of OIDs to search
  
  ## Returns
  
  - List of immediate child OIDs
  
  ## Examples
  
      children = SnmpLib.OID.get_children([1, 3, 6, 1], [[1, 3, 6, 1, 2], [1, 3, 6, 1, 4], [1, 3, 6, 1, 2, 1]])
      # Returns [[1, 3, 6, 1, 2], [1, 3, 6, 1, 4]]
  """
  @spec get_children(oid(), [oid()]) :: [oid()]
  def get_children(parent_oid, oid_set) when is_list(parent_oid) and is_list(oid_set) do
    parent_length = length(parent_oid)
    
    oid_set
    |> Enum.filter(&is_child_of?(&1, parent_oid))
    |> Enum.map(&Enum.take(&1, parent_length + 1))
    |> Enum.uniq()
  end
  def get_children(_, _), do: []

  @doc """
  Get standard SNMP OID prefixes.
  
  ## Examples
  
      iex> SnmpLib.OID.standard_prefix(:internet)
      [1, 3, 6, 1]
      
      iex> SnmpLib.OID.standard_prefix(:mgmt)
      [1, 3, 6, 1, 2]
  """
  @spec standard_prefix(atom()) :: oid() | nil
  def standard_prefix(:internet), do: @iso_org_dod_internet
  def standard_prefix(:mgmt), do: @mgmt
  def standard_prefix(:mib_2), do: @mib_2
  def standard_prefix(:enterprises), do: @enterprises
  def standard_prefix(:experimental), do: @experimental
  def standard_prefix(:private), do: @private
  def standard_prefix(_), do: nil

  @doc """
  Gets the next OID in lexicographic order from a given set.
  
  ## Parameters
  
  - `current_oid`: The current OID
  - `oid_set`: Set of OIDs to search (must be sorted)
  
  ## Returns
  
  - `{:ok, next_oid}` if found
  - `{:error, :end_of_mib}` if no next OID exists
  
  ## Examples
  
      oid_set = [[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 2, 0], [1, 3, 6, 1, 2, 1, 1, 3, 0]]
      {:ok, [1, 3, 6, 1, 2, 1, 1, 2, 0]} = SnmpLib.OID.get_next_oid([1, 3, 6, 1, 2, 1, 1, 1, 0], oid_set)
  """
  @spec get_next_oid(oid(), [oid()]) :: {:ok, oid()} | {:error, atom()}
  def get_next_oid(current_oid, oid_set) when is_list(current_oid) and is_list(oid_set) do
    case Enum.find(oid_set, &(compare(&1, current_oid) == :gt)) do
      nil -> {:error, :end_of_mib}
      next_oid -> {:ok, next_oid}
    end
  end
  def get_next_oid(_, _), do: {:error, :invalid_input}

  ## Comparison Operations

  @doc """
  Compares two OIDs lexicographically.
  
  ## Returns
  
  - `:lt` if oid1 < oid2
  - `:eq` if oid1 == oid2
  - `:gt` if oid1 > oid2
  
  ## Examples
  
      :lt = SnmpLib.OID.compare([1, 3, 6, 1], [1, 3, 6, 2])
      :eq = SnmpLib.OID.compare([1, 3, 6, 1], [1, 3, 6, 1])
      :gt = SnmpLib.OID.compare([1, 3, 6, 2], [1, 3, 6, 1])
  """
  @spec compare(oid(), oid()) :: :lt | :eq | :gt
  def compare(oid1, oid2) when is_list(oid1) and is_list(oid2) do
    compare_components(oid1, oid2)
  end

  @doc """
  Sorts a list of OIDs in lexicographic order.
  
  ## Examples
  
      sorted = SnmpLib.OID.sort([[1, 3, 6, 2], [1, 3, 6, 1, 2], [1, 3, 6, 1]])
      # Returns [[1, 3, 6, 1], [1, 3, 6, 1, 2], [1, 3, 6, 2]]
  """
  @spec sort([oid()]) :: [oid()]
  def sort(oid_list) when is_list(oid_list) do
    Enum.sort(oid_list, &(compare(&1, &2) != :gt))
  end
  def sort(_), do: []

  ## Table Operations

  @doc """
  Extracts table index from an instance OID given the table column OID.
  
  ## Parameters
  
  - `table_oid`: Base table column OID
  - `instance_oid`: Full instance OID including index
  
  ## Returns
  
  - `{:ok, index}` if successful
  - `{:error, reason}` if extraction fails
  
  ## Examples
  
      table_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 1]
      instance_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1]
      {:ok, [1]} = SnmpLib.OID.extract_table_index(table_oid, instance_oid)
  """
  @spec extract_table_index(table_oid(), oid()) :: {:ok, index()} | {:error, atom()}
  def extract_table_index(table_oid, instance_oid) 
      when is_list(table_oid) and is_list(instance_oid) do
    table_length = length(table_oid)
    instance_length = length(instance_oid)
    
    if instance_length > table_length and 
       Enum.take(instance_oid, table_length) == table_oid do
      index = Enum.drop(instance_oid, table_length)
      {:ok, index}
    else
      {:error, :invalid_table_instance}
    end
  end
  def extract_table_index(_, _), do: {:error, :invalid_input}

  @doc """
  Builds a table instance OID from table OID and index.
  
  ## Parameters
  
  - `table_oid`: Base table column OID
  - `index`: Table index as list of integers
  
  ## Returns
  
  - `{:ok, instance_oid}` if successful
  - `{:error, reason}` if construction fails
  
  ## Examples
  
      table_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 1]
      index = [1]
      {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1]} = SnmpLib.OID.build_table_instance(table_oid, index)
  """
  @spec build_table_instance(table_oid(), index()) :: {:ok, oid()} | {:error, atom()}
  def build_table_instance(table_oid, index) 
      when is_list(table_oid) and is_list(index) do
    case {validate_oid_list(table_oid), validate_oid_list(index)} do
      {:ok, :ok} ->
        instance_oid = table_oid ++ index
        {:ok, instance_oid}
      {{:error, reason}, _} ->
        {:error, reason}
      {_, {:error, reason}} ->
        {:error, reason}
    end
  end
  def build_table_instance(_, _), do: {:error, :invalid_input}

  @doc """
  Parses a table index according to index syntax definition.
  
  ## Parameters
  
  - `index`: Raw index from OID
  - `syntax`: Index syntax specification
  
  ## Returns
  
  - `{:ok, parsed_index}` if successful
  - `{:error, reason}` if parsing fails
  
  ## Index Syntax Examples
  
  - `:integer` - Single integer index
  - `{:string, length}` - Fixed-length string
  - `{:variable_string}` - Length-prefixed string
  - `[:integer, :integer]` - Multiple integer indices
  
  ## Examples
  
      {:ok, 42} = SnmpLib.OID.parse_table_index([42], :integer)
      {:ok, "test"} = SnmpLib.OID.parse_table_index([4, 116, 101, 115, 116], {:variable_string})
  """
  @spec parse_table_index(index(), term()) :: {:ok, term()} | {:error, atom()}
  def parse_table_index(index, :integer) when is_list(index) and length(index) == 1 do
    {:ok, hd(index)}
  end
  
  def parse_table_index(index, {:string, length}) when is_list(index) and length(index) == length do
    case build_string_from_bytes(index) do
      {:ok, string} -> {:ok, string}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def parse_table_index([length | rest], {:variable_string}) when length(rest) == length do
    case build_string_from_bytes(rest) do
      {:ok, string} -> {:ok, string}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def parse_table_index(index, syntax_list) when is_list(syntax_list) do
    case parse_index_components(index, syntax_list, []) do
      {:ok, {parsed, _remaining}} -> {:ok, parsed}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def parse_table_index(_, _), do: {:error, :unsupported_syntax}

  @doc """
  Builds a table index from parsed components according to syntax.
  
  ## Examples
  
      {:ok, [42]} = SnmpLib.OID.build_table_index(42, :integer)
      {:ok, [4, 116, 101, 115, 116]} = SnmpLib.OID.build_table_index("test", {:variable_string})
  """
  @spec build_table_index(term(), term()) :: {:ok, index()} | {:error, atom()}
  def build_table_index(values, syntax_list) when is_list(values) and is_list(syntax_list) do
    if length(values) == length(syntax_list) do
      case build_compound_index(values, syntax_list) do
        {:ok, index} -> {:ok, index}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :syntax_value_mismatch}
    end
  end
  
  def build_table_index(value, :integer) when is_integer(value) and value >= 0 do
    {:ok, [value]}
  end
  
  def build_table_index(value, {:string, length}) when is_binary(value) do
    if String.length(value) == length do
      index = value |> String.to_charlist()
      {:ok, index}
    else
      {:error, :invalid_string_length}
    end
  end
  
  def build_table_index(value, {:variable_string}) when is_binary(value) do
    char_list = String.to_charlist(value)
    index = [length(char_list) | char_list]
    {:ok, index}
  end
  
  def build_table_index(_, _), do: {:error, :unsupported_syntax}

  ## Validation

  @doc """
  Validates an OID list for correctness.
  
  ## Returns
  
  - `:ok` if valid
  - `{:error, reason}` if invalid
  
  ## Examples
  
      :ok = SnmpLib.OID.valid_oid?([1, 3, 6, 1, 2, 1, 1, 1, 0])
      {:error, :empty_oid} = SnmpLib.OID.valid_oid?([])
      {:error, :invalid_component} = SnmpLib.OID.valid_oid?([1, 3, -1, 4])
  """
  @spec valid_oid?(oid()) :: :ok | {:error, atom()}
  def valid_oid?(oid) when is_list(oid), do: validate_oid_list(oid)
  def valid_oid?(_), do: {:error, :invalid_input}

  @doc """
  Normalizes an OID to a consistent format.
  
  Accepts either string or list format and returns a list.
  
  ## Examples
  
      {:ok, [1, 3, 6, 1]} = SnmpLib.OID.normalize("1.3.6.1")
      {:ok, [1, 3, 6, 1]} = SnmpLib.OID.normalize([1, 3, 6, 1])
  """
  @spec normalize(oid() | oid_string()) :: {:ok, oid()} | {:error, atom()}
  def normalize(oid) when is_list(oid) do
    case valid_oid?(oid) do
      :ok -> {:ok, oid}
      error -> error
    end
  end
  def normalize(oid) when is_binary(oid), do: string_to_list(oid)
  def normalize(_), do: {:error, :invalid_input}

  ## Utility Functions

  @doc """
  Returns standard SNMP OID prefixes.
  """
  @spec mib_2() :: oid()
  def mib_2, do: @mib_2

  @spec enterprises() :: oid()
  def enterprises, do: @enterprises

  @spec experimental() :: oid()
  def experimental, do: @experimental

  @spec private() :: oid()
  def private, do: @private

  @doc """
  Checks if an OID is under a specific standard tree.
  
  ## Examples
  
      true = SnmpLib.OID.is_mib_2?([1, 3, 6, 1, 2, 1, 1, 1, 0])
      true = SnmpLib.OID.is_enterprise?([1, 3, 6, 1, 4, 1, 9, 1, 1])
  """
  @spec is_mib_2?(oid()) :: boolean()
  def is_mib_2?(oid), do: is_child_of?(oid, @mib_2) or oid == @mib_2

  @spec is_enterprise?(oid()) :: boolean()
  def is_enterprise?(oid), do: is_child_of?(oid, @enterprises)

  @spec is_experimental?(oid()) :: boolean()
  def is_experimental?(oid), do: is_child_of?(oid, @experimental)

  @spec is_private?(oid()) :: boolean()
  def is_private?(oid), do: is_child_of?(oid, @private)

  @doc """
  Gets the enterprise number from an enterprise OID.
  
  ## Examples
  
      {:ok, 9} = SnmpLib.OID.get_enterprise_number([1, 3, 6, 1, 4, 1, 9, 1, 1])
      {:error, :not_enterprise_oid} = SnmpLib.OID.get_enterprise_number([1, 3, 6, 1, 2, 1])
  """
  @spec get_enterprise_number(oid()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def get_enterprise_number(oid) when is_list(oid) do
    if is_enterprise?(oid) and length(oid) > length(@enterprises) do
      enterprise_num = Enum.at(oid, length(@enterprises))
      {:ok, enterprise_num}
    else
      {:error, :not_enterprise_oid}
    end
  end
  def get_enterprise_number(_), do: {:error, :invalid_input}

  ## Private Helper Functions

  defp parse_oid_components(parts) do
    try do
      oid_list = Enum.map(parts, fn part ->
        case parse_oid_component(part) do
          {:error, reason} -> throw(reason)
          num -> num
        end
      end)
      {:ok, oid_list}
    catch
      reason -> {:error, reason}
    end
  end

  defp parse_oid_component(component) when is_binary(component) do
    case Integer.parse(component) do
      {num, ""} when num >= 0 -> num
      _ -> {:error, :invalid_oid_string}
    end
  end

  defp validate_oid_list([]), do: {:error, :empty_oid}
  defp validate_oid_list(oid_list) when is_list(oid_list) do
    if Enum.all?(oid_list, &is_valid_oid_component/1) do
      :ok
    else
      {:error, :invalid_component}
    end
  end
  defp validate_oid_list(_), do: {:error, :invalid_input}

  defp is_valid_oid_component(component) when is_integer(component) and component >= 0, do: true
  defp is_valid_oid_component(_), do: false

  defp compare_components([], []), do: :eq
  defp compare_components([], _), do: :lt
  defp compare_components(_, []), do: :gt
  defp compare_components([h1 | t1], [h2 | t2]) do
    cond do
      h1 < h2 -> :lt
      h1 > h2 -> :gt
      true -> compare_components(t1, t2)
    end
  end

  defp parse_index_components(index, [], acc) do
    {:ok, {Enum.reverse(acc), index}}
  end
  
  defp parse_index_components(index, [syntax | rest_syntax], acc) do
    case parse_table_index(index, syntax) do
      {:ok, value} ->
        # Calculate how many components were consumed
        case build_table_index(value, syntax) do
          {:ok, consumed_index} ->
            consumed_length = length(consumed_index)
            remaining_index = Enum.drop(index, consumed_length)
            parse_index_components(remaining_index, rest_syntax, [value | acc])
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_string_from_bytes(bytes) do
    try do
      string = bytes |> Enum.map(&<<&1>>) |> Enum.join("")
      {:ok, string}
    rescue
      _ -> {:error, :invalid_string_index}
    end
  end

  defp build_compound_index(values, syntax_list) do
    index_parts = Enum.zip(values, syntax_list)
               |> Enum.map(fn {val, syntax} ->
                  case build_table_index(val, syntax) do
                    {:ok, idx} -> idx
                    {:error, reason} -> {:error, reason}
                  end
                end)
    case Enum.find(index_parts, &match?({:error, _}, &1)) do
      nil ->
        index = List.flatten(index_parts)
        {:ok, index}
      {:error, reason} -> {:error, reason}
    end
  end
end