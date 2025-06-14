defmodule SnmpSim.ValueSimulator do
  @moduledoc """
  Generate realistic values based on MIB-derived behavior patterns.
  Supports counters, gauges, enums, and correlated metrics with time-based variations.
  """

  alias SnmpSim.TimePatterns

  @doc """
  Simulate a value based on profile data, behavior configuration, and device state.

  ## Examples

      # Traffic counter simulation
      value = SnmpSim.ValueSimulator.simulate_value(
        %{type: "Counter32", value: 1000000},
        {:traffic_counter, %{rate_range: {1000, 125_000_000}}},
        %{device_id: "cm_001", uptime: 3600, interface_utilization: 0.3}
      )
      
  """
  def simulate_value(profile_data, behavior_config, device_state) do
    current_time = DateTime.utc_now()

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
    traffic_config = get_traffic_config_for_device(device_type, config)

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
    device_pattern_factor = get_device_traffic_pattern(device_type, current_time)
    pattern_adjusted_rate = temporal_rate * device_pattern_factor

    # Add realistic variance and bursts
    variance = add_realistic_variance(pattern_adjusted_rate, traffic_config)
    burst_factor = apply_burst_pattern(traffic_config, current_time, device_type)

    current_rate = pattern_adjusted_rate * variance * burst_factor

    # Calculate total increment based on uptime with rate smoothing
    increment_rate = apply_rate_smoothing(current_rate, device_state, traffic_config)
    total_increment = trunc(increment_rate * uptime_seconds)

    # Calculate new counter value
    new_value = base_value + total_increment

    # Apply device-specific counter behavior including wrapping
    final_value =
      apply_device_specific_counter_behavior(
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
    packet_variance = add_packet_variance(base_pps, config)

    total_packets = trunc(base_pps * packet_variance * uptime_seconds)
    final_value = apply_counter_wrapping(base_value + total_packets, profile_data.type)

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

    final_value = apply_counter_wrapping(base_value + total_errors, profile_data.type)
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
    current_utilization = apply_smooth_transition(target_utilization, device_state, config)

    # Apply configurable jitter
    device_type = Map.get(device_state, :device_type, :unknown)
    jitter_config = Map.get(config, :jitter, %{})

    jittered_utilization =
      apply_configurable_jitter(
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
      apply_configurable_jitter(
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

  defp add_realistic_variance(base_rate, config) do
    variance_type = Map.get(config, :variance_type, :uniform)
    variance_factor = Map.get(config, :variance, 0.1)

    case variance_type do
      :uniform ->
        # Standard uniform variance (original behavior)
        1.0 + (:rand.uniform() - 0.5) * 2 * variance_factor

      :gaussian ->
        # Gaussian/normal distribution variance
        apply_gaussian_variance(variance_factor)

      :burst ->
        # Burst-based variance with occasional spikes
        apply_burst_variance(variance_factor, config)

      :time_correlated ->
        # Time-correlated variance that changes gradually
        apply_time_correlated_variance(base_rate, variance_factor, config)

      :device_specific ->
        # Device-specific variance patterns
        device_type = Map.get(config, :device_type, :unknown)
        apply_device_specific_variance(device_type, variance_factor)

      _ ->
        # Default to uniform
        1.0 + (:rand.uniform() - 0.5) * 2 * variance_factor
    end
  end

  defp add_packet_variance(_base_pps, _config) do
    # Packet counters are more bursty than byte counters
    # 85% to 115%
    burst_factor = :rand.uniform() * 0.3 + 0.85
    burst_factor
  end

  defp apply_burst_pattern(config, current_time, device_type) do
    burst_probability = Map.get(config, :burst_probability, 0.1)

    # Device-specific burst patterns
    device_burst_factor =
      case device_type do
        # Moderate bursts for residential
        :cable_modem -> 1.5
        # High bursts during peak aggregation
        :cmts -> 3.0
        # Network equipment bursts
        :switch -> 2.0
        # Routing bursts
        :router -> 2.5
        # Server workload bursts
        :server -> 4.0
        _ -> 2.0
      end

    # Time-based burst patterns
    minute = current_time.minute
    hour = current_time.hour

    # Peak hour burst probability increases
    time_burst_probability =
      if hour >= 19 and hour <= 22 do
        # Evening peak
        burst_probability * 2.0
      else
        burst_probability
      end

    # Check if we're in a burst period
    if rem(minute, 10) == 0 and :rand.uniform() < time_burst_probability do
      device_burst_factor
    else
      1.0
    end
  end

  defp get_correlation_factor(nil, _device_state), do: 1.0

  defp get_correlation_factor(correlation_oid, device_state) do
    # Get value from correlated OID (simplified)
    Map.get(device_state, :correlation_factors, %{})
    |> Map.get(correlation_oid, 1.0)
  end

  defp apply_smooth_transition(target_value, device_state, _config) do
    previous_value = Map.get(device_state, :previous_utilization, target_value)

    # Smooth transition to prevent abrupt changes
    smoothing_factor = 0.1
    previous_value + (target_value - previous_value) * smoothing_factor
  end

  defp apply_counter_wrapping(value, type) do
    case String.downcase(type) do
      "counter32" ->
        handle_counter32_wrapping(value)

      "counter64" ->
        handle_counter64_wrapping(value)

      _ ->
        value
    end
  end

  defp handle_counter32_wrapping(value) do
    # 32-bit counter: 0 to 4,294,967,295 (2^32 - 1)
    max_value = 4_294_967_296

    cond do
      value < 0 ->
        # Handle negative values (shouldn't happen but be defensive)
        0

      value >= max_value ->
        # Wrap around: simulate realistic counter wrapping behavior
        wrapped_value = rem(value, max_value)
        # Add small random variation to simulate real hardware behavior
        jitter = trunc((:rand.uniform() - 0.5) * 10)
        max(0, wrapped_value + jitter)

      true ->
        value
    end
  end

  defp handle_counter64_wrapping(value) do
    # 64-bit counter: 0 to 18,446,744,073,709,551,615 (2^64 - 1)
    max_value = 18_446_744_073_709_551_616

    cond do
      value < 0 ->
        0

      value >= max_value ->
        # 64-bit counters rarely wrap in practice, but handle it properly
        wrapped_value = rem(value, max_value)
        # Minimal jitter for 64-bit counters
        jitter = trunc((:rand.uniform() - 0.5) * 2)
        max(0, wrapped_value + jitter)

      true ->
        value
    end
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
          "object_identifier" -> data_value  # Preserve OID list format
          "oid" -> data_value  # Preserve OID list format (alternate name)
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

  defp format_static_value(profile_data) do
    # Handle non-map data (fallback for direct values)
    profile_data
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

  defp get_traffic_config_for_device(device_type, base_config) do
    device_specific =
      case device_type do
        :cable_modem ->
          %{
            # 8KB/s to 100MB/s
            rate_range: {8_000, 100_000_000},
            # 15% variance
            variance: 0.15,
            # 10% burst chance
            burst_probability: 0.1,
            # Moderate smoothing
            smoothing_factor: 0.2
          }

        :mta ->
          %{
            # 1KB/s to 10MB/s (voice traffic)
            rate_range: {1_000, 10_000_000},
            # 5% variance (voice is steady)
            variance: 0.05,
            # 2% burst chance
            burst_probability: 0.02,
            # High smoothing for voice
            smoothing_factor: 0.1
          }

        :switch ->
          %{
            # 100KB/s to 1GB/s
            rate_range: {100_000, 1_000_000_000},
            # 25% variance
            variance: 0.25,
            # 15% burst chance
            burst_probability: 0.15,
            # Less smoothing for switches
            smoothing_factor: 0.3
          }

        :router ->
          %{
            # 500KB/s to 10GB/s
            rate_range: {500_000, 10_000_000_000},
            # 20% variance
            variance: 0.20,
            # 12% burst chance
            burst_probability: 0.12,
            # Router smoothing
            smoothing_factor: 0.25
          }

        :cmts ->
          %{
            # 10MB/s to 100GB/s
            rate_range: {10_000_000, 100_000_000_000},
            # 30% variance (high aggregation)
            variance: 0.30,
            # 20% burst chance
            burst_probability: 0.20,
            # Higher variance for CMTS
            smoothing_factor: 0.4
          }

        :server ->
          %{
            # 50KB/s to 10GB/s
            rate_range: {50_000, 10_000_000_000},
            # 40% variance (workload dependent)
            variance: 0.40,
            # 25% burst chance
            burst_probability: 0.25,
            # High variance for servers
            smoothing_factor: 0.5
          }

        _ ->
          %{
            # Default range
            rate_range: {1_000, 10_000_000},
            variance: 0.15,
            burst_probability: 0.1,
            smoothing_factor: 0.2
          }
      end

    # Merge with base config, preferring base config values
    Map.merge(device_specific, base_config)
  end

  defp get_device_traffic_pattern(device_type, current_time) do
    hour = current_time.hour
    day_of_week = Date.day_of_week(current_time)

    case device_type do
      :cable_modem ->
        # Residential patterns - peak in evening, low during work hours
        residential_pattern(hour, day_of_week)

      :mta ->
        # Voice traffic - business hours peak, some evening usage
        voice_pattern(hour, day_of_week)

      :switch ->
        # Business network - business hours peak
        business_pattern(hour, day_of_week)

      :router ->
        # ISP backbone - more constant with moderate daily variation
        backbone_pattern(hour, day_of_week)

      :cmts ->
        # CMTS aggregates many residential customers
        # Similar to residential but with higher baseline due to aggregation
        cmts_pattern(hour, day_of_week)

      :server ->
        # Server workload - depends on server type, assume web server
        server_pattern(hour, day_of_week)

      _ ->
        # Default no pattern
        1.0
    end
  end

  defp residential_pattern(hour, day_of_week) do
    # Weekend vs weekday
    weekend_factor = if day_of_week >= 6, do: 1.2, else: 1.0

    # Hourly pattern for residential
    hourly_factor =
      case hour do
        # Late night/early morning
        h when h >= 0 and h <= 6 -> 0.3
        # Morning getting ready
        h when h >= 7 and h <= 8 -> 0.6
        # Work hours (low)
        h when h >= 9 and h <= 17 -> 0.4
        # Evening peak
        h when h >= 18 and h <= 22 -> 1.5
        # Late evening
        h when h >= 23 and h <= 23 -> 0.8
        _ -> 0.5
      end

    hourly_factor * weekend_factor
  end

  defp voice_pattern(hour, day_of_week) do
    # Business voice traffic
    weekday_factor = if day_of_week <= 5, do: 1.0, else: 0.3

    hourly_factor =
      case hour do
        # Business hours peak
        h when h >= 8 and h <= 17 -> 1.0
        # Some evening calls
        h when h >= 18 and h <= 20 -> 0.6
        # Low voice traffic otherwise
        _ -> 0.2
      end

    hourly_factor * weekday_factor
  end

  defp business_pattern(hour, day_of_week) do
    # Business network pattern
    weekday_factor = if day_of_week <= 5, do: 1.0, else: 0.2

    hourly_factor =
      case hour do
        # Business hours
        h when h >= 8 and h <= 18 -> 1.0
        # Early arrivals
        h when h >= 6 and h <= 7 -> 0.5
        # Late workers
        h when h >= 19 and h <= 21 -> 0.4
        # Very low after hours
        _ -> 0.1
      end

    hourly_factor * weekday_factor
  end

  defp backbone_pattern(hour, _day_of_week) do
    # ISP backbone - more constant but still has daily patterns
    # High baseline
    base = 0.7

    # Moderate daily variation
    daily_variation =
      case hour do
        # Evening peak
        h when h >= 20 and h <= 23 -> 0.3
        # Business hours
        h when h >= 8 and h <= 17 -> 0.2
        _ -> 0.1
      end

    base + daily_variation
  end

  defp cmts_pattern(hour, day_of_week) do
    # CMTS aggregates many signals, more stable
    # Similar to residential but with higher baseline due to aggregation
    residential_factor = residential_pattern(hour, day_of_week)
    # Higher baseline, less variation
    0.6 + residential_factor * 0.4
  end

  defp server_pattern(hour, day_of_week) do
    # Web server pattern - depends on user base
    # Assume mixed business/consumer user base
    business_factor = business_pattern(hour, day_of_week)
    residential_factor = residential_pattern(hour, day_of_week)

    # Weighted average
    business_factor * 0.4 + residential_factor * 0.6
  end

  defp apply_rate_smoothing(current_rate, device_state, config) do
    smoothing_factor = Map.get(config, :smoothing_factor, 0.2)
    previous_rate = Map.get(device_state, :previous_rate, current_rate)

    # Exponential smoothing to prevent abrupt rate changes
    smoothed_rate = previous_rate + (current_rate - previous_rate) * smoothing_factor

    # Store for next iteration (this would need to be persisted in real implementation)
    smoothed_rate
  end

  @doc """
  Check if a counter value is approaching its maximum and likely to wrap soon.
  Used to predict and prepare for counter wrap events.
  """
  def counter_approaching_wrap?(value, type, threshold_percent \\ 0.95) do
    max_value =
      case String.downcase(type) do
        "counter32" -> 4_294_967_296
        "counter64" -> 18_446_744_073_709_551_616
        _ -> nil
      end

    if max_value do
      value / max_value >= threshold_percent
    else
      false
    end
  end

  @doc """
  Calculate the time until counter wrap based on current increment rate.
  Returns estimated seconds until wrap occurs.
  """
  def time_until_counter_wrap(current_value, increment_rate, type) do
    max_value =
      case String.downcase(type) do
        "counter32" -> 4_294_967_296
        "counter64" -> 18_446_744_073_709_551_616
        _ -> :infinity
      end

    if increment_rate > 0 do
      remaining_value = max_value - current_value
      trunc(remaining_value / increment_rate)
    else
      :infinity
    end
  end

  @doc """
  Simulate realistic counter wrap behavior with device-specific patterns.
  Different device types may handle wrap differently.
  """
  def apply_device_specific_counter_behavior(value, type, device_type, config \\ %{}) do
    wrapped_value = apply_counter_wrapping(value, type)

    # Apply device-specific behavior after wrapping
    case device_type do
      :cable_modem ->
        # Cable modems may have slight delays after wrap
        apply_cable_modem_wrap_behavior(wrapped_value, type, config)

      :cmts ->
        # CMTS devices handle high-rate counters with better precision
        apply_cmts_wrap_behavior(wrapped_value, type, config)

      :switch ->
        # Network switches may have buffering effects
        apply_switch_wrap_behavior(wrapped_value, type, config)

      :router ->
        # Routers may reset related counters on wrap
        apply_router_wrap_behavior(wrapped_value, type, config)

      _ ->
        wrapped_value
    end
  end

  defp apply_cable_modem_wrap_behavior(value, type, config) do
    # Cable modems may have small inconsistencies after counter wrap
    if Map.get(config, :post_wrap_jitter, true) do
      jitter_range =
        case type do
          # Up to 50 count variation
          "counter32" -> 50
          # Minimal variation for 64-bit
          "counter64" -> 5
          _ -> 0
        end

      jitter = trunc((:rand.uniform() - 0.5) * jitter_range * 2)
      max(0, value + jitter)
    else
      value
    end
  end

  defp apply_cmts_wrap_behavior(value, _type, config) do
    # CMTS devices typically handle wrapping more precisely
    # May sync counter wraps across interfaces
    if Map.get(config, :synchronized_wrap, false) do
      # Round to nearest synchronization boundary
      sync_boundary = Map.get(config, :sync_boundary, 1000)
      rounded_value = div(value, sync_boundary) * sync_boundary
      rounded_value
    else
      value
    end
  end

  defp apply_switch_wrap_behavior(value, type, config) do
    # Switches may buffer counter updates, causing delayed wrap appearance
    # 2% delay
    buffer_delay = Map.get(config, :buffer_delay_percent, 0.02)

    if :rand.uniform() < buffer_delay do
      # Simulate buffered counter that hasn't updated yet
      # Return a value slightly before wrap
      case type do
        "counter32" -> max(0, 4_294_967_295 - trunc(:rand.uniform() * 1000))
        "counter64" -> max(0, 18_446_744_073_709_551_615 - trunc(:rand.uniform() * 1000))
        _ -> value
      end
    else
      value
    end
  end

  defp apply_router_wrap_behavior(value, _type, config) do
    # Routers may reset related counters when primary counters wrap
    reset_related = Map.get(config, :reset_related_counters, false)

    # Just wrapped (small value)
    if reset_related and value < 1000 do
      # Simulate related counter resets by adding some randomness
      reset_jitter = trunc(:rand.uniform() * 100)
      value + reset_jitter
    else
      value
    end
  end

  @doc """
  Generate counter discontinuity events that occur during counter wraps.
  Some devices increment discontinuity counters when main counters wrap.
  """
  def handle_counter_discontinuity(old_value, new_value, discontinuity_counter) do
    # Detect if a wrap occurred (new value much smaller than old value)
    # If new value is 1M+ less than old, likely wrapped
    wrap_threshold = 1_000_000

    if old_value - new_value > wrap_threshold do
      # Counter wrapped, increment discontinuity counter
      discontinuity_counter + 1
    else
      discontinuity_counter
    end
  end

  # Advanced Variance and Jitter Functions

  defp apply_gaussian_variance(variance_factor) do
    # Box-Muller transform for Gaussian distribution
    # Generate two independent standard normal random variables
    u1 = :rand.uniform()
    u2 = :rand.uniform()

    # Box-Muller transformation
    z0 = :math.sqrt(-2 * :math.log(u1)) * :math.cos(2 * :math.pi() * u2)

    # Scale to desired variance and center around 1.0
    # Scale down for practical use
    1.0 + z0 * variance_factor * 0.5
  end

  defp apply_burst_variance(variance_factor, config) do
    # 5% chance
    burst_probability = Map.get(config, :burst_probability, 0.05)
    # 3x burst
    burst_multiplier = Map.get(config, :burst_multiplier, 3.0)

    if :rand.uniform() < burst_probability do
      # Burst event - significant variance
      1.0 + variance_factor * burst_multiplier * (:rand.uniform() - 0.5) * 2
    else
      # Normal variance
      1.0 + variance_factor * (:rand.uniform() - 0.5) * 2
    end
  end

  defp apply_time_correlated_variance(_base_rate, variance_factor, config) do
    # Use current time to create slowly-changing variance
    current_time = DateTime.utc_now()
    time_seed = current_time.hour * 3600 + current_time.minute * 60 + current_time.second

    # Create a slowly changing sine wave based on time
    # 1 hour period
    correlation_period = Map.get(config, :correlation_period_seconds, 3600)
    time_phase = time_seed / correlation_period * 2 * :math.pi()

    # Sine wave variance that changes over time
    time_factor = :math.sin(time_phase) * variance_factor

    # Add some random component for realism
    random_component = (:rand.uniform() - 0.5) * variance_factor * 0.3

    1.0 + time_factor + random_component
  end

  defp apply_device_specific_variance(device_type, variance_factor) do
    # Different device types have different variance characteristics
    device_variance_profile =
      case device_type do
        :cable_modem ->
          # Residential devices have moderate variance
          %{base_variance: variance_factor, spike_probability: 0.08, spike_magnitude: 2.0}

        :mta ->
          # Voice devices need low variance for quality
          %{base_variance: variance_factor * 0.3, spike_probability: 0.02, spike_magnitude: 1.2}

        :switch ->
          # Network switches have protocol-driven variance
          %{base_variance: variance_factor * 0.8, spike_probability: 0.15, spike_magnitude: 1.8}

        :router ->
          # Routers have routing-protocol-driven variance
          %{base_variance: variance_factor * 0.9, spike_probability: 0.12, spike_magnitude: 2.2}

        :cmts ->
          # CMTS aggregates many signals, more stable
          %{base_variance: variance_factor * 0.6, spike_probability: 0.20, spike_magnitude: 3.0}

        :server ->
          # Servers have workload-driven high variance
          %{base_variance: variance_factor * 1.5, spike_probability: 0.25, spike_magnitude: 4.0}

        _ ->
          # Default variance profile
          %{base_variance: variance_factor, spike_probability: 0.10, spike_magnitude: 2.0}
      end

    base_var = device_variance_profile.base_variance
    spike_prob = device_variance_profile.spike_probability
    spike_mag = device_variance_profile.spike_magnitude

    if :rand.uniform() < spike_prob do
      # Device-specific spike event
      1.0 + base_var * spike_mag * (:rand.uniform() - 0.5) * 2
    else
      # Normal device variance
      1.0 + base_var * (:rand.uniform() - 0.5) * 2
    end
  end

  @doc """
  Apply configurable jitter to gauge values based on device and metric type.
  Different metrics have different jitter characteristics.
  """
  def apply_configurable_jitter(value, metric_type, device_type, jitter_config \\ %{}) do
    jitter_amount = calculate_jitter_amount(metric_type, device_type, jitter_config)
    jitter_pattern = Map.get(jitter_config, :jitter_pattern, :uniform)

    case jitter_pattern do
      :uniform ->
        apply_uniform_jitter(value, jitter_amount)

      :gaussian ->
        apply_gaussian_jitter(value, jitter_amount)

      :periodic ->
        apply_periodic_jitter(value, jitter_amount, jitter_config)

      :burst ->
        apply_burst_jitter(value, jitter_amount, jitter_config)

      :correlated ->
        apply_correlated_jitter(value, jitter_amount, jitter_config)

      _ ->
        apply_uniform_jitter(value, jitter_amount)
    end
  end

  defp calculate_jitter_amount(metric_type, device_type, jitter_config) do
    # Base jitter amounts by metric type
    base_jitter =
      case metric_type do
        # 2% jitter for traffic counters
        :traffic_counter -> 0.02
        # 5% jitter for error counters (more volatile)
        :error_counter -> 0.05
        # 3% jitter for utilization
        :utilization_gauge -> 0.03
        # 8% jitter for CPU (more variable)
        :cpu_gauge -> 0.08
        # 1% jitter for power levels (stable)
        :power_gauge -> 0.01
        # 4% jitter for SNR (environmental)
        :snr_gauge -> 0.04
        # 3% jitter for signal strength
        :signal_gauge -> 0.03
        # 2% jitter for temperature
        :temperature_gauge -> 0.02
        # Default 5% jitter
        _ -> 0.05
      end

    # Device-specific jitter multipliers
    device_multiplier =
      case device_type do
        # Residential devices more variable
        :cable_modem -> 1.2
        # Voice devices need stability
        :mta -> 0.6
        # Network equipment moderate
        :switch -> 0.8
        # Standard jitter
        :router -> 1.0
        # Head-end equipment more stable
        :cmts -> 0.9
        # Server workloads highly variable
        :server -> 1.5
        _ -> 1.0
      end

    # Allow configuration override
    configured_jitter = Map.get(jitter_config, :jitter_amount, base_jitter)
    configured_jitter * device_multiplier
  end

  defp apply_uniform_jitter(value, jitter_amount) do
    jitter = (:rand.uniform() - 0.5) * 2 * jitter_amount * value
    value + jitter
  end

  defp apply_gaussian_jitter(value, jitter_amount) do
    # Use Box-Muller for Gaussian jitter
    u1 = :rand.uniform()
    u2 = :rand.uniform()
    z0 = :math.sqrt(-2 * :math.log(u1)) * :math.cos(2 * :math.pi() * u2)

    # Scale for practical use
    jitter = z0 * jitter_amount * value * 0.3
    value + jitter
  end

  defp apply_periodic_jitter(value, jitter_amount, config) do
    # Periodic jitter based on time
    # 5 minute default
    period_seconds = Map.get(config, :jitter_period, 300)
    current_time = DateTime.utc_now()
    time_offset = current_time.hour * 3600 + current_time.minute * 60 + current_time.second

    phase = time_offset / period_seconds * 2 * :math.pi()
    periodic_factor = :math.sin(phase)

    jitter = periodic_factor * jitter_amount * value
    value + jitter
  end

  defp apply_burst_jitter(value, jitter_amount, config) do
    burst_probability = Map.get(config, :jitter_burst_probability, 0.1)
    # Increased from 3.0 to 8.0
    burst_magnitude = Map.get(config, :jitter_burst_magnitude, 8.0)

    if :rand.uniform() < burst_probability do
      # Burst jitter event - more dramatic variation
      burst_jitter = (:rand.uniform() - 0.5) * 2 * jitter_amount * burst_magnitude * value
      value + burst_jitter
    else
      # Normal jitter - but not too reduced to ensure some variation
      # Increased from 0.3 to 0.5
      apply_uniform_jitter(value, jitter_amount * 0.5)
    end
  end

  defp apply_correlated_jitter(value, jitter_amount, config) do
    # Jitter that correlates with some external factor
    correlation_factor = Map.get(config, :correlation_factor, 1.0)
    correlation_strength = Map.get(config, :correlation_strength, 0.5)

    # Base jitter
    base_jitter = (:rand.uniform() - 0.5) * 2 * jitter_amount * value

    # Correlated component
    correlated_jitter = correlation_factor * correlation_strength * jitter_amount * value

    value + base_jitter + correlated_jitter
  end
end
