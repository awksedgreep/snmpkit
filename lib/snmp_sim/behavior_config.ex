defmodule SnmpSim.BehaviorConfig do
  @moduledoc """
  Configuration system for enhancing walk files with realistic behaviors.
  Provides easy-to-use behavior presets and customization options.
  """

  @doc """
  Apply behavior configurations to a loaded profile.

  ## Examples

      # Apply basic realistic behaviors
      enhanced_profile = SnmpSim.BehaviorConfig.apply_behaviors(profile, [
        :realistic_counters,
        :daily_patterns,
        {:custom_utilization, peak_hours: {9, 17}}
      ])
      
  """
  def apply_behaviors(profile, behavior_configs) do
    # Normalize behavior configurations first
    normalized_configs = Enum.map(behavior_configs, &normalize_behavior_spec/1)

    Enum.reduce(normalized_configs, profile, fn config, acc_profile ->
      apply_single_behavior(acc_profile, config)
    end)
  end

  @doc """
  Get predefined behavior configuration sets.

  ## Examples

      # Cable modem realistic simulation
      behaviors = SnmpSim.BehaviorConfig.get_preset(:cable_modem_realistic)
      
      # High traffic simulation  
      behaviors = SnmpSim.BehaviorConfig.get_preset(:high_traffic_simulation)
      
  """
  def get_preset(preset_name) do
    case preset_name do
      :cable_modem_realistic ->
        cable_modem_realistic_preset()

      :cmts_realistic ->
        cmts_realistic_preset()

      :switch_realistic ->
        switch_realistic_preset()

      :high_traffic_simulation ->
        high_traffic_simulation_preset()

      :low_signal_quality ->
        low_signal_quality_preset()

      :network_congestion ->
        network_congestion_preset()

      :maintenance_mode ->
        maintenance_mode_preset()

      :development_testing ->
        development_testing_preset()

      _ ->
        {:error, :unknown_preset}
    end
  end

  @doc """
  Create custom behavior configuration.

  ## Examples

      config = SnmpSim.BehaviorConfig.create_custom([
        {:traffic_counters, %{
          rate_multiplier: 1.5,
          daily_pattern: true,
          burst_probability: 0.2
        }},
        {:signal_quality, %{
          base_snr: 25,
          weather_impact: true,
          degradation_rate: 0.1
        }}
      ])
      
  """
  def create_custom(behavior_specs) do
    behavior_specs
    |> Enum.map(&normalize_behavior_spec/1)
    |> validate_behavior_config()
  end

  @doc """
  Get available behavior types and their configurations.
  """
  def list_available_behaviors do
    %{
      counter_behaviors: [
        :realistic_counters,
        :high_traffic_counters,
        :bursty_counters,
        :steady_counters
      ],
      gauge_behaviors: [
        :realistic_gauges,
        :stable_gauges,
        :volatile_gauges,
        :degrading_gauges
      ],
      time_patterns: [
        :daily_patterns,
        :weekly_patterns,
        :seasonal_patterns,
        :custom_schedule
      ],
      signal_quality: [
        :docsis_signal_simulation,
        :weather_correlation,
        :distance_based_degradation
      ],
      error_simulation: [
        :realistic_errors,
        :burst_errors,
        :correlated_errors
      ]
    }
  end

  # Preset Definitions

  defp cable_modem_realistic_preset do
    [
      # Traffic counters with realistic patterns
      {:increment_counters,
       %{
         oid_patterns: ["ifInOctets", "ifOutOctets"],
         rate_range: {1_000, 50_000_000},
         daily_variation: true,
         weekend_factor: 0.7,
         burst_probability: 0.1
       }},

      # Packet counters correlated with traffic
      {:increment_counters,
       %{
         oid_patterns: ["ifInUcastPkts", "ifOutUcastPkts"],
         rate_range: {10, 500_000},
         correlation_with: "octets_counters",
         packet_size_avg: 1200
       }},

      # Error counters - very low but realistic
      {:increment_counters,
       %{
         oid_patterns: ["ifInErrors", "ifOutErrors"],
         rate_range: {0, 10},
         correlation_with: "utilization",
         error_burst_probability: 0.02
       }},

      # DOCSIS signal quality gauges
      {:vary_gauges,
       %{
         oid_patterns: ["docsIfSigQSignalNoise"],
         range: {20, 35},
         pattern: :inverse_utilization,
         weather_correlation: true,
         noise_factor: 1.0
       }},

      # Power level gauges
      {:vary_gauges,
       %{
         oid_patterns: ["docsIfDownChannelPower"],
         range: {-10, 10},
         pattern: :environmental,
         seasonal_variation: true
       }},

      # System uptime
      {:increment_uptime,
       %{
         # Very rare reboots
         reset_probability: 0.0001,
         # Standard TimeTicks
         increment_rate: 100
       }},

      # Interface utilization calculation
      {:calculate_utilization,
       %{
         based_on: ["ifInOctets", "ifOutOctets"],
         interface_speed: "ifSpeed",
         smoothing_factor: 0.9
       }}
    ]
  end

  defp cmts_realistic_preset do
    [
      # High-capacity traffic handling
      {:increment_counters,
       %{
         oid_patterns: ["ifInOctets", "ifOutOctets"],
         rate_range: {100_000, 1_000_000_000},
         # Aggregates many modems
         aggregation_factor: 100,
         daily_variation: true
       }},

      # Modem management counters
      {:increment_counters,
       %{
         oid_patterns: ["docsIfCmtsServiceNewCmStatusTxFails"],
         rate_range: {0, 50},
         pattern: :sporadic
       }},

      # System resource gauges
      {:vary_gauges,
       %{
         oid_patterns: ["hrProcessorLoad"],
         range: {10, 80},
         pattern: :correlated_with_traffic,
         spike_probability: 0.05
       }},

      # Temperature monitoring
      {:vary_gauges,
       %{
         oid_patterns: ["entSensorValue"],
         range: {30, 75},
         pattern: :temperature,
         load_correlation: true
       }}
    ]
  end

  defp switch_realistic_preset do
    [
      # Per-port traffic counters
      {:increment_counters,
       %{
         oid_patterns: ["ifInOctets", "ifOutOctets"],
         rate_range: {100, 125_000_000},
         per_interface: true,
         trunk_multiplier: 10
       }},

      # Spanning tree and forwarding
      {:increment_counters,
       %{
         oid_patterns: ["dot1dTpLearnedEntryDiscards"],
         rate_range: {0, 100},
         pattern: :learning_phase
       }},

      # VLAN statistics
      {:increment_counters,
       %{
         oid_patterns: ["dot1qVlanStatisticsInPkts"],
         rate_range: {10, 100_000},
         per_vlan: true
       }},

      # CPU and memory utilization
      {:vary_gauges,
       %{
         oid_patterns: ["cpmCPUTotalPhysicalIndex"],
         range: {5, 60},
         pattern: :processing_load
       }}
    ]
  end

  defp high_traffic_simulation_preset do
    [
      {:increment_counters,
       %{
         rate_multiplier: 5.0,
         burst_probability: 0.3,
         sustained_high_load: true
       }},
      {:vary_gauges,
       %{
         utilization_bias: 0.8,
         volatility: 0.3
       }},
      {:realistic_errors,
       %{
         error_rate_multiplier: 2.0,
         congestion_errors: true
       }}
    ]
  end

  defp low_signal_quality_preset do
    [
      {:vary_gauges,
       %{
         oid_patterns: ["docsIfSigQSignalNoise"],
         # Poor SNR range
         range: {8, 20},
         degradation_trend: true,
         weather_impact_multiplier: 2.0
       }},
      {:increment_counters,
       %{
         oid_patterns: ["ifInErrors", "ifOutErrors"],
         rate_multiplier: 5.0,
         correlation_with: "signal_quality"
       }},
      {:vary_gauges,
       %{
         oid_patterns: ["docsIfDownChannelPower"],
         # Weak signal power
         range: {-15, -5},
         instability: true
       }}
    ]
  end

  defp network_congestion_preset do
    [
      {:increment_counters,
       %{
         rate_multiplier: 1.5,
         sustained_load: 0.9,
         burst_frequency: 0.4
       }},
      {:increment_counters,
       %{
         oid_patterns: ["ifInDiscards", "ifOutDiscards"],
         rate_range: {10, 1000},
         congestion_correlation: true
       }},
      {:vary_gauges,
       %{
         oid_patterns: ["ifOutQLen"],
         range: {10, 100},
         pattern: :queue_buildup
       }}
    ]
  end

  defp maintenance_mode_preset do
    [
      {:static_values,
       %{
         oid_patterns: ["ifAdminStatus"],
         # Interface down
         value: 2
       }},
      {:increment_counters,
       %{
         # Very low traffic
         rate_multiplier: 0.1,
         maintenance_pattern: true
       }},
      {:vary_gauges,
       %{
         # Very stable during maintenance
         stability_factor: 0.95,
         reduced_variation: true
       }}
    ]
  end

  defp development_testing_preset do
    [
      {:predictable_patterns,
       %{
         counter_increment: 1000,
         gauge_pattern: :sine_wave,
         # 5 minutes
         cycle_duration: 300
       }},
      {:test_scenarios,
       %{
         error_injection: :scheduled,
         value_validation: true,
         debugging_enabled: true
       }}
    ]
  end

  # Behavior Application Functions

  defp apply_single_behavior(profile, behavior_config) do
    case behavior_config do
      :realistic_counters ->
        apply_realistic_counters(profile)

      {:realistic_counters, _config} ->
        apply_realistic_counters(profile)

      :daily_patterns ->
        apply_daily_patterns(profile)

      {:daily_patterns, _config} ->
        apply_daily_patterns(profile)

      :weekly_patterns ->
        apply_weekly_patterns(profile)

      {:weekly_patterns, _config} ->
        apply_weekly_patterns(profile)

      {:increment_counters, config} ->
        apply_increment_counters(profile, config)

      {:vary_gauges, config} ->
        apply_vary_gauges(profile, config)

      {:realistic_errors, config} ->
        apply_realistic_errors(profile, config)

      {:custom_utilization, config} ->
        apply_custom_utilization(profile, config)

      _ ->
        # Unknown behavior config, return profile unchanged
        profile
    end
  end

  defp apply_realistic_counters(profile) do
    # Enhance counter OIDs with realistic increment behaviors
    enhanced_oids =
      profile.oid_map
      |> Enum.map(fn {oid, value_info} ->
        if is_counter_type?(value_info.type) do
          enhanced_info =
            Map.put(value_info, :behavior, determine_counter_behavior(oid, value_info))

          {oid, enhanced_info}
        else
          {oid, value_info}
        end
      end)
      |> Map.new()

    %{profile | oid_map: enhanced_oids}
  end

  defp apply_daily_patterns(profile) do
    # Add daily pattern behavior to all appropriate OIDs
    enhanced_oids =
      profile.oid_map
      |> Enum.map(fn {oid, value_info} ->
        if supports_time_patterns?(value_info.type) do
          current_behavior = Map.get(value_info, :behavior, {:static_value, %{}})
          enhanced_behavior = add_daily_pattern(current_behavior)
          enhanced_info = Map.put(value_info, :behavior, enhanced_behavior)
          {oid, enhanced_info}
        else
          {oid, value_info}
        end
      end)
      |> Map.new()

    %{profile | oid_map: enhanced_oids}
  end

  defp apply_weekly_patterns(profile) do
    # Similar to daily patterns but for weekly cycles
    enhanced_oids =
      profile.oid_map
      |> Enum.map(fn {oid, value_info} ->
        if supports_time_patterns?(value_info.type) do
          current_behavior = Map.get(value_info, :behavior, {:static_value, %{}})
          enhanced_behavior = add_weekly_pattern(current_behavior)
          enhanced_info = Map.put(value_info, :behavior, enhanced_behavior)
          {oid, enhanced_info}
        else
          {oid, value_info}
        end
      end)
      |> Map.new()

    %{profile | oid_map: enhanced_oids}
  end

  defp apply_increment_counters(profile, config) do
    oid_patterns = Map.get(config, :oid_patterns, [])

    enhanced_oids =
      profile.oid_map
      |> Enum.map(fn {oid, value_info} ->
        if matches_oid_patterns?(oid, oid_patterns) and is_counter_type?(value_info.type) do
          behavior_config = create_counter_behavior_config(config)
          enhanced_info = Map.put(value_info, :behavior, {:traffic_counter, behavior_config})
          {oid, enhanced_info}
        else
          {oid, value_info}
        end
      end)
      |> Map.new()

    %{profile | oid_map: enhanced_oids}
  end

  defp apply_vary_gauges(profile, config) do
    oid_patterns = Map.get(config, :oid_patterns, [])

    enhanced_oids =
      profile.oid_map
      |> Enum.map(fn {oid, value_info} ->
        if matches_oid_patterns?(oid, oid_patterns) and is_gauge_type?(value_info.type) do
          behavior_config = create_gauge_behavior_config(config)
          enhanced_info = Map.put(value_info, :behavior, {:utilization_gauge, behavior_config})
          {oid, enhanced_info}
        else
          {oid, value_info}
        end
      end)
      |> Map.new()

    %{profile | oid_map: enhanced_oids}
  end

  defp apply_realistic_errors(profile, config) do
    # Apply error behaviors to error counter OIDs
    enhanced_oids =
      profile.oid_map
      |> Enum.map(fn {oid, value_info} ->
        if is_error_counter?(oid, value_info) do
          behavior_config = create_error_behavior_config(config)
          enhanced_info = Map.put(value_info, :behavior, {:error_counter, behavior_config})
          {oid, enhanced_info}
        else
          {oid, value_info}
        end
      end)
      |> Map.new()

    %{profile | oid_map: enhanced_oids}
  end

  defp apply_custom_utilization(profile, config) do
    # Apply custom utilization patterns
    enhanced_oids =
      profile.oid_map
      |> Enum.map(fn {oid, value_info} ->
        if is_utilization_related?(oid, value_info) do
          behavior_config = Map.merge(%{behavior_type: :custom_utilization}, config)
          enhanced_info = Map.put(value_info, :behavior, {:utilization_gauge, behavior_config})
          {oid, enhanced_info}
        else
          {oid, value_info}
        end
      end)
      |> Map.new()

    %{profile | oid_map: enhanced_oids}
  end

  # Helper Functions

  defp normalize_behavior_spec({behavior_type, config}) when is_map(config) do
    {behavior_type, config}
  end

  defp normalize_behavior_spec({behavior_type, config}) when is_list(config) do
    # Convert keyword list to map
    {behavior_type, Map.new(config)}
  end

  defp normalize_behavior_spec(behavior_atom) when is_atom(behavior_atom) do
    {behavior_atom, %{}}
  end

  defp normalize_behavior_spec(invalid_spec) do
    # Return the invalid spec as-is so it can be caught by validation
    invalid_spec
  end

  defp validate_behavior_config(behavior_specs) do
    # Validate that all behavior specifications are valid
    case Enum.find(behavior_specs, &(!valid_behavior_spec?(&1))) do
      nil -> {:ok, behavior_specs}
      invalid_spec -> {:error, {:invalid_behavior_spec, invalid_spec}}
    end
  end

  defp valid_behavior_spec?({behavior_type, config})
       when is_atom(behavior_type) and is_map(config) do
    behavior_type in [
      :increment_counters,
      :vary_gauges,
      :realistic_errors,
      :custom_utilization,
      :daily_patterns,
      :weekly_patterns,
      :seasonal_patterns,
      :traffic_counters,
      :realistic_counters,
      :signal_quality
    ]
  end

  defp valid_behavior_spec?(_), do: false

  defp is_counter_type?(type) do
    String.downcase(type) in ["counter32", "counter64"]
  end

  defp is_gauge_type?(type) do
    String.downcase(type) in ["gauge32", "gauge"]
  end

  defp is_error_counter?(oid, _value_info) do
    # First check the OID string directly
    oid_lower = String.downcase(oid)

    if String.contains?(oid_lower, "error") or
         String.contains?(oid_lower, "discard") or
         String.contains?(oid_lower, "drop") do
      true
    else
      # Also check the OID name mapping
      oid_name = get_oid_name(oid)

      oid_name &&
        (String.contains?(String.downcase(oid_name), "error") or
           String.contains?(String.downcase(oid_name), "discard") or
           String.contains?(String.downcase(oid_name), "drop"))
    end
  end

  defp is_utilization_related?(oid, _value_info) do
    oid_lower = String.downcase(oid)

    String.contains?(oid_lower, "util") or
      String.contains?(oid_lower, "load") or
      String.contains?(oid_lower, "cpu")
  end

  defp supports_time_patterns?(type) do
    is_counter_type?(type) or is_gauge_type?(type)
  end

  defp matches_oid_patterns?(oid, patterns) do
    Enum.any?(patterns, fn pattern ->
      oid_matches_pattern?(oid, pattern)
    end)
  end

  # Check if an OID matches a pattern (either by containing the pattern string or by OID name mapping)
  defp oid_matches_pattern?(oid, pattern) do
    # First try direct string matching (for cases where OID contains the pattern)
    if String.contains?(String.downcase(oid), String.downcase(pattern)) do
      true
    else
      # Try OID name mapping for common SNMP objects
      oid_name = get_oid_name(oid)
      oid_name && String.contains?(String.downcase(oid_name), String.downcase(pattern))
    end
  end

  # Basic mapping of common SNMP interface OIDs to their names
  defp get_oid_name(oid) do
    cond do
      # Interface statistics (IF-MIB)
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.10.") -> "ifInOctets"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.16.") -> "ifOutOctets"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.11.") -> "ifInUcastPkts"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.17.") -> "ifOutUcastPkts"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.14.") -> "ifInErrors"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.20.") -> "ifOutErrors"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.13.") -> "ifInDiscards"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.19.") -> "ifOutDiscards"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.5.") -> "ifSpeed"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.8.") -> "ifOperStatus"
      String.starts_with?(oid, "1.3.6.1.2.1.2.2.1.7.") -> "ifAdminStatus"
      # System group (SNMPv2-MIB)
      String.starts_with?(oid, "1.3.6.1.2.1.1.1.") -> "sysDescr"
      String.starts_with?(oid, "1.3.6.1.2.1.1.3.") -> "sysUpTime"
      String.starts_with?(oid, "1.3.6.1.2.1.1.4.") -> "sysContact"
      String.starts_with?(oid, "1.3.6.1.2.1.1.5.") -> "sysName"
      String.starts_with?(oid, "1.3.6.1.2.1.1.6.") -> "sysLocation"
      # DOCSIS-specific OIDs (commonly used in cable modems)
      String.starts_with?(oid, "1.3.6.1.2.1.10.127.1.1.1.1.6.") -> "docsIfSigQSignalNoise"
      String.starts_with?(oid, "1.3.6.1.2.1.10.127.1.1.1.1.2.") -> "docsIfDownChannelPower"
      # CPU and memory (HOST-RESOURCES-MIB)
      String.starts_with?(oid, "1.3.6.1.2.1.25.3.3.1.2.") -> "hrProcessorLoad"
      String.starts_with?(oid, "1.3.6.1.2.1.25.2.2.1.") -> "hrStorageUsed"
      true -> nil
    end
  end

  defp determine_counter_behavior(oid, _value_info) do
    cond do
      String.contains?(String.downcase(oid), "octets") ->
        {:traffic_counter, %{rate_range: {1_000, 50_000_000}}}

      String.contains?(String.downcase(oid), "packets") ->
        {:packet_counter, %{rate_range: {10, 500_000}}}

      String.contains?(String.downcase(oid), "error") ->
        {:error_counter, %{rate_range: {0, 10}}}

      true ->
        {:generic_counter, %{rate_range: {100, 10_000}}}
    end
  end

  defp add_daily_pattern({behavior_type, config}) do
    enhanced_config = Map.put(config, :daily_pattern, true)
    {behavior_type, enhanced_config}
  end

  defp add_weekly_pattern({behavior_type, config}) do
    enhanced_config = Map.put(config, :weekly_pattern, true)
    {behavior_type, enhanced_config}
  end

  defp create_counter_behavior_config(config) do
    %{
      rate_range: Map.get(config, :rate_range, {1_000, 10_000_000}),
      daily_variation: Map.get(config, :daily_variation, true),
      burst_probability: Map.get(config, :burst_probability, 0.1),
      correlation_with: Map.get(config, :correlation_with),
      rate_multiplier: Map.get(config, :rate_multiplier, 1.0)
    }
  end

  defp create_gauge_behavior_config(config) do
    %{
      range: Map.get(config, :range, {0, 100}),
      pattern: Map.get(config, :pattern, :daily_variation),
      weather_correlation: Map.get(config, :weather_correlation, false),
      utilization_bias: Map.get(config, :utilization_bias, 0.5),
      volatility: Map.get(config, :volatility, 0.1)
    }
  end

  defp create_error_behavior_config(config) do
    %{
      rate_range: Map.get(config, :rate_range, {0, 10}),
      error_rate_multiplier: Map.get(config, :error_rate_multiplier, 1.0),
      burst_probability: Map.get(config, :burst_probability, 0.02),
      correlation_with: Map.get(config, :correlation_with, "utilization")
    }
  end
end
