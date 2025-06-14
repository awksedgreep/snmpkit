defmodule SnmpMgr do
  @moduledoc """
  Lightweight SNMP client library for Elixir.
  
  This library provides a simple, stateless interface for SNMP operations
  without requiring heavyweight management processes or configurations.
  """

  @type target :: binary() | tuple() | map()
  @type oid :: binary() | list()
  @type opts :: keyword()

  @doc """
  Performs an SNMP GET request.

  ## Parameters
  - `target` - The target device (e.g., "192.168.1.1:161" or "device.local")
  - `oid` - The OID to retrieve (string format)
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, value} = SnmpMgr.get("device.local:161", "sysDescr.0", community: "public")
      # "Linux server 5.4.0-42-generic #46-Ubuntu SMP Fri Jul 10 00:24:02 UTC 2020 x86_64"

      {:ok, uptime} = SnmpMgr.get("router.local", "sysUpTime.0")
      # {:timeticks, 123456789}  # System uptime in hundredths of seconds
  """
  def get(target, oid, opts \\ []) do
    merged_opts = SnmpMgr.Config.merge_opts(opts)
    SnmpMgr.Core.send_get_request(target, oid, merged_opts)
  end

  @doc """
  Performs an SNMP GET request and returns the result in 3-tuple format.
  
  This function returns the same format as walk, bulk, and other operations:
  `{oid_string, type, value}` for consistency across the library.

  ## Parameters
  - `target` - The target device (e.g., "192.168.1.1:161" or "device.local")
  - `oid` - The OID to retrieve (string format)
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, {oid, type, value}} = SnmpMgr.get_with_type("device.local:161", "sysDescr.0", community: "public")
      # {:ok, {"1.3.6.1.2.1.1.1.0", :octet_string, "Linux server 5.4.0-42-generic"}}

      {:ok, {oid, type, uptime}} = SnmpMgr.get_with_type("router.local", "sysUpTime.0")
      # {:ok, {"1.3.6.1.2.1.1.3.0", :timeticks, 123456789}}
  """
  def get_with_type(target, oid, opts \\ []) do
    merged_opts = SnmpMgr.Config.merge_opts(opts)
    SnmpMgr.Core.send_get_request_with_type(target, oid, merged_opts)
  end

  @doc """
  Performs an SNMP GETNEXT request.

  ## Parameters
  - `target` - The target device
  - `oid` - The starting OID
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, {next_oid, value}} = SnmpMgr.get_next("switch.local", "1.3.6.1.2.1.1")
      # {"1.3.6.1.2.1.1.1.0", "Cisco IOS Software, C2960 Software"}

      {:ok, {oid, val}} = SnmpMgr.get_next("device.local", "sysDescr")
      # {"1.3.6.1.2.1.1.1.0", "Linux hostname 5.4.0 #1 SMP"}
  """
  def get_next(target, oid, opts \\ []) do
    merged_opts = SnmpMgr.Config.merge_opts(opts)
    SnmpMgr.Core.send_get_next_request(target, oid, merged_opts)
  end

  @doc """
  Performs an SNMP SET request.

  ## Parameters
  - `target` - The target device
  - `oid` - The OID to set
  - `value` - The value to set
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, :ok} = SnmpMgr.set("device.local", "sysLocation.0", "Server Room A")
      # :ok

      {:ok, :ok} = SnmpMgr.set("switch.local", "sysContact.0", "admin@company.com", 
        community: "private", timeout: 3000)
      # :ok
  """
  def set(target, oid, value, opts \\ []) do
    merged_opts = SnmpMgr.Config.merge_opts(opts)
    SnmpMgr.Core.send_set_request(target, oid, value, merged_opts)
  end

  @doc """
  Performs an asynchronous SNMP GET request.

  Returns immediately with a reference. The caller will receive a message
  with the result.

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      ref = SnmpMgr.get_async("device.local", "sysDescr.0")
      receive do
        {^ref, {:ok, description}} -> description
        {^ref, {:error, reason}} -> {:error, reason}
      after
        5000 -> {:error, :timeout}
      end
      # "Linux server 5.4.0-42-generic"
  """
  def get_async(target, oid, opts \\ []) do
    merged_opts = SnmpMgr.Config.merge_opts(opts)
    SnmpMgr.Core.send_get_request_async(target, oid, merged_opts)
  end

  @doc """
  Performs an SNMP GETBULK request (SNMPv2c only).

  GETBULK is more efficient than multiple GETNEXT requests for retrieving
  large amounts of data. It can retrieve multiple variables in a single request.

  ## Parameters
  - `target` - The target device
  - `oid` - The starting OID
  - `opts` - Options including :non_repeaters, :max_repetitions, :community, :timeout

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpMgr.get_bulk("switch.local", "ifTable", max_repetitions: 10)
      # [
      #   {"1.3.6.1.2.1.2.2.1.1.1", 1},                    # ifIndex.1
      #   {"1.3.6.1.2.1.2.2.1.2.1", "FastEthernet0/1"},    # ifDescr.1
      #   {"1.3.6.1.2.1.2.2.1.8.1", 1},                    # ifOperStatus.1 (up)
      #   {"1.3.6.1.2.1.2.2.1.1.2", 2},                    # ifIndex.2
      #   {"1.3.6.1.2.1.2.2.1.2.2", "FastEthernet0/2"},    # ifDescr.2
      #   # ... up to max_repetitions entries
      # ]
  """
  def get_bulk(target, oid, opts \\ []) do
    # Check if user explicitly specified a version other than v2c
    case Keyword.get(opts, :version) do
      :v1 -> {:error, {:unsupported_operation, :get_bulk_requires_v2c}}
      :v3 -> {:error, {:unsupported_operation, :get_bulk_requires_v2c}}
      _ ->
        # Force version to v2c for GETBULK
        merged_opts = 
          opts
          |> Keyword.put(:version, :v2c)
          |> (&SnmpMgr.Config.merge_opts/1).()
        
        SnmpMgr.Core.send_get_bulk_request(target, oid, merged_opts)
    end
  end

  @doc """
  Performs an asynchronous SNMP GETBULK request.

  Returns immediately with a reference. The caller will receive a message
  with the result.
  """
  def get_bulk_async(target, oid, opts \\ []) do
    # Check if user explicitly specified a version other than v2c
    case Keyword.get(opts, :version) do
      :v1 -> {:error, {:unsupported_operation, :get_bulk_requires_v2c}}
      :v3 -> {:error, {:unsupported_operation, :get_bulk_requires_v2c}}
      _ ->
        # Force version to v2c for GETBULK
        merged_opts = 
          opts
          |> Keyword.put(:version, :v2c)
          |> (&SnmpMgr.Config.merge_opts/1).()
        
        SnmpMgr.Core.send_get_bulk_request_async(target, oid, merged_opts)
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
      #   {"1.3.6.1.2.1.1.1.0", "Linux hostname 5.4.0-42-generic"},  # sysDescr
      #   {"1.3.6.1.2.1.1.2.0", [1,3,6,1,4,1,8072,3,2,10]},         # sysObjectID
      #   {"1.3.6.1.2.1.1.3.0", {:timeticks, 12345678}},             # sysUpTime
      #   {"1.3.6.1.2.1.1.4.0", "admin@company.com"},                # sysContact
      #   {"1.3.6.1.2.1.1.5.0", "server01.company.com"},             # sysName
      #   {"1.3.6.1.2.1.1.6.0", "Data Center Room 42"}               # sysLocation
      # ]
  """
  def walk(target, root_oid, opts \\ []) do
    SnmpMgr.Walk.walk(target, root_oid, opts)
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
      #   {"1.3.6.1.2.1.2.2.1.1.1", 1},
      #   {"1.3.6.1.2.1.2.2.1.2.1", "GigabitEthernet0/1"},
      #   {"1.3.6.1.2.1.2.2.1.3.1", 6},  # ethernetCsmacd
      #   {"1.3.6.1.2.1.2.2.1.5.1", 1000000000},  # 1 Gbps
      #   # ... all interface table entries
      # ]
  """
  def walk_table(target, table_oid, opts \\ []) do
    SnmpMgr.Walk.walk_table(target, table_oid, opts)
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
      # %{
      #   columns: ["ifIndex", "ifDescr", "ifType", "ifMtu", "ifSpeed", "ifOperStatus"],
      #   rows: [
      #     %{"ifIndex" => 1, "ifDescr" => "GigabitEthernet0/1", "ifType" => 6, 
      #       "ifMtu" => 1500, "ifSpeed" => 1000000000, "ifOperStatus" => 1},
      #     %{"ifIndex" => 2, "ifDescr" => "GigabitEthernet0/2", "ifType" => 6, 
      #       "ifMtu" => 1500, "ifSpeed" => 1000000000, "ifOperStatus" => 2}
      #   ]
      # }
  """
  def get_table(target, table_oid, opts \\ []) do
    case resolve_oid_if_needed(table_oid) do
      {:ok, resolved_oid} ->
        case walk_table(target, resolved_oid, opts) do
          {:ok, entries} -> SnmpMgr.Table.to_table(entries, resolved_oid)
          error -> error
        end
      error -> error
    end
  end

  @doc """
  Gets a specific column from an SNMP table.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID
  - `column` - The column number or name
  - `opts` - Options including :community, :timeout
  """
  def get_column(target, table_oid, column, opts \\ []) do
    case resolve_oid_if_needed(table_oid) do
      {:ok, resolved_table_oid} ->
        column_oid = if is_integer(column) do
          resolved_table_oid ++ [1, column]
        else
          case SnmpMgr.MIB.resolve(column) do
            {:ok, oid} -> oid
            error -> error
          end
        end
        walk(target, column_oid, opts)
      error -> error
    end
  end

  @doc """
  Performs concurrent GET operations against multiple targets.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} tuples
  - `opts` - Options applied to all requests

  ## Examples

      # Note: Network operations will fail on unreachable hosts
      iex> SnmpMgr.get_multi([{"device1", [1,3,6,1,2,1,1,1,0]}, {"device2", [1,3,6,1,2,1,1,3,0]}])
      [{:error, {:network_error, :hostname_resolution_failed}}, {:error, {:network_error, :hostname_resolution_failed}}]
  """
  def get_multi(targets_and_oids, opts \\ []) do
    merged_opts = SnmpMgr.Config.merge_opts(opts)
    SnmpMgr.Multi.get_multi(targets_and_oids, merged_opts)
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
      |> Keyword.put(:version, :v2c)
      |> (&SnmpMgr.Config.merge_opts/1).()
    
    SnmpMgr.Multi.get_bulk_multi(targets_and_oids, merged_opts)
  end

  @doc """
  Performs concurrent walk operations against multiple targets.

  ## Parameters
  - `targets_and_oids` - List of {target, root_oid} tuples
  - `opts` - Options applied to all requests
  """
  def walk_multi(targets_and_oids, opts \\ []) do
    merged_opts = SnmpMgr.Config.merge_opts(opts)
    SnmpMgr.Multi.walk_multi(targets_and_oids, merged_opts)
  end

  @doc """
  Performs an adaptive bulk walk that automatically optimizes parameters.

  Uses intelligent parameter tuning based on device response characteristics
  for optimal performance.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :adaptive_tuning, :max_entries

  ## Examples

      # Note: This function makes actual network calls and is not suitable for doctests
      {:ok, results} = SnmpMgr.adaptive_walk("switch.local", "ifTable")
      # Returns optimally retrieved interface table data:
      # [
      #   {"1.3.6.1.2.1.2.2.1.1.1", 1},           # ifIndex.1
      #   {"1.3.6.1.2.1.2.2.1.2.1", "eth0"},      # ifDescr.1  
      #   {"1.3.6.1.2.1.2.2.1.8.1", 1},           # ifOperStatus.1
      #   {"1.3.6.1.2.1.2.2.1.1.2", 2},           # ifIndex.2
      #   {"1.3.6.1.2.1.2.2.1.2.2", "eth1"},      # ifDescr.2
      #   {"1.3.6.1.2.1.2.2.1.8.2", 1}            # ifOperStatus.2
      # ]
  """
  def adaptive_walk(target, root_oid, opts \\ []) do
    SnmpMgr.AdaptiveWalk.bulk_walk(target, root_oid, opts)
  end

  @doc """
  Creates a stream for memory-efficient processing of large SNMP data.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :chunk_size, :adaptive

  ## Examples

      # Note: Requires Erlang SNMP modules for actual operation
      stream = SnmpMgr.walk_stream("192.0.2.1", "ifTable")
      # Process stream lazily...
  """
  def walk_stream(target, root_oid, opts \\ []) do
    SnmpMgr.Stream.walk_stream(target, root_oid, opts)
  end

  @doc """
  Creates a stream for processing large SNMP tables.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to stream
  - `opts` - Options including :chunk_size, :columns

  ## Examples

      # Note: Requires Erlang SNMP modules for actual operation
      stream = SnmpMgr.table_stream("192.0.2.1", "ifTable")
      # Process table stream...
  """
  def table_stream(target, table_oid, opts \\ []) do
    SnmpMgr.Stream.table_stream(target, table_oid, opts)
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
    SnmpMgr.Table.analyze(table_data, opts)
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
    SnmpMgr.AdaptiveWalk.benchmark_device(target, test_oid, opts)
  end

  @doc """
  Starts the streaming PDU engine infrastructure.

  Initializes all Phase 5 components including engines, routers, connection pools,
  circuit breakers, and metrics collection for high-performance SNMP operations.

  ## Options
  - `:engine` - Engine configuration options
  - `:router` - Router configuration options  
  - `:pool` - Connection pool options
  - `:circuit_breaker` - Circuit breaker options
  - `:metrics` - Metrics collection options

  ## Examples

      {:ok, _pid} = SnmpMgr.start_engine(
        engine: [pool_size: 20, max_rps: 500],
        router: [strategy: :least_connections],
        pool: [pool_size: 50],
        metrics: [window_size: 120]
      )
  """
  def start_engine(opts \\ []) do
    SnmpMgr.Supervisor.start_link(opts)
  end

  @doc """
  Submits a request through the streaming engine.

  Routes the request through the high-performance engine infrastructure
  with automatic load balancing, circuit breaking, and metrics collection.

  ## Parameters
  - `request` - Request specification map
  - `opts` - Request options

  ## Examples

      request = %{
        type: :get,
        target: "192.0.2.1",
        oid: "sysDescr.0",
        community: "public"
      }
      
      {:ok, result} = SnmpMgr.engine_request(request)
  """
  def engine_request(request, opts \\ []) do
    router = Keyword.get(opts, :router, SnmpMgr.Router)
    SnmpMgr.Router.route_request(router, request, opts)
  end

  @doc """
  Submits multiple requests as a batch through the streaming engine.

  ## Parameters
  - `requests` - List of request specification maps
  - `opts` - Batch options

  ## Examples

      requests = [
        %{type: :get, target: "device1", oid: "sysDescr.0"},
        %{type: :get, target: "device2", oid: "sysUpTime.0"}
      ]
      
      {:ok, results} = SnmpMgr.engine_batch(requests)
  """
  def engine_batch(requests, opts \\ []) do
    router = Keyword.get(opts, :router, SnmpMgr.Router)
    SnmpMgr.Router.route_batch(router, requests, opts)
  end

  @doc """
  Gets comprehensive system metrics and statistics.

  ## Parameters
  - `opts` - Options including which components to include

  ## Examples

      {:ok, stats} = SnmpMgr.get_engine_stats()
      IO.inspect(stats.router.requests_routed)
      IO.inspect(stats.metrics.current_metrics)
  """
  def get_engine_stats(opts \\ []) do
    components = Keyword.get(opts, :components, [:router, :pool, :circuit_breaker, :metrics])
    
    stats = %{}
    
    stats = if :router in components do
      Map.put(stats, :router, SnmpMgr.Router.get_stats(SnmpMgr.Router))
    else
      stats
    end
    
    # Pool component no longer exists after snmp_lib migration
    # Connection pooling is handled internally by SnmpLib.Manager
    stats = if :pool in components do
      Map.put(stats, :pool, %{status: :delegated_to_snmp_lib})
    else
      stats
    end
    
    stats = if :circuit_breaker in components do
      Map.put(stats, :circuit_breaker, SnmpMgr.CircuitBreaker.get_stats(SnmpMgr.CircuitBreaker))
    else
      stats
    end
    
    stats = if :metrics in components do
      Map.put(stats, :metrics, SnmpMgr.Metrics.get_summary(SnmpMgr.Metrics))
    else
      stats
    end
    
    {:ok, stats}
  end

  @doc """
  Executes a function with circuit breaker protection.

  ## Parameters
  - `target` - Target device identifier
  - `fun` - Function to execute with protection
  - `opts` - Circuit breaker options

  ## Examples

      result = SnmpMgr.with_circuit_breaker("192.0.2.1", fn ->
        SnmpMgr.get("192.0.2.1", "sysDescr.0")
      end)
  """
  def with_circuit_breaker(target, fun, opts \\ []) do
    circuit_breaker = Keyword.get(opts, :circuit_breaker, SnmpMgr.CircuitBreaker)
    timeout = Keyword.get(opts, :timeout, 5000)
    SnmpMgr.CircuitBreaker.call(circuit_breaker, target, fun, timeout)
  end

  @doc """
  Records a custom metric.

  ## Parameters
  - `metric_type` - Type of metric (:counter, :gauge, :histogram)
  - `metric_name` - Name of the metric
  - `value` - Value to record
  - `tags` - Optional tags

  ## Examples

      SnmpMgr.record_metric(:counter, :custom_requests, 1, %{device: "switch1"})
      SnmpMgr.record_metric(:histogram, :custom_latency, 150, %{operation: "bulk"})
  """
  def record_metric(metric_type, metric_name, value, tags \\ %{}) do
    metrics = SnmpMgr.Metrics
    
    case metric_type do
      :counter -> SnmpMgr.Metrics.counter(metrics, metric_name, value, tags)
      :gauge -> SnmpMgr.Metrics.gauge(metrics, metric_name, value, tags)
      :histogram -> SnmpMgr.Metrics.histogram(metrics, metric_name, value, tags)
    end
  end

  @doc """
  Performs an SNMP GET operation and returns a formatted value.
  
  This is a convenience function that combines `get_with_type/3` and automatic
  formatting based on the SNMP type. Returns just the formatted value since
  the OID is already known.
  
  ## Examples
  
      # Get system uptime with automatic formatting
      {:ok, formatted_uptime} = SnmpMgr.get_pretty("192.168.1.1", "1.3.6.1.2.1.1.3.0")
      # Returns: "14 days 15 hours 55 minutes 13 seconds"
      
  """
  @spec get_pretty(target(), oid(), opts()) :: {:ok, String.t()} | {:error, any()}
  def get_pretty(target, oid, opts \\ []) do
    case get_with_type(target, oid, opts) do
      {:ok, {_oid, type, value}} ->
        formatted_value = SnmpMgr.Format.format_by_type(type, value)
        {:ok, formatted_value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs an SNMP WALK operation and returns formatted results.
  
  Returns a list of {oid, formatted_value} tuples where values are automatically
  formatted based on their SNMP types.
  
  ## Examples
  
      # Walk system group with automatic formatting
      {:ok, results} = SnmpMgr.walk_pretty("192.168.1.1", "1.3.6.1.2.1.1")
      # Returns: [{"1.3.6.1.2.1.1.3.0", "14 days 15 hours"}, ...]
      
  """
  @spec walk_pretty(target(), oid(), opts()) :: {:ok, [{String.t(), String.t()}]} | {:error, any()}
  def walk_pretty(target, oid, opts \\ []) do
    case SnmpMgr.Walk.walk(target, oid, opts) do
      {:ok, results} ->
        formatted_results = Enum.map(results, fn {oid, type, value} ->
          formatted_value = SnmpMgr.Format.format_by_type(type, value)
          {oid, formatted_value}
        end)
        {:ok, formatted_results}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs an SNMP BULK operation and returns formatted results.
  
  Returns a list of {oid, formatted_value} tuples where values are automatically
  formatted based on their SNMP types.
  
  ## Examples
  
      # Bulk operation with automatic formatting
      {:ok, results} = SnmpMgr.bulk_pretty("192.168.1.1", "1.3.6.1.2.1.2.2", max_repetitions: 10)
      # Returns: [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, ...]
      
  """
  @spec bulk_pretty(target(), oid(), opts()) :: {:ok, [{String.t(), String.t()}]} | {:error, any()}
  def bulk_pretty(target, oid, opts \\ []) do
    case SnmpMgr.Bulk.get_bulk(target, oid, opts) do
      {:ok, results} ->
        formatted_results = Enum.map(results, fn {oid, type, value} ->
          formatted_value = SnmpMgr.Format.format_by_type(type, value)
          {oid, formatted_value}
        end)
        {:ok, formatted_results}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs an SNMP BULK WALK operation and returns formatted results.
  
  Returns a list of {oid, formatted_value} tuples where values are automatically
  formatted based on their SNMP types.
  
  ## Examples
  
      # Bulk walk interface table with automatic formatting
      {:ok, results} = SnmpMgr.bulk_walk_pretty("192.168.1.1", "1.3.6.1.2.1.2.2")
      # Returns: [{"1.3.6.1.2.1.2.2.1.2.1", "eth0"}, {"1.3.6.1.2.1.2.2.1.5.1", "1 Gbps"}, ...]
      
  """
  @spec bulk_walk_pretty(target(), oid(), opts()) :: {:ok, [{String.t(), String.t()}]} | {:error, any()}
  def bulk_walk_pretty(target, oid, opts \\ []) do
    case SnmpMgr.AdaptiveWalk.bulk_walk(target, oid, opts) do
      {:ok, results} ->
        formatted_results = Enum.map(results, fn {oid, type, value} ->
          formatted_value = SnmpMgr.Format.format_by_type(type, value)
          {oid, formatted_value}
        end)
        {:ok, formatted_results}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper function
  defp resolve_oid_if_needed(oid) when is_binary(oid) do
    case SnmpLib.OID.string_to_list(oid) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, _} ->
        # Try resolving as symbolic name
        SnmpMgr.MIB.resolve(oid)
    end
  end
  defp resolve_oid_if_needed(oid) when is_list(oid), do: {:ok, oid}
  defp resolve_oid_if_needed(_), do: {:error, :invalid_oid_format}
end
