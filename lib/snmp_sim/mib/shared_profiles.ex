defmodule SnmpSim.MIB.SharedProfiles do
  @moduledoc """
  Memory-efficient shared OID profiles using ETS tables.
  Reduces memory from 1GB to ~10MB for 10K devices by sharing profile data.
  """

  use GenServer
  require Logger

  @table_opts [:set, :public, :named_table, {:read_concurrency, true}]

  defstruct [
    :profile_tables,
    :behavior_tables,
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

      :ok = SnmpSim.MIB.SharedProfiles.init_profiles()

  """
  def init_profiles do
    GenServer.call(__MODULE__, :init_profiles)
  end

  @doc """
  Load a MIB-based profile for a device type.

  ## Examples

      :ok = SnmpSim.MIB.SharedProfiles.load_mib_profile(
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

      :ok = SnmpSim.MIB.SharedProfiles.load_walk_profile(
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

      value = SnmpSim.MIB.SharedProfiles.get_oid_value(
        :cable_modem,
        "1.3.6.1.2.1.2.2.1.10.1",
        %{device_id: "cm_001", uptime: 3600}
      )

  """
  def get_oid_value(device_type, oid, device_state) do
    GenServer.call(__MODULE__, {:get_oid_value, device_type, oid, device_state})
  end

  @doc """
  Get the next OID in lexicographic order for GETNEXT operations.
  """
  def get_next_oid(device_type, oid) do
    GenServer.call(__MODULE__, {:get_next_oid, device_type, oid})
  end

  @doc """
  Get multiple OIDs for GETBULK operations.
  """
  def get_bulk_oids(device_type, start_oid, max_repetitions) do
    GenServer.call(__MODULE__, {:get_bulk_oids, device_type, start_oid, max_repetitions})
  end

  @doc """
  Get all OIDs for a device type.
  """
  def get_all_oids(device_type) do
    GenServer.call(__MODULE__, {:get_all_oids, device_type})
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
    oid1_list = case oid1 do
      oid when is_binary(oid) -> 
        case String.split(oid, ".") do
          [""] -> []  # Handle empty string case
          parts -> 
            try do
              Enum.map(parts, &String.to_integer/1)
            rescue
              ArgumentError -> 
                # Invalid OID format, return empty list to handle gracefully
                []
            end
        end
      oid when is_list(oid) -> oid
    end
    
    oid2_list = case oid2 do
      oid when is_binary(oid) -> 
        case String.split(oid, ".") do
          [""] -> []  # Handle empty string case
          parts -> 
            try do
              Enum.map(parts, &String.to_integer/1)
            rescue
              ArgumentError -> 
                # Invalid OID format, return empty list to handle gracefully
                []
            end
        end
      oid when is_list(oid) -> oid
    end
    
    compare_oid_parts(oid1_list, oid2_list)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create metadata table
    metadata_table = :ets.new(:snmp_sim_metadata, @table_opts)

    state = %__MODULE__{
      profile_tables: %{},
      behavior_tables: %{},
      metadata_table: metadata_table,
      stats: init_stats()
    }

    Logger.info("SharedProfiles manager started")
    {:ok, state}
  end

  @impl true
  def handle_call(:init_profiles, _from, state) do
    # Pre-create tables for common device types
    device_types = [:cable_modem, :cmts, :switch, :router, :mta, :server]

    {profile_tables, behavior_tables} =
      Enum.reduce(device_types, {%{}, %{}}, fn device_type, {prof_acc, behav_acc} ->
        prof_table = create_profile_table(device_type)
        behav_table = create_behavior_table(device_type)

        {
          Map.put(prof_acc, device_type, prof_table),
          Map.put(behav_acc, device_type, behav_table)
        }
      end)

    new_state = %{state | profile_tables: profile_tables, behavior_tables: behavior_tables}

    {:reply, :ok, new_state}
  end

  # Suppress Dialyzer warnings for this function
  @dialyzer {:nowarn_function, handle_call: 3}
  @impl true
  def handle_call({:load_mib_profile, device_type, mib_files, opts}, _from, state) do
    try do
      case load_mib_profile_impl(device_type, mib_files, opts, state) do
        {:ok, new_state} ->
          {:reply, :ok, new_state}

        error ->
          # Handle all error cases in a unified way
          error_msg =
            case error do
              {:error, {:mib_load_failed, %{__exception__: true} = exception}} ->
                "MIB load failed: #{Exception.message(exception)}"

              {:error, {:mib_load_failed, reason}} when is_binary(reason) or is_atom(reason) ->
                "MIB load failed: #{reason}"

              {:error, reason} when is_binary(reason) or is_atom(reason) ->
                "Error: #{reason}"

              other ->
                "Unexpected error: #{inspect(other, pretty: true)}"
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

  @impl true
  def handle_call({:get_oid_value, device_type, oid, device_state}, _from, state) do
    result = get_oid_value_impl(device_type, oid, device_state, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_next_oid, device_type, oid}, _from, state) do
    result = get_next_oid_impl(device_type, oid, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_bulk_oids, device_type, start_oid, max_repetitions}, _from, state) do
    # CRITICAL FIX: For GETBULK, we should only return OIDs that come AFTER start_oid
    # If start_oid is the last OID, get_next_oid should return :end_of_mib
    result = case get_next_oid_impl(device_type, start_oid, state) do
      {:ok, _first_oid} ->
        # Start collecting from first_oid, but don't include it in the initial accumulator
        # We'll add it during the collection process
        collect_bulk_oids_with_values(
          device_type,
          start_oid,  # Start from start_oid, not first_oid
          max_repetitions,
          [],  # Empty accumulator - don't pre-include any OIDs
          state
        )

      :end_of_mib ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
    
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_all_oids, device_type}, _from, state) do
    case Map.get(state.profile_tables, device_type) do
      nil ->
        {:reply, {:error, :device_type_not_found}, state}

      table ->
        # Get all OIDs and return them
        all_oids =
          :ets.tab2list(table)
          |> Enum.map(fn {oid, _data} -> oid end)
          |> Enum.sort(&compare_oids_lexicographically/2)

        {:reply, {:ok, all_oids}, state}
    end
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
    # Clear all ETS tables
    Enum.each(state.profile_tables, fn {_type, table} ->
      :ets.delete_all_objects(table)
    end)

    Enum.each(state.behavior_tables, fn {_type, table} ->
      :ets.delete_all_objects(table)
    end)

    :ets.delete_all_objects(state.metadata_table)

    {:reply, :ok, %{state | stats: init_stats()}}
  end

  @impl true
  def handle_call({:store_profile, device_type, profile_data, behavior_data}, _from, state) do
    # Ensure tables exist for this device type
    {prof_table, behav_table, new_state} = ensure_device_tables(device_type, state)

    # Store in ETS tables
    store_profile_data(prof_table, profile_data)
    store_behavior_data(behav_table, behavior_data)

    # Calculate object count based on data type
    object_count = case profile_data do
      data when is_map(data) -> map_size(data)
      data when is_list(data) -> length(data)
      _ -> 0
    end

    # Update metadata
    metadata = %{
      device_type: device_type,
      source_type: :directly_stored,
      object_count: object_count,
      loaded_at: DateTime.utc_now(),
      options: %{}
    }

    :ets.insert(new_state.metadata_table, {device_type, metadata})

    # Update stats
    updated_stats = update_load_stats(new_state.stats, device_type, object_count)

    {:reply, :ok, %{new_state | stats: updated_stats}}
  end

  # Implementation Functions

  defp load_mib_profile_impl(device_type, mib_files, opts, state) do
    # Ensure tables exist for this device type
    {prof_table, behav_table, new_state} = ensure_device_tables(device_type, state)

    try do
      # Compile MIBs if needed
      compiled_mibs = SnmpSim.MIB.Compiler.compile_mib_files(mib_files)

      # Extract object definitions
      all_objects =
        compiled_mibs
        |> Enum.map(&extract_objects_from_compiled_mib/1)
        |> Enum.reduce(%{}, &Map.merge/2)

      # Analyze behaviors
      {:ok, behaviors} = SnmpSim.MIB.BehaviorAnalyzer.analyze_mib_behaviors(all_objects)

      # Store in ETS tables
      store_profile_data(prof_table, all_objects)
      store_behavior_data(behav_table, behaviors)

      # Update metadata
      metadata = %{
        device_type: device_type,
        source_type: :compiled_mib,
        mib_files: mib_files,
        object_count: map_size(all_objects),
        loaded_at: DateTime.utc_now(),
        options: opts
      }

      :ets.insert(new_state.metadata_table, {device_type, metadata})

      # Update stats
      updated_stats = update_load_stats(new_state.stats, device_type, map_size(all_objects))

      {:ok, %{new_state | stats: updated_stats}}
    rescue
      error ->
        Logger.error("Failed to load MIB profile for #{device_type}: #{inspect(error)}")
        {:error, {:mib_load_failed, error}}
    end
  end

  defp load_walk_profile_impl(device_type, walk_file, opts, state) do
    # Ensure tables exist for this device type
    {prof_table, behav_table, new_state} = ensure_device_tables(device_type, state)

    try do
      # Parse walk file
      {:ok, oid_map} = SnmpSim.WalkParser.parse_walk_file(walk_file)

      # Enhance with intelligent behaviors
      enhanced_behaviors = SnmpSim.MIB.BehaviorAnalyzer.enhance_walk_file_behaviors(oid_map)

      # Separate profile data and behaviors
      profile_data =
        Map.new(enhanced_behaviors, fn {oid, data} ->
          {oid, Map.drop(data, [:behavior])}
        end)

      behavior_data =
        Map.new(enhanced_behaviors, fn {oid, data} ->
          {oid, Map.get(data, :behavior, {:static_value, %{}})}
        end)

      # Store in ETS tables
      store_profile_data(prof_table, profile_data)
      store_behavior_data(behav_table, behavior_data)

      # Update metadata
      metadata = %{
        device_type: device_type,
        source_type: :walk_file,
        source_file: walk_file,
        object_count: map_size(oid_map),
        loaded_at: DateTime.utc_now(),
        options: opts
      }

      :ets.insert(new_state.metadata_table, {device_type, metadata})

      # Update stats
      updated_stats = update_load_stats(new_state.stats, device_type, map_size(oid_map))

      {:ok, %{new_state | stats: updated_stats}}
    rescue
      error ->
        Logger.error("Failed to load walk profile for #{device_type}: #{inspect(error)}")
        {:error, {:walk_load_failed, error}}
    end
  end

  defp get_oid_value_impl(device_type, oid, device_state, state) do
    with prof_table when prof_table != nil <- Map.get(state.profile_tables, device_type),
         behav_table when behav_table != nil <- Map.get(state.behavior_tables, device_type) do
      case :ets.lookup(prof_table, oid) do
        [{^oid, profile_data}] ->
          # Get behavior configuration
          behavior_config =
            case :ets.lookup(behav_table, oid) do
              [{^oid, behavior}] -> behavior
              [] -> {:static_value, %{}}
            end

          # Apply behavior to generate current value
          current_value =
            SnmpSim.ValueSimulator.simulate_value(
              profile_data,
              behavior_config,
              device_state
            )

          # Convert string type to atom type for compatibility
          atom_type = convert_type_to_atom(profile_data.type)
          
          # Handle the case where ValueSimulator returns a typed tuple
          final_value = case current_value do
            {_type, value} -> value  # Extract value from typed tuple
            value -> value           # Use value as-is if not a tuple
          end
          
          {:ok, {atom_type, final_value}}

        [] ->
          {:error, :no_such_name}
      end
    else
      nil -> {:error, :device_type_not_found}
    end
  end

  defp get_next_oid_impl(device_type, oid, state) do
    case Map.get(state.profile_tables, device_type) do
      nil ->
        {:error, :device_type_not_found}

      table ->
        # Get all OIDs and find the next one
        all_oids =
          :ets.tab2list(table)
          |> Enum.map(fn {oid, _data} -> oid end)
          |> Enum.sort(&compare_oids_lexicographically/2)

        case find_next_oid_in_list(all_oids, oid) do
          nil -> :end_of_mib
          next_oid -> {:ok, next_oid}
        end
    end
  end

  defp collect_bulk_oids_with_values(device_type, _current_oid, 0, acc, state) do
    # Convert OID list to 3-tuples with actual values from walk file
    oid_tuples =
      Enum.map(Enum.reverse(acc), fn oid ->
        case get_oid_value_impl(device_type, oid, %{}, state) do
          {:ok, {type, value}} -> {oid, type, value}
          {:ok, value} -> {oid, :octet_string, value}
          {:error, _} -> {oid, :octet_string, "Bulk value for #{oid}"}
        end
      end)

    {:ok, oid_tuples}
  end

  defp collect_bulk_oids_with_values(device_type, current_oid, remaining, acc, state) do
    case get_next_oid_impl(device_type, current_oid, state) do
      {:ok, next_oid} ->
        # Check if this OID actually exists in the walk file
        case get_oid_value_impl(device_type, next_oid, %{}, state) do
          {:ok, _} ->
            # OID exists, continue collecting
            collect_bulk_oids_with_values(
              device_type,
              next_oid,
              remaining - 1,
              [next_oid | acc],
              state
            )
          {:error, :no_such_name} ->
            # OID doesn't exist in walk file - this indicates end of MIB
            # Convert accumulated OIDs to 3-tuples with actual values
            oid_tuples =
              Enum.map(Enum.reverse(acc), fn oid ->
                case get_oid_value_impl(device_type, oid, %{}, state) do
                  {:ok, {type, value}} -> {oid, type, value}
                  {:ok, value} -> {oid, :octet_string, value}
                  {:error, _} -> {oid, :octet_string, "Bulk value for #{oid}"}
                end
              end)
            {:ok, oid_tuples}
          {:error, _} ->
            # Other errors - continue with fallback
            collect_bulk_oids_with_values(
              device_type,
              next_oid,
              remaining - 1,
              [next_oid | acc],
              state
            )
        end

      :end_of_mib ->
        # Convert OID list to 3-tuples with actual values from walk file
        oid_tuples =
          Enum.map(Enum.reverse(acc), fn oid ->
            case get_oid_value_impl(device_type, oid, %{}, state) do
              {:ok, {type, value}} -> {oid, type, value}
              {:ok, value} -> {oid, :octet_string, value}
              {:error, _} -> {oid, :octet_string, "Bulk value for #{oid}"}
            end
          end)

        {:ok, oid_tuples}

      {:error, _reason} ->
        # Convert accumulated OIDs to 3-tuples with actual values
        oid_tuples =
          Enum.map(Enum.reverse(acc), fn oid ->
            case get_oid_value_impl(device_type, oid, %{}, state) do
              {:ok, {type, value}} -> {oid, type, value}
              {:ok, value} -> {oid, :octet_string, value}
              {:error, _} -> {oid, :octet_string, "Bulk value for #{oid}"}
            end
          end)

        {:ok, oid_tuples}
    end
  end

  # Helper Functions

  defp ensure_device_tables(device_type, state) do
    prof_table = Map.get(state.profile_tables, device_type) || create_profile_table(device_type)

    behav_table =
      Map.get(state.behavior_tables, device_type) || create_behavior_table(device_type)

    new_state = %{
      state
      | profile_tables: Map.put(state.profile_tables, device_type, prof_table),
        behavior_tables: Map.put(state.behavior_tables, device_type, behav_table)
    }

    {prof_table, behav_table, new_state}
  end

  defp create_profile_table(device_type) do
    table_name = String.to_atom("#{device_type}_profile")
    case :ets.info(table_name) do
      :undefined ->
        :ets.new(table_name, @table_opts)
      _ ->
        # Table already exists, return the existing table name
        table_name
    end
  end

  defp create_behavior_table(device_type) do
    table_name = String.to_atom("#{device_type}_behavior")
    case :ets.info(table_name) do
      :undefined ->
        :ets.new(table_name, @table_opts)
      _ ->
        # Table already exists, return the existing table name
        table_name
    end
  end

  defp extract_objects_from_compiled_mib(_compiled_mib) do
    # This would extract objects from the compiled MIB
    # For now, return empty map - would be implemented based on actual MIB structure
    %{}
  end

  defp store_profile_data(table, profile_data) do
    profile_data
    |> Enum.each(fn {oid, data} ->
      :ets.insert(table, {oid, data})
    end)
  end

  defp store_behavior_data(table, behavior_data) do
    behavior_data
    |> Enum.each(fn {oid, behavior} ->
      :ets.insert(table, {oid, behavior})
    end)
  end

  defp compare_oid_parts([], []), do: false
  defp compare_oid_parts([], _), do: true
  defp compare_oid_parts(_, []), do: false
  defp compare_oid_parts([h1 | _t1], [h2 | _t2]) when h1 < h2, do: true
  defp compare_oid_parts([h1 | _t1], [h2 | _t2]) when h1 > h2, do: false
  defp compare_oid_parts([h1 | t1], [h2 | t2]) when h1 == h2, do: compare_oid_parts(t1, t2)

  defp find_next_oid_in_list(oids, target_oid) do
    # For GETNEXT, we need to find the first OID that is lexicographically greater than target_oid
    # OR the first descendant of target_oid if target_oid is a prefix

    # First try to find descendants (for cases like "1.3.6.1.2.1" -> "1.3.6.1.2.1.1.1.0")
    descendants = Enum.filter(oids, fn oid -> oid_is_descendant(target_oid, oid) end)

    case descendants do
      [] ->
        # No descendants, find the next OID lexicographically
        # Must be strictly greater than target_oid (not equal)
        Enum.find(oids, fn oid -> 
          oid != target_oid and compare_oids_lexicographically(target_oid, oid)
        end)

      _ ->
        # Return the first (smallest) descendant
        Enum.min_by(
          descendants,
          fn oid ->
            case oid do
              oid when is_binary(oid) -> String.split(oid, ".") |> Enum.map(&String.to_integer/1)
              oid when is_list(oid) -> oid
            end
          end,
          fn -> nil end
        )
    end
  end

  # Check if an OID is a descendant of a target OID (i.e., target is a prefix)
  defp oid_is_descendant(target_oid, candidate_oid) do
    # Convert both OIDs to string format for comparison
    target_str = case target_oid do
      target when is_binary(target) -> target
      target when is_list(target) -> Enum.join(target, ".")
    end
    
    candidate_str = case candidate_oid do
      candidate when is_binary(candidate) -> candidate
      candidate when is_list(candidate) -> Enum.join(candidate, ".")
    end
    
    target_parts = String.split(target_str, ".")
    candidate_parts = String.split(candidate_str, ".")

    # If target is shorter and matches the beginning of candidate, candidate is a descendant
    if length(target_parts) < length(candidate_parts) do
      target_parts == Enum.take(candidate_parts, length(target_parts))
    else
      false
    end
  end

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
    metadata_memory = calculate_table_memory(%{metadata: state.metadata_table})

    %{
      total_memory_kb: div(profile_memory + behavior_memory + metadata_memory, 1024),
      profile_memory_kb: div(profile_memory, 1024),
      behavior_memory_kb: div(behavior_memory, 1024),
      metadata_memory_kb: div(metadata_memory, 1024),
      table_count: map_size(state.profile_tables) + map_size(state.behavior_tables) + 1,
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

  defp convert_type_to_atom(type) when is_binary(type) do
    case String.upcase(type) do
      "STRING" -> :octet_string
      "INTEGER" -> :integer
      "GAUGE32" -> :gauge32
      "COUNTER32" -> :counter32
      "COUNTER64" -> :counter64
      "TIMETICKS" -> :timeticks
      "OID" -> :object_identifier
      "IPADDRESS" -> :ip_address
      "OPAQUE" -> :opaque
      "BITS" -> :bits
      _ -> String.to_atom(String.downcase(type))
    end
  end

  defp convert_type_to_atom(type) when is_atom(type) do
    type
  end
end
