defmodule SnmpMgr.Table do
  @moduledoc """
  Table processing utilities for SNMP table data.
  
  Provides functions to convert flat OID/type/value lists into structured
  table representations and perform table analysis operations.
  """

  @doc """
  Converts flat OID/type/value tuples to a structured table format.

  Takes a list of {oid_string, type, value} tuples from a table walk
  and converts them into a structured table with rows and columns.

  ## Parameters
  - `oid_type_value_tuples` - List of {oid_string, type, value} tuples
  - `table_oid` - The base table OID (used to determine table structure)

  ## Examples

      iex> tuples = [
      ...>   {"1.3.6.1.2.1.2.2.1.2.1", :string, "eth0"},
      ...>   {"1.3.6.1.2.1.2.2.1.2.2", :string, "eth1"},
      ...>   {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6},
      ...>   {"1.3.6.1.2.1.2.2.1.3.2", :integer, 6}
      ...> ]
      iex> SnmpMgr.Table.to_table(tuples, [1, 3, 6, 1, 2, 1, 2, 2])
      {:ok, %{
        1 => %{2 => "eth0", 3 => 6},
        2 => %{2 => "eth1", 3 => 6}
      }}
  """
  def to_table(oid_type_value_tuples, table_oid) when is_list(table_oid) do
    table_oid_length = length(table_oid)
    
    table_data = 
      oid_type_value_tuples
      |> Enum.map(fn {oid_string, _type, value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} ->
            if List.starts_with?(oid_list, table_oid) and length(oid_list) > table_oid_length + 2 do
              # Extract: table_oid + [1] + column + index_parts
              rest = Enum.drop(oid_list, table_oid_length)
              case rest do
                [1, column | [_ | _] = index_parts] ->
                  index = if length(index_parts) == 1 do
                    hd(index_parts)
                  else
                    index_parts
                  end
                  {index, column, value}
                _ -> nil
              end
            else
              nil
            end
          {:error, _} -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.group_by(fn {index, _column, _value} -> index end)
      |> Enum.map(fn {index, entries} ->
        columns = 
          entries
          |> Enum.map(fn {_index, column, value} -> {column, value} end)
          |> Enum.into(%{})
        {index, columns}
      end)
      |> Enum.into(%{})

    {:ok, table_data}
  end

  def to_table(oid_type_value_tuples, table_oid) when is_binary(table_oid) do
    case SnmpLib.OID.string_to_list(table_oid) do
      {:ok, oid_list} -> to_table(oid_type_value_tuples, oid_list)
      error -> error
    end
  end

  @doc """
  Converts OID/type/value tuples to a list of row maps.

  Each row is a map where keys are column numbers and values are the data values.
  """
  def to_rows(oid_type_value_tuples) do
    # Group by index (last part of OID)
    rows = 
      oid_type_value_tuples
      |> Enum.map(fn {oid_string, _type, value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} when length(oid_list) >= 3 ->
            # Extract column and index from the end of the OID
            # Format: ...table.1.column.index
            [index | rest] = Enum.reverse(oid_list)
            [column | _] = rest
            {index, column, value}
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.group_by(fn {index, _column, _value} -> index end)
      |> Enum.map(fn {index, entries} ->
        row = 
          entries
          |> Enum.map(fn {_index, column, value} -> {column, value} end)
          |> Enum.into(%{})
        Map.put(row, :index, index)
      end)

    {:ok, rows}
  end

  @doc """
  Converts table data to a map keyed by a specific column.

  ## Parameters
  - `oid_type_value_tuples` - List of {oid_string, type, value} tuples
  - `key_column` - Column number to use as the key

  ## Examples

      iex> tuples = [
      ...>   {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
      ...>   {"1.3.6.1.2.1.2.2.1.2.1", :string, "eth0"},
      ...>   {"1.3.6.1.2.1.2.2.1.1.2", :integer, 2},
      ...>   {"1.3.6.1.2.1.2.2.1.2.2", :string, "eth1"}
      ...> ]
      iex> SnmpMgr.Table.to_map(tuples, 1)
      {:ok, %{
        1 => %{ifIndex: 1, ifDescr: "eth0"},
        2 => %{ifIndex: 2, ifDescr: "eth1"}
      }}
  """
  def to_map(oid_type_value_tuples, key_column) do
    case to_rows(oid_type_value_tuples) do
      {:ok, rows} ->
        mapped_data = 
          rows
          |> Enum.filter(fn row -> Map.has_key?(row, key_column) end)
          |> Enum.map(fn row -> {Map.get(row, key_column), row} end)
          |> Enum.into(%{})
        {:ok, mapped_data}
      error -> error
    end
  end

  @doc """
  Extracts all unique indexes from table data.
  """
  def get_indexes(table_data) when is_map(table_data) do
    {:ok, Map.keys(table_data)}
  end

  def get_indexes(oid_type_value_tuples) when is_list(oid_type_value_tuples) do
    indexes = 
      oid_type_value_tuples
      |> Enum.map(fn {oid_string, _type, _value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} when length(oid_list) >= 1 ->
            List.last(oid_list)
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()
      |> Enum.sort()

    {:ok, indexes}
  end

  @doc """
  Extracts all unique column numbers from table data.
  """
  def get_columns(table_data) when is_map(table_data) do
    columns = 
      table_data
      |> Map.values()
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()
      |> Enum.sort()
    {:ok, columns}
  end

  def get_columns(oid_type_value_tuples) when is_list(oid_type_value_tuples) do
    columns = 
      oid_type_value_tuples
      |> Enum.map(fn {oid_string, _type, _value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} when length(oid_list) >= 2 ->
            # Get second-to-last element (column number)
            oid_list |> Enum.reverse() |> Enum.at(1)
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()
      |> Enum.sort()

    {:ok, columns}
  end

  @doc """
  Filters table data by index using a filter function.

  ## Parameters
  - `table_data` - Table data as returned by to_table/2
  - `index_filter` - Function that takes an index and returns boolean

  ## Examples

      iex> table = %{1 => %{2 => "eth0"}, 2 => %{2 => "eth1"}, 10 => %{2 => "lo"}}
      iex> SnmpMgr.Table.filter_by_index(table, fn index -> index < 10 end)
      {:ok, %{1 => %{2 => "eth0"}, 2 => %{2 => "eth1"}}}
  """
  def filter_by_index(table_data, index_filter) when is_map(table_data) and is_function(index_filter, 1) do
    filtered = 
      table_data
      |> Enum.filter(fn {index, _data} -> index_filter.(index) end)
      |> Enum.into(%{})
    {:ok, filtered}
  end

  @doc """
  Converts table data to a list format for easier processing.

  ## Examples

      iex> table = %{1 => %{2 => "eth0", 3 => 6}, 2 => %{2 => "eth1", 3 => 6}}
      iex> SnmpMgr.Table.to_list(table)
      {:ok, [
        %{index: 1, 2 => "eth0", 3 => 6},
        %{index: 2, 2 => "eth1", 3 => 6}
      ]}
  """
  def to_list(table_data) when is_map(table_data) do
    list = 
      table_data
      |> Enum.map(fn {index, columns} ->
        Map.put(columns, :index, index)
      end)
      |> Enum.sort_by(fn row -> Map.get(row, :index) end)
    {:ok, list}
  end

  @doc """
  Analyzes table structure and returns metadata about the table.

  Provides detailed information about table dimensions, column types,
  missing data, and statistical analysis.

  ## Parameters
  - `table_data` - Table data as returned by to_table/2
  - `opts` - Options including :analyze_types, :find_missing

  ## Examples

      iex> table = %{1 => %{2 => "eth0", 3 => 100}, 2 => %{2 => "eth1", 3 => 200}}
      iex> SnmpMgr.Table.analyze(table)
      {:ok, %{
        row_count: 2,
        column_count: 2,
        columns: [2, 3],
        indexes: [1, 2],
        completeness: 1.0,
        column_types: %{2 => :string, 3 => :integer}
      }}
  """
  def analyze(table_data, opts \\ []) when is_map(table_data) do
    analyze_types = Keyword.get(opts, :analyze_types, true)
    find_missing = Keyword.get(opts, :find_missing, true)
    
    indexes = Map.keys(table_data)
    all_columns = table_data
                 |> Map.values()
                 |> Enum.flat_map(&Map.keys/1)
                 |> Enum.uniq()
                 |> Enum.sort()
    
    row_count = length(indexes)
    column_count = length(all_columns)
    
    # Calculate completeness
    total_cells = row_count * column_count
    filled_cells = table_data
                  |> Map.values()
                  |> Enum.map(&map_size/1)
                  |> Enum.sum()
    completeness = if total_cells > 0, do: filled_cells / total_cells, else: 0.0
    
    analysis = %{
      row_count: row_count,
      column_count: column_count,
      columns: all_columns,
      indexes: Enum.sort(indexes),
      completeness: completeness,
      density: completeness
    }
    
    # Add type analysis if requested
    analysis = if analyze_types do
      column_types = analyze_column_types(table_data, all_columns)
      Map.put(analysis, :column_types, column_types)
    else
      analysis
    end
    
    # Add missing data analysis if requested
    analysis = if find_missing do
      missing = find_missing_data(table_data, indexes, all_columns)
      Map.put(analysis, :missing_data, missing)
    else
      analysis
    end
    
    {:ok, analysis}
  end

  @doc """
  Filters table data by column values using a filter function.

  ## Parameters
  - `table_data` - Table data as returned by to_table/2
  - `column` - Column number to filter on
  - `filter_fn` - Function that takes a value and returns boolean

  ## Examples

      iex> table = %{1 => %{2 => "eth0", 3 => 1}, 2 => %{2 => "eth1", 3 => 0}}
      iex> SnmpMgr.Table.filter_by_column(table, 3, fn val -> val == 1 end)
      {:ok, %{1 => %{2 => "eth0", 3 => 1}}}
  """
  def filter_by_column(table_data, column, filter_fn) when is_map(table_data) and is_function(filter_fn, 1) do
    filtered = 
      table_data
      |> Enum.filter(fn {_index, row_data} ->
        case Map.get(row_data, column) do
          nil -> false
          value -> filter_fn.(value)
        end
      end)
      |> Enum.into(%{})
    {:ok, filtered}
  end

  @doc """
  Sorts table data by a specific column.

  ## Parameters
  - `table_data` - Table data as returned by to_table/2
  - `column` - Column number to sort by
  - `direction` - :asc or :desc (default: :asc)

  ## Examples

      iex> table = %{1 => %{2 => "eth1"}, 2 => %{2 => "eth0"}}
      iex> SnmpMgr.Table.sort_by_column(table, 2)
      {:ok, [{2, %{2 => "eth0"}}, {1, %{2 => "eth1"}}]}
  """
  def sort_by_column(table_data, column, direction \\ :asc) when is_map(table_data) do
    sorted = 
      table_data
      |> Enum.filter(fn {_index, row_data} -> Map.has_key?(row_data, column) end)
      |> Enum.sort_by(fn {_index, row_data} -> Map.get(row_data, column) end, direction)
    
    {:ok, sorted}
  end

  @doc """
  Groups table rows by values in a specific column.

  ## Parameters
  - `table_data` - Table data as returned by to_table/2
  - `column` - Column number to group by

  ## Examples

      iex> table = %{1 => %{2 => "eth", 3 => 1}, 2 => %{2 => "lo", 3 => 1}}
      iex> SnmpMgr.Table.group_by_column(table, 3)
      {:ok, %{1 => [%{index: 1, 2 => "eth", 3 => 1}, %{index: 2, 2 => "lo", 3 => 1}]}}
  """
  def group_by_column(table_data, column) when is_map(table_data) do
    grouped = 
      table_data
      |> Enum.filter(fn {_index, row_data} -> Map.has_key?(row_data, column) end)
      |> Enum.group_by(fn {_index, row_data} -> Map.get(row_data, column) end)
      |> Enum.map(fn {group_value, entries} ->
        rows = Enum.map(entries, fn {index, row_data} ->
          Map.put(row_data, :index, index)
        end)
        {group_value, rows}
      end)
      |> Enum.into(%{})
    
    {:ok, grouped}
  end

  @doc """
  Calculates statistics for numeric columns in the table.

  ## Parameters
  - `table_data` - Table data as returned by to_table/2
  - `columns` - List of column numbers to analyze (optional, analyzes all numeric columns)

  ## Examples

      iex> table = %{1 => %{2 => "eth0", 3 => 100}, 2 => %{2 => "eth1", 3 => 200}}
      iex> SnmpMgr.Table.column_stats(table, [3])
      {:ok, %{3 => %{count: 2, sum: 300, avg: 150.0, min: 100, max: 200}}}
  """
  def column_stats(table_data, columns \\ nil) when is_map(table_data) do
    target_columns = columns || detect_numeric_columns(table_data)
    
    stats = 
      target_columns
      |> Enum.map(fn column ->
        values = 
          table_data
          |> Map.values()
          |> Enum.map(&Map.get(&1, column))
          |> Enum.filter(&is_number/1)
        
        column_stats = if Enum.empty?(values) do
          %{count: 0}
        else
          %{
            count: length(values),
            sum: Enum.sum(values),
            avg: Enum.sum(values) / length(values),
            min: Enum.min(values),
            max: Enum.max(values)
          }
        end
        
        {column, column_stats}
      end)
      |> Enum.into(%{})
    
    {:ok, stats}
  end

  @doc """
  Finds duplicate rows in the table based on specified columns.

  ## Parameters
  - `table_data` - Table data as returned by to_table/2
  - `columns` - List of column numbers to check for duplicates

  ## Examples

      iex> table = %{1 => %{2 => "eth", 3 => 1}, 2 => %{2 => "eth", 3 => 1}}
      iex> SnmpMgr.Table.find_duplicates(table, [2, 3])
      {:ok, [[{1, %{2 => "eth", 3 => 1}}, {2, %{2 => "eth", 3 => 1}}]]}
  """
  def find_duplicates(table_data, columns) when is_map(table_data) and is_list(columns) do
    duplicates = 
      table_data
      |> Enum.group_by(fn {_index, row_data} ->
        Enum.map(columns, &Map.get(row_data, &1))
      end)
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.map(fn {_key, group} -> group end)
    
    {:ok, duplicates}
  end

  @doc """
  Validates table data integrity and consistency.

  ## Parameters
  - `table_data` - Table data as returned by to_table/2
  - `opts` - Validation options

  ## Examples

      iex> table = %{1 => %{2 => "eth0", 3 => 100}}
      iex> SnmpMgr.Table.validate(table)
      {:ok, %{valid: true, issues: []}}
  """
  def validate(table_data, opts \\ []) when is_map(table_data) do
    issues = []
    
    # Check for empty table
    issues = if map_size(table_data) == 0 do
      [{:warning, :empty_table} | issues]
    else
      issues
    end
    
    # Check for inconsistent column sets
    all_column_sets = 
      table_data
      |> Map.values()
      |> Enum.map(&MapSet.new(Map.keys(&1)))
      |> Enum.uniq()
    
    issues = if length(all_column_sets) > 1 do
      [{:warning, :inconsistent_columns} | issues]
    else
      issues
    end
    
    # Check for missing data in critical columns
    issues = if Keyword.get(opts, :check_required_columns) do
      required_columns = Keyword.get(opts, :required_columns, [])
      missing_required = 
        table_data
        |> Enum.filter(fn {_index, row_data} ->
          not Enum.all?(required_columns, &Map.has_key?(row_data, &1))
        end)
      
      if not Enum.empty?(missing_required) do
        [{:error, {:missing_required_columns, length(missing_required)}} | issues]
      else
        issues
      end
    else
      issues
    end
    
    valid = not Enum.any?(issues, fn {level, _} -> level == :error end)
    
    {:ok, %{valid: valid, issues: Enum.reverse(issues)}}
  end

  # Private helper functions

  defp analyze_column_types(table_data, columns) do
    columns
    |> Enum.map(fn column ->
      sample_values = 
        table_data
        |> Map.values()
        |> Enum.map(&Map.get(&1, column))
        |> Enum.filter(&(&1 != nil))
        |> Enum.take(10)  # Sample first 10 non-nil values
      
      inferred_type = infer_column_type(sample_values)
      {column, inferred_type}
    end)
    |> Enum.into(%{})
  end

  defp infer_column_type([]), do: :unknown
  defp infer_column_type(values) do
    type_counts = 
      values
      |> Enum.map(&get_value_type/1)
      |> Enum.frequencies()
    
    # Return the most common type
    {type, _count} = Enum.max_by(type_counts, fn {_type, count} -> count end)
    type
  end

  defp get_value_type(value) when is_binary(value), do: :string
  defp get_value_type(value) when is_integer(value), do: :integer
  defp get_value_type(value) when is_float(value), do: :float
  defp get_value_type(value) when is_boolean(value), do: :boolean
  defp get_value_type(_), do: :other

  defp find_missing_data(table_data, indexes, columns) do
    indexes
    |> Enum.flat_map(fn index ->
      row_data = Map.get(table_data, index, %{})
      missing_columns = 
        columns
        |> Enum.filter(fn column -> not Map.has_key?(row_data, column) end)
      
      if Enum.empty?(missing_columns) do
        []
      else
        [{index, missing_columns}]
      end
    end)
  end

  defp detect_numeric_columns(table_data) do
    table_data
    |> Map.values()
    |> Enum.flat_map(&Map.to_list/1)
    |> Enum.group_by(fn {column, _value} -> column end)
    |> Enum.filter(fn {_column, values} ->
      sample_values = Enum.take(values, 5)
      numeric_count = Enum.count(sample_values, fn {_col, val} -> is_number(val) end)
      numeric_count > length(sample_values) / 2  # More than half are numeric
    end)
    |> Enum.map(fn {column, _values} -> column end)
  end
end