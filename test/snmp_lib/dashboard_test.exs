defmodule SnmpKit.SnmpLib.DashboardTest do
  use ExUnit.Case, async: false
  doctest SnmpKit.SnmpLib.Dashboard

  alias SnmpKit.SnmpKit.SnmpLib.Dashboard

  @moduletag :dashboard_test

  setup do
    # Ensure dashboard process is stopped before each test
    if Process.whereis(Dashboard) do
      try do
        GenServer.stop(Dashboard, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end

    :timer.sleep(10)
    :ok
  end

  describe "Dashboard.start_link/1" do
    test "starts with default configuration" do
      assert {:ok, pid} = Dashboard.start_link()
      assert Process.alive?(pid)

      try do
        GenServer.stop(Dashboard)
      catch
        :exit, _ -> :ok
      end
    end

    test "starts with custom configuration" do
      opts = [
        port: 8080,
        prometheus_enabled: true,
        retention_days: 14
      ]

      assert {:ok, pid} = Dashboard.start_link(opts)
      assert Process.alive?(pid)

      try do
        GenServer.stop(Dashboard)
      catch
        :exit, _ -> :ok
      end
    end
  end

  describe "Dashboard.record_metric/3" do
    setup do
      {:ok, _pid} = Dashboard.start_link()

      on_exit(fn ->
        if Process.whereis(Dashboard) do
          try do
            GenServer.stop(Dashboard, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "records simple metrics" do
      :ok = Dashboard.record_metric(:test_metric, 100)
      :ok = Dashboard.record_metric(:test_metric, 200, %{device: "test_device"})

      # Allow time for async processing
      :timer.sleep(10)
    end

    test "records SNMP operation metrics" do
      :ok =
        Dashboard.record_metric(:snmp_response_time, 125, %{
          device: "192.168.1.1",
          operation: "get",
          status: :success
        })

      :ok =
        Dashboard.record_metric(:snmp_errors, 1, %{
          device: "192.168.1.1",
          error_type: "timeout"
        })
    end
  end

  describe "Dashboard.create_alert/3" do
    setup do
      {:ok, _pid} = Dashboard.start_link()

      on_exit(fn ->
        if Process.whereis(Dashboard) do
          try do
            GenServer.stop(Dashboard, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "creates alerts with different levels" do
      :ok = Dashboard.create_alert(:test_info, :info, %{message: "Info alert"})
      :ok = Dashboard.create_alert(:test_warning, :warning, %{message: "Warning alert"})
      :ok = Dashboard.create_alert(:test_critical, :critical, %{message: "Critical alert"})

      # Allow time for async processing
      :timer.sleep(10)
    end

    test "creates device-specific alerts" do
      :ok =
        Dashboard.create_alert(:device_unreachable, :critical, %{
          device: "192.168.1.1",
          last_seen: DateTime.utc_now(),
          consecutive_failures: 5
        })

      :ok =
        Dashboard.create_alert(:slow_response, :warning, %{
          device: "192.168.1.1",
          avg_response_time: 5000,
          threshold: 2000
        })
    end
  end

  describe "Dashboard.get_metrics_summary/0" do
    setup do
      {:ok, _pid} = Dashboard.start_link()

      on_exit(fn ->
        if Process.whereis(Dashboard) do
          try do
            GenServer.stop(Dashboard, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "returns metrics summary" do
      # Record some test metrics
      Dashboard.record_metric(:snmp_response_time, 100, %{device: "device1", status: :success})
      Dashboard.record_metric(:snmp_response_time, 200, %{device: "device2", status: :success})
      Dashboard.record_metric(:snmp_errors, 1, %{device: "device3", status: :error})

      :timer.sleep(10)

      summary = Dashboard.get_metrics_summary()

      assert is_map(summary)
      assert Map.has_key?(summary, :total_operations)
      assert Map.has_key?(summary, :success_rate)
      assert Map.has_key?(summary, :avg_response_time)
      assert Map.has_key?(summary, :active_devices)
      assert Map.has_key?(summary, :pool_utilization)
      assert Map.has_key?(summary, :error_rates)

      assert is_number(summary.total_operations)
      assert is_float(summary.success_rate)
      assert is_float(summary.avg_response_time)
    end
  end

  describe "Dashboard.get_device_metrics/1" do
    setup do
      {:ok, _pid} = Dashboard.start_link()

      on_exit(fn ->
        if Process.whereis(Dashboard) do
          try do
            GenServer.stop(Dashboard, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "returns device-specific metrics" do
      device_id = "192.168.1.1"

      # Record some metrics for the device
      Dashboard.record_metric(:snmp_response_time, 150, %{device: device_id})
      Dashboard.record_metric(:snmp_response_time, 175, %{device: device_id})

      :timer.sleep(10)

      device_metrics = Dashboard.get_device_metrics(device_id)

      assert is_map(device_metrics)
      assert Map.has_key?(device_metrics, :device_id)
      assert Map.has_key?(device_metrics, :total_operations)
      assert Map.has_key?(device_metrics, :response_times)
      assert Map.has_key?(device_metrics, :error_count)
      assert Map.has_key?(device_metrics, :last_seen)

      assert device_metrics.device_id == device_id
    end
  end

  describe "Dashboard.get_active_alerts/1" do
    setup do
      {:ok, _pid} = Dashboard.start_link()

      on_exit(fn ->
        if Process.whereis(Dashboard) do
          try do
            GenServer.stop(Dashboard, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "returns all active alerts" do
      # Create some test alerts
      Dashboard.create_alert(:test_alert1, :warning, %{device: "device1"})
      Dashboard.create_alert(:test_alert2, :critical, %{device: "device2"})

      :timer.sleep(10)

      alerts = Dashboard.get_active_alerts()
      assert is_list(alerts)
    end

    test "filters alerts by level" do
      # Create alerts with different levels
      Dashboard.create_alert(:test_warning, :warning, %{device: "device1"})
      Dashboard.create_alert(:test_critical, :critical, %{device: "device2"})

      :timer.sleep(10)

      critical_alerts = Dashboard.get_active_alerts(level: :critical)
      assert is_list(critical_alerts)
    end
  end

  describe "Dashboard.acknowledge_alert/2" do
    setup do
      {:ok, _pid} = Dashboard.start_link()

      on_exit(fn ->
        if Process.whereis(Dashboard) do
          try do
            GenServer.stop(Dashboard, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "acknowledges device alerts" do
      # Create an alert
      Dashboard.create_alert(:device_down, :critical, %{device: "192.168.1.1"})

      :timer.sleep(10)

      # Acknowledge the alert
      :ok = Dashboard.acknowledge_alert(:device_down, "192.168.1.1")
    end
  end

  describe "Dashboard.export_prometheus/0" do
    setup do
      {:ok, _pid} = Dashboard.start_link()

      on_exit(fn ->
        if Process.whereis(Dashboard) do
          try do
            GenServer.stop(Dashboard, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "exports metrics in Prometheus format" do
      # Record some metrics
      Dashboard.record_metric(:snmp_response_time, 100, %{status: :success})
      Dashboard.record_metric(:snmp_response_time, 200, %{status: :success})

      :timer.sleep(10)

      prometheus_data = Dashboard.export_prometheus()

      assert is_binary(prometheus_data)
      assert String.contains?(prometheus_data, "snmp_lib_total_operations")
      assert String.contains?(prometheus_data, "snmp_lib_success_rate")
      assert String.contains?(prometheus_data, "snmp_lib_avg_response_time")
    end
  end

  describe "Dashboard.get_timeseries/3" do
    setup do
      {:ok, _pid} = Dashboard.start_link()

      on_exit(fn ->
        if Process.whereis(Dashboard) do
          try do
            GenServer.stop(Dashboard, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "returns timeseries data for metrics" do
      # Record some metrics
      Dashboard.record_metric(:snmp_response_time, 100, %{device: "device1"})
      Dashboard.record_metric(:snmp_response_time, 200, %{device: "device1"})

      :timer.sleep(10)

      # Get timeseries data
      timeseries = Dashboard.get_timeseries(:snmp_response_time, 3_600_000)
      assert is_list(timeseries)

      # Get filtered timeseries data
      device_timeseries =
        Dashboard.get_timeseries(:snmp_response_time, 3_600_000, %{device: "device1"})

      assert is_list(device_timeseries)
    end
  end
end
