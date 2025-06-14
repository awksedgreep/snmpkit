defmodule SnmpKit.SnmpSim.CorrelationEngineTest do
  use ExUnit.Case, async: false
  alias SnmpKit.SnmpSim.CorrelationEngine

  describe "apply_correlations/5" do
    test "applies correlations between related metrics" do
      device_state = %{
        interface_utilization: 0.7,
        signal_quality: 85.0,
        temperature: 45.0,
        error_rate: 0.001
      }

      correlations = [
        {:interface_utilization, :error_rate, :positive, 0.7},
        {:signal_quality, :throughput, :positive, 0.9},
        {:temperature, :cpu_usage, :positive, 0.6}
      ]

      current_time = DateTime.utc_now()

      updated_state =
        CorrelationEngine.apply_correlations(
          :interface_utilization,
          0.8,
          device_state,
          correlations,
          current_time
        )

      # State should be updated with correlated values
      assert is_map(updated_state)
      assert Map.has_key?(updated_state, :interface_utilization)
      assert Map.has_key?(updated_state, :error_rate)
    end

    test "handles missing secondary metrics gracefully" do
      device_state = %{
        interface_utilization: 0.5
        # Missing error_rate intentionally
      }

      correlations = [
        {:interface_utilization, :error_rate, :positive, 0.7}
      ]

      current_time = DateTime.utc_now()

      updated_state =
        CorrelationEngine.apply_correlations(
          :interface_utilization,
          0.6,
          device_state,
          correlations,
          current_time
        )

      # Should return original state when secondary metric missing
      assert updated_state == device_state
    end

    test "processes multiple correlations for single primary metric" do
      device_state = %{
        interface_utilization: 0.6,
        error_rate: 0.002,
        throughput: 50_000_000,
        cpu_usage: 30.0
      }

      correlations = [
        {:interface_utilization, :error_rate, :positive, 0.7},
        {:interface_utilization, :throughput, :negative, 0.8},
        {:interface_utilization, :cpu_usage, :positive, 0.6}
      ]

      current_time = DateTime.utc_now()

      updated_state =
        CorrelationEngine.apply_correlations(
          :interface_utilization,
          0.8,
          device_state,
          correlations,
          current_time
        )

      # All correlated metrics should be updated
      assert Map.has_key?(updated_state, :error_rate)
      assert Map.has_key?(updated_state, :throughput)
      assert Map.has_key?(updated_state, :cpu_usage)

      # Values should have changed from originals
      assert updated_state.error_rate != device_state.error_rate
      assert updated_state.throughput != device_state.throughput
      assert updated_state.cpu_usage != device_state.cpu_usage
    end
  end

  describe "get_device_correlations/1" do
    test "returns cable modem correlations" do
      correlations = CorrelationEngine.get_device_correlations(:cable_modem)

      assert is_list(correlations)
      assert length(correlations) > 0

      # Should include typical cable modem correlations
      signal_throughput =
        Enum.find(correlations, fn
          {:signal_quality, :throughput, _, _} -> true
          _ -> false
        end)

      assert signal_throughput != nil
    end

    test "returns MTA correlations" do
      correlations = CorrelationEngine.get_device_correlations(:mta)

      assert is_list(correlations)
      assert length(correlations) > 0

      # Should include voice-specific correlations
      signal_jitter =
        Enum.find(correlations, fn
          {:signal_quality, :jitter, _, _} -> true
          _ -> false
        end)

      assert signal_jitter != nil
    end

    test "returns switch correlations" do
      correlations = CorrelationEngine.get_device_correlations(:switch)

      assert is_list(correlations)

      # Should include network equipment correlations
      cpu_temp =
        Enum.find(correlations, fn
          {:cpu_usage, :temperature, _, _} -> true
          _ -> false
        end)

      assert cpu_temp != nil
    end

    test "returns router correlations" do
      correlations = CorrelationEngine.get_device_correlations(:router)

      assert is_list(correlations)

      # Should include routing-specific correlations
      cpu_routing =
        Enum.find(correlations, fn
          {:cpu_usage, :routing_table_misses, _, _} -> true
          _ -> false
        end)

      assert cpu_routing != nil
    end

    test "returns CMTS correlations" do
      correlations = CorrelationEngine.get_device_correlations(:cmts)

      assert is_list(correlations)

      # Should include aggregation-specific correlations
      modems_cpu =
        Enum.find(correlations, fn
          {:total_modems_online, :cpu_usage, _, _} -> true
          _ -> false
        end)

      assert modems_cpu != nil
    end

    test "returns server correlations" do
      correlations = CorrelationEngine.get_device_correlations(:server)

      assert is_list(correlations)

      # Should include server-specific correlations
      cpu_memory =
        Enum.find(correlations, fn
          {:cpu_usage, :memory_usage, _, _} -> true
          _ -> false
        end)

      assert cpu_memory != nil
    end

    test "returns generic correlations for unknown device types" do
      correlations = CorrelationEngine.get_device_correlations(:unknown_device)

      assert is_list(correlations)
      assert length(correlations) > 0

      # Should include basic correlations
      basic_correlation =
        Enum.find(correlations, fn
          {:interface_utilization, :error_rate, _, _} -> true
          _ -> false
        end)

      assert basic_correlation != nil
    end
  end

  describe "calculate_signal_throughput_correlation/3" do
    test "calculates throughput based on excellent signal quality" do
      snr_db = 35.0
      power_level_dbmv = 5.0
      # 100 Mbps
      max_throughput = 100_000_000

      result =
        CorrelationEngine.calculate_signal_throughput_correlation(
          snr_db,
          power_level_dbmv,
          max_throughput
        )

      # Excellent signal should give near-maximum throughput
      assert result >= max_throughput * 0.9
      # Allow for jitter
      assert result <= max_throughput * 1.1
    end

    test "reduces throughput for poor signal quality" do
      # Poor SNR
      snr_db = 15.0
      # Poor power level
      power_level_dbmv = -12.0
      max_throughput = 100_000_000

      result =
        CorrelationEngine.calculate_signal_throughput_correlation(
          snr_db,
          power_level_dbmv,
          max_throughput
        )

      # Poor signal should significantly reduce throughput
      assert result < max_throughput * 0.5
      assert result > 0
    end

    test "handles marginal signal conditions" do
      # Marginal SNR
      snr_db = 25.0
      # Marginal power level
      power_level_dbmv = 8.0
      max_throughput = 100_000_000

      result =
        CorrelationEngine.calculate_signal_throughput_correlation(
          snr_db,
          power_level_dbmv,
          max_throughput
        )

      # Marginal signal should give moderate throughput
      assert result >= max_throughput * 0.4
      assert result <= max_throughput * 0.804
    end
  end

  describe "calculate_utilization_error_correlation/2" do
    test "increases error rates with higher utilization" do
      low_util_errors =
        CorrelationEngine.calculate_utilization_error_correlation(
          20.0,
          :ethernet_gigabit
        )

      high_util_errors =
        CorrelationEngine.calculate_utilization_error_correlation(
          90.0,
          :ethernet_gigabit
        )

      # High utilization should result in higher error rates
      assert high_util_errors > low_util_errors
      assert low_util_errors >= 0
      # Capped at 10%
      assert high_util_errors <= 0.1
    end

    test "applies different base error rates by interface type" do
      utilization = 50.0

      gigabit_errors =
        CorrelationEngine.calculate_utilization_error_correlation(
          utilization,
          :ethernet_gigabit
        )

      wifi_errors =
        CorrelationEngine.calculate_utilization_error_correlation(
          utilization,
          :wifi
        )

      docsis_errors =
        CorrelationEngine.calculate_utilization_error_correlation(
          utilization,
          :docsis
        )

      # WiFi should have higher base error rate than gigabit ethernet
      assert wifi_errors > gigabit_errors
      # DOCSIS should be between gigabit and WiFi
      assert docsis_errors > gigabit_errors
      assert docsis_errors < wifi_errors
    end

    test "caps error rates at reasonable maximum" do
      # Even at 100% utilization, error rate should be capped
      max_errors =
        CorrelationEngine.calculate_utilization_error_correlation(
          100.0,
          :wifi
        )

      # Should not exceed 10%
      assert max_errors <= 0.1
    end
  end

  describe "calculate_temperature_performance_correlation/2" do
    test "calculates impact for cable modem at optimal temperature" do
      result =
        CorrelationEngine.calculate_temperature_performance_correlation(
          25.0,
          :cable_modem
        )

      # At optimal temperature, impacts should be minimal
      assert result.cpu_impact == 1.0
      assert result.signal_impact == 1.0
      assert result.error_impact >= 1.0
      assert result.error_impact <= 1.1
    end

    test "reduces performance at high temperatures" do
      result =
        CorrelationEngine.calculate_temperature_performance_correlation(
          70.0,
          :cable_modem
        )

      # High temperature should degrade performance
      assert result.cpu_impact < 1.0
      assert result.signal_impact < 1.0
      assert result.error_impact > 1.0
    end

    test "handles different equipment types appropriately" do
      high_temp = 55.0

      cable_modem_result =
        CorrelationEngine.calculate_temperature_performance_correlation(
          high_temp,
          :cable_modem
        )

      server_result =
        CorrelationEngine.calculate_temperature_performance_correlation(
          high_temp,
          :server
        )

      # Server equipment should be more sensitive to temperature
      assert server_result.cpu_impact <= cable_modem_result.cpu_impact
      assert server_result.signal_impact <= cable_modem_result.signal_impact
    end

    test "handles extreme temperatures" do
      result =
        CorrelationEngine.calculate_temperature_performance_correlation(
          85.0,
          :server
        )

      # Extreme temperature should cause severe impact
      assert result.cpu_impact <= 0.3
      assert result.signal_impact <= 0.6
      assert result.error_impact >= 2.0
    end
  end

  describe "calculate_power_consumption_correlation/2" do
    test "calculates power based on device metrics" do
      device_metrics = %{
        cpu_utilization: 50.0,
        interface_utilization: 0.6,
        temperature: 35.0
      }

      result =
        CorrelationEngine.calculate_power_consumption_correlation(
          device_metrics,
          :cable_modem
        )

      # Should return a reasonable power consumption value
      assert is_float(result)
      assert result > 0
      # Cable modem base power is ~12W, with activity should be higher
      assert result >= 12.0
      # Reasonable upper bound
      assert result <= 25.0
    end

    test "varies power consumption by device type" do
      device_metrics = %{
        cpu_utilization: 50.0,
        interface_utilization: 0.5,
        temperature: 30.0
      }

      cable_modem_power =
        CorrelationEngine.calculate_power_consumption_correlation(
          device_metrics,
          :cable_modem
        )

      server_power =
        CorrelationEngine.calculate_power_consumption_correlation(
          device_metrics,
          :server
        )

      cmts_power =
        CorrelationEngine.calculate_power_consumption_correlation(
          device_metrics,
          :cmts
        )

      # Server and CMTS should consume more power than cable modem
      assert server_power > cable_modem_power
      assert cmts_power > cable_modem_power
      # CMTS is largest equipment
      assert cmts_power > server_power
    end

    test "increases power with CPU and network activity" do
      low_activity_metrics = %{
        cpu_utilization: 10.0,
        interface_utilization: 0.1,
        temperature: 25.0
      }

      high_activity_metrics = %{
        cpu_utilization: 90.0,
        interface_utilization: 0.9,
        temperature: 25.0
      }

      low_power =
        CorrelationEngine.calculate_power_consumption_correlation(
          low_activity_metrics,
          :switch
        )

      high_power =
        CorrelationEngine.calculate_power_consumption_correlation(
          high_activity_metrics,
          :switch
        )

      # Higher activity should result in higher power consumption
      assert high_power > low_power
    end

    test "includes cooling power for high temperatures" do
      normal_temp_metrics = %{
        cpu_utilization: 50.0,
        interface_utilization: 0.5,
        temperature: 25.0
      }

      high_temp_metrics = %{
        cpu_utilization: 50.0,
        interface_utilization: 0.5,
        temperature: 45.0
      }

      normal_power =
        CorrelationEngine.calculate_power_consumption_correlation(
          normal_temp_metrics,
          :router
        )

      high_temp_power =
        CorrelationEngine.calculate_power_consumption_correlation(
          high_temp_metrics,
          :router
        )

      # Higher temperature should include cooling power
      assert high_temp_power > normal_power
    end
  end

  describe "integration and performance" do
    test "correlations work together without conflicts" do
      device_state = %{
        interface_utilization: 0.7,
        signal_quality: 80.0,
        temperature: 40.0,
        cpu_usage: 45.0,
        error_rate: 0.002,
        throughput: 75_000_000,
        power_consumption: 15.0
      }

      correlations = CorrelationEngine.get_device_correlations(:cable_modem)
      current_time = DateTime.utc_now()

      # Apply correlations for multiple metrics
      updated_state1 =
        CorrelationEngine.apply_correlations(
          :interface_utilization,
          0.8,
          device_state,
          correlations,
          current_time
        )

      updated_state2 =
        CorrelationEngine.apply_correlations(
          :temperature,
          45.0,
          updated_state1,
          correlations,
          current_time
        )

      # Final state should be stable and realistic
      assert is_map(updated_state2)
      assert map_size(updated_state2) >= map_size(device_state)

      # All values should be within reasonable bounds
      Enum.each(updated_state2, fn {_key, value} ->
        assert is_number(value)
        # Allow negative floats for some metrics
        assert value >= 0 or is_float(value)
      end)
    end

    test "correlation calculations are efficient" do
      device_metrics = %{
        cpu_utilization: 60.0,
        interface_utilization: 0.7,
        temperature: 35.0
      }

      start_time = :os.system_time(:microsecond)

      # Perform 1000 correlation calculations
      for _ <- 1..1000 do
        CorrelationEngine.calculate_power_consumption_correlation(
          device_metrics,
          :cable_modem
        )
      end

      end_time = :os.system_time(:microsecond)
      duration_ms = (end_time - start_time) / 1000

      # Should complete 1000 calculations quickly
      assert duration_ms < 50
    end

    test "signal throughput calculations handle edge cases" do
      # Test very low SNR
      low_result =
        CorrelationEngine.calculate_signal_throughput_correlation(
          5.0,
          -20.0,
          100_000_000
        )

      # Test very high SNR
      high_result =
        CorrelationEngine.calculate_signal_throughput_correlation(
          45.0,
          15.0,
          100_000_000
        )

      # Both should be positive and reasonable
      assert low_result > 0
      assert high_result > 0
      assert high_result > low_result
      # Should be significantly reduced
      assert low_result < 50_000_000
      # Should be reasonably high (allow for jitter)
      assert high_result >= 60_000_000
    end
  end
end
