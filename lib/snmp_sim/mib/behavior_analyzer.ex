defmodule SnmpSim.MIB.BehaviorAnalyzer do
  # Suppress warnings for private functions that are only called internally
  @dialyzer [
    {:nowarn_function, finalize_behavior: 1},
    {:nowarn_function, determine_final_behavior: 4},
    {:nowarn_function, determine_behavior_by_type: 2},
    {:nowarn_function, generate_behavior_config: 2},
    {:nowarn_function, analyze_by_oid_pattern: 1},
    {:nowarn_function, analyze_by_description: 1},
    {:nowarn_function, analyze_by_name: 1},
    {:nowarn_function, analyze_by_type: 1}
  ]
  @moduledoc """
  Automatically determine realistic behaviors from MIB object definitions.
  Analyze object names, descriptions, and types to infer simulation patterns.
  """

  require Logger

  @doc """
  Analyze a MIB object and determine its simulation behavior.

  ## Examples

      behavior = SnmpSim.MIB.BehaviorAnalyzer.analyze_object_behavior(%{
        name: "ifInOctets",
        oid: "1.3.6.1.2.1.2.2.1.10",
        type: :counter32,
        description: "The total number of octets received on the interface"
      })
      
      # Returns: {:traffic_counter, %{rate_range: {1000, 125_000_000}, increment_pattern: :bursty}}
      
  """
  def analyze_object_behavior(oid_info) do
    oid_info
    |> analyze_by_name()
    |> analyze_by_type()
    |> analyze_by_description()
    |> analyze_by_oid_pattern()
    |> finalize_behavior()
  end

  @doc """
  Analyze a complete MIB and generate behavior patterns for all objects.

  ## Examples

      {:ok, behaviors} = SnmpSim.MIB.BehaviorAnalyzer.analyze_mib_behaviors(compiled_mib)
      
  """
  def analyze_mib_behaviors(mib_objects) when is_map(mib_objects) do
    behaviors =
      mib_objects
      |> Enum.map(fn {oid, object_info} ->
        behavior = analyze_object_behavior(object_info)
        {oid, behavior}
      end)
      |> Map.new()

    # Analyze correlations between objects
    correlated_behaviors = analyze_object_correlations(behaviors)

    {:ok, correlated_behaviors}
  end

  @doc """
  Create behavior specifications from walk file data enhanced with intelligent analysis.
  """
  def enhance_walk_file_behaviors(oid_map) when is_map(oid_map) do
    oid_map
    |> Enum.map(fn {oid, value_info} ->
      # Convert walk file data to object info format for analysis
      object_info = %{
        oid: oid,
        name: extract_object_name_from_oid(oid),
        type: normalize_snmp_type(value_info.type),
        description: "",
        value: value_info.value
      }

      behavior = analyze_object_behavior(object_info)
      {oid, Map.merge(value_info, %{behavior: behavior})}
    end)
    |> Map.new()
  end

  # Private analysis functions

  defp analyze_by_name(oid_info) do
    name = String.downcase(oid_info.name || "")

    patterns = %{
      # Traffic counters
      traffic_patterns: [
        {"octets", :traffic_counter},
        {"bytes", :traffic_counter},
        {"packets", :packet_counter},
        {"pkts", :packet_counter},
        {"frames", :packet_counter}
      ],

      # Error counters
      error_patterns: [
        {"errors", :error_counter},
        {"discards", :error_counter},
        {"drops", :error_counter},
        {"failures", :error_counter}
      ],

      # Utilization gauges
      utilization_patterns: [
        {"utilization", :utilization_gauge},
        {"usage", :utilization_gauge},
        {"load", :utilization_gauge},
        {"cpu", :cpu_gauge}
      ],

      # Signal quality (DOCSIS specific)
      signal_patterns: [
        {"power", :power_gauge},
        {"signalnoise", :snr_gauge},
        {"snr", :snr_gauge},
        {"signal", :signal_gauge},
        {"noise", :noise_gauge}
      ],

      # Environmental
      environmental_patterns: [
        {"temperature", :temperature_gauge},
        {"voltage", :voltage_gauge},
        {"current", :current_gauge},
        {"fan", :fan_gauge}
      ],

      # Status indicators
      status_patterns: [
        {"status", :status_enum},
        {"state", :status_enum},
        {"admin", :admin_status},
        {"oper", :operational_status}
      ]
    }

    detected_type =
      patterns
      |> Enum.find_value(fn {_category, pattern_list} ->
        Enum.find_value(pattern_list, fn {pattern, type} ->
          if String.contains?(name, pattern), do: type, else: nil
        end)
      end)

    Map.put(oid_info, :detected_name_pattern, detected_type)
  end

  defp analyze_by_type(oid_info) do
    type_behaviors = %{
      :counter32 => :counter_behavior,
      :counter64 => :counter_behavior,
      :gauge32 => :gauge_behavior,
      :gauge => :gauge_behavior,
      :timeticks => :timeticks_behavior,
      :integer => :integer_behavior,
      :string => :string_behavior,
      :objectid => :oid_behavior,
      :ipaddress => :ip_address_behavior
    }

    snmp_type = normalize_snmp_type(oid_info.type)
    detected_type = Map.get(type_behaviors, snmp_type, :unknown_behavior)

    Map.put(oid_info, :detected_type_pattern, detected_type)
  end

  @type description_pattern ::
          :rate_based
          | :cumulative
          | :instantaneous
          | :inbound
          | :outbound
          | :quality_metric
          | :threshold_based
          | :time_based
          | :timestamp_based

  @spec analyze_by_description(map()) :: map()
  defp analyze_by_description(oid_info) do
    description = String.downcase(oid_info.description || "")

    description_patterns = [
      # Rate indicators
      {~r/per second|\/sec|rate/, :rate_based},
      {~r/total|cumulative|aggregate/, :cumulative},
      {~r/current|instantaneous|immediate/, :instantaneous},

      # Directional indicators
      {~r/inbound|incoming|input|received/, :inbound},
      {~r/outbound|outgoing|output|transmitted/, :outbound},

      # Quality indicators
      {~r/quality|level|strength/, :quality_metric},
      {~r/threshold|limit|maximum|minimum/, :threshold_based},

      # Time-based
      {~r/time|duration|interval|period/, :time_based},
      {~r/last|since|elapsed/, :timestamp_based}
    ]

    detected_patterns =
      description_patterns
      |> Enum.filter(fn {regex, _type} -> Regex.match?(regex, description) end)
      |> Enum.map(fn {_regex, type} -> type end)

    Map.put(oid_info, :detected_description_patterns, detected_patterns)
  end

  defp analyze_by_oid_pattern(oid_info) do
    oid = oid_info.oid || ""

    # Common OID patterns and their typical behaviors
    oid_patterns = [
      # System group (1.3.6.1.2.1.1)
      {~r/^1\.3\.6\.1\.2\.1\.1\./, :system_info},

      # Interface group (1.3.6.1.2.1.2)
      {~r/^1\.3\.6\.1\.2\.1\.2\./, :interface_metrics},

      # IP group (1.3.6.1.2.1.4)
      {~r/^1\.3\.6\.1\.2\.1\.4\./, :ip_metrics},

      # ICMP group (1.3.6.1.2.1.5)
      {~r/^1\.3\.6\.1\.2\.1\.5\./, :icmp_metrics},

      # TCP group (1.3.6.1.2.1.6)
      {~r/^1\.3\.6\.1\.2\.1\.6\./, :tcp_metrics},

      # UDP group (1.3.6.1.2.1.7)
      {~r/^1\.3\.6\.1\.2\.1\.7\./, :udp_metrics},

      # DOCSIS Cable Device (1.3.6.1.2.1.69)
      {~r/^1\.3\.6\.1\.2\.1\.69\./, :docsis_cable_device},

      # DOCSIS Interface (1.3.6.1.2.1.10.127)
      {~r/^1\.3\.6\.1\.2\.1\.10\.127\./, :docsis_interface}
    ]

    detected_oid_pattern =
      oid_patterns
      |> Enum.find_value(fn {regex, pattern} ->
        if Regex.match?(regex, oid), do: pattern, else: nil
      end)

    Map.put(oid_info, :detected_oid_pattern, detected_oid_pattern)
  end

  defp finalize_behavior(analysis_result) do
    # Combine all analysis results to determine final behavior
    name_pattern = analysis_result.detected_name_pattern
    type_pattern = analysis_result.detected_type_pattern
    oid_pattern = analysis_result.detected_oid_pattern
    description_patterns = analysis_result.detected_description_patterns || []

    # Priority-based behavior determination
    behavior =
      determine_final_behavior(name_pattern, type_pattern, oid_pattern, description_patterns)

    # Add behavior-specific configuration
    behavior_config = generate_behavior_config(behavior, analysis_result)

    {behavior, behavior_config}
  end

  # This function determines the final behavior based on name, type, and description patterns
  defp determine_final_behavior(name_pattern, type_pattern, _oid_pattern, description_patterns) do
    # Name patterns have highest priority
    case name_pattern do
      nil ->
        # If no name pattern, fall through to type-based behavior
        determine_behavior_by_type(type_pattern, description_patterns)

      :traffic_counter ->
        :traffic_counter

      :packet_counter ->
        :packet_counter

      :error_counter ->
        :error_counter

      :utilization_gauge ->
        :utilization_gauge

      :cpu_gauge ->
        :cpu_gauge

      :power_gauge ->
        :power_gauge

      :snr_gauge ->
        :snr_gauge

      :signal_gauge ->
        :signal_gauge

      :temperature_gauge ->
        :temperature_gauge

      :status_enum ->
        :status_enum

      :admin_status ->
        :admin_status

      :operational_status ->
        :operational_status

      _ ->
        # Fall back to type-based behavior
        determine_behavior_by_type(type_pattern, description_patterns)
    end
  end

  defp determine_behavior_by_type(type_pattern, description_patterns) do
    case type_pattern do
      :counter_behavior ->
        if :inbound in description_patterns, do: :inbound_counter, else: :generic_counter

      :gauge_behavior ->
        cond do
          :quality_metric in description_patterns -> :quality_gauge
          :utilization_gauge in description_patterns -> :utilization_gauge
          true -> :generic_gauge
        end

      :timeticks_behavior ->
        :uptime_counter

      :integer_behavior ->
        :configuration_value

      :string_behavior ->
        :static_string

      _ ->
        :static_value
    end
  end

  defp generate_behavior_config(behavior, analysis_result) do
    base_config = %{
      behavior_type: behavior,
      oid: analysis_result.oid,
      name: analysis_result.name
    }

    case behavior do
      :traffic_counter ->
        Map.merge(base_config, %{
          rate_range: {1_000, 125_000_000},
          increment_pattern: :realistic,
          time_of_day_variation: true,
          burst_probability: 0.1
        })

      :packet_counter ->
        Map.merge(base_config, %{
          rate_range: {10, 500_000},
          increment_pattern: :packet_based,
          correlation_with: nil
        })

      :error_counter ->
        Map.merge(base_config, %{
          rate_range: {0, 100},
          increment_pattern: :sporadic,
          error_burst_probability: 0.05,
          correlation_with_utilization: true
        })

      :utilization_gauge ->
        Map.merge(base_config, %{
          range: {0, 100},
          pattern: :daily_variation,
          peak_hours: {9, 17},
          weekend_variation: 0.3
        })

      :power_gauge ->
        Map.merge(base_config, %{
          range: {-15, 15},
          pattern: :signal_quality,
          noise_factor: 0.5,
          weather_correlation: true
        })

      :snr_gauge ->
        Map.merge(base_config, %{
          range: {10, 40},
          pattern: :inverse_utilization,
          degradation_factor: 0.1
        })

      :uptime_counter ->
        Map.merge(base_config, %{
          # TimeTicks increment by 100 per second
          increment_rate: 100,
          # Very rare reboot
          reset_probability: 0.0001
        })

      _ ->
        base_config
    end
  end

  defp analyze_object_correlations(behaviors) do
    # Find objects that should be correlated (e.g., ifInOctets with ifInUcastPkts)
    correlations = find_correlated_objects(behaviors)

    # Apply correlation configurations
    Enum.reduce(correlations, behaviors, fn {oid1, oid2, correlation_type}, acc ->
      acc
      |> update_behavior_correlation(oid1, oid2, correlation_type)
      |> update_behavior_correlation(oid2, oid1, correlation_type)
    end)
  end

  defp find_correlated_objects(behaviors) do
    # Look for common correlation patterns
    interface_correlations = find_interface_correlations(behaviors)
    error_correlations = find_error_correlations(behaviors)
    quality_correlations = find_quality_correlations(behaviors)

    interface_correlations ++ error_correlations ++ quality_correlations
  end

  defp find_interface_correlations(behaviors) do
    # Find ifInOctets/ifOutOctets pairs, ifInPkts/ifOutPkts pairs, etc.
    behaviors
    |> Enum.filter(fn {_oid, {behavior_type, _config}} ->
      behavior_type in [:traffic_counter, :packet_counter]
    end)
    |> group_by_interface()
    |> Enum.flat_map(&create_interface_correlations/1)
  end

  defp find_error_correlations(_behaviors) do
    # Error counters should correlate with high utilization
    []
  end

  defp find_quality_correlations(_behaviors) do
    # Signal quality metrics should be inversely correlated with utilization
    []
  end

  # Helper functions

  defp normalize_snmp_type(type) when is_binary(type) do
    case String.downcase(type) do
      "counter32" -> :counter32
      "counter64" -> :counter64
      "gauge32" -> :gauge32
      "gauge" -> :gauge32
      "timeticks" -> :timeticks
      "integer" -> :integer
      "string" -> :string
      "octet" -> :string
      "oid" -> :objectid
      "ipaddress" -> :ipaddress
      _ -> :unknown
    end
  end

  defp normalize_snmp_type(type), do: type

  defp extract_object_name_from_oid(oid) do
    # Try to determine object name from OID patterns
    case oid do
      "1.3.6.1.2.1.1.1.0" ->
        "sysDescr"

      "1.3.6.1.2.1.1.3.0" ->
        "sysUpTime"

      "1.3.6.1.2.1.2.1.0" ->
        "ifNumber"

      oid_string ->
        cond do
          String.contains?(oid_string, "1.3.6.1.2.1.2.2.1.10") -> "ifInOctets"
          String.contains?(oid_string, "1.3.6.1.2.1.2.2.1.16") -> "ifOutOctets"
          String.contains?(oid_string, "1.3.6.1.2.1.2.2.1.11") -> "ifInUcastPkts"
          String.contains?(oid_string, "1.3.6.1.2.1.2.2.1.17") -> "ifOutUcastPkts"
          String.contains?(oid_string, "1.3.6.1.2.1.2.2.1.14") -> "ifInErrors"
          String.contains?(oid_string, "1.3.6.1.2.1.2.2.1.20") -> "ifOutErrors"
          true -> "unknown"
        end
    end
  end

  defp group_by_interface(interface_objects) do
    # Group interface objects by interface index
    interface_objects
    |> Enum.group_by(fn {oid, _behavior} ->
      # Extract interface index from OID
      case Regex.run(~r/1\.3\.6\.1\.2\.1\.2\.2\.1\.\d+\.(\d+)/, oid) do
        [_, interface_index] -> interface_index
        _ -> "unknown"
      end
    end)
    |> Map.values()
  end

  defp create_interface_correlations(_interface_group) do
    # Create correlations between objects on the same interface
    # For now, return empty list - this would be expanded in production
    []
  end

  defp update_behavior_correlation(behaviors, oid1, oid2, correlation_type) do
    case Map.get(behaviors, oid1) do
      {behavior_type, config} ->
        updated_config = Map.put(config, :correlated_with, %{oid: oid2, type: correlation_type})
        Map.put(behaviors, oid1, {behavior_type, updated_config})

      _ ->
        behaviors
    end
  end
end
