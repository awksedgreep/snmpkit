defmodule SnmpKit.SnmpMgr.Bulk do
  @moduledoc """
  Advanced SNMP bulk operations using SNMPv2c GETBULK.

  This module provides efficient bulk operations that are significantly faster
  than iterative GETNEXT requests for retrieving large amounts of data.
  """

@default_max_repetitions 30
@default_non_repeaters 0

  @doc """
  Performs a single GETBULK request.

  Returns enriched varbind maps (same standardized shape as other SnmpMgr APIs).

  ## Parameters
  - `target` - The target device
  - `oids` - Single OID or list of OIDs to retrieve
  - `opts` - Options including :max_repetitions, :non_repeaters

  ## Examples

      iex> SnmpKit.SnmpMgr.Bulk.get_bulk("192.168.1.1", "ifTable", max_repetitions: 20)
      {:ok, [
        {[1,3,6,1,2,1,2,2,1,2,1], :octet_string, "eth0"},
        {[1,3,6,1,2,1,2,2,1,2,2], :octet_string, "eth1"},
        # ... up to 20 entries with type information
      ]}
  """
  def get_bulk(target, oids, opts \\ []) do
    # Check if user explicitly specified a version other than v2c
    case Keyword.get(opts, :version) do
      :v1 ->
        {:error, {:unsupported_operation, :get_bulk_requires_v2c}}

      :v3 ->
        {:error, {:unsupported_operation, :get_bulk_requires_v2c}}

      _ ->
        oids_list = if is_list(oids), do: oids, else: [oids]

        case resolve_oids(oids_list) do
          {:ok, resolved_oids} ->
            # For multiple OIDs, use non_repeaters to get single values for some
            non_repeaters = Keyword.get(opts, :non_repeaters, @default_non_repeaters)
            max_repetitions = Keyword.get(opts, :max_repetitions, @default_max_repetitions)

            bulk_opts =
              opts
              |> Keyword.put(:non_repeaters, non_repeaters)
              |> Keyword.put(:max_repetitions, max_repetitions)
              |> Keyword.put(:version, :v2c)

            # Use the first OID as the starting point for GETBULK
            starting_oid = hd(resolved_oids)

            case SnmpKit.SnmpMgr.Core.send_get_bulk_request(target, starting_oid, bulk_opts) do
              {:ok, results} ->
                merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)
                {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}

              {:error, reason} ->
                {:error, reason}
            end

          error ->
            error
        end
    end
  end

  @doc """
  Optimized table retrieval using GETBULK.

  Returns enriched varbind maps for each entry, e.g.:
  {:ok, [%{oid: "1.3.6.1...", oid_list: [...], type: :octet_string, value: "eth0", name: ..., formatted: ...}, ...]}

  Uses GETBULK to efficiently retrieve an entire SNMP table,
  automatically handling pagination when tables are larger than max_repetitions.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to retrieve
  - `opts` - Options including :max_repetitions, :max_entries

  ## Examples

      iex> SnmpKit.SnmpMgr.Bulk.get_table_bulk("switch.local", "ifTable")
      {:ok, [
        {"1.3.6.1.2.1.2.2.1.2.1", "eth0"},
        {"1.3.6.1.2.1.2.2.1.3.1", 6},
        {"1.3.6.1.2.1.2.2.1.2.2", "eth1"},
        {"1.3.6.1.2.1.2.2.1.3.2", 6}
      ]}
  """
  def get_table_bulk(target, table_oid, opts \\ []) do
    max_entries = Keyword.get(opts, :max_entries, 1000)

    case resolve_oid(table_oid) do
      {:ok, start_oid} ->
        case bulk_walk_table(target, start_oid, start_oid, [], max_entries, opts) do
          {:ok, results} ->
            merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)
            {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Bulk walk operation using GETBULK instead of iterative GETNEXT.

  Returns enriched varbind maps for each entry (same shape as other APIs).

  Significantly more efficient than traditional walks for large subtrees.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :max_repetitions, :max_entries

  ## Examples

      iex> SnmpKit.SnmpMgr.Bulk.walk_bulk("device.local", "system")
      {:ok, [
        {"1.3.6.1.2.1.1.1.0", "System Description"},
        {"1.3.6.1.2.1.1.2.0", "1.3.6.1.4.1.9"},
        {"1.3.6.1.2.1.1.3.0", 12345}
      ]}
  """
  def walk_bulk(target, root_oid, opts \\ []) do
    max_entries = Keyword.get(opts, :max_entries, 1000)

    case resolve_oid(root_oid) do
      {:ok, start_oid} ->
        case bulk_walk_subtree(target, start_oid, start_oid, [], max_entries, opts) do
          {:ok, results} ->
            merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)
            {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}

          error ->
            error
        end

      error ->
      error
    end
  end

  @doc """
  Performs multiple concurrent GETBULK operations.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} tuples
  - `opts` - Options for all requests

  ## Examples

      iex> requests = [
      ...>   {"device1", "sysDescr.0"},
      ...>   {"device2", "sysUpTime.0"},
      ...>   {"device3", "ifNumber.0"}
      ...> ]
      iex> SnmpKit.SnmpMgr.Bulk.get_bulk_multi(requests)
      [
        {:ok, [{"1.3.6.1.2.1.1.1.0", "Device 1"}]},
        {:ok, [{"1.3.6.1.2.1.1.3.0", 123456}]},
        {:error, :timeout}
      ]
  """
  def get_bulk_multi(targets_and_oids, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    tasks =
      targets_and_oids
      |> Enum.map(fn {target, oid} ->
        Task.async(fn ->
          get_bulk(target, oid, opts)
        end)
      end)

    tasks
    |> Task.yield_many(timeout)
    |> Enum.map(fn {_task, result} ->
      case result do
        {:ok, value} -> value
        nil -> {:error, :timeout}
        {:exit, reason} -> {:error, {:task_failed, reason}}
      end
    end)
  end

  # Private functions

  defp bulk_walk_table(target, current_oid, root_oid, acc, remaining, opts) when remaining > 0 do
    max_repetitions =
      min(remaining, Keyword.get(opts, :max_repetitions, @default_max_repetitions))

    bulk_opts =
      opts
      |> Keyword.put(:max_repetitions, max_repetitions)
      |> Keyword.put(:version, :v2c)

    case SnmpKit.SnmpMgr.Core.send_get_bulk_request(target, current_oid, bulk_opts) do
      {:ok, results} ->
        # Filter results that are still within the table scope
        {in_scope, next_oid} = filter_table_results(results, root_oid)

        if Enum.empty?(in_scope) or next_oid == nil do
          {:ok, Enum.reverse(acc)}
        else
          new_acc = Enum.reverse(in_scope) ++ acc
          bulk_walk_table(target, next_oid, root_oid, new_acc, remaining - length(in_scope), opts)
        end

      {:error, _} = error ->
        error
    end
  end

  defp bulk_walk_table(_target, _current_oid, _root_oid, acc, 0, _opts) do
    {:ok, Enum.reverse(acc)}
  end

  defp bulk_walk_subtree(target, current_oid, root_oid, acc, remaining, opts)
       when remaining > 0 do
    max_repetitions =
      min(remaining, Keyword.get(opts, :max_repetitions, @default_max_repetitions))

    bulk_opts =
      opts
      |> Keyword.put(:max_repetitions, max_repetitions)
      |> Keyword.put(:version, :v2c)

    # Debug logging for walk_multi issue investigation
    require Logger

    Logger.debug(
      "bulk_walk_subtree: current_oid=#{inspect(current_oid)}, remaining=#{remaining}, max_rep=#{max_repetitions}"
    )

    case SnmpKit.SnmpMgr.Core.send_get_bulk_request(target, current_oid, bulk_opts) do
      {:ok, results} ->
        Logger.debug("bulk_walk_subtree: got #{length(results)} raw results")

        # Filter results that are still within the subtree scope
        {in_scope, next_oid} = filter_subtree_results(results, root_oid)

        Logger.debug(
          "bulk_walk_subtree: #{length(in_scope)} in_scope, next_oid=#{inspect(next_oid)}"
        )

        Logger.debug(
          "bulk_walk_subtree: in_scope OIDs: #{inspect(Enum.map(in_scope, fn {oid, _, _} -> oid end))}"
        )

        if Enum.empty?(in_scope) or next_oid == nil do
          Logger.debug(
            "bulk_walk_subtree: stopping - empty_in_scope=#{Enum.empty?(in_scope)}, next_oid_nil=#{next_oid == nil}"
          )

          {:ok, Enum.reverse(acc)}
        else
          new_acc = Enum.reverse(in_scope) ++ acc

          Logger.debug(
            "bulk_walk_subtree: continuing with #{length(new_acc)} total results so far"
          )

          bulk_walk_subtree(
            target,
            next_oid,
            root_oid,
            new_acc,
            remaining - length(in_scope),
            opts
          )
        end

      {:error, _} = error ->
        Logger.debug("bulk_walk_subtree: error - #{inspect(error)}")
        error
    end
  end

  defp bulk_walk_subtree(_target, _current_oid, _root_oid, acc, 0, _opts) do
    {:ok, Enum.reverse(acc)}
  end

  defp filter_table_results(results, root_oid) do
    require Logger

    in_scope_results =
      results
      |> Enum.filter(fn
        # Only accept 3-tuple format with proper type information
        {oid_list, _type, _value} ->
          starts_with = List.starts_with?(oid_list, root_oid)

          Logger.debug(
            "filter: checking #{inspect(oid_list)} starts_with #{inspect(root_oid)} = #{starts_with}"
          )

          starts_with

        # Reject 2-tuple format - type information must be preserved
        {_oid_list, _value} ->
          Logger.debug("filter: rejecting 2-tuple format")
          false
      end)

    # Keep OIDs as lists internally - conversion to strings happens at final output

    # Fix: next_oid should be derived from last in_scope result, not last overall result
    # and we need to increment it properly for the next GETBULK request
    next_oid =
      case List.last(in_scope_results) do
        {oid_list, _type, _value} ->
          # For bulk operations, the next OID should be the last successful OID
          # The SNMP agent will return the next available OIDs from this point
          Logger.debug("filter: next_oid from last in_scope: #{inspect(oid_list)}")
          oid_list

        _ ->
          # If no in_scope results, try to get next_oid from last overall result
          case List.last(results) do
            {oid_list, _type, _value} ->
              Logger.debug("filter: next_oid from last overall: #{inspect(oid_list)}")
              oid_list

            {_oid_list, _value} ->
              nil

            _ ->
              nil
          end
      end

    Logger.debug(
      "filter: returning #{length(in_scope_results)} in_scope, next_oid=#{inspect(next_oid)}"
    )

    {in_scope_results, next_oid}
  end

  defp filter_subtree_results(results, root_oid) do
    filter_table_results(results, root_oid)
  end

  defp resolve_oids(oids) do
    resolved =
      oids
      |> Enum.map(&SnmpKit.SnmpMgr.Core.parse_oid/1)
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, oid}, {:ok, acc} -> {:cont, {:ok, [oid | acc]}}
        error, _acc -> {:halt, error}
      end)

    case resolved do
      {:ok, oid_list} -> {:ok, Enum.reverse(oid_list)}
      error -> error
    end
  end

  defp resolve_oid(oid), do: SnmpKit.SnmpMgr.Core.parse_oid(oid)

  # Type information must never be inferred - it must be preserved from SNMP responses
  # Removing type inference functions to prevent loss of critical type information
end
