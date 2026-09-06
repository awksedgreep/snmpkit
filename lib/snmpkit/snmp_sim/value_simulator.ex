defmodule SnmpKit.SnmpSim.ValueSimulator do
  @moduledoc """
  Generate realistic values based on MIB-derived behavior patterns.
  Supports counters, gauges, enums, and correlated metrics with time-based variations.
  """

  alias SnmpKit.SnmpSim.TimePatterns
  alias SnmpKit.SnmpSim.ValueSimulator.{Counters, Patterns, Variance}

  @doc """
  Simulate a value based on profile data, behavior configuration, and device state.

  ## Examples

      # Traffic counter simulation
      value = SnmpKit.SnmpSim.ValueSimulator.simulate_value(
        %{type: "Counter32", value: 1000000},
        {:traffic_counter, %{rate_range: {1000, 125_000_000}}},
        %{device_id: "cm_001", uptime: 3600, interface_utilization: 0.3}
      )

  """
  def simulate_value(profile_data, behavior_config, device_state) do
    current_time = DateTime.utc_now()

    # Values are reproducible: the process RNG is seeded from the device, the
    # object and (for gauges) the current minute, then restored. Counters use a
    # time-free seed so their random factors are constant and the value only
    # grows with uptime; a fresh random draw per GET made counters step
    # backwards between polls and made tests non-deterministic.
    previous_seed = :rand.export_seed()

    :rand.seed(
      :exsss,
      deterministic_seed(profile_data, behavior_config, device_state, current_time)
    )

    try do
      do_simulate_value(profile_data, behavior_config, device_state, current_time)
    after
      restore_seed(previous_seed)
    end
  end

  @counter_behaviors [:traffic_counter, :packet_counter, :error_counter, :uptime_counter]

  defp deterministic_seed(profile_data, behavior_config, device_state, current_time) do
    device_id = Map.get(device_state, :device_id) || Map.get(device_state, :port) || :default
    behavior = if is_tuple(behavior_config), do: elem(behavior_config, 0), else: behavior_config
    object = {Map.get(profile_data, :type), Map.get(profile_data, :value)}

    bucket =
      if behavior in @counter_behaviors,
        do: :constant,
        else:
          {current_time.year, current_time.month, current_time.day, current_time.hour,
           current_time.minute}

    hash = :erlang.phash2({device_id, behavior, object, bucket}, 1_000_000_007)

    {hash, :erlang.phash2({object, device_id}, 1_000_000_007),
     :erlang.phash2({behavior, bucket}, 1_000_000_007)}
  end

  defp restore_seed(:undefined), do: :erlang.erase(:rand_seed)
  defp restore_seed(seed), do: :rand.seed(seed)

  defp do_simulate_value(profile_data, behavior_config, device_state, current_time) do
    case behavior_config do
      {:traffic_counter, config} ->
        simulate_traffic_counter(profile_data, config, device_state, current_time)

      {:packet_counter, config} ->
        simulate_packet_counter(profile_data, config, device_state, current_time)

      {:error_counter, config} ->
        simulate_error_counter(profile_data, config, device_state, current_time)

      {:utilization_gauge, config} ->
        simulate_utilization_gauge(profile_data, config, device_state, current_time)

      {:cpu_gauge, config} ->
        simulate_cpu_gauge(profile_data, config, device_state, current_time)

      {:power_gauge, config} ->
        simulate_power_gauge(profile_data, config, device_state, current_time)

      {:snr_gauge, config} ->
        simulate_snr_gauge(profile_data, config, device_state, current_time)

      {:signal_gauge, config} ->
        simulate_signal_gauge(profile_data, config, device_state, current_time)

      {:temperature_gauge, config} ->
        simulate_temperature_gauge(profile_data, config, device_state, current_time)

      {:uptime_counter, config} ->
        simulate_uptime_counter(profile_data, config, device_state, current_time)

      {:status_enum, config} ->
        simulate_status_enum(profile_data, config, device_state, current_time)

      {:static_value, _config} ->
        # Return the original value from the profile
        format_static_value(profile_data)

      _ ->
        # Unknown behavior, return static value
        format_static_value(profile_data)
    end
  end

  # Traffic Counter Simulation
  defp simulate_traffic_counter(profile_data, config, device_state, current_time) do
    base_value = get_base_counter_value(profile_data)
    uptime_seconds = Map.get(device_state, :uptime, 0)
    device_type = Map.get(device_state, :device_type, :unknown)

    # Get device-specific traffic characteristics
    traffic_config = Patterns.get_traffic_config_for_device(device_type, config)

    # Calculate rate based on time of day and utilization patterns
    daily_factor = TimePatterns.get_daily_utilization_pattern(current_time)
    weekly_factor = TimePatterns.get_weekly_pattern(current_time)
    interface_utilization = Map.get(device_state, :interface_utilization, 0.3)

    # Base rate configuration with device-specific ranges
    {min_rate, max_rate} = Map.get(traffic_config, :rate_range, {1000, 10_000_000})

    # Calculate current rate with multiple factors
    utilization_rate = min_rate + (max_rate - min_rate) * interface_utilization
    temporal_rate = utilization_rate * daily_factor * weekly_factor

    # Add device-specific traffic patterns
    device_pattern_factor = Patterns.get_device_traffic_pattern(device_type, current_time)
    pattern_adjusted_rate = temporal_rate * device_pattern_factor

    # Add realistic variance and bursts
    variance = Variance.add_realistic_variance(pattern_adjusted_rate, traffic_config)
    burst_factor = Variance.apply_burst_pattern(traffic_config, current_time, device_type)

    current_rate = pattern_adjusted_rate * variance * burst_factor

    # Calculate total increment based on uptime with rate smoothing
    increment_rate = Variance.apply_rate_smoothing(current_rate, device_state, traffic_config)
    total_increment = trunc(increment_rate * uptime_seconds)

    # Calculate new counter value
    new_value = base_value + total_increment

    # Apply device-specific counter behavior including wrapping
    final_value =
      Counters.apply_device_specific_counter_behavior(
        new_value,
        profile_data.type,
        device_type,
        traffic_config
      )

    format_counter_value(final_value, profile_data.type)
  end

  # Packet Counter Simulation
  defp simulate_packet_counter(profile_data, config, device_state, current_time) do
    base_value = get_base_counter_value(profile_data)
    uptime_seconds = Map.get(device_state, :uptime, 0)

    # Packet counters often correlate with traffic counters
    correlation_oid = Map.get(config, :correlation_with)
    correlation_factor = get_correlation_factor(correlation_oid, device_state)

    # Base packet rate
    {min_pps, max_pps} = Map.get(config, :rate_range, {10, 100_000})
    daily_factor = TimePatterns.get_daily_utilization_pattern(current_time)

    base_pps = min_pps + (max_pps - min_pps) * daily_factor * correlation_factor

    # Add packet-specific variance (more bursty than byte counters)
    packet_variance = Variance.add_packet_variance(base_pps, config)

    total_packets = trunc(base_pps * packet_variance * uptime_seconds)
    final_value = Counters.apply_counter_wrapping(base_value + total_packets, profile_data.type)

    format_counter_value(final_value, profile_data.type)
  end

  # Error Counter Simulation
  defp simulate_error_counter(profile_data, config, device_state, _current_time) do
    base_value = get_base_counter_value(profile_data)
    uptime_seconds = Map.get(device_state, :uptime, 0)

    # Error rates correlate with utilization and environmental factors
    utilization = Map.get(device_state, :interface_utilization, 0.3)
    signal_quality = Map.get(device_state, :signal_quality, 1.0)

    # Base error rate (much lower than traffic)
    {min_rate, max_rate} = Map.get(config, :rate_range, {0, 100})

    # Higher utilization and poor signal quality increase errors
    error_factor = utilization * 0.7 + (1.0 - signal_quality) * 0.3
    base_error_rate = min_rate + (max_rate - min_rate) * error_factor

    # Sporadic burst patterns for errors
    burst_probability = Map.get(config, :error_burst_probability, 0.05)
    burst_factor = if :rand.uniform() < burst_probability, do: 10, else: 1

    current_error_rate = base_error_rate * burst_factor
    # Errors per hour
    total_errors = trunc(current_error_rate * uptime_seconds / 3600)

    final_value = Counters.apply_counter_wrapping(base_value + total_errors, profile_data.type)
    format_counter_value(final_value, profile_data.type)
  end

  # Utilization Gauge Simulation
  defp simulate_utilization_gauge(profile_data, config, device_state, current_time) do
    base_value = get_base_gauge_value(profile_data)

    # Get daily utilization pattern
    daily_pattern = TimePatterns.get_daily_utilization_pattern(current_time)

    # Apply weekly patterns (weekends are typically different)
    weekly_factor = TimePatterns.get_weekly_pattern(current_time)

    # Device-specific factors
    device_factor = Map.get(device_state, :utilization_bias, 1.0)

    # Calculate current utilization
    target_utilization = base_value * daily_pattern * weekly_factor * device_factor

    # Apply smooth transitions and variance
    current_utilization =
      Variance.apply_smooth_transition(target_utilization, device_state, config)

    # Apply configurable jitter
    device_type = Map.get(device_state, :device_type, :unknown)
    jitter_config = Map.get(config, :jitter, %{})

    jittered_utilization =
      Variance.apply_configurable_jitter(
        current_utilization,
        :utilization_gauge,
        device_type,
        jitter_config
      )

    # Clamp to valid range
    clamped_value = max(0, min(100, jittered_utilization))

    format_gauge_value(clamped_value, profile_data.type)
  end

  # CPU Gauge Simulation
  defp simulate_cpu_gauge(profile_data, config, device_state, current_time) do
    base_cpu = get_base_gauge_value(profile_data)

    # CPU usage often correlates with network activity
    network_utilization = Map.get(device_state, :interface_utilization, 0.3)

    # Time-based patterns
    daily_factor = TimePatterns.get_daily_utilization_pattern(current_time)

    # CPU has different patterns than network utilization
    cpu_factor = 0.3 + network_utilization * 0.4 + daily_factor * 0.3

    # Add CPU-specific spikes
    spike_probability = 0.02
    spike_factor = if :rand.uniform() < spike_probability, do: 2.0, else: 1.0

    current_cpu = base_cpu * cpu_factor * spike_factor

    # Apply configurable jitter for CPU
    device_type = Map.get(device_state, :device_type, :unknown)
    jitter_config = Map.get(config, :jitter, %{})

    jittered_cpu =
      Variance.apply_configurable_jitter(
        current_cpu,
        :cpu_gauge,
        device_type,
        jitter_config
      )

    clamped_cpu = max(0, min(100, jittered_cpu))

    format_gauge_value(clamped_cpu, profile_data.type)
  end

  # Power Gauge Simulation (DOCSIS)
  defp simulate_power_gauge(profile_data, config, device_state, current_time) do
    base_power = get_base_gauge_value(profile_data)

    # Power levels affected by signal quality and environmental factors
    signal_quality = Map.get(device_state, :signal_quality, 1.0)
    temperature = Map.get(device_state, :temperature, 25.0)

    # Environmental correlation
    # 1% per degree
    temp_factor = 1.0 + (temperature - 25.0) * 0.01

    # Signal quality correlation
    quality_factor = 0.8 + signal_quality * 0.4

    # Weather patterns (simplified)
    weather_factor = TimePatterns.apply_weather_variation(current_time)

    current_power = base_power * temp_factor * quality_factor * weather_factor

    # Apply power level constraints
    {min_power, max_power} = Map.get(config, :range, {-15, 15})
    clamped_power = max(min_power, min(max_power, current_power))

    format_gauge_value(clamped_power, profile_data.type)
  end

  # SNR Gauge Simulation
  defp simulate_snr_gauge(profile_data, _config, device_state, current_time) do
    base_snr = get_base_gauge_value(profile_data)

    # SNR inversely correlates with utilization and environmental factors
    utilization = Map.get(device_state, :interface_utilization, 0.3)

    # Higher utilization typically means lower SNR
    utilization_impact = 1.0 - utilization * 0.2

    # Weather and environmental impact
    weather_factor = TimePatterns.apply_weather_variation(current_time)
    environmental_factor = 0.9 + weather_factor * 0.2

    # Add realistic noise
    noise_factor = 0.95 + :rand.uniform() * 0.1

    current_snr = base_snr * utilization_impact * environmental_factor * noise_factor

    # SNR typically ranges from 10-40 dB
    clamped_snr = max(10, min(40, current_snr))

    format_gauge_value(clamped_snr, profile_data.type)
  end

  # Signal Gauge Simulation
  defp simulate_signal_gauge(profile_data, config, device_state, current_time) do
    base_signal = get_base_gauge_value(profile_data)

    # Signal strength varies with environmental conditions
    weather_impact = TimePatterns.apply_weather_variation(current_time)
    distance_factor = Map.get(device_state, :distance_factor, 1.0)

    # Signal degrades with distance and weather
    signal_factor = weather_impact * distance_factor

    current_signal = base_signal * signal_factor

    # Apply signal-specific constraints
    {min_signal, max_signal} = Map.get(config, :range, {-20, 20})
    clamped_signal = max(min_signal, min(max_signal, current_signal))

    format_gauge_value(clamped_signal, profile_data.type)
  end

  # Temperature Gauge Simulation
  defp simulate_temperature_gauge(profile_data, _config, device_state, current_time) do
    base_temp = get_base_gauge_value(profile_data)

    # Temperature varies with time of day and seasonal patterns
    daily_temp_variation = TimePatterns.get_daily_temperature_pattern(current_time)
    seasonal_variation = TimePatterns.get_seasonal_temperature_pattern(current_time)

    # Device load affects internal temperature
    cpu_load = Map.get(device_state, :cpu_utilization, 0.3)
    # 10% increase at full load
    load_factor = 1.0 + cpu_load * 0.1

    current_temp = base_temp + daily_temp_variation + seasonal_variation
    current_temp = current_temp * load_factor

    # Reasonable temperature range
    clamped_temp = max(-10, min(85, current_temp))

    format_gauge_value(clamped_temp, profile_data.type)
  end

  # Uptime Counter Simulation
  defp simulate_uptime_counter(_profile_data, _config, device_state, _current_time) do
    uptime_seconds = Map.get(device_state, :uptime, 0)

    # SNMP sysUpTime is in TimeTicks (1/100th of a second)
    uptime_timeticks = uptime_seconds * 100

    # Apply 32-bit wrapping for TimeTicks
    wrapped_timeticks = rem(uptime_timeticks, 4_294_967_296)

    {:timeticks, wrapped_timeticks}
  end

  # Status Enumeration Simulation
  defp simulate_status_enum(profile_data, _config, device_state, _current_time) do
    base_status = get_base_enum_value(profile_data)

    # Status can change based on device health
    device_health = Map.get(device_state, :health_score, 1.0)
    error_rate = Map.get(device_state, :error_rate, 0.0)

    # Determine current status based on health metrics
    current_status =
      case {device_health, error_rate} do
        {health, _} when health < 0.5 -> "down"
        {_, error} when error > 0.1 -> "degraded"
        {health, _} when health >= 0.9 -> "up"
        _ -> base_status
      end

    format_enum_value(current_status, profile_data.type)
  end

  # Helper Functions

  defp get_base_counter_value(profile_data) do
    case profile_data.value do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  defp get_base_gauge_value(profile_data) do
    case profile_data.value do
      value when is_number(value) -> value
      # Default gauge value
      _ -> 50.0
    end
  end

  defp get_base_enum_value(profile_data) do
    case profile_data.value do
      value when is_binary(value) -> value
      value when is_integer(value) -> value
      _ -> "up"
    end
  end

  defp get_correlation_factor(nil, _device_state), do: 1.0

  defp get_correlation_factor(correlation_oid, device_state) do
    # Get value from correlated OID (simplified)
    Map.get(device_state, :correlation_factors, %{})
    |> Map.get(correlation_oid, 1.0)
  end

  defp format_static_value(profile_data) when is_map(profile_data) do
    # Handle both atom and string keys for backward compatibility
    data_type = Map.get(profile_data, :type) || Map.get(profile_data, "type")
    data_value = Map.get(profile_data, :value) || Map.get(profile_data, "value")

    case data_type do
      nil ->
        # No type specified, return the value as-is or try to infer
        case data_value do
          nil -> nil
          val when is_binary(val) -> val
          val when is_integer(val) -> val
          _ -> to_string(data_value)
        end

      type_str when is_binary(type_str) ->
        case String.downcase(type_str) do
          "counter32" -> {:counter32, data_value || 0}
          "counter64" -> {:counter64, data_value || 0}
          "gauge32" -> {:gauge32, data_value || 0}
          "gauge" -> {:gauge32, data_value || 0}
          "timeticks" -> {:timeticks, data_value || 0}
          "integer" -> data_value || 0
          "string" -> to_string(data_value || "")
          # Preserve OID list format
          "object_identifier" -> data_value
          # Preserve OID list format (alternate name)
          "oid" -> data_value
          _ -> to_string(data_value || "")
        end

      :object_identifier ->
        # Handle atom type for object_identifier - preserve list format
        data_value

      _ ->
        # Type is not a string, return value as-is
        data_value || nil
    end
  end

  defp format_counter_value(value, type) do
    case String.downcase(type) do
      "counter32" -> {:counter32, value}
      "counter64" -> {:counter64, value}
      _ -> value
    end
  end

  defp format_gauge_value(value, type) do
    case String.downcase(type) do
      "gauge32" -> {:gauge32, trunc(value)}
      "gauge" -> {:gauge32, trunc(value)}
      _ -> trunc(value)
    end
  end

  defp format_enum_value(value, _type) do
    cond do
      is_binary(value) -> value
      is_integer(value) -> value
      true -> to_string(value)
    end
  end

  # Device-Specific Traffic Patterns

  # Advanced Variance and Jitter Functions
end
