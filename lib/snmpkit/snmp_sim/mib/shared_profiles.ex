defmodule SnmpKit.SnmpSim.MIB.SharedProfiles do
  @moduledoc """
  Memory-efficient shared OID profiles using ETS tables.
  Reduces memory from 1GB to ~10MB for 10K devices by sharing profile data.
  """

  use GenServer
  require Logger

  # Profile / behavior tables are unnamed (device types come from config and
  # walk-file names, so minting an atom per type would let external input grow
  # the atom table) and public, so readers use them directly via their tids.
  @table_opts [:set, :public, {:read_concurrency, true}]
  # OID index: ordered_set keyed by the OID as an integer list. Erlang term
  # order on integer lists is exactly SNMP lexicographic order (a prefix sorts
  # before its descendants), so :ets.next/2 is GETNEXT in O(log n).
  @index_opts [:ordered_set, :public, {:read_concurrency, true}]
  # One public, named registry maps device_type -> table tids for direct reads.
  @registry :snmp_sim_profile_registry

  defstruct [
    :profile_tables,
    :behavior_tables,
    :index_tables,
    :metadata_table,
    :stats
  ]

  # API Functions

  @doc """
  Start the shared profiles manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initialize shared profiles for device types.

  ## Examples

      :ok = SnmpKit.SnmpSim.MIB.SharedProfiles.init_profiles()

  """
  def init_profiles do
    GenServer.call(__MODULE__, :init_profiles)
  end

  @doc """
  Load a MIB-based profile for a device type.

  ## Examples

      :ok = SnmpKit.SnmpSim.MIB.SharedProfiles.load_mib_profile(
        :cable_modem,
        ["DOCS-CABLE-DEVICE-MIB", "IF-MIB"]
      )

  """
  def load_mib_profile(device_type, mib_files, opts \\ []) do
    GenServer.call(__MODULE__, {:load_mib_profile, device_type, mib_files, opts}, 30_000)
  end

  @doc """
  Load a walk file-based profile with enhanced behaviors.

  ## Examples

      :ok = SnmpKit.SnmpSim.MIB.SharedProfiles.load_walk_profile(
        :cable_modem,
        "priv/walks/cable_modem.walk",
        behaviors: [:realistic_counters, :daily_patterns]
      )

  """
  def load_walk_profile(device_type, walk_file, opts \\ []) do
    GenServer.call(__MODULE__, {:load_walk_profile, device_type, walk_file, opts}, 30_000)
  end

  @doc """
  Get a value for a specific OID with device-specific state applied.

  ## Examples

      value = SnmpKit.SnmpSim.MIB.SharedProfiles.get_oid_value(
        :cable_modem,
        "1.3.6.1.2.1.2.2.1.10.1",
        %{device_id: "cm_001", uptime: 3600}
      )

  """
  def get_oid_value(device_type, oid, device_state) do
    with {:ok, tables} <- lookup_tables(device_type) do
      read_oid_value(tables, oid, device_state)
    end
  end

  @doc """
  Get the next OID in lexicographic order for GETNEXT operations.
  """
  def get_next_oid(device_type, oid) do
    with {:ok, tables} <- lookup_tables(device_type) do
      read_next_oid(tables, oid)
    end
  end

  @doc """
  Get multiple OIDs for GETBULK operations.
  """
  def get_bulk_oids(device_type, start_oid, max_repetitions, device_state \\ %{}) do
    with {:ok, tables} <- lookup_tables(device_type) do
      read_bulk_oids(tables, start_oid, max_repetitions, device_state)
    end
  end

  @doc """
  Get all OIDs for a device type.
  """
  def get_all_oids(device_type) do
    with {:ok, tables} <- lookup_tables(device_type) do
      try do
        {:ok, :ets.select(tables.index, [{{:_, :"$1"}, [], [:"$1"]}])}
      rescue
        ArgumentError -> {:error, :device_type_not_found}
      end
    end
  end

  @doc """
  Get memory usage statistics for the shared profiles.
  """
  def get_memory_stats do
    GenServer.call(__MODULE__, :get_memory_stats)
  end

  @doc """
  List all available device type profiles.
  """
  def list_profiles do
    GenServer.call(__MODULE__, :list_profiles)
  end

  @doc """
  Clear all profiles (useful for testing).
  """
  def clear_all_profiles do
    GenServer.call(__MODULE__, :clear_all_profiles)
  end

  @doc """
  Store profile data directly (useful for testing).
  """
  def store_profile(device_type, profile_data, behavior_data) do
    GenServer.call(__MODULE__, {:store_profile, device_type, profile_data, behavior_data})
  end

  @doc """
  Compare OIDs lexicographically (useful for testing).
  """
  def compare_oids_lexicographically(oid1, oid2) do
    # Convert OIDs to lists if they're strings
    oid1_list =
      case oid1 do
        oid when is_binary(oid) ->
          case String.split(oid, ".") do
            # Handle empty string case
            [""] ->
              []

            parts ->
              try do
                Enum.map(parts, &String.to_integer/1)
              rescue
                ArgumentError ->
                  # Invalid OID format, return empty list to handle gracefully
                  []
              end
          end

        oid when is_list(oid) ->
          oid
      end

    oid2_list =
      case oid2 do
        oid when is_binary(oid) ->
          case String.split(oid, ".") do
            # Handle empty string case
            [""] ->
              []

            parts ->
              try do
                Enum.map(parts, &String.to_integer/1)
              rescue
                ArgumentError ->
                  # Invalid OID format, return empty list to handle gracefully
                  []
              end
          end

        oid when is_list(oid) ->
          oid
      end

    compare_oid_parts(oid1_list, oid2_list)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    metadata_table = :ets.new(:snmp_sim_metadata, @table_opts)

    # Registry survives no longer than this process (it owns the table)
    case :ets.whereis(@registry) do
      :undefined -> :ets.new(@registry, [:set, :public, :named_table, {:read_concurrency, true}])
      _ -> :ets.delete_all_objects(@registry)
    end

    state = %__MODULE__{
      profile_tables: %{},
      behavior_tables: %{},
      index_tables: %{},
      metadata_table: metadata_table,
      stats: init_stats()
    }

    Logger.info("SharedProfiles manager started")
    {:ok, state}
  end

  @impl true
  def handle_call(:init_profiles, _from, state) do
    device_types = [:cable_modem, :cmts, :switch, :router, :mta, :server]

    new_state =
      Enum.reduce(device_types, state, fn device_type, acc ->
        {_tables, acc} = ensure_device_tables(device_type, acc)
        acc
      end)

    {:reply, :ok, new_state}
  end

  @dialyzer {:nowarn_function, handle_call: 3}
  @impl true
  def handle_call({:load_mib_profile, device_type, mib_files, opts}, _from, state) do
    try do
      case load_mib_profile_impl(device_type, mib_files, opts, state) do
        {:ok, new_state} ->
          {:reply, :ok, new_state}

        error ->
          error_msg =
            case error do
              {:error, {:mib_load_failed, %{__exception__: true} = exception}} ->
                "MIB load failed: #{Exception.message(exception)}"

              {:error, {:mib_load_failed, reason}} ->
                "MIB load failed: #{inspect(reason)}"
            end

          Logger.error(error_msg)
          {:reply, {:error, :load_failed}, state}
      end
    rescue
      e ->
        error_msg = "Error in load_mib_profile: #{Exception.format(:error, e, __STACKTRACE__)}"
        Logger.error(error_msg)
        {:reply, {:error, :internal_error}, state}
    end
  end

  @impl true
  def handle_call({:load_walk_profile, device_type, walk_file, opts}, _from, state) do
    case load_walk_profile_impl(device_type, walk_file, opts, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Kept for callers that still go through the server; reads are served from
  # ETS in the caller's process by the public functions above.
  @impl true
  def handle_call({:get_oid_value, device_type, oid, device_state}, _from, state) do
    {:reply, get_oid_value(device_type, oid, device_state), state}
  end

  @impl true
  def handle_call({:get_next_oid, device_type, oid}, _from, state) do
    {:reply, get_next_oid(device_type, oid), state}
  end

  @impl true
  def handle_call({:get_bulk_oids, device_type, start_oid, max_repetitions}, _from, state) do
    {:reply, get_bulk_oids(device_type, start_oid, max_repetitions), state}
  end

  @impl true
  def handle_call({:get_all_oids, device_type}, _from, state) do
    {:reply, get_all_oids(device_type), state}
  end

  @impl true
  def handle_call(:get_memory_stats, _from, state) do
    stats = calculate_memory_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:list_profiles, _from, state) do
    profiles = Map.keys(state.profile_tables)
    {:reply, profiles, state}
  end

  @impl true
  def handle_call(:clear_all_profiles, _from, state) do
    # Delete the tables outright so cleared profiles do not keep their ETS
    # footprint (and readers hit the registry miss path).
    :ets.delete_all_objects(@registry)

    for tables <- [state.profile_tables, state.behavior_tables, state.index_tables],
        {_type, table} <- tables do
      :ets.delete(table)
    end

    :ets.delete_all_objects(state.metadata_table)

    {:reply, :ok,
     %{state | profile_tables: %{}, behavior_tables: %{}, index_tables: %{}, stats: init_stats()}}
  end

  @impl true
  def handle_call({:store_profile, device_type, profile_data, behavior_data}, _from, state) do
    {tables, new_state} = ensure_device_tables(device_type, state)

    store_profile_data(tables, profile_data)
    store_behavior_data(tables, behavior_data)

    object_count =
      case profile_data do
        data when is_map(data) -> map_size(data)
        data when is_list(data) -> length(data)
        _ -> 0
      end

    metadata = %{
      device_type: device_type,
      source_type: :directly_stored,
      object_count: object_count,
      loaded_at: DateTime.utc_now(),
      options: %{}
    }

    :ets.insert(new_state.metadata_table, {device_type, metadata})

    updated_stats = update_load_stats(new_state.stats, device_type, object_count)

    {:reply, :ok, %{new_state | stats: updated_stats}}
  end

  ## Loading -------------------------------------------------------------------

  defp load_mib_profile_impl(device_type, mib_files, opts, state) do
    {tables, new_state} = ensure_device_tables(device_type, state)

    try do
      compiled_mibs = SnmpKit.SnmpSim.MIB.Compiler.compile_mib_files(mib_files)

      all_objects =
        compiled_mibs
        |> Enum.map(&extract_objects_from_compiled_mib/1)
        |> Enum.reduce(%{}, &Map.merge/2)

      if map_size(all_objects) == 0 do
        # Compiled-MIB object extraction is not implemented; loading "success"
        # with zero OIDs would only surface later as an empty device.
        throw({:error, :no_objects_in_compiled_mibs})
      end

      {:ok, behaviors} = SnmpKit.SnmpSim.MIB.BehaviorAnalyzer.analyze_mib_behaviors(all_objects)

      store_profile_data(tables, all_objects)
      store_behavior_data(tables, behaviors)

      metadata = %{
        device_type: device_type,
        source_type: :compiled_mib,
        mib_files: mib_files,
        object_count: map_size(all_objects),
        loaded_at: DateTime.utc_now(),
        options: opts
      }

      :ets.insert(new_state.metadata_table, {device_type, metadata})

      updated_stats = update_load_stats(new_state.stats, device_type, map_size(all_objects))

      {:ok, %{new_state | stats: updated_stats}}
    rescue
      error ->
        Logger.error("Failed to load MIB profile for #{device_type}: #{inspect(error)}")
        {:error, {:mib_load_failed, error}}
    catch
      {:error, reason} ->
        Logger.error("Failed to load MIB profile for #{device_type}: #{inspect(reason)}")
        {:error, {:mib_load_failed, reason}}
    end
  end

  defp load_walk_profile_impl(device_type, walk_file, opts, state) do
    {tables, new_state} = ensure_device_tables(device_type, state)

    try do
      {:ok, oid_map} = SnmpKit.SnmpSim.WalkParser.parse_walk_file(walk_file)

      enhanced_behaviors =
        SnmpKit.SnmpSim.MIB.BehaviorAnalyzer.enhance_walk_file_behaviors(oid_map)

      profile_data =
        Map.new(enhanced_behaviors, fn {oid, data} ->
          {oid, Map.drop(data, [:behavior])}
        end)

      behavior_data =
        Map.new(enhanced_behaviors, fn {oid, data} ->
          {oid, Map.get(data, :behavior, {:static_value, %{}})}
        end)

      store_profile_data(tables, profile_data)
      store_behavior_data(tables, behavior_data)

      metadata = %{
        device_type: device_type,
        source_type: :walk_file,
        source_file: walk_file,
        object_count: map_size(oid_map),
        loaded_at: DateTime.utc_now(),
        options: opts
      }

      :ets.insert(new_state.metadata_table, {device_type, metadata})

      updated_stats = update_load_stats(new_state.stats, device_type, map_size(oid_map))

      {:ok, %{new_state | stats: updated_stats}}
    rescue
      error ->
        Logger.error("Failed to load walk profile for #{device_type}: #{inspect(error)}")
        {:error, {:walk_load_failed, error}}
    end
  end

  ## Direct ETS reads (run in the caller) -----------------------------------

  defp lookup_tables(device_type) do
    case :ets.lookup(@registry, device_type) do
      [{_, tables}] -> {:ok, tables}
      [] -> {:error, :device_type_not_found}
    end
  rescue
    ArgumentError -> {:error, :device_type_not_found}
  end

  defp read_oid_value(tables, oid, device_state) do
    case lookup_profile(tables, oid) do
      {:ok, key, profile_data} ->
        behavior_config =
          case :ets.lookup(tables.behavior, key) do
            [{^key, behavior}] -> behavior
            [] -> {:static_value, %{}}
          end

        current_value =
          SnmpKit.SnmpSim.ValueSimulator.simulate_value(
            profile_data,
            behavior_config,
            device_state
          )

        atom_type = convert_type_to_atom(profile_data.type)

        final_value =
          case current_value do
            {_type, value} -> value
            value -> value
          end

        {:ok, {atom_type, final_value}}

      :error ->
        {:error, :no_such_name}
    end
  rescue
    ArgumentError -> {:error, :device_type_not_found}
  end

  # Profiles are keyed by the OID form the loader produced (dotted string for
  # walk files); callers may pass either form, so fall back through the index.
  defp lookup_profile(tables, oid) do
    case :ets.lookup(tables.profile, oid) do
      [{^oid, data}] ->
        {:ok, oid, data}

      [] ->
        with {:ok, int_list} <- oid_to_list(oid),
             [{^int_list, key}] <- :ets.lookup(tables.index, int_list),
             [{^key, data}] <- :ets.lookup(tables.profile, key) do
          {:ok, key, data}
        else
          _ -> :error
        end
    end
  end

  defp read_next_oid(tables, oid) do
    with {:ok, int_list} <- oid_to_list(oid) do
      case :ets.next(tables.index, int_list) do
        :"$end_of_table" ->
          :end_of_mib

        next_list ->
          case :ets.lookup(tables.index, next_list) do
            [{_, key}] -> {:ok, key}
            [] -> :end_of_mib
          end
      end
    else
      _ -> {:error, :invalid_oid}
    end
  rescue
    ArgumentError -> {:error, :device_type_not_found}
  end

  defp read_bulk_oids(tables, start_oid, max_repetitions, device_state) do
    collect_bulk(tables, start_oid, max_repetitions, device_state, [])
  rescue
    ArgumentError -> {:error, :device_type_not_found}
  end

  defp collect_bulk(_tables, _oid, remaining, _device_state, acc) when remaining <= 0 do
    {:ok, Enum.reverse(acc)}
  end

  defp collect_bulk(tables, oid, remaining, device_state, acc) do
    case read_next_oid(tables, oid) do
      {:ok, next_oid} ->
        tuple =
          case read_oid_value(tables, next_oid, device_state) do
            {:ok, {type, value}} -> {next_oid, type, value}
            {:error, _} -> {next_oid, :octet_string, "Bulk value for #{next_oid}"}
          end

        collect_bulk(tables, next_oid, remaining - 1, device_state, [tuple | acc])

      :end_of_mib ->
        {:ok, Enum.reverse(acc)}

      {:error, _} = error ->
        if acc == [], do: error, else: {:ok, Enum.reverse(acc)}
    end
  end

  ## Tables -------------------------------------------------------------------

  defp ensure_device_tables(device_type, state) do
    case Map.get(state.profile_tables, device_type) do
      nil ->
        tables = %{
          profile: :ets.new(:snmp_sim_profile, @table_opts),
          behavior: :ets.new(:snmp_sim_behavior, @table_opts),
          index: :ets.new(:snmp_sim_oid_index, @index_opts)
        }

        :ets.insert(@registry, {device_type, tables})

        new_state = %{
          state
          | profile_tables: Map.put(state.profile_tables, device_type, tables.profile),
            behavior_tables: Map.put(state.behavior_tables, device_type, tables.behavior),
            index_tables: Map.put(state.index_tables, device_type, tables.index)
        }

        {tables, new_state}

      profile ->
        tables = %{
          profile: profile,
          behavior: Map.fetch!(state.behavior_tables, device_type),
          index: Map.fetch!(state.index_tables, device_type)
        }

        {tables, state}
    end
  end

  # Object extraction from compiled MIBs is not implemented yet; callers get
  # an explicit error from load_mib_profile instead of an empty profile.
  defp extract_objects_from_compiled_mib(_compiled_mib) do
    %{}
  end

  defp store_profile_data(tables, profile_data) do
    Enum.each(profile_data, fn {oid, data} ->
      :ets.insert(tables.profile, {oid, data})

      case oid_to_list(oid) do
        {:ok, int_list} -> :ets.insert(tables.index, {int_list, oid})
        :error -> Logger.warning("Skipping unindexable OID #{inspect(oid)}")
      end
    end)
  end

  defp store_behavior_data(tables, behavior_data) do
    Enum.each(behavior_data, fn {oid, behavior} ->
      :ets.insert(tables.behavior, {oid, behavior})
    end)
  end

  defp oid_to_list(oid) when is_list(oid) do
    if Enum.all?(oid, &is_integer/1), do: {:ok, oid}, else: :error
  end

  defp oid_to_list(oid) when is_binary(oid) do
    parts = oid |> String.trim_leading(".") |> String.split(".", trim: true)

    if parts != [] and Enum.all?(parts, &Regex.match?(~r/^\d+$/, &1)) do
      {:ok, Enum.map(parts, &String.to_integer/1)}
    else
      :error
    end
  end

  defp oid_to_list(_), do: :error

  defp compare_oid_parts([], []), do: false
  defp compare_oid_parts([], _), do: true
  defp compare_oid_parts(_, []), do: false
  defp compare_oid_parts([h1 | _t1], [h2 | _t2]) when h1 < h2, do: true
  defp compare_oid_parts([h1 | _t1], [h2 | _t2]) when h1 > h2, do: false
  defp compare_oid_parts([h1 | t1], [h2 | t2]) when h1 == h2, do: compare_oid_parts(t1, t2)

  defp init_stats do
    %{
      profiles_loaded: 0,
      total_objects: 0,
      memory_usage: 0,
      lookup_count: 0,
      cache_hits: 0
    }
  end

  defp update_load_stats(stats, _device_type, object_count) do
    %{
      stats
      | profiles_loaded: stats.profiles_loaded + 1,
        total_objects: stats.total_objects + object_count
    }
  end

  defp calculate_memory_stats(state) do
    profile_memory = calculate_table_memory(state.profile_tables)
    behavior_memory = calculate_table_memory(state.behavior_tables)
    index_memory = calculate_table_memory(state.index_tables)
    metadata_memory = calculate_table_memory(%{metadata: state.metadata_table})

    %{
      total_memory_kb:
        div(profile_memory + behavior_memory + index_memory + metadata_memory, 1024),
      profile_memory_kb: div(profile_memory, 1024),
      behavior_memory_kb: div(behavior_memory, 1024),
      index_memory_kb: div(index_memory, 1024),
      metadata_memory_kb: div(metadata_memory, 1024),
      table_count:
        map_size(state.profile_tables) + map_size(state.behavior_tables) +
          map_size(state.index_tables) + 1,
      profiles_loaded: state.stats.profiles_loaded,
      total_objects: state.stats.total_objects
    }
  end

  defp calculate_table_memory(tables) when is_map(tables) do
    tables
    |> Enum.map(fn {_name, table} ->
      :ets.info(table, :memory) * :erlang.system_info(:wordsize)
    end)
    |> Enum.sum()
  end

  # Types come from walk files / MIBs, i.e. external input: never mint atoms
  # for them. Unknown names fall back to :octet_string.
  defp convert_type_to_atom(type) when is_binary(type) do
    case String.upcase(type) do
      "OCTET STRING" ->
        :octet_string

      "STRING" ->
        :octet_string

      "HEX-STRING" ->
        :octet_string

      "INTEGER" ->
        :integer

      "INTEGER32" ->
        :integer

      "UNSIGNED32" ->
        :gauge32

      "GAUGE32" ->
        :gauge32

      "GAUGE" ->
        :gauge32

      "COUNTER32" ->
        :counter32

      "COUNTER" ->
        :counter32

      "COUNTER64" ->
        :counter64

      "TIMETICKS" ->
        :timeticks

      "OBJECT IDENTIFIER" ->
        :object_identifier

      "OID" ->
        :object_identifier

      "IP ADDRESS" ->
        :ip_address

      "IPADDRESS" ->
        :ip_address

      "OPAQUE" ->
        :opaque

      "BITS" ->
        :bits

      "NULL" ->
        :null

      other ->
        try do
          String.to_existing_atom(String.downcase(other))
        rescue
          ArgumentError ->
            Logger.debug("Unknown SNMP type #{inspect(type)}, treating as OCTET STRING")
            :octet_string
        end
    end
  end

  defp convert_type_to_atom(type) when is_atom(type) do
    type
  end
end
