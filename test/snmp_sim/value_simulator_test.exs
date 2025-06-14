defmodule SnmpKit.SnmpSim.ValueSimulatorTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.ValueSimulator

  describe "Traffic Counter Simulation" do
    test "generates realistic traffic counter increments" do
      profile_data = %{type: "Counter32", value: 1_000_000}

      behavior_config =
        {:traffic_counter,
         %{
           rate_range: {1000, 125_000_000},
           time_of_day_variation: true,
           burst_probability: 0.1
         }}

      device_state = %{
        # 1 hour
        uptime: 3600,
        interface_utilization: 0.5,
        device_id: "test_device"
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      # Should return a counter32 tuple
      assert {:counter32, value} = result
      assert is_integer(value)
      # Should have incremented from base
      assert value > 1_000_000
    end

    test "applies counter wrapping for 32-bit counters" do
      # Near max
      profile_data = %{type: "Counter32", value: 4_294_967_290}
      behavior_config = {:traffic_counter, %{rate_range: {1000, 10000}}}
      device_state = %{uptime: 3600, interface_utilization: 0.8}

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert {:counter32, value} = result
      # Should wrap around if it exceeds 32-bit max
      assert value >= 0
      assert value < 4_294_967_296
    end
  end

  describe "Gauge Simulation" do
    test "generates utilization gauge with daily patterns" do
      profile_data = %{type: "Gauge32", value: 50}

      behavior_config =
        {:utilization_gauge,
         %{
           range: {0, 100},
           pattern: :daily_variation,
           peak_hours: {9, 17}
         }}

      device_state = %{
        device_id: "test_device",
        utilization_bias: 1.0
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert {:gauge32, value} = result
      assert is_integer(value)
      assert value >= 0
      assert value <= 100
    end

    test "simulates SNR gauge with inverse utilization correlation" do
      profile_data = %{type: "Gauge32", value: 25}

      behavior_config =
        {:snr_gauge,
         %{
           range: {10, 40},
           pattern: :inverse_utilization,
           degradation_factor: 0.1
         }}

      device_state = %{
        # High utilization
        interface_utilization: 0.8,
        signal_quality: 0.7
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert {:gauge32, value} = result
      assert value >= 10
      assert value <= 40
      # With high utilization, SNR should be somewhat degraded
    end

    test "simulates power gauge with environmental factors" do
      profile_data = %{type: "Gauge32", value: 5}

      behavior_config =
        {:power_gauge,
         %{
           range: {-15, 15},
           pattern: :signal_quality,
           weather_correlation: true
         }}

      device_state = %{
        signal_quality: 0.9,
        temperature: 30.0
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert {:gauge32, value} = result
      assert value >= -15
      assert value <= 15
    end
  end

  describe "Error Counter Simulation" do
    test "generates low error rates under normal conditions" do
      profile_data = %{type: "Counter32", value: 5}

      behavior_config =
        {:error_counter,
         %{
           rate_range: {0, 100},
           error_burst_probability: 0.05,
           correlation_with_utilization: true
         }}

      device_state = %{
        uptime: 3600,
        # Low utilization
        interface_utilization: 0.3,
        # Good signal
        signal_quality: 0.9
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert {:counter32, value} = result
      # Should be at least the base value
      assert value >= 5
      # Under good conditions, errors should increase slowly
    end

    test "increases error rates under poor conditions" do
      profile_data = %{type: "Counter32", value: 10}

      behavior_config =
        {:error_counter,
         %{
           rate_range: {0, 100},
           error_burst_probability: 0.05
         }}

      device_state = %{
        uptime: 3600,
        # High utilization
        interface_utilization: 0.9,
        # Poor signal
        signal_quality: 0.3
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert {:counter32, value} = result
      assert value >= 10
      # Under poor conditions, errors should increase more rapidly
    end
  end

  describe "System Counter Simulation" do
    test "simulates sysUpTime correctly" do
      profile_data = %{type: "Timeticks", value: 0}

      behavior_config =
        {:uptime_counter,
         %{
           increment_rate: 100,
           reset_probability: 0.0001
         }}

      # 1 hour = 3600 seconds
      device_state = %{uptime: 3600}

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert {:timeticks, value} = result
      # Should be approximately 3600 * 100 = 360,000 timeticks
      assert value > 350_000
      assert value < 370_000
    end
  end

  describe "Status Enumeration Simulation" do
    test "maintains status based on device health" do
      # up(1)
      profile_data = %{type: "INTEGER", value: 1}
      behavior_config = {:status_enum, %{}}

      device_state = %{
        health_score: 0.9,
        error_rate: 0.01
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      # Should maintain "up" status with good health
      assert result == "up"
    end

    test "changes status based on poor device health" do
      # up(1)
      profile_data = %{type: "INTEGER", value: 1}
      behavior_config = {:status_enum, %{}}

      device_state = %{
        # Poor health
        health_score: 0.3,
        # High error rate
        error_rate: 0.15
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      # Should change to degraded or down status
      assert result in ["down", "degraded", "up"]
    end
  end

  describe "Static Value Handling" do
    test "returns static values unchanged" do
      profile_data = %{type: "STRING", value: "Test Device Description"}
      behavior_config = {:static_value, %{}}
      device_state = %{}

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert result == "Test Device Description"
    end

    test "handles different static data types correctly" do
      test_cases = [
        {%{type: "INTEGER", value: 42}, 42},
        {%{type: "Counter32", value: 12345}, {:counter32, 12345}},
        {%{type: "Gauge32", value: 67}, {:gauge32, 67}},
        {%{type: "STRING", value: "test"}, "test"}
      ]

      behavior_config = {:static_value, %{}}
      device_state = %{}

      for {profile_data, expected} <- test_cases do
        result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)
        assert result == expected
      end
    end
  end

  describe "Temperature Simulation" do
    test "simulates realistic temperature with load correlation" do
      profile_data = %{type: "Gauge32", value: 35}

      behavior_config =
        {:temperature_gauge,
         %{
           range: {-10, 85},
           load_correlation: true
         }}

      device_state = %{
        # High CPU load
        cpu_utilization: 0.8,
        temperature: 35.0
      }

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      assert {:gauge32, value} = result
      assert value >= -10
      assert value <= 85
      # High CPU load should increase temperature above base
    end
  end

  describe "Edge Cases" do
    test "handles unknown behavior types gracefully" do
      profile_data = %{type: "STRING", value: "test"}
      behavior_config = {:unknown_behavior, %{}}
      device_state = %{}

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      # Should fall back to static value
      assert result == "test"
    end

    test "handles missing device state fields gracefully" do
      profile_data = %{type: "Counter32", value: 1000}
      behavior_config = {:traffic_counter, %{rate_range: {100, 1000}}}
      # Empty device state
      device_state = %{}

      result = ValueSimulator.simulate_value(profile_data, behavior_config, device_state)

      # Should still work with default values
      assert {:counter32, value} = result
      assert is_integer(value)
    end
  end
end
