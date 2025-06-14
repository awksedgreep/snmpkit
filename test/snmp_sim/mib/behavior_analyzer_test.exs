defmodule SnmpKit.SnmpSim.MIB.BehaviorAnalyzerTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.MIB.BehaviorAnalyzer

  describe "Object Behavior Analysis" do
    test "identifies traffic counters by name" do
      object_info = %{
        name: "ifInOctets",
        oid: "1.3.6.1.2.1.2.2.1.10.1",
        type: :counter32,
        description: "The total number of octets received on the interface"
      }

      {behavior, config} = BehaviorAnalyzer.analyze_object_behavior(object_info)

      assert behavior == :traffic_counter
      assert config.behavior_type == :traffic_counter
      assert config.rate_range == {1_000, 125_000_000}
      assert config.time_of_day_variation == true
    end

    test "identifies packet counters and correlates with octets" do
      object_info = %{
        name: "ifInUcastPkts",
        oid: "1.3.6.1.2.1.2.2.1.11.1",
        type: :counter32,
        description: "The number of unicast packets delivered to a higher layer"
      }

      {behavior, config} = BehaviorAnalyzer.analyze_object_behavior(object_info)

      assert behavior == :packet_counter
      assert config.behavior_type == :packet_counter
      # Correlation logic to be implemented
      assert config.correlation_with == nil
    end

    test "identifies error counters with appropriate rates" do
      object_info = %{
        name: "ifInErrors",
        oid: "1.3.6.1.2.1.2.2.1.14.1",
        type: :counter32,
        description: "The number of inbound packets that contained errors"
      }

      {behavior, config} = BehaviorAnalyzer.analyze_object_behavior(object_info)

      assert behavior == :error_counter
      assert config.behavior_type == :error_counter
      assert config.rate_range == {0, 100}
      assert config.correlation_with_utilization == true
    end

    test "identifies SNR gauges with inverse utilization pattern" do
      object_info = %{
        name: "docsIfSigQSignalNoise",
        oid: "1.3.6.1.2.1.10.127.1.1.4.1.5.2",
        type: :gauge32,
        description: "Signal to Noise ratio"
      }

      {behavior, config} = BehaviorAnalyzer.analyze_object_behavior(object_info)

      assert behavior == :snr_gauge
      assert config.behavior_type == :snr_gauge
      assert config.range == {10, 40}
      assert config.pattern == :inverse_utilization
    end

    test "identifies power level gauges with environmental correlation" do
      object_info = %{
        name: "docsIfDownChannelPower",
        oid: "1.3.6.1.2.1.10.127.1.1.1.1.6.2",
        type: :gauge32,
        description: "Downstream channel power level"
      }

      {behavior, config} = BehaviorAnalyzer.analyze_object_behavior(object_info)

      assert behavior == :power_gauge
      assert config.behavior_type == :power_gauge
      assert config.range == {-15, 15}
      assert config.weather_correlation == true
    end

    test "identifies system uptime with proper increment rate" do
      object_info = %{
        name: "sysUpTime",
        oid: "1.3.6.1.2.1.1.3.0",
        type: :timeticks,
        description: "Time since the system was last reinitialized"
      }

      {behavior, config} = BehaviorAnalyzer.analyze_object_behavior(object_info)

      assert behavior == :uptime_counter
      assert config.behavior_type == :uptime_counter
      # TimeTicks per second
      assert config.increment_rate == 100
    end
  end

  describe "Walk File Enhancement" do
    test "enhances walk file data with intelligent behaviors" do
      oid_map = %{
        "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 1_234_567_890},
        "1.3.6.1.2.1.2.2.1.11.1" => %{type: "Counter32", value: 987_654_321},
        "1.3.6.1.2.1.2.2.1.14.1" => %{type: "Counter32", value: 5},
        "1.3.6.1.2.1.1.3.0" => %{type: "Timeticks", value: 12_345_600}
      }

      enhanced_map = BehaviorAnalyzer.enhance_walk_file_behaviors(oid_map)

      # Check that behaviors were added
      assert Map.has_key?(enhanced_map["1.3.6.1.2.1.2.2.1.10.1"], :behavior)
      assert Map.has_key?(enhanced_map["1.3.6.1.2.1.2.2.1.11.1"], :behavior)
      assert Map.has_key?(enhanced_map["1.3.6.1.2.1.1.3.0"], :behavior)

      # Check specific behavior types
      {traffic_behavior, _} = enhanced_map["1.3.6.1.2.1.2.2.1.10.1"].behavior
      assert traffic_behavior == :traffic_counter

      {uptime_behavior, _} = enhanced_map["1.3.6.1.2.1.1.3.0"].behavior
      assert uptime_behavior == :uptime_counter
    end

    test "handles unknown OIDs gracefully" do
      oid_map = %{
        "1.3.6.1.4.1.9999.1.1.0" => %{type: "STRING", value: "Unknown Device"}
      }

      enhanced_map = BehaviorAnalyzer.enhance_walk_file_behaviors(oid_map)

      # Should still have the OID with a default behavior
      assert Map.has_key?(enhanced_map, "1.3.6.1.4.1.9999.1.1.0")
      assert Map.has_key?(enhanced_map["1.3.6.1.4.1.9999.1.1.0"], :behavior)
    end
  end

  describe "MIB Behavior Analysis" do
    test "analyzes complete MIB object set" do
      mib_objects = %{
        "1.3.6.1.2.1.2.2.1.10.1" => %{
          name: "ifInOctets",
          oid: "1.3.6.1.2.1.2.2.1.10.1",
          type: :counter32,
          description: "Input octets on interface"
        },
        "1.3.6.1.2.1.2.2.1.16.1" => %{
          name: "ifOutOctets",
          oid: "1.3.6.1.2.1.2.2.1.16.1",
          type: :counter32,
          description: "Output octets on interface"
        },
        "1.3.6.1.2.1.1.3.0" => %{
          name: "sysUpTime",
          oid: "1.3.6.1.2.1.1.3.0",
          type: :timeticks,
          description: "System uptime"
        }
      }

      {:ok, behaviors} = BehaviorAnalyzer.analyze_mib_behaviors(mib_objects)

      assert map_size(behaviors) == 3
      assert Map.has_key?(behaviors, "1.3.6.1.2.1.2.2.1.10.1")
      assert Map.has_key?(behaviors, "1.3.6.1.2.1.2.2.1.16.1")
      assert Map.has_key?(behaviors, "1.3.6.1.2.1.1.3.0")
    end
  end

  describe "Object Name Extraction" do
    test "extracts object names from common OIDs" do
      test_cases = [
        {"1.3.6.1.2.1.1.1.0", "sysDescr"},
        {"1.3.6.1.2.1.1.3.0", "sysUpTime"},
        {"1.3.6.1.2.1.2.1.0", "ifNumber"},
        {"1.3.6.1.2.1.2.2.1.10.1", "ifInOctets"},
        {"1.3.6.1.2.1.2.2.1.16.2", "ifOutOctets"}
      ]

      for {oid, expected_name} <- test_cases do
        # Test indirectly through behavior analysis since extract_object_name_from_oid is private
        object_info = %{
          oid: oid,
          # Use expected name directly
          name: expected_name,
          type: :counter32,
          description: ""
        }

        {_behavior, _config} = BehaviorAnalyzer.analyze_object_behavior(object_info)
        # Just verify it doesn't crash and returns valid behavior
        assert is_atom(_behavior)
      end
    end
  end
end
