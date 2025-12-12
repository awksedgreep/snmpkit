defmodule SnmpKit do
  @moduledoc """
  Unified API for SnmpKit - A comprehensive SNMP toolkit for Elixir.

  This module provides a clean, organized interface to all SnmpKit functionality
  through context-based sub-modules:

  - `SnmpKit.SNMP` - SNMP operations (get, walk, bulk, etc.)
  - `SnmpKit.MIB` - MIB compilation, loading, and resolution
  - `SnmpKit.Sim` - SNMP device simulation and testing

  ## Timeout Behavior

  SnmpKit uses two types of timeouts:

  ### PDU Timeout (`:timeout` parameter)
  - Controls how long to wait for each individual SNMP PDU response
  - Default: 10 seconds for GET/GETBULK, 30 seconds for walks
  - Applied per SNMP packet, not per operation

  ### Task Timeout (internal)
  - Prevents operations from hanging indefinitely
  - GET/GETBULK: PDU timeout + 1 second (safeguard)
  - Walk operations: 20 minutes maximum (allows large table walks)

  ### Walk Operations
  Walk operations may send many GETBULK PDUs to retrieve all data:
  - Each PDU has its own timeout (PDU timeout)
  - Large tables may need 50-200+ PDUs
  - Total time = N_pdus × PDU_timeout (up to 20 minute maximum)

  ## Quick Examples

      # SNMP Operations
      {:ok, value} = SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0")
      {:ok, results} = SnmpKit.SNMP.walk("192.168.1.1", "system")

      # With custom PDU timeout
      {:ok, value} = SnmpKit.SNMP.get("192.168.1.1", "sysDescr.0", timeout: 15_000)
      {:ok, results} = SnmpKit.SNMP.walk("192.168.1.1", "ifTable", timeout: 30_000)

      # MIB Operations
      {:ok, oid} = SnmpKit.MIB.resolve("sysDescr.0")
      {:ok, compiled} = SnmpKit.MIB.compile("MY-MIB.mib")

      # Simulation
      {:ok, device} = SnmpKit.Sim.start_device(profile, port: 1161)

  For backward compatibility, many common operations are also available
  directly on the main SnmpKit module.
  """

  # Direct API for most common operations (backward compatibility)
  defdelegate get(target, oid), to: SnmpKit.SnmpMgr
  defdelegate get(target, oid, opts), to: SnmpKit.SnmpMgr
  defdelegate walk(target, oid), to: SnmpKit.SnmpMgr
  defdelegate walk(target, oid, opts), to: SnmpKit.SnmpMgr
  defdelegate set(target, oid, value), to: SnmpKit.SnmpMgr
  defdelegate set(target, oid, value, opts), to: SnmpKit.SnmpMgr
  defdelegate resolve(name), to: SnmpKit.SnmpMgr.MIB

  # Bulk operations (top-level convenience)
  defdelegate get_bulk(target, oid_or_oids), to: SnmpKit.SnmpMgr
  defdelegate get_bulk(target, oid_or_oids, opts), to: SnmpKit.SnmpMgr
  defdelegate bulk_walk(target, root_oid), to: SnmpKit.SnmpMgr
  defdelegate bulk_walk(target, root_oid, opts), to: SnmpKit.SnmpMgr

  # Walk table convenience
  defdelegate walk_table(target, table_oid), to: SnmpKit.SnmpMgr
  defdelegate walk_table(target, table_oid, opts), to: SnmpKit.SnmpMgr

  # Multi-target bulk helpers
  defdelegate get_bulk_multi(targets_and_oids), to: SnmpKit.SnmpMgr
  defdelegate get_bulk_multi(targets_and_oids, opts), to: SnmpKit.SnmpMgr
  defdelegate walk_multi(targets_and_oids), to: SnmpKit.SnmpMgr
  defdelegate walk_multi(targets_and_oids, opts), to: SnmpKit.SnmpMgr

  defmodule SNMP do
    @moduledoc """
    SNMP client operations for querying and managing SNMP devices.

    This module provides all SNMP protocol operations including:
    - Basic operations: get, set, get_next
    - Bulk operations: get_bulk, walk, table operations
    - Advanced features: streaming, async operations, multi-target
    - Pretty formatting and analysis tools
    """

    # Core SNMP Operations
    defdelegate get(target, oid), to: SnmpKit.SnmpMgr
    defdelegate get(target, oid, opts), to: SnmpKit.SnmpMgr
    defdelegate get_next(target, oid), to: SnmpKit.SnmpMgr
    defdelegate get_next(target, oid, opts), to: SnmpKit.SnmpMgr
    defdelegate set(target, oid, value), to: SnmpKit.SnmpMgr
    defdelegate set(target, oid, value, opts), to: SnmpKit.SnmpMgr

    # Async Operations
    defdelegate get_async(target, oid), to: SnmpKit.SnmpMgr
    defdelegate get_async(target, oid, opts), to: SnmpKit.SnmpMgr
    defdelegate get_bulk_async(target, oid), to: SnmpKit.SnmpMgr
    defdelegate get_bulk_async(target, oid, opts), to: SnmpKit.SnmpMgr

    # Bulk Operations
    defdelegate get_bulk(target, oid), to: SnmpKit.SnmpMgr
    defdelegate get_bulk(target, oid, opts), to: SnmpKit.SnmpMgr
    defdelegate bulk_walk(target, oid), to: SnmpKit.SnmpMgr
    defdelegate bulk_walk(target, oid, opts), to: SnmpKit.SnmpMgr

    @doc """
    Like get_bulk/3 but raises on error.
    """
    @spec get_bulk!(term(), term(), keyword()) :: term()
    def get_bulk!(target, oid, opts \\ []) do
      case get_bulk(target, oid, opts) do
        {:ok, result} -> result
        {:error, reason} -> raise("get_bulk! failed: #{inspect(reason)}")
      end
    end

    @doc """
    Like bulk_walk/3 but raises on error.
    """
    @spec bulk_walk!(term(), term(), keyword()) :: term()
    def bulk_walk!(target, root_oid, opts \\ []) do
      case bulk_walk(target, root_oid, opts) do
        {:ok, result} -> result
        {:error, reason} -> raise("bulk_walk! failed: #{inspect(reason)}")
      end
    end

    # Walk Operations
    defdelegate walk(target, oid), to: SnmpKit.SnmpMgr
    defdelegate walk(target, oid, opts), to: SnmpKit.SnmpMgr
    defdelegate walk_table(target, table_oid), to: SnmpKit.SnmpMgr
    defdelegate walk_table(target, table_oid, opts), to: SnmpKit.SnmpMgr
    defdelegate adaptive_walk(target, root_oid), to: SnmpKit.SnmpMgr
    defdelegate adaptive_walk(target, root_oid, opts), to: SnmpKit.SnmpMgr

    # Table Operations
    defdelegate get_table(target, table_oid), to: SnmpKit.SnmpMgr
    defdelegate get_table(target, table_oid, opts), to: SnmpKit.SnmpMgr
    defdelegate get_column(target, table_oid, column), to: SnmpKit.SnmpMgr
    defdelegate get_column(target, table_oid, column, opts), to: SnmpKit.SnmpMgr

    # Multi-target Operations
    defdelegate get_multi(targets_and_oids), to: SnmpKit.SnmpMgr
    defdelegate get_multi(targets_and_oids, opts), to: SnmpKit.SnmpMgr
    defdelegate get_bulk_multi(targets_and_oids), to: SnmpKit.SnmpMgr
    defdelegate get_bulk_multi(targets_and_oids, opts), to: SnmpKit.SnmpMgr
    defdelegate walk_multi(targets_and_oids), to: SnmpKit.SnmpMgr
    defdelegate walk_multi(targets_and_oids, opts), to: SnmpKit.SnmpMgr

    # Streaming Operations
    defdelegate walk_stream(target, root_oid), to: SnmpKit.SnmpMgr
    defdelegate walk_stream(target, root_oid, opts), to: SnmpKit.SnmpMgr
    defdelegate table_stream(target, table_oid), to: SnmpKit.SnmpMgr
    defdelegate table_stream(target, table_oid, opts), to: SnmpKit.SnmpMgr

    @doc """
    Streaming variant of bulk_walk/3 that enforces bulk semantics (v2c) and lazily
    retrieves data in chunks.
    """
    @spec bulk_walk_stream(term(), term(), keyword()) :: Enumerable.t()
    def bulk_walk_stream(target, root_oid, opts \\ []) do
      opts = Keyword.put_new(opts, :version, :v2c)
      SnmpKit.SnmpMgr.Stream.walk_stream(target, root_oid, opts)
    end

    @doc """
    Streaming variant of table walk that enforces bulk semantics (v2c).
    """
    @spec table_bulk_stream(term(), term(), keyword()) :: Enumerable.t()
    def table_bulk_stream(target, table_oid, opts \\ []) do
      opts = Keyword.put_new(opts, :version, :v2c)
      SnmpKit.SnmpMgr.Stream.table_stream(target, table_oid, opts)
    end

    # Analysis and Utilities
    defdelegate analyze_table(table_data), to: SnmpKit.SnmpMgr
    defdelegate analyze_table(table_data, opts), to: SnmpKit.SnmpMgr
    defdelegate benchmark_device(target, test_oid), to: SnmpKit.SnmpMgr
    defdelegate benchmark_device(target, test_oid, opts), to: SnmpKit.SnmpMgr

    # Pretty Formatting
    defdelegate get_pretty(target, oid), to: SnmpKit.SnmpMgr
    defdelegate get_pretty(target, oid, opts), to: SnmpKit.SnmpMgr
    defdelegate walk_pretty(target, oid), to: SnmpKit.SnmpMgr
    defdelegate walk_pretty(target, oid, opts), to: SnmpKit.SnmpMgr
    defdelegate bulk_pretty(target, oid), to: SnmpKit.SnmpMgr
    defdelegate bulk_pretty(target, oid, opts), to: SnmpKit.SnmpMgr
    defdelegate bulk_walk_pretty(target, oid), to: SnmpKit.SnmpMgr
    defdelegate bulk_walk_pretty(target, oid, opts), to: SnmpKit.SnmpMgr

    # Engine Management
    defdelegate start_engine(), to: SnmpKit.SnmpMgr
    defdelegate start_engine(opts), to: SnmpKit.SnmpMgr
    defdelegate engine_request(request), to: SnmpKit.SnmpMgr
    defdelegate engine_request(request, opts), to: SnmpKit.SnmpMgr
    defdelegate engine_batch(requests), to: SnmpKit.SnmpMgr
    defdelegate engine_batch(requests, opts), to: SnmpKit.SnmpMgr
    defdelegate get_engine_stats(), to: SnmpKit.SnmpMgr
    defdelegate get_engine_stats(opts), to: SnmpKit.SnmpMgr

    # Circuit Breaker and Metrics
    defdelegate with_circuit_breaker(target, fun), to: SnmpKit.SnmpMgr
    defdelegate with_circuit_breaker(target, fun, opts), to: SnmpKit.SnmpMgr
    defdelegate record_metric(metric_type, metric_name, value), to: SnmpKit.SnmpMgr
    defdelegate record_metric(metric_type, metric_name, value, tags), to: SnmpKit.SnmpMgr
  end

  defmodule MIB do
    @moduledoc """
    MIB (Management Information Base) operations.

    This module provides comprehensive MIB support including:
    - MIB compilation from source files
    - Loading and managing compiled MIBs
    - OID name resolution and reverse lookup
    - MIB tree navigation and analysis
    """

    # MIB Resolution and Lookup
    defdelegate resolve(name), to: SnmpKit.SnmpMgr.MIB
    defdelegate reverse_lookup(oid), to: SnmpKit.SnmpMgr.MIB
    defdelegate children(oid), to: SnmpKit.SnmpMgr.MIB
    defdelegate parent(oid), to: SnmpKit.SnmpMgr.MIB
    defdelegate walk_tree(root_oid), to: SnmpKit.SnmpMgr.MIB
    defdelegate walk_tree(root_oid, opts), to: SnmpKit.SnmpMgr.MIB

    # High-level MIB Management (SnmpMgr.MIB)
    defdelegate compile(mib_file), to: SnmpKit.SnmpMgr.MIB
    defdelegate compile(mib_file, opts), to: SnmpKit.SnmpMgr.MIB
    defdelegate compile_dir(directory), to: SnmpKit.SnmpMgr.MIB
    defdelegate compile_dir(directory, opts), to: SnmpKit.SnmpMgr.MIB
    defdelegate load(compiled_mib_path), to: SnmpKit.SnmpMgr.MIB
    defdelegate parse_mib_file(mib_file), to: SnmpKit.SnmpMgr.MIB
    defdelegate parse_mib_file(mib_file, opts), to: SnmpKit.SnmpMgr.MIB
    defdelegate parse_mib_content(content), to: SnmpKit.SnmpMgr.MIB
    defdelegate parse_mib_content(content, opts), to: SnmpKit.SnmpMgr.MIB
    defdelegate resolve_enhanced(name), to: SnmpKit.SnmpMgr.MIB
    defdelegate resolve_enhanced(name, opts), to: SnmpKit.SnmpMgr.MIB
    defdelegate load_and_integrate_mib(mib_file), to: SnmpKit.SnmpMgr.MIB
    defdelegate load_and_integrate_mib(mib_file, opts), to: SnmpKit.SnmpMgr.MIB
    defdelegate load_standard_mibs(), to: SnmpKit.SnmpMgr.MIB

    # Low-level MIB Compilation (SnmpLib.MIB)
    defdelegate compile_raw(mib_source), to: SnmpKit.SnmpLib.MIB, as: :compile
    defdelegate compile_raw(mib_source, opts), to: SnmpKit.SnmpLib.MIB, as: :compile
    defdelegate compile_string(mib_content), to: SnmpKit.SnmpLib.MIB
    defdelegate compile_string(mib_content, opts), to: SnmpKit.SnmpLib.MIB
    defdelegate load_compiled(compiled_path), to: SnmpKit.SnmpLib.MIB
    defdelegate compile_all(mib_files), to: SnmpKit.SnmpLib.MIB
    defdelegate compile_all(mib_files, opts), to: SnmpKit.SnmpLib.MIB

    # Registry Management
    defdelegate start_link(), to: SnmpKit.SnmpMgr.MIB
    defdelegate start_link(opts), to: SnmpKit.SnmpMgr.MIB
  end

  defmodule Sim do
    @moduledoc """
    SNMP device simulation for testing and development.

    This module provides tools for creating and managing simulated SNMP devices:
    - Start individual devices with custom profiles
    - Create device populations for testing
    - Manage device lifecycles
    """

    # Device Management
    defdelegate start_device(profile), to: SnmpKit.TestSupport
    defdelegate start_device(profile, opts), to: SnmpKit.TestSupport
    defdelegate start_device_population(device_configs), to: SnmpKit.TestSupport
    defdelegate start_device_population(device_configs, opts), to: SnmpKit.TestSupport

    # For more advanced simulation features, use SnmpKit.SnmpSim modules directly:
    # - SnmpKit.SnmpSim.Device for device behavior
    # - SnmpKit.SnmpSim.ProfileLoader for loading device profiles
    # - SnmpKit.SnmpSim.LazyDevicePool for device pool management
  end
end
