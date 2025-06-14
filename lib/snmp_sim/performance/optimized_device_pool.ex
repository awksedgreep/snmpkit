defmodule SnmpSim.Performance.OptimizedDevicePool do
  @moduledoc """
  High-performance device pool with ETS-based caching and optimization.
  Designed for 10K+ concurrent devices with sub-millisecond lookup times.

  Features:
  - ETS-based device registry for O(1) lookups
  - Profile caching to avoid repeated profile loading
  - Connection pooling for efficient resource reuse
  - Hot/warm/cold device tiers for optimal memory usage
  - Pre-computed response caching for common OIDs
  """

  use GenServer
  require Logger

  alias SnmpSim.Device

  alias SnmpSim.Performance.ResourceManager

  # ETS table names
  @device_registry :snmp_device_registry
  @profile_cache :snmp_profile_cache
  @response_cache :snmp_response_cache
  @port_assignments :snmp_port_assignments
  @device_stats :snmp_device_stats

  # Device tiers
  # Active devices (frequent access)
  @hot_tier :hot
  # Recently used devices
  @warm_tier :warm
  # Idle devices (candidates for cleanup)
  @cold_tier :cold

  # Performance tuning
  # 5 minutes
  @cache_ttl_ms 300_000
  # Requests per tier evaluation
  @hot_access_threshold 100
  # 1 minute
  @tier_evaluation_interval 60_000
  # Max cached responses
  @response_cache_size 10_000

  defstruct [
    :device_tiers,
    :tier_timer,
    :cache_cleanup_timer,
    :port_range_start,
    :port_range_end,
    :total_devices,
    :performance_stats
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get device PID with optimized lookup (O(1) from ETS).
  Creates device lazily if it doesn't exist.
  """
  def get_device(port) when is_integer(port) do
    case :ets.lookup(@device_registry, port) do
      [{^port, device_pid, tier, _last_access}] when is_pid(device_pid) ->
        # Fast path: device exists and is alive
        if Process.alive?(device_pid) do
          update_access_time(port, tier)
          {:ok, device_pid}
        else
          # Device died, clean up and recreate
          cleanup_dead_device(port)
          create_device_optimized(port)
        end

      [] ->
        # Device doesn't exist, create it
        create_device_optimized(port)
    end
  end

  @doc """
  Get cached response for common OID requests.
  Returns {:cache_hit, response} or :cache_miss.
  """
  def get_cached_response(port, oid) do
    cache_key = {port, oid}

    case :ets.lookup(@response_cache, cache_key) do
      [{^cache_key, response, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:cache_hit, response}
        else
          :ets.delete(@response_cache, cache_key)
          :cache_miss
        end

      [] ->
        :cache_miss
    end
  end

  @doc """
  Cache response for future requests.
  """
  def cache_response(port, oid, response, ttl_ms \\ @cache_ttl_ms) do
    cache_key = {port, oid}
    expires_at = System.monotonic_time(:millisecond) + ttl_ms

    # Maintain cache size limit
    if :ets.info(@response_cache, :size) >= @response_cache_size do
      cleanup_oldest_cache_entries()
    end

    :ets.insert(@response_cache, {cache_key, response, expires_at})
  end

  @doc """
  Get device profile from cache or load it.
  """
  def get_device_profile(device_type) do
    case :ets.lookup(@profile_cache, device_type) do
      [{^device_type, profile, cached_at}] ->
        # Check if cache is still valid
        if System.monotonic_time(:millisecond) - cached_at < @cache_ttl_ms do
          profile
        else
          load_and_cache_profile(device_type)
        end

      [] ->
        load_and_cache_profile(device_type)
    end
  end

  @doc """
  Configure port assignments for device types.
  """
  def configure_port_assignments(assignments) do
    GenServer.call(__MODULE__, {:configure_port_assignments, assignments})
  end

  @doc """
  Get performance statistics for monitoring.
  """
  def get_performance_stats() do
    GenServer.call(__MODULE__, :get_performance_stats)
  end

  @doc """
  Promote device to hot tier for frequent access optimization.
  """
  def promote_to_hot_tier(port) do
    case :ets.lookup(@device_registry, port) do
      [{^port, device_pid, _current_tier, last_access}] ->
        :ets.insert(@device_registry, {port, device_pid, @hot_tier, last_access})
        increment_tier_stat(@hot_tier)
        :ok

      [] ->
        {:error, :device_not_found}
    end
  end

  @doc """
  Force cleanup of cold tier devices.
  """
  def cleanup_cold_devices() do
    GenServer.call(__MODULE__, :cleanup_cold_devices)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Create ETS tables for high-performance lookups
    :ets.new(@device_registry, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@profile_cache, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@response_cache, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@port_assignments, [:named_table, :public, :set, {:read_concurrency, true}])
    :ets.new(@device_stats, [:named_table, :public, :set, {:write_concurrency, true}])

    # Initialize performance counters
    init_performance_counters()

    # Schedule periodic tier evaluation and cache cleanup
    tier_timer = Process.send_after(self(), :evaluate_device_tiers, @tier_evaluation_interval)
    cache_timer = Process.send_after(self(), :cleanup_expired_cache, @cache_ttl_ms)

    port_range_start = Keyword.get(opts, :port_range_start, 30_000)
    port_range_end = Keyword.get(opts, :port_range_end, 39_999)

    state = %__MODULE__{
      device_tiers: %{@hot_tier => 0, @warm_tier => 0, @cold_tier => 0},
      tier_timer: tier_timer,
      cache_cleanup_timer: cache_timer,
      port_range_start: port_range_start,
      port_range_end: port_range_end,
      total_devices: 0,
      performance_stats: initialize_performance_stats()
    }

    Logger.info(
      "OptimizedDevicePool started with port range #{port_range_start}-#{port_range_end}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:configure_port_assignments, assignments}, _from, state) do
    Enum.each(assignments, fn {device_type, port_range} ->
      :ets.insert(@port_assignments, {device_type, port_range})
    end)

    Logger.info("Configured port assignments for #{length(assignments)} device types")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_performance_stats, _from, state) do
    ets_stats = %{
      device_registry_size: :ets.info(@device_registry, :size),
      profile_cache_size: :ets.info(@profile_cache, :size),
      response_cache_size: :ets.info(@response_cache, :size),
      cache_hit_ratio: calculate_cache_hit_ratio(),
      device_tiers: state.device_tiers,
      total_devices: state.total_devices
    }

    combined_stats = Map.merge(state.performance_stats, ets_stats)
    {:reply, combined_stats, state}
  end

  @impl true
  def handle_call(:cleanup_cold_devices, _from, state) do
    cold_devices = get_devices_by_tier(@cold_tier)
    cleaned_count = cleanup_devices(cold_devices)

    new_tiers = Map.update!(state.device_tiers, @cold_tier, &(&1 - cleaned_count))

    new_state = %{
      state
      | device_tiers: new_tiers,
        total_devices: state.total_devices - cleaned_count
    }

    Logger.info("Cleaned up #{cleaned_count} cold tier devices")
    {:reply, {:ok, cleaned_count}, new_state}
  end

  @impl true
  def handle_info(:evaluate_device_tiers, state) do
    # Evaluate device access patterns and adjust tiers
    {promoted, demoted} = evaluate_and_adjust_tiers()

    new_tiers = update_tier_counts(state.device_tiers, promoted, demoted)
    new_stats = update_tier_evaluation_stats(state.performance_stats, promoted, demoted)

    # Schedule next evaluation
    tier_timer = Process.send_after(self(), :evaluate_device_tiers, @tier_evaluation_interval)

    new_state = %{
      state
      | device_tiers: new_tiers,
        tier_timer: tier_timer,
        performance_stats: new_stats
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_expired_cache, state) do
    # Clean up expired cache entries
    cleanup_expired_responses()
    cleanup_expired_profiles()

    # Schedule next cleanup
    cache_timer = Process.send_after(self(), :cleanup_expired_cache, @cache_ttl_ms)

    {:noreply, %{state | cache_cleanup_timer: cache_timer}}
  end

  # Private functions

  defp create_device_optimized(port) do
    # Check resource limits before creating device
    case ResourceManager.can_allocate_device?() do
      true ->
        device_type = determine_device_type(port)
        profile = get_device_profile(device_type)

        case Device.start_link(%{
               port: port,
               device_type: device_type,
               device_id: "device_#{port}",
               community: Map.get(profile, :community, "public")
             }) do
          {:ok, device_pid} ->
            # Register device in ETS for fast lookup
            current_time = System.monotonic_time(:millisecond)
            :ets.insert(@device_registry, {port, device_pid, @warm_tier, current_time})

            # Register with resource manager
            ResourceManager.register_device(device_pid, device_type)

            # Update statistics
            increment_tier_stat(@warm_tier)
            increment_performance_stat(:devices_created)

            {:ok, device_pid}

          {:error, reason} ->
            Logger.error("Failed to create device on port #{port}: #{inspect(reason)}")
            {:error, reason}
        end

      false ->
        {:error, :resource_limit_exceeded}
    end
  end

  defp cleanup_dead_device(port) do
    :ets.delete(@device_registry, port)
    # Assume it was in warm tier
    decrement_tier_stat(@warm_tier)
    increment_performance_stat(:devices_cleaned)
  end

  defp update_access_time(port, tier) do
    current_time = System.monotonic_time(:millisecond)

    case :ets.lookup(@device_registry, port) do
      [{^port, _device_pid, ^tier, _}] ->
        :ets.update_element(@device_registry, port, {4, current_time})
        increment_performance_stat(:device_accesses)

      [] ->
        :ok
    end
  end

  defp load_and_cache_profile(device_type) do
    # Try to get profile from SharedProfiles, fallback to default profile
    profile =
      try do
        case SnmpSim.MIB.SharedProfiles.get_oid_value(device_type, "1.3.6.1.2.1.1.1.0", %{}) do
          {:ok, _} ->
            # SharedProfiles has data for this device type, create a simple profile
            %{device_type: device_type, has_data: true}

          _ ->
            create_default_profile(device_type)
        end
      catch
        _type, _error ->
          # SharedProfiles not available or device type not found, use default profile
          create_default_profile(device_type)
      end

    current_time = System.monotonic_time(:millisecond)
    :ets.insert(@profile_cache, {device_type, profile, current_time})
    increment_performance_stat(:profile_loads)
    profile
  end

  defp create_default_profile(device_type) do
    %{
      device_type: device_type,
      has_data: false,
      # Default walk file
      walk_file: "priv/walks/cable_modem.walk",
      community: "public"
    }
  end

  defp determine_device_type(port) do
    # Look up device type by port range
    case :ets.match(@port_assignments, {~c"$1", ~c"$2"}) do
      [] ->
        :default_device

      assignments ->
        Enum.find_value(assignments, :default_device, fn [device_type, port_range] ->
          if port in port_range, do: device_type
        end)
    end
  end

  defp cleanup_oldest_cache_entries() do
    # Remove 10% of oldest cache entries to make room
    all_entries = :ets.tab2list(@response_cache)
    sorted_entries = Enum.sort_by(all_entries, fn {_, _, expires_at} -> expires_at end)

    entries_to_remove = Enum.take(sorted_entries, div(length(sorted_entries), 10))

    Enum.each(entries_to_remove, fn {cache_key, _, _} ->
      :ets.delete(@response_cache, cache_key)
    end)
  end

  defp evaluate_and_adjust_tiers() do
    current_time = System.monotonic_time(:millisecond)
    all_devices = :ets.tab2list(@device_registry)

    {promoted, demoted} =
      Enum.reduce(all_devices, {[], []}, fn {port, _device_pid, tier, last_access},
                                            {prom_acc, dem_acc} ->
        idle_time = current_time - last_access
        access_frequency = get_access_frequency(port)

        new_tier = determine_optimal_tier(tier, idle_time, access_frequency)

        if new_tier != tier do
          :ets.update_element(@device_registry, port, {3, new_tier})

          if tier_rank(new_tier) > tier_rank(tier) do
            {[{port, tier, new_tier} | prom_acc], dem_acc}
          else
            {prom_acc, [{port, tier, new_tier} | dem_acc]}
          end
        else
          {prom_acc, dem_acc}
        end
      end)

    {promoted, demoted}
  end

  defp determine_optimal_tier(current_tier, idle_time, access_frequency) do
    cond do
      access_frequency > @hot_access_threshold and idle_time < 300_000 ->
        @hot_tier

      access_frequency > 10 and idle_time < 1_800_000 ->
        @warm_tier

      idle_time > 3_600_000 ->
        @cold_tier

      true ->
        current_tier
    end
  end

  defp get_access_frequency(port) do
    case :ets.lookup(@device_stats, {:access_frequency, port}) do
      [{_, frequency}] -> frequency
      [] -> 0
    end
  end

  defp tier_rank(@hot_tier), do: 3
  defp tier_rank(@warm_tier), do: 2
  defp tier_rank(@cold_tier), do: 1

  defp get_devices_by_tier(tier) do
    :ets.match(@device_registry, {~c"$1", ~c"$2", tier, ~c"$3"})
  end

  defp cleanup_devices(device_list) do
    Enum.reduce(device_list, 0, fn [port, device_pid, _last_access], count ->
      case Device.stop(device_pid) do
        :ok ->
          :ets.delete(@device_registry, port)
          ResourceManager.unregister_device(device_pid)
          count + 1

        {:error, _reason} ->
          count
      end
    end)
  end

  defp cleanup_expired_responses() do
    current_time = System.monotonic_time(:millisecond)

    # Find and delete expired entries
    :ets.select_delete(@response_cache, [
      {{~c"$1", ~c"$2", ~c"$3"}, [{:<, ~c"$3", current_time}], [true]}
    ])
  end

  defp cleanup_expired_profiles() do
    current_time = System.monotonic_time(:millisecond)
    expired_threshold = current_time - @cache_ttl_ms

    :ets.select_delete(@profile_cache, [
      {{~c"$1", ~c"$2", ~c"$3"}, [{:<, ~c"$3", expired_threshold}], [true]}
    ])
  end

  defp init_performance_counters() do
    counters = [
      :devices_created,
      :devices_cleaned,
      :device_accesses,
      :profile_loads,
      :cache_hits,
      :cache_misses,
      :tier_promotions,
      :tier_demotions
    ]

    Enum.each(counters, fn counter ->
      :ets.insert(@device_stats, {counter, 0})
    end)
  end

  defp increment_performance_stat(stat) do
    :ets.update_counter(@device_stats, stat, {2, 1}, {stat, 0})
  end

  defp increment_tier_stat(tier) do
    increment_performance_stat({:tier_count, tier})
  end

  defp decrement_tier_stat(tier) do
    :ets.update_counter(@device_stats, {:tier_count, tier}, {2, -1}, {{:tier_count, tier}, 0})
  end

  defp calculate_cache_hit_ratio() do
    hits = get_stat_value(:cache_hits)
    misses = get_stat_value(:cache_misses)
    total = hits + misses

    if total > 0 do
      Float.round(hits / total * 100, 2)
    else
      0.0
    end
  end

  defp get_stat_value(stat) do
    case :ets.lookup(@device_stats, stat) do
      [{^stat, value}] -> value
      [] -> 0
    end
  end

  defp update_tier_counts(current_tiers, promoted, demoted) do
    # Update tier counts based on promotions and demotions
    Enum.reduce(promoted ++ demoted, current_tiers, fn {_port, old_tier, new_tier}, acc ->
      acc
      |> Map.update!(old_tier, &(&1 - 1))
      |> Map.update!(new_tier, &(&1 + 1))
    end)
  end

  defp update_tier_evaluation_stats(stats, promoted, demoted) do
    %{
      stats
      | tier_promotions: stats.tier_promotions + length(promoted),
        tier_demotions: stats.tier_demotions + length(demoted),
        last_tier_evaluation: System.monotonic_time(:millisecond)
    }
  end

  defp initialize_performance_stats() do
    %{
      devices_created: 0,
      devices_cleaned: 0,
      device_accesses: 0,
      profile_loads: 0,
      cache_hits: 0,
      cache_misses: 0,
      tier_promotions: 0,
      tier_demotions: 0,
      last_tier_evaluation: System.monotonic_time(:millisecond)
    }
  end
end
