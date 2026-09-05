defmodule SnmpKit.SnmpMgr.Walk do
  @moduledoc """
  SNMP walk operations using iterative GETNEXT requests.

  This module provides efficient walking of SNMP trees and tables
  using the GETNEXT operation repeatedly until the end of the subtree.

  ## Return shape

  Like every other SnmpMgr operation since 1.0, walks return **enriched
  varbind maps**, one per object:

      %{
        oid: "1.3.6.1.2.1.1.1.0",          # dotted string
        oid_list: [1, 3, 6, 1, 2, 1, 1, 1, 0],
        type: :octet_string,
        value: "System description",
        name: "sysDescr.0",                # when include_names: true (default)
        formatted: "System description"    # when include_formatted: true (default)
      }

  `:name` and `:formatted` can be switched off per call with
  `include_names: false` / `include_formatted: false`, or globally through
  `SnmpKit.SnmpMgr.Config`. The pre-1.0 `{oid, type, value}` tuples are no
  longer returned by any path; pattern-match on the map keys instead.
  """

  @default_max_iterations 100
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

      {:ok, results} = SnmpKit.SnmpMgr.Walk.walk("192.168.1.1", [1, 3, 6, 1, 2, 1, 1])
      # [
      #   %{oid: "1.3.6.1.2.1.1.1.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 1, 0], name: "sysDescr.0",
      #     type: :octet_string, value: "System description", formatted: "System description"},
      #   %{oid: "1.3.6.1.2.1.1.2.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 2, 0], name: "sysObjectID.0",
      #     type: :object_identifier, value: [1, 3, 6, 1, 4, 1, 9, 1, 1], formatted: "1.3.6.1.4.1.9.1.1"},
      #   %{oid: "1.3.6.1.2.1.1.3.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 3, 0], name: "sysUpTime.0",
      #     type: :timeticks, value: 12345, formatted: "2 minutes 3 seconds"}
      # ]

      # Bare maps without names/formatting:
      {:ok, [%{oid: _, type: _, value: _} | _]} =
        SnmpKit.SnmpMgr.Walk.walk("192.168.1.1", "system", include_names: false, include_formatted: false)
  """
  @type target :: binary() | tuple() | map()
  @type oid :: binary() | [non_neg_integer()]
  @type varbind :: map()

  @spec walk(target(), oid(), keyword()) :: {:ok, [varbind()]} | {:error, term()}
  def walk(target, root_oid, opts \\ []) do
    version = Keyword.get(opts, :version, :v2c)

    case version do
      :v2c ->
        # Validate the OID first so a bad root fails fast rather than timing out
        with {:ok, _} <- resolve_oid(root_oid) do
          SnmpKit.SnmpMgr.Bulk.walk_bulk(target, root_oid, opts)
        end

      _ ->
        # Fall back to traditional GETNEXT walk (SNMPv1)
        # Use max_iterations instead of max_repetitions for v1 (which doesn't support bulk operations)
        max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
        _timeout = Keyword.get(opts, :timeout, @default_timeout)

        # Remove max_repetitions from opts for v1 operations since it's not supported
        v1_opts = Keyword.delete(opts, :max_repetitions)

        case resolve_oid(root_oid) do
          {:ok, start_oid} ->
            target
            |> walk_from_oid(start_oid, start_oid, [], max_iterations, v1_opts)
            |> enrich(opts)

          error ->
            error
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
  @spec walk_table(target(), oid(), keyword()) :: {:ok, [varbind()]} | {:error, term()}
  def walk_table(target, table_oid, opts \\ []) do
    version = Keyword.get(opts, :version, :v2c)

    case version do
      :v2c ->
        # Use bulk table walk for better performance
        SnmpKit.SnmpMgr.Bulk.get_table_bulk(target, table_oid, opts)

      _ ->
        # Fall back to traditional GETNEXT walk (SNMPv1)
        # Use max_iterations instead of max_repetitions for v1
        max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
        v1_opts = Keyword.delete(opts, :max_repetitions)

        case resolve_oid(table_oid) do
          {:ok, start_oid} ->
            target
            |> walk_from_oid(start_oid, start_oid, [], max_iterations, v1_opts)
            |> enrich(opts)

          error ->
            error
        end
    end
  end

  @doc """
  Walks a specific table column.

  Returns enriched varbind maps (see the module documentation).

  ## Parameters
  - `target` - The target device
  - `column_oid` - The full column OID (table + entry + column)
  - `opts` - Options
  """
  @spec walk_column(target(), oid(), keyword()) :: {:ok, [varbind()]} | {:error, term()}
  def walk_column(target, column_oid, opts \\ []) do
    case resolve_oid(column_oid) do
      {:ok, start_oid} ->
        max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
        v1_opts = Keyword.delete(opts, :max_repetitions)

        target
        |> walk_from_oid(start_oid, start_oid, [], max_iterations, v1_opts)
        |> enrich(opts)

      error ->
        error
    end
  end

  # Private functions

  # The GETNEXT (v1) path used to hand back raw {oid, type, value} tuples while
  # the GETBULK path returned enriched maps; both now return the same shape.
  defp enrich({:ok, results}, opts),
    do: {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, opts)}

  defp enrich(error, _opts), do: error

  defp walk_from_oid(target, current_oid, root_oid, acc, remaining, opts) when remaining > 0 do
    case SnmpKit.SnmpMgr.Core.send_get_next_request(target, current_oid, opts) do
      {:ok, {next_oid_string, type, value}} ->
        case SnmpKit.SnmpLib.OID.string_to_list(next_oid_string) do
          {:ok, next_oid} ->
            if still_in_scope?(next_oid, root_oid) do
              new_acc = [{next_oid_string, type, value} | acc]
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

      {:error, :end_of_mib_view} ->
        # Reached end of MIB (alternative format)
        {:ok, Enum.reverse(acc)}

      {:error, :no_such_name} ->
        # No more objects (alternative format)
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

  # OID resolution helper - delegates to canonical Core.parse_oid
  defp resolve_oid(oid), do: SnmpKit.SnmpMgr.Core.parse_oid(oid)

  # Type information must never be inferred - it must be preserved from SNMP responses
  # Removing type inference functions to prevent loss of critical type information
  # All operations must reject responses with type_information_lost to maintain data integrity
end
