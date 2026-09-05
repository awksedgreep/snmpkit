defmodule SnmpKit.SnmpSim.ValueSimulator.Variance do
  @moduledoc """
  Variance, burst, smoothing and jitter functions applied to simulated rates and gauges. Randomness comes from the process RNG, which `SnmpKit.SnmpSim.ValueSimulator.simulate_value/3` seeds deterministically per device/object.
  """

  def add_realistic_variance(base_rate, config) do
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

  def add_packet_variance(_base_pps, _config) do
    # Packet counters are more bursty than byte counters
    # 85% to 115%
    burst_factor = :rand.uniform() * 0.3 + 0.85
    burst_factor
  end

  def apply_burst_pattern(config, current_time, device_type) do
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

  def apply_smooth_transition(target_value, device_state, _config) do
    previous_value = Map.get(device_state, :previous_utilization, target_value)

    # Smooth transition to prevent abrupt changes
    smoothing_factor = 0.1
    previous_value + (target_value - previous_value) * smoothing_factor
  end

  def apply_rate_smoothing(current_rate, device_state, config) do
    smoothing_factor = Map.get(config, :smoothing_factor, 0.2)
    previous_rate = Map.get(device_state, :previous_rate, current_rate)

    # Exponential smoothing to prevent abrupt rate changes
    smoothed_rate = previous_rate + (current_rate - previous_rate) * smoothing_factor

    # Store for next iteration (this would need to be persisted in real implementation)
    smoothed_rate
  end

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
