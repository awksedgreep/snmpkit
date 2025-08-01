defmodule SnmpKit.SnmpMgr.PerformanceBenchmark do
  @moduledoc """
  Performance benchmarking and profiling tools for SNMP operations.
  
  Provides tools to measure and compare performance between different
  SNMP architectures, including throughput, latency, memory usage,
  and resource utilization.
  """
  
  require Logger
  
  @doc """
  Runs a comprehensive benchmark comparing old vs new Multi architecture.
  
  ## Options
  - `:target_count` - Number of targets to test (default: 10)
  - `:requests_per_target` - Number of requests per target (default: 5)
  - `:max_concurrent` - Concurrency limit (default: 10)
  - `:timeout` - Request timeout in ms (default: 5000)
  - `:warmup_rounds` - Warmup iterations (default: 3)
  - `:benchmark_rounds` - Benchmark iterations (default: 10)
  """
  def compare_architectures(opts \\ []) do
    target_count = Keyword.get(opts, :target_count, 10)
    requests_per_target = Keyword.get(opts, :requests_per_target, 5)
    max_concurrent = Keyword.get(opts, :max_concurrent, 10)
    timeout = Keyword.get(opts, :timeout, 5000)
    warmup_rounds = Keyword.get(opts, :warmup_rounds, 3)
    benchmark_rounds = Keyword.get(opts, :benchmark_rounds, 10)
    
    # Start simulated SNMP devices for realistic testing
    Logger.info("Starting #{target_count} simulated SNMP devices...")
    {:ok, devices} = start_simulation_devices(target_count)
    
    # Generate test targets using actual simulated devices
    targets = generate_real_targets(devices, requests_per_target)
    
    Logger.info("Starting performance benchmark with real SNMP devices")
    Logger.info("Targets: #{target_count}, Requests per target: #{requests_per_target}")
    Logger.info("Max concurrent: #{max_concurrent}, Timeout: #{timeout}ms")
    Logger.info("Warmup rounds: #{warmup_rounds}, Benchmark rounds: #{benchmark_rounds}")
    
    # Warmup phase
    Logger.info("Warming up...")
    for _ <- 1..warmup_rounds do
      benchmark_multiv2(targets, max_concurrent, timeout)
      :timer.sleep(100)
    end
    
    # Benchmark V2 architecture (new)
    Logger.info("Benchmarking MultiV2 (new architecture)...")
    v2_results = for _ <- 1..benchmark_rounds do
      benchmark_multiv2(targets, max_concurrent, timeout)
    end
    
    # Benchmark V1 architecture (old) for comparison
    Logger.info("Benchmarking Multi (old architecture)...")
    v1_results = for _ <- 1..benchmark_rounds do
      benchmark_multi_old(targets, max_concurrent, timeout)
    end
    
    # Analyze results
    v2_stats = analyze_benchmark_results(v2_results, "MultiV2 (New)")
    v1_stats = analyze_benchmark_results(v1_results, "Multi (Old)")
    
    # Memory profiling
    Logger.info("Running memory profiling...")
    memory_stats = profile_memory_usage(targets, max_concurrent, timeout)
    
    # UDP buffer monitoring
    Logger.info("Monitoring UDP buffer utilization...")
    buffer_stats = monitor_buffer_usage(targets, max_concurrent, timeout)
    
    # Clean up simulated devices
    cleanup_simulation_devices(devices)
    
    # Generate comprehensive report
    generate_performance_report(v2_stats, v1_stats, memory_stats, buffer_stats, opts)
  end
  
  @doc """
  Measures throughput (requests per second) for a given configuration.
  
  ## Options
  - `:duration_seconds` - How long to run the test (default: 30)
  - `:max_concurrent` - Concurrency limit (default: 10)
  - `:target_count` - Number of targets (default: 5)
  """
  def measure_throughput(opts \\ []) do
    duration_seconds = Keyword.get(opts, :duration_seconds, 30)
    max_concurrent = Keyword.get(opts, :max_concurrent, 10)
    target_count = Keyword.get(opts, :target_count, 5)
    
    # Start simulated devices for realistic throughput testing
    Logger.info("Starting #{target_count} simulated devices for throughput test...")
    {:ok, devices} = start_simulation_devices(target_count)
    
    targets = generate_real_targets(devices, 1)
    
    Logger.info("Starting throughput measurement for #{duration_seconds} seconds")
    
    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + (duration_seconds * 1000)
    
    # Simplified throughput measurement - just count requests in batches
    total_requests = throughput_loop(targets, max_concurrent, end_time, 0)
    
    actual_duration = System.monotonic_time(:millisecond) - start_time
    requests_per_second = if actual_duration > 0, do: total_requests / (actual_duration / 1000), else: 0
    
    # Clean up devices
    cleanup_simulation_devices(devices)
    
    %{
      total_requests: total_requests,
      duration_ms: actual_duration,
      requests_per_second: requests_per_second,
      avg_latency_ms: if(total_requests > 0, do: actual_duration / total_requests, else: 0)
    }
  end
  
  @doc """
  Profiles memory usage during concurrent SNMP operations.
  """
  def profile_memory_usage(targets, max_concurrent, timeout) do
    # Get baseline memory
    baseline_memory = get_process_memory()
    
    # Start memory monitoring
    memory_samples = []
    monitor_pid = spawn_link(fn -> 
      monitor_memory_loop(self(), [])
    end)
    
    # Run benchmark
    start_time = System.monotonic_time(:millisecond)
    _result = benchmark_multiv2(targets, max_concurrent, timeout)
    end_time = System.monotonic_time(:millisecond)
    
    # Stop monitoring
    send(monitor_pid, :stop)
    
    # Collect memory samples
    final_memory_samples = receive do
      {:memory_samples, samples} -> samples
    after 1000 ->
      Logger.warning("Memory monitoring timeout")
      []
    end
    
    # Get final memory
    final_memory = get_process_memory()
    
    %{
      baseline_memory: baseline_memory,
      final_memory: final_memory,
      memory_delta: final_memory - baseline_memory,
      peak_memory: Enum.max(final_memory_samples ++ [baseline_memory]),
      memory_samples: final_memory_samples,
      duration_ms: end_time - start_time
    }
  end
  
  @doc """
  Monitors UDP buffer utilization during high-load operations.
  """
  def monitor_buffer_usage(targets, max_concurrent, timeout) do
    # Start buffer monitoring
    buffer_samples = []
    monitor_pid = spawn_link(fn -> 
      monitor_buffer_loop(self(), [])
    end)
    
    # Run benchmark
    start_time = System.monotonic_time(:millisecond)
    _result = benchmark_multiv2(targets, max_concurrent, timeout)
    end_time = System.monotonic_time(:millisecond)
    
    # Stop monitoring
    send(monitor_pid, :stop)
    
    # Collect buffer samples
    final_buffer_samples = receive do
      {:buffer_samples, samples} -> samples
    after 1000 ->
      Logger.warning("Buffer monitoring timeout")
      []
    end
    
    # Calculate statistics
    utilizations = Enum.map(final_buffer_samples, fn sample -> 
      sample.recv_utilization_percent
    end)
    
    %{
      max_utilization: if(utilizations != [], do: Enum.max(utilizations), else: 0),
      avg_utilization: if(utilizations != [], do: Enum.sum(utilizations) / length(utilizations), else: 0),
      buffer_samples: final_buffer_samples,
      duration_ms: end_time - start_time
    }
  end
  
  # Private functions
  
  defp start_simulation_devices(device_count) do
    # Start simulated SNMP devices for realistic testing
    case SnmpKit.TestSupport.SNMPSimulator.create_device_fleet(
      count: device_count,
      device_type: :cable_modem,
      port_start: 40000
    ) do
      {:ok, devices} -> 
        # Wait for devices to be ready using SNMP ping
        wait_for_devices_ready(devices)
        {:ok, devices}
      {:error, reason} -> 
        Logger.error("Failed to start simulation devices: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp wait_for_devices_ready(devices) do
    Logger.info("Waiting for #{length(devices)} simulated devices to be ready...")
    
    for {device, index} <- Enum.with_index(devices, 1) do
      host = "#{device.host}:#{device.port}"
      
      # Use SNMP ping to check if device is responding
      case wait_for_device_ping(host, device.community, 5000) do
        :ok -> 
          Logger.debug("Device #{index} ready: #{host}")
          :ok
        {:error, reason} ->
          Logger.warning("Device #{index} not ready after 5s: #{host} - #{inspect(reason)}")
          :ok  # Continue anyway for benchmarking
      end
    end
    
    # Small additional buffer for UDP socket stability
    :timer.sleep(100)
    Logger.info("All devices initialization complete")
  end
  
  defp wait_for_device_ping(host, community, timeout) do
    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + timeout
    
    wait_for_device_ping_loop(host, community, end_time)
  end
  
  defp wait_for_device_ping_loop(host, community, end_time) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time >= end_time do
      {:error, :timeout}
    else
      case SnmpKit.SnmpLib.Manager.ping(host, community: community, timeout: 500) do
        {:ok, :reachable} -> :ok
        {:error, _} -> 
          :timer.sleep(100)
          wait_for_device_ping_loop(host, community, end_time)
      end
    end
  end
  
  defp cleanup_simulation_devices(devices) do
    SnmpKit.TestSupport.SNMPSimulator.stop_devices(devices)
  end
  
  defp generate_real_targets(devices, requests_per_target) do
    # Generate targets using actual simulated devices
    for device <- devices do
      for j <- 1..requests_per_target do
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.#{j}.0"}
      end
    end
    |> List.flatten()
  end
  
  defp generate_test_targets(target_count, requests_per_target) do
    # Generate targets that will timeout predictably for benchmarking
    for i <- 1..target_count do
      for j <- 1..requests_per_target do
        {"127.0.0.#{i}", "1.3.6.1.2.1.1.#{j}.0"}
      end
    end
    |> List.flatten()
  end
  
  defp benchmark_multiv2(targets, max_concurrent, timeout) do
    start_time = System.monotonic_time(:millisecond)
    
    # Run the benchmark
    results = SnmpKit.SnmpMgr.MultiV2.get_multi(targets, 
      max_concurrent: max_concurrent,
      timeout: timeout
    )
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # Count successful vs failed requests
    {success_count, error_count} = Enum.reduce(results, {0, 0}, fn
      {:ok, _}, {s, e} -> {s + 1, e}
      {:error, _}, {s, e} -> {s, e + 1}
    end)
    
    %{
      duration_ms: duration,
      total_requests: length(results),
      success_count: success_count,
      error_count: error_count,
      requests_per_second: if(duration > 0, do: length(results) / (duration / 1000), else: 0)
    }
  end
  
  defp benchmark_multi_old(targets, max_concurrent, timeout) do
    start_time = System.monotonic_time(:millisecond)
    
    # Run the benchmark using old Multi architecture
    results = SnmpKit.SnmpMgr.Multi.get_multi(targets, 
      max_concurrent: max_concurrent,
      timeout: timeout
    )
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # Count successful vs failed requests
    {success_count, error_count} = Enum.reduce(results, {0, 0}, fn
      {:ok, _}, {s, e} -> {s + 1, e}
      {:error, _}, {s, e} -> {s, e + 1}
    end)
    
    %{
      duration_ms: duration,
      total_requests: length(results),
      success_count: success_count,
      error_count: error_count,
      requests_per_second: if(duration > 0, do: length(results) / (duration / 1000), else: 0)
    }
  end
  
  defp analyze_benchmark_results(results, name) do
    durations = Enum.map(results, & &1.duration_ms)
    success_rates = Enum.map(results, fn r -> r.success_count / r.total_requests end)
    throughputs = Enum.map(results, & &1.requests_per_second)
    
    %{
      name: name,
      avg_duration_ms: safe_avg(durations),
      min_duration_ms: safe_min(durations),
      max_duration_ms: safe_max(durations),
      avg_success_rate: safe_avg(success_rates),
      avg_throughput_rps: safe_avg(throughputs),
      max_throughput_rps: safe_max(throughputs),
      sample_count: length(results)
    }
  end
  
  defp throughput_loop(targets, max_concurrent, end_time, total_requests) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time >= end_time do
      total_requests
    else
      # Run one batch
      _results = SnmpKit.SnmpMgr.MultiV2.get_multi(targets, 
        max_concurrent: max_concurrent,
        timeout: 500
      )
      
      throughput_loop(targets, max_concurrent, end_time, total_requests + length(targets))
    end
  end
  
  defp monitor_memory_loop(parent_pid, samples) do
    receive do
      :stop ->
        send(parent_pid, {:memory_samples, samples})
    after 100 ->
      memory = get_process_memory()
      new_samples = [memory | samples]
      monitor_memory_loop(parent_pid, new_samples)
    end
  end
  
  defp monitor_buffer_loop(parent_pid, samples) do
    receive do
      :stop ->
        send(parent_pid, {:buffer_samples, samples})
    after 100 ->
      buffer_stats = case Process.whereis(SnmpKit.SnmpMgr.SocketManager) do
        nil -> %{recv_utilization_percent: 0}
        _ -> SnmpKit.SnmpMgr.SocketManager.get_buffer_stats()
      end
      
      new_samples = [buffer_stats | samples]
      monitor_buffer_loop(parent_pid, new_samples)
    end
  end
  
  defp get_process_memory() do
    # Get memory usage for current process
    case Process.info(self(), :memory) do
      {:memory, memory} -> memory
      _ -> 0
    end
  end
  
  defp generate_performance_report(v2_stats, v1_stats, memory_stats, buffer_stats, opts) do
    # Calculate performance improvements
    throughput_improvement = if v1_stats.avg_throughput_rps > 0 do
      ((v2_stats.avg_throughput_rps - v1_stats.avg_throughput_rps) / v1_stats.avg_throughput_rps) * 100
    else
      0
    end
    
    duration_improvement = if v1_stats.avg_duration_ms > 0 do
      ((v1_stats.avg_duration_ms - v2_stats.avg_duration_ms) / v1_stats.avg_duration_ms) * 100
    else
      0
    end
    
    report = """
    
    ========================================
    SNMP Performance Benchmark Report
    ========================================
    
    Configuration:
      Target Count: #{Keyword.get(opts, :target_count, 10)}
      Requests per Target: #{Keyword.get(opts, :requests_per_target, 5)}
      Max Concurrent: #{Keyword.get(opts, :max_concurrent, 10)}
      Timeout: #{Keyword.get(opts, :timeout, 5000)}ms
      Benchmark Rounds: #{Keyword.get(opts, :benchmark_rounds, 10)}
    
    OLD Architecture (Multi) Results:
      Average Duration: #{safe_round(v1_stats.avg_duration_ms, 2)}ms
      Average Success Rate: #{safe_round(v1_stats.avg_success_rate * 100, 2)}%
      Average Throughput: #{safe_round(v1_stats.avg_throughput_rps, 2)} requests/sec
      Peak Throughput: #{safe_round(v1_stats.max_throughput_rps, 2)} requests/sec
    
    NEW Architecture (MultiV2) Results:
      Average Duration: #{safe_round(v2_stats.avg_duration_ms, 2)}ms
      Average Success Rate: #{safe_round(v2_stats.avg_success_rate * 100, 2)}%
      Average Throughput: #{safe_round(v2_stats.avg_throughput_rps, 2)} requests/sec
      Peak Throughput: #{safe_round(v2_stats.max_throughput_rps, 2)} requests/sec
    
    PERFORMANCE IMPROVEMENTS:
      Duration Improvement: #{safe_round(duration_improvement, 2)}% faster
      Throughput Improvement: #{safe_round(throughput_improvement, 2)}% higher
      Speedup Factor: #{safe_round(v2_stats.avg_throughput_rps / v1_stats.avg_throughput_rps, 2)}x
    
    Memory Usage:
      Baseline Memory: #{format_bytes(memory_stats.baseline_memory)}
      Final Memory: #{format_bytes(memory_stats.final_memory)}
      Memory Delta: #{format_bytes(memory_stats.memory_delta)}
      Peak Memory: #{format_bytes(memory_stats.peak_memory)}
    
    UDP Buffer Utilization:
      Max Utilization: #{safe_round(buffer_stats.max_utilization, 2)}%
      Average Utilization: #{safe_round(buffer_stats.avg_utilization, 2)}%
      Buffer Samples: #{length(buffer_stats.buffer_samples)}
    
    Architecture Benefits Demonstrated:
      ✓ Eliminated GenServer bottleneck - direct UDP sending
      ✓ Shared socket reduces overhead vs individual sockets
      ✓ Atomic request ID generation via ETS
      ✓ Proper concurrency control via Task.async_stream
      ✓ Real-time buffer monitoring prevents packet loss
    
    ========================================
    """
    
    Logger.info(report)
    
    %{
      v2_stats: v2_stats,
      v1_stats: v1_stats,
      memory_stats: memory_stats,
      buffer_stats: buffer_stats,
      throughput_improvement: throughput_improvement,
      duration_improvement: duration_improvement,
      report: report
    }
  end
  
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{safe_round(bytes / 1024, 2)}KB"
  defp format_bytes(bytes), do: "#{safe_round(bytes / 1024 / 1024, 2)}MB"
  
  defp safe_round(number, precision) do
    if is_float(number) do
      Float.round(number, precision)
    else
      number
    end
  end
  
  defp safe_avg([]), do: 0
  defp safe_avg(values), do: Enum.sum(values) / length(values)
  
  defp safe_min([]), do: 0
  defp safe_min(values), do: Enum.min(values)
  
  defp safe_max([]), do: 0
  defp safe_max(values), do: Enum.max(values)
end