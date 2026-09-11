defmodule SnmpKit.SnmpMgr.Bulk do
  @moduledoc """
  Advanced SNMP bulk operations using SNMPv2c GETBULK.

  This module provides efficient bulk operations that are significantly faster
  than iterative GETNEXT requests for retrieving large amounts of data.

  Every function returns enriched varbind maps, see
  `t:SnmpKit.SnmpMgr.Format.enriched_varbind/0`.
  """

  alias SnmpKit.SnmpLib.Types

  alias SnmpKit.SnmpLib.Types

  @default_max_repetitions 30
  @default_non_repeaters 0

  @type target :: SnmpKit.SnmpMgr.Core.target()
  @type oid :: SnmpKit.SnmpMgr.Core.oid()
  @type varbind :: SnmpKit.SnmpMgr.Format.enriched_varbind()

  @doc """
  Performs a single GETBULK request.

  Returns enriched varbind maps (same standardized shape as other SnmpMgr APIs).

  ## Parameters
  - `target` - The target device
  - `oids` - Single OID or list of OIDs to retrieve
  - `opts` - Options including :max_repetitions, :non_repeaters

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpKit.SnmpMgr.Bulk.get_bulk("192.168.1.1", "ifTable", max_repetitions: 20)
      # [
      #   %{oid: "1.3.6.1.2.1.2.2.1.1.1", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1], name: "ifIndex.1",
      #     type: :integer, value: 1, formatted: "1"},
      #   %{oid: "1.3.6.1.2.1.2.2.1.1.2", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 2], name: "ifIndex.2",
      #     type: :integer, value: 2, formatted: "2"},
      #   # ... up to 20 entries
      # ]

  Pass `include_names: false, include_formatted: false` for bare
  `%{oid, oid_list, type, value}` maps.
  """
  @spec get_bulk(target(), oid() | [oid()], keyword()) :: {:ok, [varbind()]} | {:error, term()}
  def get_bulk(target, oids, opts \\ []) do
    # GETBULK exists from SNMPv2 on; v2c and v3 both carry it
    case Keyword.get(opts, :version) do
      :v1 ->
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

  Uses GETBULK to efficiently retrieve an entire SNMP table,
  automatically handling pagination when tables are larger than max_repetitions.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to retrieve
  - `opts` - Options including :max_repetitions, :max_entries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpKit.SnmpMgr.Bulk.get_table_bulk("switch.local", "ifTable")
      # [
      #   %{oid: "1.3.6.1.2.1.2.2.1.2.1", oid_list: [...], name: "ifDescr.1",
      #     type: :octet_string, value: "eth0", formatted: "eth0"},
      #   %{oid: "1.3.6.1.2.1.2.2.1.3.1", oid_list: [...], name: "ifType.1",
      #     type: :integer, value: 6, formatted: "ethernetCsmacd"},
      #   # ...
      # ]
  """
  @spec get_table_bulk(target(), oid(), keyword()) :: {:ok, [varbind()]} | {:error, term()}
  def get_table_bulk(target, table_oid, opts \\ []) do
    max_entries = Keyword.get(opts, :max_entries, 1000)
    opts = Keyword.put(opts, :version, :v2c)

    case resolve_oid(table_oid) do
      {:ok, start_oid} ->
        with_private_socket(target, fn socket ->
          case bulk_walk_loop(socket, target, start_oid, start_oid, [], max_entries, opts) do
            {:ok, results} ->
              merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)
              {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}

            error ->
              error
          end
        end)

      error ->
        error
    end
  end

  @doc """
  Bulk walk operation using GETBULK instead of iterative GETNEXT.

  Significantly more efficient than traditional walks for large subtrees.
  The walk stops at the first `endOfMibView`/`noSuchObject`/`noSuchInstance`
  marker or OID outside `root_oid`, or when the agent stops making progress;
  the markers themselves are never part of the result.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :max_repetitions, :max_entries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpKit.SnmpMgr.Bulk.walk_bulk("device.local", "system")
      # [
      #   %{oid: "1.3.6.1.2.1.1.1.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 1, 0], name: "sysDescr.0",
      #     type: :octet_string, value: "System Description", formatted: "System Description"},
      #   %{oid: "1.3.6.1.2.1.1.3.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 3, 0], name: "sysUpTime.0",
      #     type: :timeticks, value: 12345, formatted: "2 minutes 3 seconds"},
      #   # ...
      # ]
  """
  @spec walk_bulk(target(), oid(), keyword()) :: {:ok, [varbind()]} | {:error, term()}
  def walk_bulk(target, root_oid, opts \\ []) do
    max_entries = Keyword.get(opts, :max_entries, 1000)
    opts = Keyword.put(opts, :version, :v2c)

    case resolve_oid(root_oid) do
      {:ok, start_oid} ->
        with_private_socket(target, fn socket ->
          case bulk_walk_loop(socket, target, start_oid, start_oid, [], max_entries, opts) do
            {:ok, results} ->
              merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)
              {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}

            error ->
              error
          end
        end)

      error ->
        error
    end
  end

  # Private functions

  defp with_private_socket(target, fun) do
    family = SnmpKit.SnmpLib.Transport.target_family(target)

    case SnmpKit.SnmpLib.Transport.create_client_socket(family: family) do
      {:ok, socket} ->
        try do
          fun.(socket)
        after
          :ok = SnmpKit.SnmpLib.Transport.close_socket(socket)
        end

      {:error, reason} ->
        {:error, {:socket_error, reason}}
    end
  end

  defp bulk_walk_loop(socket, target, current_oid, root_oid, acc, remaining, opts)
       when remaining > 0 do
    max_repetitions =
      min(remaining, Keyword.get(opts, :max_repetitions, @default_max_repetitions))

    bulk_opts =
      opts
      |> Keyword.put(:max_repetitions, max_repetitions)
      |> Keyword.put(:keep_exceptions, true)

    case SnmpKit.SnmpLib.Manager.get_bulk_with_socket(socket, target, current_oid, bulk_opts) do
      {:ok, results} ->
        {in_scope, done?} = Types.take_in_scope(results, root_oid)

        case List.last(in_scope) do
          # Nothing left in scope: the walk is over
          nil ->
            {:ok, Enum.reverse(acc)}

          # The agent answered with the OID we asked from: no progress, and
          # the page is a repeat of what we already hold
          {^current_oid, _, _} ->
            {:ok, Enum.reverse(acc)}

          {next_oid, _, _} ->
            acc = Enum.reverse(in_scope) ++ acc

            # An end marker or an OID outside the root was seen: done
            if done? do
              {:ok, Enum.reverse(acc)}
            else
              bulk_walk_loop(
                socket,
                target,
                next_oid,
                root_oid,
                acc,
                remaining - length(in_scope),
                opts
              )
            end
        end

      {:error, _} = error ->
        error
    end
  end

  defp bulk_walk_loop(_socket, _target, _current_oid, _root_oid, acc, _remaining, _opts) do
    {:ok, Enum.reverse(acc)}
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
