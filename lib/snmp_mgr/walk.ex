defmodule SnmpMgr.Walk do
  @moduledoc """
  SNMP walk operations using iterative GETNEXT requests.
  
  This module provides efficient walking of SNMP trees and tables
  using the GETNEXT operation repeatedly until the end of the subtree.
  """

  @default_max_repetitions 100
  @default_timeout 5000

  @doc """
  Performs a walk starting from the given root OID.

  Automatically chooses between GETNEXT (SNMPv1) and GETBULK (SNMPv2c)
  based on the version specified in options.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :version, :max_repetitions, :timeout, :community

  ## Examples

      iex> SnmpMgr.Walk.walk("192.168.1.1", [1, 3, 6, 1, 2, 1, 1])
      {:ok, [
        {"1.3.6.1.2.1.1.1.0", "System description"},
        {"1.3.6.1.2.1.1.2.0", "1.3.6.1.4.1.9.1.1"},
        {"1.3.6.1.2.1.1.3.0", 12345}
      ]}
  """
  def walk(target, root_oid, opts \\ []) do
    version = Keyword.get(opts, :version, :v1)
    
    case version do
      :v2c -> 
        # Use bulk walk for better performance
        SnmpMgr.Bulk.walk_bulk(target, root_oid, opts)
      _ ->
        # Fall back to traditional GETNEXT walk
        max_repetitions = Keyword.get(opts, :max_repetitions, @default_max_repetitions)
        _timeout = Keyword.get(opts, :timeout, @default_timeout)
        
        case resolve_oid(root_oid) do
          {:ok, start_oid} ->
            walk_from_oid(target, start_oid, start_oid, [], max_repetitions, opts)
          error -> error
        end
    end
  end

  @doc """
  Walks an SNMP table starting from the table OID.

  Automatically chooses between GETNEXT and GETBULK based on version.
  GETBULK provides significantly better performance for large tables.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to walk
  - `opts` - Options including :version, :max_repetitions, :timeout, :community
  """
  def walk_table(target, table_oid, opts \\ []) do
    version = Keyword.get(opts, :version, :v1)
    
    case version do
      :v2c ->
        # Use bulk table walk for better performance
        SnmpMgr.Bulk.get_table_bulk(target, table_oid, opts)
      _ ->
        # Fall back to traditional GETNEXT walk
        case resolve_oid(table_oid) do
          {:ok, start_oid} ->
            walk_from_oid(target, start_oid, start_oid, [], @default_max_repetitions, opts)
          error -> error
        end
    end
  end

  @doc """
  Walks a specific table column.

  ## Parameters
  - `target` - The target device
  - `column_oid` - The full column OID (table + entry + column)
  - `opts` - Options
  """
  def walk_column(target, column_oid, opts \\ []) do
    case resolve_oid(column_oid) do
      {:ok, start_oid} ->
        walk_from_oid(target, start_oid, start_oid, [], @default_max_repetitions, opts)
      error -> error
    end
  end

  # Private functions

  defp walk_from_oid(target, current_oid, root_oid, acc, remaining, opts) when remaining > 0 do
    case SnmpMgr.Core.send_get_next_request(target, current_oid, opts) do
      {:ok, {next_oid_string, value}} ->
        case SnmpLib.OID.string_to_list(next_oid_string) do
          {:ok, next_oid} ->
            if still_in_scope?(next_oid, root_oid) do
              new_acc = [{next_oid_string, value} | acc]
              walk_from_oid(target, next_oid, root_oid, new_acc, remaining - 1, opts)
            else
              # Walked beyond the root scope
              {:ok, Enum.reverse(acc)}
            end
          {:error, _} ->
            {:ok, Enum.reverse(acc)}
        end
      
      {:error, {:snmp_error, :endOfMibView}} ->
        # Reached end of MIB
        {:ok, Enum.reverse(acc)}
      
      {:error, {:snmp_error, :noSuchName}} ->
        # No more objects
        {:ok, Enum.reverse(acc)}
      
      {:error, _} = error ->
        error
    end
  end

  defp walk_from_oid(_target, _current_oid, _root_oid, acc, 0, _opts) do
    # Hit max repetitions limit
    {:ok, Enum.reverse(acc)}
  end

  defp still_in_scope?(current_oid, root_oid) do
    # Check if current OID is still within the root OID scope
    List.starts_with?(current_oid, root_oid)
  end

  defp resolve_oid(oid) when is_binary(oid) do
    case SnmpLib.OID.string_to_list(oid) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, _} ->
        # Try as symbolic name
        case SnmpMgr.MIB.resolve(oid) do
          {:ok, resolved_oid} -> {:ok, resolved_oid}
          error -> error
        end
    end
  end
  defp resolve_oid(oid) when is_list(oid), do: {:ok, oid}
  defp resolve_oid(_), do: {:error, :invalid_oid_format}
end