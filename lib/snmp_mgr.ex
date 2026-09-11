defmodule SnmpKit.SnmpMgr do
  @moduledoc """
  Lightweight SNMP client library for Elixir.

  This library provides a simple, stateless interface for SNMP operations
  without requiring heavyweight management processes or configurations.
  """

  @concurrent_services [
    SnmpKit.SnmpMgr.RequestIdGenerator,
    SnmpKit.SnmpMgr.Engine
  ]

  @doc """
  Ensures internal manager services are started.

  Starts RequestIdGenerator and Engine if they are not running.
  Safe to call multiple times and from concurrent callers: the services are
  started under `SnmpKit.SnmpMgr.ServiceSupervisor` (part of the application
  tree), so a start race resolves to `{:error, {:already_started, _}}` inside
  the supervisor and the winner is used, and a caller exiting does not take
  the services down with it.

  This call ignores the `auto_start_services` configuration; it is the explicit
  way to start the services when auto-start is disabled.
  """
  @spec ensure_started() :: :ok | {:error, term()}
  def ensure_started() do
    Enum.reduce_while(@concurrent_services, :ok, fn module, :ok ->
      case start_service(module) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {module, reason}}}
      end
    end)
  end

  @doc """
  Returns `true` when all concurrent manager services are running.
  """
  @spec services_running?() :: boolean()
  def services_running? do
    Enum.all?(@concurrent_services, &is_pid(Process.whereis(&1)))
  end

  defp start_service(module) do
    if Process.whereis(module) do
      :ok
    else
      spec = %{
        id: module,
        start: {module, :start_link, [[name: module]]},
        # :transient so an explicit GenServer.stop/1 is honoured (the service
        # stays down) while a crash is restarted.
        restart: :transient
      }

      case Process.whereis(SnmpKit.SnmpMgr.ServiceSupervisor) do
        nil ->
          # Application tree not running (e.g. library used without its
          # application); fall back to an unsupervised start.
          case GenServer.start(module, [name: module], name: module) do
            {:ok, _} -> :ok
            {:error, {:already_started, _}} -> :ok
            {:error, reason} -> {:error, reason}
          end

        supervisor ->
          case DynamicSupervisor.start_child(supervisor, spec) do
            {:ok, _} -> :ok
            {:error, {:already_started, _}} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  @type target :: binary() | tuple() | map()
  @type oid :: binary() | list()
  @type opts :: keyword()
  @type varbind :: SnmpKit.SnmpMgr.Format.enriched_varbind()

  @doc """
  Performs an SNMP GET request.

  ## Parameters
  - `target` - The target device (e.g., "192.168.1.1:161" or "device.local")
  - `oid` - The OID to retrieve (name "sysDescr.0", string "1.3.6.1.2.1.1.1.0"
    or list [1,3,6,1,2,1,1,1,0]), or a list of several of them for one PDU
  - `opts` - Options including :community, :timeout, :retries

  Returns an enriched varbind map; with a list of OIDs, a list of them.
  An OID that does not parse or resolve is `{:error, {:invalid_oid, input, reason}}`.

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, %{value: descr, type: :octet_string}} =
        SnmpMgr.get("device.local:161", "sysDescr.0", community: "public")
      # %{name: "sysDescr.0", oid: "1.3.6.1.2.1.1.1.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 1, 0],
      #   type: :octet_string, value: "Linux server 5.4.0-42-generic", formatted: "Linux server ..."}

      {:ok, %{type: :timeticks, value: 123_456_789, formatted: uptime}} =
        SnmpMgr.get("router.local", "sysUpTime.0")

      {:ok, [%{name: "sysDescr.0"}, %{name: "sysName.0"}]} =
        SnmpMgr.get("router.local", ["sysDescr.0", "sysName.0"])
  """
  def get(target, oid, opts \\ [])

  def get(_target, [], _opts), do: {:error, :empty_oids}

  # Several OIDs (names, strings or lists) in one PDU: {:ok, [enriched, ...]}
  def get(target, [first | _] = oids, opts) when not is_integer(first) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    case SnmpKit.SnmpMgr.Core.send_get_varbinds(target, oids, merged_opts) do
      {:ok, varbinds} -> {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(varbinds, merged_opts)}
      {:error, reason} -> {:error, reason}
    end
  end

  def get(target, oid, opts) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    # Ensure we always return type and apply enrichment
    case SnmpKit.SnmpMgr.Core.send_get_request_with_type(target, oid, merged_opts) do
      {:ok, {oid_str, type, value}} ->
        {:ok, SnmpKit.SnmpMgr.Format.enrich_varbind({oid_str, type, value}, merged_opts)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Performs an SNMP GETNEXT request.

  ## Parameters
  - `target` - The target device
  - `oid` - The starting OID (string "1.3.6.1.2.1.1.1.0" or list [1,3,6,1,2,1,1,1,0] format)
  - `opts` - Options including :community, :timeout, :retries

  Returns the enriched varbind map of the next object.

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, %{oid: "1.3.6.1.2.1.1.1.0", value: value}} =
        SnmpMgr.get_next("switch.local", "1.3.6.1.2.1.1")
      # value: "Cisco IOS Software, C2960 Software"

      {:ok, %{name: "sysDescr.0", type: :octet_string}} = SnmpMgr.get_next("device.local", "sysDescr")
  """
  def get_next(target, oid, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    case SnmpKit.SnmpMgr.Core.send_get_next_request(target, oid, merged_opts) do
      {:ok, {oid_string, type, value}} ->
        {:ok, SnmpKit.SnmpMgr.Format.enrich_varbind({oid_string, type, value}, merged_opts)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Performs an SNMP SET request.

  ## Parameters
  - `target` - The target device
  - `oid` - The OID to set (string "1.3.6.1.2.1.1.1.0" or list [1,3,6,1,2,1,1,1,0] format)
  - `value` - The value to set
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      :ok = SnmpMgr.set("device.local", "sysLocation.0", "Server Room A")
      # :ok

      :ok = SnmpMgr.set("switch.local", "sysContact.0", "admin@company.com",
        community: "private", timeout: 3000)
      # :ok
  """
  def set(target, oid, value, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    case SnmpKit.SnmpMgr.Core.send_set_request(target, oid, value, merged_opts) do
      {:ok, :success} -> :ok
      {:ok, other} -> {:ok, other}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets several objects in one SET PDU. `pairs` are `{oid, value}` tuples with
  the value forms `set/4` accepts. Agents apply the SET atomically, so the
  whole call succeeds or fails together.

      :ok = SnmpMgr.set_many("device", [{"sysContact.0", "ops"}, {"sysLocation.0", "rack 4"}])
  """
  def set_many(target, pairs, opts \\ []) when is_list(pairs) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    case SnmpKit.SnmpMgr.Core.send_set_varbinds(target, pairs, merged_opts) do
      {:ok, :success} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs an asynchronous SNMP GET request.

  Returns a `Task` whose result is the same `{:ok, varbind}` or `{:error, reason}`
  tuple `get/3` returns.

  ## Parameters
  - `target` - The target device
  - `oid` - The OID to retrieve (string "1.3.6.1.2.1.1.1.0" or list [1,3,6,1,2,1,1,1,0] format)
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      task = SnmpMgr.get_async("device.local", "sysDescr.0")
      {:ok, %{value: description}} = Task.await(task, 5000)
  """
  def get_async(target, oid, opts \\ []) do
    Task.async(fn -> get(target, oid, opts) end)
  end

  @doc """
  Performs an SNMP GETBULK request (SNMPv2c or SNMPv3; there is no GETBULK in v1).

  GETBULK is more efficient than multiple GETNEXT requests for retrieving
  large amounts of data. It can retrieve multiple variables in a single request.

  ## Parameters
  - `target` - The target device
  - `oid` - The starting OID (string "1.3.6.1.2.1.1.1.0" or list [1,3,6,1,2,1,1,1,0] format)
  - `opts` - Options including :non_repeaters, :max_repetitions, :community, :timeout

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpMgr.get_bulk("switch.local", "ifTable", max_repetitions: 10)
      # [
      #   %{name: "ifIndex.1", oid: "1.3.6.1.2.1.2.2.1.1.1", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1],
      #     type: :integer, value: 1, formatted: "1"},
      #   %{name: "ifIndex.2", oid: "1.3.6.1.2.1.2.2.1.1.2", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 2],
      #     type: :integer, value: 2, formatted: "2"},
      #   # ... up to max_repetitions entries, one enriched map each
      # ]

  Pass `include_names: false, include_formatted: false` for bare
  `%{oid, oid_list, type, value}` maps. `version: :v1` returns
  `{:error, {:unsupported_operation, :get_bulk_requires_v2c}}`; `:v3` is honoured.
  """
  @spec get_bulk(target(), oid(), opts()) :: {:ok, [varbind()]} | {:error, any()}
  def get_bulk(target, oid, opts \\ []) do
    # GETBULK is an SNMPv2 PDU: v2c or v3, never v1 (one rule, shared with Bulk)
    with {:ok, merged_opts} <- SnmpKit.SnmpMgr.Bulk.bulk_opts(opts) do
      case SnmpKit.SnmpMgr.Core.send_get_bulk_request(target, oid, merged_opts) do
        {:ok, results} -> {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Performs an asynchronous SNMP GETBULK request.

  Returns a `Task`; await it with `Task.await/2` for the same result
  `get_bulk/3` returns. `{:error, {:unsupported_operation, _}}` is returned
  directly when `version: :v1` is requested; `:v3` is honoured.

      task = SnmpMgr.get_bulk_async("device.local", "ifTable")
      {:ok, rows} = Task.await(task, 5000)
  """
  def get_bulk_async(target, oid, opts \\ []) do
    case Keyword.get(opts, :version) do
      :v1 -> {:error, {:unsupported_operation, :get_bulk_requires_v2c}}
      _ -> Task.async(fn -> get_bulk(target, oid, opts) end)
    end
  end

  @doc """
  Performs an SNMP walk operation using iterative GETNEXT requests.

  Walks the SNMP tree starting from the given OID and returns all OID/value
  pairs found under that subtree.

  ## Parameters
  - `target` - The target device
  - `root_oid` - The starting OID for the walk
  - `opts` - Options including :community, :timeout, :max_repetitions

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpMgr.walk("device.local", "1.3.6.1.2.1.1")
      # [
      #   %{name: "sysDescr.0", oid: "1.3.6.1.2.1.1.1.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 1, 0],
      #     type: :octet_string, value: "Linux hostname 5.4.0-42-generic", formatted: "Linux hostname 5.4.0-42-generic"},
      #   %{name: "sysObjectID.0", oid: "1.3.6.1.2.1.1.2.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 2, 0],
      #     type: :object_identifier, value: [1, 3, 6, 1, 4, 1, 8072, 3, 2, 10], formatted: "1.3.6.1.4.1.8072.3.2.10"},
      #   %{name: "sysUpTime.0", oid: "1.3.6.1.2.1.1.3.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 3, 0],
      #     type: :timeticks, value: 12345678, formatted: "1 day 10 hours 17 minutes 36 seconds"},
      #   ...
      # ]

  Pass `include_names: false, include_formatted: false` for bare
  `%{oid, oid_list, type, value}` maps.
  """
  @spec walk(target(), oid(), opts()) :: {:ok, [map()]} | {:error, any()}
  def walk(target, root_oid, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    SnmpKit.Telemetry.span(
      :walk,
      %{operation: :walk, target: target, root_oid: root_oid},
      fn ->
        case SnmpKit.SnmpMgr.Walk.walk(target, root_oid, merged_opts) do
          {:ok, results} -> {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}
          {:error, reason} -> {:error, reason}
        end
      end,
      &walk_span_extra/1
    )
  end

  @doc """
  Walks an SNMP table and returns all entries.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to walk
  - `opts` - Options including :community, :timeout

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, entries} = SnmpMgr.walk_table("switch.local", "ifTable")
      # [
      #   %{name: "ifIndex.1", oid: "1.3.6.1.2.1.2.2.1.1.1", type: :integer, value: 1, ...},
      #   %{name: "ifDescr.1", oid: "1.3.6.1.2.1.2.2.1.2.1", type: :octet_string, value: "GigabitEthernet0/1", ...},
      #   %{name: "ifType.1", oid: "1.3.6.1.2.1.2.2.1.3.1", type: :integer, value: 6, formatted: "ethernetCsmacd", ...},
      #   %{name: "ifSpeed.1", oid: "1.3.6.1.2.1.2.2.1.5.1", type: :gauge32, value: 1000000000, formatted: "1.0 Gbps", ...},
      #   # ... all interface table entries, one enriched map each
      # ]
  """
  @spec walk_table(target(), oid(), opts()) :: {:ok, [map()]} | {:error, any()}
  def walk_table(target, table_oid, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    SnmpKit.Telemetry.span(
      :walk,
      %{operation: :walk_table, target: target, root_oid: table_oid},
      fn ->
        case SnmpKit.SnmpMgr.Walk.walk_table(target, table_oid, merged_opts) do
          {:ok, results} -> {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}
          {:error, reason} -> {:error, reason}
        end
      end,
      &walk_span_extra/1
    )
  end

  @doc """
  Gets all entries from an SNMP table and formats them as a structured table.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID
  - `opts` - Options including :community, :timeout

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, table} = SnmpMgr.get_table("switch.local", "ifTable")
      # %{1 => %{1 => 1, 2 => "GigabitEthernet0/1", 3 => 6, ...},
      #   2 => %{1 => 2, 2 => "GigabitEthernet0/2", 3 => 6, ...}}

      {:ok, table} = SnmpMgr.get_table("switch.local", "ifTable", named: true)
      # %{1 => %{"ifIndex" => 1, "ifDescr" => "GigabitEthernet0/1", "ifType" => 6, ...}, ...}

  With `named: true` column names come from the MIB registry and the row's
  INDEX objects are decoded into it (composite indexes included); see
  `SnmpKit.SnmpMgr.Table.to_named_table/2`.
  """
  def get_table(target, table_oid, opts \\ []) do
    {named, opts} = Keyword.pop(opts, :named, false)

    case resolve_oid_if_needed(table_oid) do
      {:ok, resolved_oid} ->
        case walk_table(target, resolved_oid, opts) do
          {:ok, entries} when named -> SnmpKit.SnmpMgr.Table.to_named_table(entries, resolved_oid)
          {:ok, entries} -> SnmpKit.SnmpMgr.Table.to_table(entries, resolved_oid)
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Gets a specific column from an SNMP table.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID
  - `column` - The column number (relative to the table's entry) or a
    registered column name such as `"ifDescr"`
  - `opts` - Options including :community, :timeout

  Returns the column's enriched varbind maps, as `walk/3` does.
  """
  def get_column(target, table_oid, column, opts \\ []) do
    case resolve_oid_if_needed(table_oid) do
      {:ok, resolved_table_oid} ->
        column_oid =
          if is_integer(column) do
            resolved_table_oid ++ [1, column]
          else
            case SnmpKit.SnmpMgr.MIB.resolve(column) do
              {:ok, oid} -> oid
              error -> error
            end
          end

        walk(target, column_oid, opts)

      error ->
        error
    end
  end

  @doc """
  Performs concurrent GET operations against multiple targets.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} tuples
  - `opts` - Options applied to all requests

  Returns one result per request, in order: `{:ok, varbind}` or
  `{:error, reason}` (see `SnmpKit.SnmpMgr.Multi` for `:return_format`).

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      SnmpMgr.get_multi([{"device1", [1,3,6,1,2,1,1,1,0]}, {"device2", [1,3,6,1,2,1,1,3,0]}])
      # [{:ok, %{name: "sysDescr.0", ...}}, {:error, :hostname_resolution_failed}]
  """
  def get_multi(targets_and_oids, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)
    SnmpKit.SnmpMgr.Multi.get_multi(targets_and_oids, merged_opts)
  end

  @doc """
  Performs concurrent GETBULK operations against multiple targets.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} tuples
  - `opts` - Options applied to all requests including :max_repetitions
  """
  def get_bulk_multi(targets_and_oids, opts \\ []) do
    merged_opts =
      opts
      |> Keyword.put_new(:version, :v2c)
      |> (&SnmpKit.SnmpMgr.Config.merge_opts/1).()

    SnmpKit.SnmpMgr.Multi.get_bulk_multi(targets_and_oids, merged_opts)
  end

  @doc """
  Performs concurrent walk operations against multiple targets.

  ## Parameters
  - `targets_and_oids` - List of {target, root_oid} tuples
  - `opts` - Options applied to all requests
  """
  def walk_multi(targets_and_oids, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)
    SnmpKit.SnmpMgr.Multi.walk_multi(targets_and_oids, merged_opts)
  end

  @doc """
  Performs concurrent table walk operations against multiple targets.

  ## Parameters
  - `targets_and_tables` - List of {target, table_oid} tuples
  - `opts` - Options applied to all requests
  """
  def walk_table_multi(targets_and_tables, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)
    SnmpKit.SnmpMgr.Multi.walk_table_multi(targets_and_tables, merged_opts)
  end

  @doc """
  Performs an adaptive bulk walk that automatically optimizes parameters.

  Uses intelligent parameter tuning based on device response characteristics
  for optimal performance.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :adaptive_tuning, :max_entries (default 1000)

  Uses GETBULK, so `version: :v1` is
  `{:error, {:unsupported_operation, :get_bulk_requires_v2c}}`; `:v3` is honoured.

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpMgr.adaptive_walk("switch.local", "ifTable")
      # Enriched varbind maps, the same shape as walk/3:
      # [
      #   %{name: "ifIndex.1", oid: "1.3.6.1.2.1.2.2.1.1.1", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1],
      #     type: :integer, value: 1, formatted: "1"},
      #   %{name: "ifDescr.1", oid: "1.3.6.1.2.1.2.2.1.2.1", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1],
      #     type: :octet_string, value: "eth0", formatted: "eth0"},
      #   ...
      # ]
  """
  def adaptive_walk(target, root_oid, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    SnmpKit.Telemetry.span(
      :walk,
      %{operation: :adaptive_walk, target: target, root_oid: root_oid},
      fn ->
        case SnmpKit.SnmpMgr.AdaptiveWalk.bulk_walk(target, root_oid, merged_opts) do
          {:ok, results} -> {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}
          {:error, reason} -> {:error, reason}
        end
      end,
      &walk_span_extra/1
    )
  end

  @doc """
  Creates a stream for memory-efficient processing of large SNMP data.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :chunk_size (default 50), :adaptive, :version

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      stream = SnmpMgr.walk_stream("192.0.2.1", "ifTable")
      # Process stream lazily...
  """
  def walk_stream(target, root_oid, opts \\ []) do
    SnmpKit.SnmpMgr.Stream.walk_stream(target, root_oid, opts)
  end

  @doc """
  Creates a stream for processing large SNMP tables.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to stream
  - `opts` - Options including :chunk_size (default 50), :columns

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      stream = SnmpMgr.table_stream("192.0.2.1", "ifTable")
      # Process table stream...
  """
  def table_stream(target, table_oid, opts \\ []) do
    SnmpKit.SnmpMgr.Stream.table_stream(target, table_oid, opts)
  end

  @doc """
  Analyzes table structure and returns detailed metadata.

  ## Parameters
  - `table_data` - Table data as returned by get_table/3
  - `opts` - Analysis options

  ## Examples

      {:ok, table} = SnmpMgr.get_table("192.0.2.1", "ifTable")
      {:ok, analysis} = SnmpMgr.analyze_table(table)
      IO.inspect(analysis.completeness)  # Shows data completeness ratio
  """
  def analyze_table(table_data, opts \\ []) do
    SnmpKit.SnmpMgr.Table.analyze(table_data, opts)
  end

  @doc """
  Benchmarks a device to determine optimal bulk parameters.

  ## Parameters
  - `target` - The target device to benchmark
  - `test_oid` - OID to use for testing
  - `opts` - Benchmark options

  ## Examples

      {:ok, results} = SnmpMgr.benchmark_device("192.0.2.1", "ifTable")
      optimal_size = results.optimal_bulk_size
  """
  def benchmark_device(target, test_oid, opts \\ []) do
    SnmpKit.SnmpMgr.AdaptiveWalk.benchmark_device(target, test_oid, opts)
  end

  @doc """
  Performs an SNMP GET operation with formatting forced on.

  Same as `get/3` except that `include_formatted` cannot be turned off, so
  the enriched map always carries a human-readable `:formatted` value.

  ## Examples

      # Get system uptime with automatic formatting
      {:ok, %{formatted: uptime}} = SnmpMgr.get_pretty("192.168.1.1", "1.3.6.1.2.1.1.3.0")
      # uptime: "14 days 15 hours 55 minutes 13 seconds"
      # The full map: %{oid: "1.3.6.1.2.1.1.3.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 3, 0],
      #   name: "sysUpTime.0", type: :timeticks, value: 126_355_300, formatted: "14 days ..."}

  """
  @spec get_pretty(target(), oid(), opts()) :: {:ok, varbind()} | {:error, any()}
  def get_pretty(target, oid, opts \\ []) do
    # Force include_formatted: true to ensure formatted field is present
    merged_opts =
      opts
      |> Keyword.put(:include_formatted, true)
      |> SnmpKit.SnmpMgr.Config.merge_opts()

    case get(target, oid, merged_opts) do
      {:ok, enriched} -> {:ok, enriched}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs an SNMP WALK operation with formatting forced on.

  Same as `walk/3` except that every enriched map carries a `:formatted`
  value regardless of the `include_formatted` setting.

  ## Examples

      # Walk system group with automatic formatting
      {:ok, results} = SnmpMgr.walk_pretty("192.168.1.1", "1.3.6.1.2.1.1")
      # [
      #   %{name: "sysUpTime.0", oid: "1.3.6.1.2.1.1.3.0", oid_list: [1, 3, 6, 1, 2, 1, 1, 3, 0],
      #     type: :timeticks, value: 126_355_300, formatted: "14 days 15 hours 55 minutes 13 seconds"},
      #   ...
      # ]

  """
  @spec walk_pretty(target(), oid(), opts()) :: {:ok, [varbind()]} | {:error, any()}
  def walk_pretty(target, oid, opts \\ []) do
    merged_opts =
      opts
      |> Keyword.put(:include_formatted, true)
      |> SnmpKit.SnmpMgr.Config.merge_opts()

    case SnmpKit.SnmpMgr.Walk.walk(target, oid, merged_opts) do
      {:ok, results} -> {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs an SNMP GETBULK operation with formatting forced on.

  Same as `get_bulk/3` (including its `:version` rule) except that every
  enriched map carries a `:formatted` value regardless of the
  `include_formatted` setting.

  ## Examples

      # Bulk operation with automatic formatting
      {:ok, results} = SnmpMgr.bulk_pretty("192.168.1.1", "1.3.6.1.2.1.2.2", max_repetitions: 10)
      # [
      #   %{name: "ifIndex.1", oid: "1.3.6.1.2.1.2.2.1.1.1", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1],
      #     type: :integer, value: 1, formatted: "1"},
      #   ...
      # ]

  """
  @spec bulk_pretty(target(), oid(), opts()) :: {:ok, [varbind()]} | {:error, any()}
  def bulk_pretty(target, oid, opts \\ []) do
    SnmpKit.SnmpMgr.Bulk.get_bulk(target, oid, Keyword.put(opts, :include_formatted, true))
  end

  @doc """
  Performs an SNMP BULK WALK operation (adaptive GETBULK) and returns
  enriched varbind maps, the same shape as `walk/3`.

  ## Examples

      # Bulk walk the interface table
      {:ok, results} = SnmpMgr.bulk_walk("192.168.1.1", "1.3.6.1.2.1.2.2")
      # [
      #   %{name: "ifDescr.1", oid: "1.3.6.1.2.1.2.2.1.2.1", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1],
      #     type: :octet_string, value: "eth0", formatted: "eth0"},
      #   %{name: "ifSpeed.1", oid: "1.3.6.1.2.1.2.2.1.5.1", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 1],
      #     type: :gauge32, value: 1_000_000_000, formatted: "1.0 Gbps"},
      #   ...
      # ]

  Pass `include_names: false, include_formatted: false` for bare
  `%{oid, oid_list, type, value}` maps.
  """
  @spec bulk_walk(target(), oid(), opts()) :: {:ok, [varbind()]} | {:error, any()}
  def bulk_walk(target, oid, opts \\ []) do
    merged_opts = SnmpKit.SnmpMgr.Config.merge_opts(opts)

    SnmpKit.Telemetry.span(
      :walk,
      %{operation: :bulk_walk, target: target, root_oid: oid},
      fn -> do_bulk_walk(target, oid, merged_opts) end,
      &walk_span_extra/1
    )
  end

  defp walk_span_extra({:ok, results}) when is_list(results), do: %{count: length(results)}
  defp walk_span_extra(_), do: %{}

  defp do_bulk_walk(target, oid, merged_opts) do
    case SnmpKit.SnmpMgr.AdaptiveWalk.bulk_walk(target, oid, merged_opts) do
      {:ok, results} ->
        {:ok, SnmpKit.SnmpMgr.Format.enrich_varbinds(results, merged_opts)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Performs an SNMP BULK WALK operation with formatting forced on.

  Same as `bulk_walk/3` except that every enriched map carries a
  `:formatted` value regardless of the `include_formatted` setting.

  ## Examples

      # Bulk walk interface table with automatic formatting
      {:ok, results} = SnmpMgr.bulk_walk_pretty("192.168.1.1", "1.3.6.1.2.1.2.2")
      # [
      #   %{name: "ifSpeed.1", oid: "1.3.6.1.2.1.2.2.1.5.1", oid_list: [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 1],
      #     type: :gauge32, value: 1_000_000_000, formatted: "1.0 Gbps"},
      #   ...
      # ]

  """
  @spec bulk_walk_pretty(target(), oid(), opts()) :: {:ok, [varbind()]} | {:error, any()}
  def bulk_walk_pretty(target, oid, opts \\ []) do
    merged_opts =
      opts
      |> Keyword.put(:include_formatted, true)
      |> SnmpKit.SnmpMgr.Config.merge_opts()

    case bulk_walk(target, oid, merged_opts) do
      {:ok, results} -> {:ok, results}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper function
  defp resolve_oid_if_needed(oid) when is_binary(oid) do
    case SnmpKit.SnmpLib.OID.string_to_list(oid) do
      {:ok, oid_list} ->
        {:ok, oid_list}

      {:error, _} ->
        # Try resolving as symbolic name
        SnmpKit.SnmpMgr.MIB.resolve(oid)
    end
  end

  defp resolve_oid_if_needed(oid) when is_list(oid), do: {:ok, oid}
  defp resolve_oid_if_needed(_), do: {:error, :invalid_oid_format}
end
