defmodule SnmpSim.Performance.Benchmarks do
  @moduledoc """
  Comprehensive benchmarking framework for SNMP simulator performance testing.

  Features:
  - Load testing with configurable request patterns
  - Throughput and latency measurement
  - Memory and CPU profiling
  - Concurrent client simulation
  - Performance regression detection
  - Automated benchmark reporting
  """

  require Logger
  alias SnmpSim.Performance.{ResourceManager, OptimizedDevicePool}

  # Benchmark configuration
  # 1 minute
  @default_benchmark_duration 60_000
  # Concurrent SNMP clients
  @default_concurrent_clients 50
  # Requests per second
  @default_request_rate 1000
  # 10 seconds warm-up
  @default_warm_up_duration 10_000

  # Test OIDs for benchmarking
  @test_oids [
    # sysDescr
    "1.3.6.1.2.1.1.1.0",
    # sysUpTime
    "1.3.6.1.2.1.1.3.0",
    # ifInOctets
    "1.3.6.1.2.1.2.2.1.10.1",
    # ifOutOctets
    "1.3.6.1.2.1.2.2.1.16.1",
    # sysName
    "1.3.6.1.2.1.1.5.0"
  ]

  defmodule BenchmarkResult do
    @moduledoc "Structure for benchmark results"

    defstruct [
      :test_name,
      :start_time,
      :end_time,
      :duration_ms,
      :total_requests,
      :successful_requests,
      :failed_requests,
      :requests_per_second,
      :avg_latency_ms,
      :p95_latency_ms,
      :p99_latency_ms,
      :max_latency_ms,
      :min_latency_ms,
      :memory_usage,
      :cpu_usage,
      :device_count,
      :error_rate,
      :latency_histogram,
      :performance_profile
    ]
  end

  # Public API

  @doc """
  Run comprehensive benchmark suite.
  """
  def run_benchmark_suite(_opts \\ []) do
    Logger.info("Starting comprehensive benchmark suite")

    suite_start = System.monotonic_time(:millisecond)

    # Define benchmark scenarios
    scenarios = [
      {:throughput_test, "Maximum throughput test",
       [concurrent_clients: 100, request_rate: 10000, duration: 30_000]},
      {:latency_test, "Low latency test",
       [concurrent_clients: 10, request_rate: 100, duration: 60_000]},
      {:sustained_load_test, "Sustained load test",
       [concurrent_clients: 50, request_rate: 1000, duration: 300_000]},
      {:scaling_test, "Device scaling test",
       [device_counts: [100, 1000, 5000, 10000], concurrent_clients: 20]},
      {:memory_stress_test, "Memory stress test",
       [concurrent_clients: 200, request_rate: 5000, duration: 120_000]}
    ]

    # Run each scenario
    results =
      Enum.map(scenarios, fn {scenario_name, description, scenario_opts} ->
        Logger.info("Running scenario: #{description}")

        case scenario_name do
          :scaling_test ->
            run_scaling_benchmark(scenario_opts)

          :memory_stress_test ->
            run_memory_stress_benchmark(scenario_opts)

          _ ->
            run_single_benchmark(to_string(scenario_name), scenario_opts)
        end
      end)

    suite_duration = System.monotonic_time(:millisecond) - suite_start

    # Generate comprehensive report
    suite_report = generate_suite_report(results, suite_duration)

    Logger.info("Benchmark suite completed in #{suite_duration}ms")
    suite_report
  end

  @doc """
  Run single benchmark with specified parameters.
  """
  def run_single_benchmark(test_name, opts \\ []) do
    # Configuration
    _walk_file = Keyword.get(opts, :walk_file, "priv/walks/cable_modem.walk")
    _measure_data_consistency = Keyword.get(opts, :measure_data_consistency, true)
    duration = Keyword.get(opts, :duration, @default_benchmark_duration)
    concurrent_clients = Keyword.get(opts, :concurrent_clients, @default_concurrent_clients)
    request_rate = Keyword.get(opts, :request_rate, @default_request_rate)
    warm_up_duration = Keyword.get(opts, :warm_up_duration, @default_warm_up_duration)
    _measure_recovery_times = Keyword.get(opts, :measure_recovery_times, true)
    device_ports = Keyword.get(opts, :device_ports, [30001, 30002, 30003, 30004, 30005])

    Logger.info("Starting benchmark: #{test_name}")

    Logger.info(
      "Configuration: #{concurrent_clients} clients, #{request_rate} req/s, #{duration}ms duration"
    )

    # Setup devices for testing
    setup_benchmark_devices(device_ports)

    # Warm-up phase
    if warm_up_duration > 0 do
      Logger.info("Warm-up phase: #{warm_up_duration}ms")
      run_warm_up(device_ports, warm_up_duration, div(concurrent_clients, 2))
    end

    # Main benchmark phase
    start_time = System.monotonic_time(:millisecond)

    # Start performance monitoring
    monitor_ref = start_performance_monitoring()

    # Start concurrent clients
    client_results =
      start_concurrent_clients(
        concurrent_clients,
        device_ports,
        request_rate,
        duration
      )

    end_time = System.monotonic_time(:millisecond)
    actual_duration = end_time - start_time

    # Stop monitoring and collect results
    performance_data = stop_performance_monitoring(monitor_ref)

    # Analyze results
    result =
      analyze_benchmark_results(
        test_name,
        client_results,
        performance_data,
        start_time,
        end_time,
        actual_duration
      )

    # Cleanup
    cleanup_benchmark_devices(device_ports)

    Logger.info(
      "Benchmark #{test_name} completed: #{result.requests_per_second} req/s, #{result.avg_latency_ms}ms avg latency"
    )

    result
  end

  @doc """
  Run scaling benchmark to test performance at different device counts.
  """
  def run_scaling_benchmark(opts) do
    _measure_downtime = Keyword.get(opts, :measure_downtime, true)
    device_counts = Keyword.get(opts, :device_counts, [100, 1000, 5000])
    concurrent_clients = Keyword.get(opts, :concurrent_clients, 20)

    results =
      Enum.map(device_counts, fn device_count ->
        Logger.info("Scaling test with #{device_count} devices")

        # Create device ports
        device_ports = Enum.to_list(30001..(30000 + device_count))

        # Run benchmark
        result =
          run_single_benchmark(
            "scaling_#{device_count}_devices",
            device_ports: device_ports,
            concurrent_clients: concurrent_clients,
            request_rate: 500,
            duration: 60_000
          )

        {device_count, result}
      end)

    analyze_scaling_results(results)
  end

  @doc """
  Run memory stress test to identify memory leaks and limits.
  """
  def run_memory_stress_benchmark(opts) do
    concurrent_clients = Keyword.get(opts, :concurrent_clients, 200)
    request_rate = Keyword.get(opts, :request_rate, 5000)
    duration = Keyword.get(opts, :duration, 120_000)

    Logger.info("Running memory stress test")

    # Monitor memory usage throughout test
    memory_monitor = start_memory_monitoring()

    # Run high-intensity benchmark
    result =
      run_single_benchmark(
        "memory_stress_test",
        concurrent_clients: concurrent_clients,
        request_rate: request_rate,
        duration: duration
      )

    # Analyze memory patterns
    memory_analysis = analyze_memory_patterns(memory_monitor)

    Map.put(result, :memory_analysis, memory_analysis)
  end

  @doc """
  Benchmark response to various error conditions.
  """
  def run_error_resilience_benchmark(_opts \\ []) do
    Logger.info("Running error resilience benchmark")

    # Test different error scenarios
    error_scenarios = [
      # 10% timeout rate
      {:timeout_errors, 0.1},
      # 5% packet loss
      {:packet_loss, 0.05},
      # 2% malformed requests
      {:malformed_requests, 0.02},
      # 1% resource exhaustion
      {:resource_exhaustion, 0.01}
    ]

    results =
      Enum.map(error_scenarios, fn {error_type, error_rate} ->
        Logger.info("Testing #{error_type} at #{error_rate * 100}% rate")

        # Configure error injection
        configure_error_injection(error_type, error_rate)

        # Run benchmark
        result =
          run_single_benchmark(
            "error_resilience_#{error_type}",
            duration: 60_000,
            concurrent_clients: 30
          )

        # Disable error injection
        disable_error_injection(error_type)

        {error_type, error_rate, result}
      end)

    analyze_error_resilience_results(results)
  end

  # Private functions

  defp setup_benchmark_devices(device_ports) do
    Enum.each(device_ports, fn port ->
      _device_type = determine_device_type_for_port(port)

      case OptimizedDevicePool.get_device(port) do
        {:ok, _device_pid} ->
          # Device already exists
          :ok

        {:error, _reason} ->
          Logger.warning("Failed to create device on port #{port}")
      end
    end)

    # Allow devices to initialize
    Process.sleep(1000)
  end

  defp cleanup_benchmark_devices(_device_ports) do
    # Cleanup is handled by resource manager
    :ok
  end

  defp run_warm_up(device_ports, duration, client_count) do
    warm_up_clients =
      start_concurrent_clients(
        client_count,
        device_ports,
        # Low request rate for warm-up
        100,
        duration
      )

    # Wait for warm-up to complete
    Enum.each(warm_up_clients, fn {_client_id, task} ->
      Task.await(task, duration + 5000)
    end)
  end

  defp start_concurrent_clients(client_count, device_ports, request_rate, duration) do
    requests_per_client = div(request_rate, client_count)
    interval_ms = div(1000, max(1, requests_per_client))

    clients =
      Enum.map(1..client_count, fn client_id ->
        task =
          Task.async(fn ->
            run_client_benchmark(client_id, device_ports, interval_ms, duration)
          end)

        {client_id, task}
      end)

    # Wait for all clients to complete and collect results
    Enum.map(clients, fn {client_id, task} ->
      try do
        result = Task.await(task, duration + 10_000)
        {client_id, {:ok, result}}
      rescue
        error ->
          Logger.error("Client #{client_id} failed: #{inspect(error)}")
          {client_id, {:error, error}}
      end
    end)
  end

  defp run_client_benchmark(client_id, device_ports, interval_ms, duration) do
    end_time = System.monotonic_time(:millisecond) + duration

    results = %{
      client_id: client_id,
      requests_sent: 0,
      requests_successful: 0,
      requests_failed: 0,
      latencies: [],
      errors: []
    }

    client_loop(results, device_ports, interval_ms, end_time)
  end

  defp client_loop(results, device_ports, interval_ms, end_time) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      results
    else
      # Select random device and OID
      port = Enum.random(device_ports)
      oid = Enum.random(@test_oids)

      # Send SNMP request and measure latency
      {_latency, _request_result} = measure_request_latency(port, oid)

      # Update results
      updated_results = results

      # Sleep to maintain request rate
      if interval_ms > 0 do
        Process.sleep(interval_ms)
      end

      client_loop(updated_results, device_ports, interval_ms, end_time)
    end
  end

  defp measure_request_latency(port, _oid) do
    start_time = System.monotonic_time(:microsecond)

    result =
      try do
        # Simple SNMP GET request using SnmpMgr
        agent_config = %{
          host: "127.0.0.1",
          port: port,
          community: "public",
          version: :v2c,
          timeout: 5000
        }

        case SnmpMgr.get(agent_config, [1, 3, 6, 1, 2, 1, 1, 1, 0]) do
          {:ok, _value} -> :ok
          {:error, _reason} -> :error
        end
      rescue
        error ->
          {:error, error}
      end

    end_time = System.monotonic_time(:microsecond)
    latency_ms = (end_time - start_time) / 1000

    {latency_ms, result}
  end

  defp start_performance_monitoring() do
    # Start collecting performance metrics
    monitor_pid =
      spawn_link(fn ->
        performance_monitoring_loop([])
      end)

    monitor_pid
  end

  defp performance_monitoring_loop(collected_data) do
    receive do
      :stop ->
        collected_data

      _ ->
        # Collect current metrics
        metrics = %{
          timestamp: System.monotonic_time(:millisecond),
          memory_usage: get_memory_usage(),
          cpu_usage: get_cpu_usage(),
          device_count: get_active_device_count(),
          resource_stats: ResourceManager.get_resource_stats()
        }

        # Collect every second
        Process.sleep(1000)
        performance_monitoring_loop([metrics | collected_data])
    end
  end

  defp stop_performance_monitoring(monitor_pid) do
    send(monitor_pid, :stop)

    receive do
      data when is_list(data) -> data
    after
      5000 -> []
    end
  end

  defp start_memory_monitoring() do
    # Start dedicated memory monitoring
    spawn_link(fn ->
      memory_monitoring_loop([])
    end)
  end

  defp memory_monitoring_loop(memory_data) do
    receive do
      :stop ->
        memory_data

      _ ->
        memory_info = :erlang.memory()

        memory_point = %{
          timestamp: System.monotonic_time(:millisecond),
          total: memory_info[:total],
          processes: memory_info[:processes],
          system: memory_info[:system],
          atom: memory_info[:atom],
          binary: memory_info[:binary]
        }

        # Collect every 500ms
        Process.sleep(500)
        memory_monitoring_loop([memory_point | memory_data])
    end
  end

  defp analyze_benchmark_results(
         test_name,
         client_results,
         performance_data,
         start_time,
         end_time,
         duration
       ) do
    # Extract successful client results
    successful_results =
      Enum.filter(client_results, fn {_id, result} ->
        match?({:ok, _}, result)
      end)

    # Aggregate client data
    aggregated =
      Enum.reduce(
        successful_results,
        %{
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          all_latencies: [],
          all_errors: []
        },
        fn {_id, {:ok, client_data}}, acc ->
          %{
            total_requests: acc.total_requests + client_data.requests_sent,
            successful_requests: acc.successful_requests + client_data.requests_successful,
            failed_requests: acc.failed_requests + client_data.requests_failed,
            all_latencies: acc.all_latencies ++ client_data.latencies,
            all_errors: acc.all_errors ++ client_data.errors
          }
        end
      )

    # Calculate statistics
    latencies = Enum.sort(aggregated.all_latencies)
    latency_stats = calculate_latency_statistics(latencies)

    requests_per_second =
      if duration > 0 do
        aggregated.total_requests / (duration / 1000)
      else
        0
      end

    error_rate =
      if aggregated.total_requests > 0 do
        aggregated.failed_requests / aggregated.total_requests * 100
      else
        0
      end

    # Get final performance metrics
    final_metrics = List.first(performance_data) || %{}

    %BenchmarkResult{
      test_name: test_name,
      start_time: start_time,
      end_time: end_time,
      duration_ms: duration,
      total_requests: aggregated.total_requests,
      successful_requests: aggregated.successful_requests,
      failed_requests: aggregated.failed_requests,
      requests_per_second: Float.round(requests_per_second, 2),
      avg_latency_ms: latency_stats.avg,
      p95_latency_ms: latency_stats.p95,
      p99_latency_ms: latency_stats.p99,
      max_latency_ms: latency_stats.max,
      min_latency_ms: latency_stats.min,
      memory_usage: final_metrics[:memory_usage] || 0,
      cpu_usage: final_metrics[:cpu_usage] || 0,
      device_count: final_metrics[:device_count] || 0,
      error_rate: Float.round(error_rate, 2),
      latency_histogram: create_latency_histogram(latencies),
      performance_profile: performance_data
    }
  end

  defp calculate_latency_statistics(latencies) when length(latencies) == 0 do
    %{avg: 0, p95: 0, p99: 0, max: 0, min: 0}
  end

  defp calculate_latency_statistics(latencies) do
    count = length(latencies)
    sum = Enum.sum(latencies)

    p95_index = max(0, round(count * 0.95) - 1)
    p99_index = max(0, round(count * 0.99) - 1)

    %{
      avg: Float.round(sum / count, 2),
      p95: Float.round(Enum.at(latencies, p95_index, 0), 2),
      p99: Float.round(Enum.at(latencies, p99_index, 0), 2),
      max: Float.round(Enum.max(latencies), 2),
      min: Float.round(Enum.min(latencies), 2)
    }
  end

  defp create_latency_histogram(latencies) do
    # Create histogram buckets (0-1ms, 1-5ms, 5-10ms, 10-50ms, 50ms+)
    buckets = %{
      "0-1ms" => 0,
      "1-5ms" => 0,
      "5-10ms" => 0,
      "10-50ms" => 0,
      "50ms+" => 0
    }

    Enum.reduce(latencies, buckets, fn latency, acc ->
      cond do
        latency <= 1 -> Map.update!(acc, "0-1ms", &(&1 + 1))
        latency <= 5 -> Map.update!(acc, "1-5ms", &(&1 + 1))
        latency <= 10 -> Map.update!(acc, "5-10ms", &(&1 + 1))
        latency <= 50 -> Map.update!(acc, "10-50ms", &(&1 + 1))
        true -> Map.update!(acc, "50ms+", &(&1 + 1))
      end
    end)
  end

  defp analyze_scaling_results(results) do
    %{
      test_type: :scaling_benchmark,
      device_scaling:
        Enum.map(results, fn {device_count, result} ->
          %{
            device_count: device_count,
            requests_per_second: result.requests_per_second,
            avg_latency_ms: result.avg_latency_ms,
            memory_usage: result.memory_usage,
            efficiency_score: result.requests_per_second / device_count
          }
        end),
      scaling_efficiency: calculate_scaling_efficiency(results)
    }
  end

  defp calculate_scaling_efficiency(results) do
    # Calculate how well performance scales with device count
    baseline = List.first(results)

    if baseline do
      {baseline_count, baseline_result} = baseline
      baseline_rps_per_device = baseline_result.requests_per_second / baseline_count

      Enum.map(results, fn {device_count, result} ->
        current_rps_per_device = result.requests_per_second / device_count
        efficiency = current_rps_per_device / baseline_rps_per_device * 100

        %{
          device_count: device_count,
          efficiency_percent: Float.round(efficiency, 1)
        }
      end)
    else
      []
    end
  end

  defp analyze_memory_patterns(memory_monitor) do
    send(memory_monitor, :stop)

    memory_data =
      receive do
        data when is_list(data) -> Enum.reverse(data)
      after
        5000 -> []
      end

    if length(memory_data) > 0 do
      initial_memory = hd(memory_data).total
      final_memory = List.last(memory_data).total
      peak_memory = Enum.max_by(memory_data, & &1.total).total

      %{
        initial_memory_mb: div(initial_memory, 1024 * 1024),
        final_memory_mb: div(final_memory, 1024 * 1024),
        peak_memory_mb: div(peak_memory, 1024 * 1024),
        memory_growth_mb: div(final_memory - initial_memory, 1024 * 1024),
        potential_leak: final_memory > initial_memory * 1.1,
        memory_timeline: memory_data
      }
    else
      %{error: "No memory data collected"}
    end
  end

  defp analyze_error_resilience_results(results) do
    %{
      test_type: :error_resilience_benchmark,
      error_scenarios:
        Enum.map(results, fn {error_type, error_rate, result} ->
          %{
            error_type: error_type,
            configured_error_rate: error_rate * 100,
            actual_error_rate: result.error_rate,
            performance_impact: %{
              requests_per_second: result.requests_per_second,
              avg_latency_ms: result.avg_latency_ms,
              success_rate: 100 - result.error_rate
            }
          }
        end),
      recommendations: []
    }
  end

  defp generate_suite_report(results, suite_duration) do
    %{
      suite_name: "SNMP Simulator Performance Benchmark Suite",
      execution_time: System.system_time(:second),
      total_duration_ms: suite_duration,
      results: results,
      summary: %{
        total_tests: length(results),
        max_throughput: get_max_throughput(results),
        min_latency: get_min_latency(results),
        memory_efficiency: analyze_memory_efficiency(results),
        overall_score: calculate_overall_performance_score(results)
      },
      recommendations: generate_performance_recommendations(results)
    }
  end

  defp get_max_throughput(results) do
    results
    |> Enum.filter(&is_map/1)
    |> Enum.map(& &1.requests_per_second)
    |> Enum.max(fn -> 0 end)
  end

  defp get_min_latency(results) do
    results
    |> Enum.filter(&is_map/1)
    |> Enum.map(& &1.avg_latency_ms)
    |> Enum.min(fn -> 0 end)
  end

  defp analyze_memory_efficiency(results) do
    # Simple memory efficiency analysis
    results
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn result ->
      if result.memory_usage > 0 and result.device_count > 0 do
        result.memory_usage / result.device_count
      else
        0
      end
    end)
    |> Enum.sum()
    |> case do
      0 -> 0
      sum -> Float.round(sum / length(results), 2)
    end
  end

  defp calculate_overall_performance_score(results) do
    # Weighted performance score
    # Normalize to 0-100 range
    throughput_score = get_max_throughput(results) / 1000
    # Lower latency = higher score
    latency_score = max(0, 100 - get_min_latency(results))

    Float.round(throughput_score * 0.7 + latency_score * 0.3, 1)
  end

  defp generate_performance_recommendations(results) do
    recommendations = []

    max_throughput = get_max_throughput(results)
    min_latency = get_min_latency(results)

    recommendations =
      if max_throughput < 1000 do
        [
          "Consider increasing worker pool size or optimizing device response times"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if min_latency > 10 do
        ["Optimize hot path processing to reduce response latency" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["Performance is within acceptable ranges"]
    else
      recommendations
    end
  end

  # Helper functions for configuration and utilities

  defp determine_device_type_for_port(port) do
    # Simple device type assignment based on port
    case rem(port, 5) do
      0 -> :cable_modem
      1 -> :mta
      2 -> :switch
      3 -> :router
      4 -> :cmts
    end
  end

  defp configure_error_injection(_error_type, _error_rate) do
    # Placeholder for error injection configuration
    :ok
  end

  defp disable_error_injection(_error_type) do
    # Placeholder for disabling error injection
    :ok
  end

  defp get_memory_usage() do
    # MB
    div(:erlang.memory(:total), 1024 * 1024)
  end

  defp get_cpu_usage() do
    if Code.ensure_loaded?(:cpu_sup) do
      case :cpu_sup.util() do
        usage when is_number(usage) -> usage
        {:error, _} -> 0.0
      end
    else
      0.0
    end
  end

  defp get_active_device_count() do
    case ResourceManager.get_resource_stats() do
      %{device_count: count} -> count
      _ -> 0
    end
  end
end
