defmodule SnmpKit.SnmpSim.Device.Metrics do
  @moduledoc """
  Dynamic device metrics derived from device state: uptime, monotonic traffic /
  packet / error counter increments, gauges (SNR, CPU, storage, temperature),
  time-of-day factors and correlation inputs.

  All functions are pure with respect to process state; randomness is replaced
  by deterministic per-device factors so repeated GETs are idempotent and
  counters only move forward with uptime.
  """

  @doc """
  Calculates device uptime in milliseconds.

  ## Parameters
  - `state` - Device state containing uptime_start timestamp

  ## Returns
  - Integer representing uptime in milliseconds
  """
  def calculate_uptime(%{uptime_start: uptime_start}) when is_integer(uptime_start) do
    current_time = :erlang.monotonic_time()
    uptime_monotonic = current_time - uptime_start
    :erlang.convert_time_unit(uptime_monotonic, :native, :millisecond)
  end

  def calculate_uptime(_state) do
    0
  end

  @doc """
  Calculates device uptime in SNMP TimeTicks (centiseconds).

  ## Parameters
  - `state` - Device state

  ## Returns
  - Integer representing uptime in centiseconds (1/100th of a second)
  """
  def calculate_uptime_ticks(state) do
    # SNMP TimeTicks are in 1/100th of a second (centiseconds)
    uptime_milliseconds = calculate_uptime(state)
    # Convert milliseconds to centiseconds
    div(uptime_milliseconds, 10)
  end

  @doc """
  Builds comprehensive device state for monitoring and OID responses.

  ## Parameters
  - `state` - Current device state

  ## Returns
  - Map containing calculated device metrics and status information
  """
  def build_device_state(state) do
    %{
      device_id: state.device_id,
      device_type: state.device_type,
      uptime: calculate_uptime(state),
      mac_address: state.mac_address,
      port: state.port,
      interface_utilization: calculate_interface_utilization(state),
      signal_quality: calculate_signal_quality(state),
      cpu_utilization: calculate_cpu_utilization(state),
      temperature: calculate_temperature(state),
      error_rate: calculate_error_rate(state),
      health_score: calculate_health_score(state),
      correlation_factors: build_correlation_factors(state)
    }
  end

  @doc """
  Gets interface description based on device type.

  ## Parameters
  - `state` - Device state containing device_type

  ## Returns
  - String description of the interface
  """
  def get_interface_description(state) do
    case state.device_type do
      :cable_modem -> "Ethernet Interface"
      :cmts -> "Cable Interface 1/0/0"
      :router -> "GigabitEthernet0/0"
      _ -> "Interface 1"
    end
  end

  @doc """
  Calculates traffic increment for counters based on device type and time.

  ## Parameters
  - `state` - Device state
  - `counter_type` - Type of traffic counter (:in_octets, :out_octets, etc.)

  ## Returns
  - Integer representing traffic increment since device start
  """
  def calculate_traffic_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Base rate depends on device type and counter type
    base_rate =
      case {state.device_type, counter_type} do
        # ~1 Mbps
        {:cable_modem, :in_octets} -> 125_000
        # ~500 Kbps
        {:cable_modem, :out_octets} -> 62_500
        # ~10 Mbps
        {:cable_modem, :hc_in_octets} -> 1_250_000
        # ~5 Mbps
        {:cable_modem, :hc_out_octets} -> 625_000
        # ~100 Mbps
        {:cmts, :in_octets} -> 12_500_000
        # ~100 Mbps
        {:cmts, :out_octets} -> 12_500_000
        # ~1 Gbps
        {:cmts, :hc_in_octets} -> 125_000_000
        # ~1 Gbps
        {:cmts, :hc_out_octets} -> 125_000_000
        # Default ~80 Kbps
        _ -> 10_000
      end

    # Add time-of-day variation (peak evening hours)
    time_factor = get_time_factor()

    # Higher utilization = more errors (congestion)
    # 0.6x to 2.4x
    utilization_impact = 1.0 + (time_factor - 0.8) * 2.0

    # Signal quality impact: a fixed per-device/per-counter factor in 0.7..1.3.
    # A per-call random factor made the counter jump backwards between polls.
    signal_quality = 0.7 + deterministic_int(state, {:signal_quality, counter_type}, 6) / 10
    # Worse signal = more errors
    signal_impact = 2.0 - signal_quality

    # Calculate total increment
    rate_with_variation = base_rate * utilization_impact * signal_impact
    total_increment = trunc(rate_with_variation * uptime_seconds)

    # Accumulated variance, ±5%, also fixed per device/counter so the value is
    # reproducible and monotonic in uptime
    variance_pct = deterministic_int(state, {:variance, counter_type}, 11) - 6
    max(0, total_increment + div(total_increment * variance_pct, 100))
  end

  # Deterministic pseudo-random integer in 1..n derived from the device identity
  # and a salt. Stable across calls, different per device and per salt.
  defp deterministic_int(state, salt, n) when n > 0 do
    device_id = Map.get(state, :device_id) || Map.get(state, :port) || :default
    :erlang.phash2({device_id, salt}, n) + 1
  end

  @doc """
  Calculates packet increment for packet counters.

  ## Parameters
  - `state` - Device state
  - `counter_type` - Type of packet counter (:in_ucast_pkts, :out_ucast_pkts, etc.)

  ## Returns
  - Integer representing packet count increment since device start
  """
  def calculate_packet_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Packet rates are typically much lower than byte rates
    # Average packet size ~1000 bytes for mixed traffic
    base_pps =
      case {state.device_type, counter_type} do
        # ~125 pps
        {:cable_modem, :in_ucast_pkts} -> 125
        # ~63 pps
        {:cable_modem, :out_ucast_pkts} -> 63
        # ~12.5K pps
        {:cmts, :in_ucast_pkts} -> 12_500
        # ~12.5K pps
        {:cmts, :out_ucast_pkts} -> 12_500
        # Default ~10 pps
        _ -> 10
      end

    # Add time-of-day variation
    time_factor = get_time_factor()
    # -15% to +15%, fixed per device/counter
    jitter = deterministic_int(state, {:packet_jitter, counter_type}, 31) - 16
    jitter_factor = 1.0 + jitter / 100.0

    # Calculate total packets
    rate_with_variation = trunc(base_pps * time_factor * jitter_factor)
    total_packets = rate_with_variation * uptime_seconds

    # ~±7% accumulated variance, fixed per device/counter
    variance_pct = deterministic_int(state, {:packet_variance, counter_type}, 15) - 8
    max(0, total_packets + div(total_packets * variance_pct, 100))
  end

  @doc """
  Calculates error increment for error counters with environmental factors.

  ## Parameters
  - `state` - Device state
  - `counter_type` - Type of error counter (:in_errors, :out_errors, etc.)

  ## Returns
  - Integer representing error count increment since device start
  """
  def calculate_error_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Error rates should be very low under normal conditions
    # Higher during poor signal quality or high utilization
    base_error_rate =
      case {state.device_type, counter_type} do
        # ~1 error per 100 seconds
        {:cable_modem, :in_errors} -> 0.01
        # ~1 error per 200 seconds
        {:cable_modem, :out_errors} -> 0.005
        # ~1 error per 10 seconds (more traffic)
        {:cmts, :in_errors} -> 0.1
        # ~1 error per 20 seconds
        {:cmts, :out_errors} -> 0.05
        # Very low default
        _ -> 0.001
      end

    # Environmental factors affect error rates
    time_factor = get_time_factor()

    # Higher utilization = more errors (congestion)
    # 0.6x to 2.4x
    utilization_impact = 1.0 + (time_factor - 0.8) * 2.0

    # Signal quality impact: fixed per device/counter in 0.7..1.3
    signal_quality = 0.7 + deterministic_int(state, {:signal_quality, counter_type}, 6) / 10
    # Worse signal = more errors
    signal_impact = 2.0 - signal_quality

    # Calculate error increment
    effective_rate = base_error_rate * utilization_impact * signal_impact
    total_errors = trunc(effective_rate * uptime_seconds)

    # Some devices carry a fixed burst of extra errors (about 5% of them, 5-15
    # errors); a random per-poll burst made the counter non-monotonic.
    if deterministic_int(state, {:error_burst, counter_type}, 20) == 1 do
      total_errors + 4 + deterministic_int(state, {:error_burst_size, counter_type}, 10)
    else
      total_errors
    end
  end

  @doc """
  Calculates Signal-to-Noise Ratio (SNR) gauge value for cable modems.

  ## Parameters
  - `state` - Device state containing device_type

  ## Returns
  - Integer representing SNR in dB (15-45 range for cable modems)
  """
  def calculate_snr_gauge(state) do
    # Base SNR for cable modem (typically 25-40 dB, higher is better)
    base_snr =
      case state.device_type do
        # Good signal quality
        :cable_modem -> 32
        # Default
        _ -> 25
      end

    # Add environmental factors
    time_factor = get_time_factor()
    # -3 to +3 dB weather variation
    weather_impact = :rand.uniform(6) - 3

    # Traffic load affects SNR (higher utilization = slightly lower SNR)
    # Small impact
    utilization_factor = 1.0 - (time_factor - 0.7) * 0.1

    # Calculate final SNR with realistic bounds
    snr = trunc(base_snr * utilization_factor + weather_impact)

    # Clamp to realistic cable modem SNR range (15-45 dB)
    max(15, min(45, snr))
  end

  @doc """
  Calculates CPU utilization gauge with realistic load patterns.

  ## Parameters
  - `state` - Device state containing device_type

  ## Returns
  - Integer representing CPU utilization percentage (0-100)
  """
  def calculate_cpu_gauge(state) do
    # Base CPU load depends on device type
    base_cpu =
      case state.device_type do
        # Light load for residential device
        :cable_modem -> 15
        # Higher load for head-end equipment
        :cmts -> 45
        # Moderate load for network equipment
        :switch -> 25
        # Higher load for routing
        :router -> 35
        # Default
        _ -> 20
      end

    # Add time-of-day variation (more load during peak hours)
    time_factor = get_time_factor()
    # 0-14% additional load during peak
    time_cpu_impact = trunc((time_factor - 0.8) * 20)

    # Add traffic correlation (higher traffic = higher CPU)
    # Cap at 1.2x
    traffic_factor = min(time_factor, 1.2)
    # 0-3% additional load
    traffic_cpu_impact = trunc((traffic_factor - 1.0) * 15)

    # Add random variation for realistic simulation
    # -10% to +10%
    cpu_jitter = :rand.uniform(21) - 10
    jitter_impact = trunc(base_cpu * (cpu_jitter / 100.0))

    # Occasional CPU spikes (process startup, background tasks)
    # 2% chance
    spike_probability = 0.02

    spike_impact =
      if :rand.uniform() < spike_probability do
        # 10-40% spike
        :rand.uniform(30) + 10
      else
        0
      end

    # Calculate final CPU percentage
    final_cpu = base_cpu + time_cpu_impact + traffic_cpu_impact + jitter_impact + spike_impact

    # Clamp to realistic range (0-100%)
    max(0, min(100, final_cpu))
  end

  @doc """
  Calculates storage usage gauge in allocation units (typically KB).

  ## Parameters
  - `state` - Device state containing device_type

  ## Returns
  - Integer representing storage usage in allocation units
  """
  def calculate_storage_gauge(state) do
    # Base storage usage depends on device type (in allocation units)
    # Typical allocation unit is 1KB, so values represent KB used
    base_storage =
      case state.device_type do
        # ~64MB for embedded device
        :cable_modem -> 65_536
        # ~512MB for head-end equipment
        :cmts -> 524_288
        # ~128MB for network equipment
        :switch -> 131_072
        # ~256MB for routing equipment
        :router -> 262_144
        # ~32MB default
        _ -> 32_768
      end

    # Add uptime-based growth (memory leaks, log files, etc.)
    # Convert to hours
    uptime_hours = div(calculate_uptime(state), 3_600_000)
    # 0.1% growth per hour
    growth_factor = 1.0 + uptime_hours * 0.001

    # Add traffic-based memory usage (buffers, connection tables)
    time_factor = get_time_factor()
    # Up to 1% more during peak
    traffic_memory_factor = 1.0 + (time_factor - 0.8) * 0.05

    # Add random variation for cache usage, temporary files, etc.
    # -5% to +5%
    usage_jitter = :rand.uniform(11) - 5
    jitter_factor = 1.0 + usage_jitter / 100.0

    # Calculate final storage usage
    final_storage = trunc(base_storage * growth_factor * traffic_memory_factor * jitter_factor)

    # Ensure reasonable bounds
    # Never below 80% of base
    min_storage = trunc(base_storage * 0.8)
    # Never above 130% of base
    max_storage = trunc(base_storage * 1.3)

    max(min_storage, min(max_storage, final_storage))
  end

  @doc """
  Gets time-of-day factor for simulating traffic patterns.

  Peak traffic occurs during evening hours (8-10 PM) with lower
  utilization during overnight and early morning hours.

  ## Returns
  - Float representing traffic multiplier (0.6 to 1.5)
  """
  def get_time_factor do
    # Simple time-of-day factor (peak at 8-10 PM)
    hour = DateTime.utc_now().hour

    case hour do
      # Peak evening
      h when h >= 20 and h <= 22 -> 1.5
      # Early evening
      h when h >= 18 and h <= 19 -> 1.3
      # Business hours
      h when h >= 8 and h <= 17 -> 1.0
      # Overnight
      h when h >= 0 and h <= 6 -> 0.6
      # Other times
      _ -> 0.8
    end
  end

  @doc """
  Calculates interface utilization as a percentage.

  ## Parameters
  - `_state` - Device state (currently unused)

  ## Returns
  - Float representing interface utilization (0.1 to 0.8)
  """
  def calculate_interface_utilization(_state) do
    # Calculate based on current traffic levels
    # For now, return a random utilization between 0.1 and 0.8
    0.1 + :rand.uniform() * 0.7
  end

  @doc """
  Calculates signal quality metric.

  ## Parameters
  - `_state` - Device state (currently unused)

  ## Returns
  - Float representing signal quality (0.0 to 1.0)
  """
  def calculate_signal_quality(_state) do
    # Calculate signal quality (0.0 to 1.0)
    # Could be based on SNR, power levels, etc.
    base_quality = 0.8
    random_variation = (:rand.uniform() - 0.5) * 0.2
    max(0.0, min(1.0, base_quality + random_variation))
  end

  @doc """
  Calculates CPU utilization correlated with network activity.

  ## Parameters
  - `state` - Device state

  ## Returns
  - Float representing CPU utilization (0.0 to 1.0)
  """
  def calculate_cpu_utilization(state) do
    # CPU utilization often correlates with network activity
    interface_util = calculate_interface_utilization(state)
    base_cpu = 0.2 + interface_util * 0.4
    random_variation = (:rand.uniform() - 0.5) * 0.1
    max(0.0, min(1.0, base_cpu + random_variation))
  end

  @doc """
  Calculates device temperature in Celsius.

  Temperature is affected by CPU load and ambient conditions.

  ## Parameters
  - `state` - Device state

  ## Returns
  - Float representing temperature in Celsius
  """
  def calculate_temperature(state) do
    # Device temperature in Celsius
    # Could be affected by CPU load, ambient temperature, etc.
    base_temp = 35.0
    cpu_util = calculate_cpu_utilization(state)
    # Up to 15°C increase under load
    load_factor = cpu_util * 15.0
    ambient_variation = (:rand.uniform() - 0.5) * 10.0

    base_temp + load_factor + ambient_variation
  end

  @doc """
  Calculates error rate as a percentage based on signal quality.

  ## Parameters
  - `state` - Device state

  ## Returns
  - Float representing error rate percentage (0.0 to 0.05)
  """
  def calculate_error_rate(state) do
    # Error rate as a percentage
    signal_quality = calculate_signal_quality(state)
    # Up to 5% errors with poor signal
    base_error_rate = (1.0 - signal_quality) * 0.05
    max(0.0, base_error_rate)
  end

  @doc """
  Calculates overall device health score.

  Health score is based on signal quality, error rate, and uptime stability.

  ## Parameters
  - `state` - Device state

  ## Returns
  - Float representing health score (0.0 to 1.0)
  """
  def calculate_health_score(state) do
    # Overall device health score (0.0 to 1.0)
    signal_quality = calculate_signal_quality(state)
    error_rate = calculate_error_rate(state)
    uptime = calculate_uptime(state)

    # Health improves with good signal, low errors, and stable uptime
    # Normalize to days
    uptime_factor = min(1.0, uptime / 86400.0)
    health = (signal_quality + (1.0 - error_rate) + uptime_factor) / 3.0
    max(0.0, min(1.0, health))
  end

  @doc """
  Builds correlation factors for related OIDs.

  This can be expanded to track relationships between different metrics.

  ## Parameters
  - `_state` - Device state (currently unused)

  ## Returns
  - Map of correlation factors (currently empty)
  """
  def build_correlation_factors(_state) do
    # Build correlation factors for related OIDs
    # This could be expanded to track actual relationships
    %{}
  end
end
