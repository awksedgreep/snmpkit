defmodule SnmpKit.SnmpLib.MonitorTest do
  use ExUnit.Case
  alias SnmpKit.SnmpLib.Monitor

  setup do
    # Start a fresh monitor for each test
    {:ok, pid} = Monitor.start_link(name: nil)
    {:ok, monitor: pid}
  end

  describe "export_data/2" do
    test "exports data as JSON" do
      # Record some test data
      Monitor.record_operation(%{
        device: "192.168.1.1",
        operation: :get,
        duration: 100,
        result: :success
      })

      # Export as JSON
      json_data = Monitor.export_data(:json, :all_time)

      # Parse to verify it's valid JSON
      assert {:ok, decoded} = JSON.decode(json_data)
      assert is_map(decoded)
      assert Map.has_key?(decoded, "operations")
      assert Map.has_key?(decoded, "system_stats")
      assert Map.has_key?(decoded, "device_stats")
    end

    test "exports data as CSV" do
      # Record some test data
      Monitor.record_operation(%{
        device: "192.168.1.1",
        operation: :get,
        duration: 100,
        result: :success
      })

      # Export as CSV
      csv_data = Monitor.export_data(:csv, :all_time)

      # Verify CSV format
      assert is_binary(csv_data)
      assert String.contains?(csv_data, "timestamp,device,operation,duration,result,error_type")
    end

    test "exports data as Prometheus format" do
      # Record some test data
      Monitor.record_operation(%{
        device: "192.168.1.1",
        operation: :get,
        duration: 100,
        result: :success
      })

      # Export as Prometheus
      prom_data = Monitor.export_data(:prometheus, :all_time)

      # Verify Prometheus format
      assert is_binary(prom_data)
      assert String.contains?(prom_data, "# HELP")
      assert String.contains?(prom_data, "# TYPE")
    end
  end

  describe "record_operation/1" do
    test "records operations and updates statistics" do
      # Record multiple operations
      Monitor.record_operation(%{
        device: "192.168.1.1",
        operation: :get,
        duration: 100,
        result: :success
      })

      Monitor.record_operation(%{
        device: "192.168.1.1",
        operation: :get_next,
        duration: 150,
        result: :error,
        error_type: :timeout
      })

      # Get device stats
      stats = Monitor.get_device_stats("192.168.1.1")

      assert stats.total_operations == 2
      assert stats.successful_operations == 1
      assert stats.failed_operations == 1
      assert stats.error_rate == 50.0
      assert stats.avg_response_time == 125.0
    end
  end

  describe "get_system_stats/0" do
    test "returns system-wide statistics" do
      # Record some operations
      Monitor.record_operation(%{
        device: "192.168.1.1",
        operation: :get,
        duration: 100,
        result: :success
      })

      # Get system stats
      stats = Monitor.get_system_stats()

      assert is_map(stats)
      assert stats.total_operations == 1
      assert stats.total_devices == 1
      assert stats.global_error_rate == 0.0
    end
  end
end
