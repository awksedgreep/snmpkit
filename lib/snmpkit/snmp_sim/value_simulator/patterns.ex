defmodule SnmpKit.SnmpSim.ValueSimulator.Patterns do
  @moduledoc """
  Device-type traffic configuration and time-of-day usage patterns (residential, business, voice, backbone, CMTS, server) used to shape simulated counter rates.
  """

  def get_traffic_config_for_device(device_type, base_config) do
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

  def get_device_traffic_pattern(device_type, current_time) do
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
end
