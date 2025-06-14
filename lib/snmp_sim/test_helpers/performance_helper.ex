defmodule SnmpSim.TestHelpers.PerformanceHelper do
  require Logger
  @moduledoc """
  Performance testing utilities for SnmpSim.
  """

  alias SnmpSim.Device

  @doc """
  Runs a sustained load test with comprehensive monitoring.
  """
  def run_sustained_load_test(devices, target_rps, duration_ms, options \\ %{}) do
    monitor_response_times = Map.get(options, :monitor_response_times, true)
    _monitor_throughput = Map.get(options, :monitor_throughput, true)
    _monitor_error_rates = Map.get(options, :monitor_error_rates, true)
    monitor_resource_usage = Map.get(options, :monitor_resource_usage, true)

    start_time = System.monotonic_time(:millisecond)
    _end_time = start_time + duration_ms

    # Start monitoring tasks
    monitoring_tasks = []

    monitoring_tasks =
      if monitor_response_times do
        [
          Task.async(fn -> collect_response_times(devices, target_rps, duration_ms) end)
          | monitoring_tasks
        ]
      else
        monitoring_tasks
      end

    monitoring_tasks =
      if monitor_resource_usage do
        [Task.async(fn -> monitor_resource_usage_over_time(duration_ms) end) | monitoring_tasks]
      else
        monitoring_tasks
      end

    # Execute load test
    load_task =
      Task.async(fn ->
        execute_sustained_load(devices, target_rps, duration_ms)
      end)

    # Await all results
    load_results = Task.await(load_task, :infinity)
    monitoring_results = Task.await_many(monitoring_tasks, :infinity)

    # Combine results
    base_results = %{
      total_requests: load_results.total_requests,
      actual_throughput_rps: load_results.actual_throughput_rps,
      errors: load_results.errors
    }

    monitoring_data =
      case monitoring_results do
        [response_times, memory_samples] ->
          %{response_times: response_times, memory_samples: memory_samples}

        [response_times] ->
          %{response_times: response_times, memory_samples: []}

        [] ->
          %{response_times: [], memory_samples: []}
      end

    Map.merge(base_results, monitoring_data)
  end

  @doc """
  Analyzes response time data and returns statistics.
  """
  def analyze_response_times(response_times)
      when is_list(response_times) and length(response_times) > 0 do
    sorted = Enum.sort(response_times)
    count = length(sorted)

    avg = Enum.sum(sorted) / count
    _min = Enum.min(sorted)
    _max = Enum.max(sorted)

    p50_index = round(count * 0.50) - 1
    p95_index = round(count * 0.95) - 1
    p99_index = round(count * 0.99) - 1

    _p50 = Enum.at(sorted, max(0, p50_index))
    p95 = Enum.at(sorted, max(0, p95_index))
    p99 = Enum.at(sorted, max(0, p99_index))

    {avg, p95, p99}
  end

  def analyze_response_times([]), do: {0.0, 0.0, 0.0}

  @doc """
  Calculates error rate from error count and total requests.
  """
  def calculate_error_rate(error_count, total_requests) when total_requests > 0 do
    error_count / total_requests * 100
  end

  def calculate_error_rate(_error_count, 0), do: 0.0

  @doc """
  Measures latency under various load conditions.
  """
  def measure_latency_under_load(devices, load_scenarios) do
    Enum.map(load_scenarios, fn scenario ->
      Logger.debug("Testing latency under #{scenario.rps} RPS load...")

      # Run load test for scenario
      results =
        run_sustained_load_test(
          devices,
          scenario.rps,
          scenario.duration_ms,
          %{monitor_response_times: true}
        )

      # Analyze latency
      {avg_latency, p95_latency, p99_latency} = analyze_response_times(results.response_times)

      %{
        rps: scenario.rps,
        avg_latency_ms: avg_latency,
        p95_latency_ms: p95_latency,
        p99_latency_ms: p99_latency,
        error_rate: calculate_error_rate(length(results.errors), results.total_requests)
      }
    end)
  end

  @doc """
  Performs throughput benchmarking.
  """
  def benchmark_throughput(devices, max_rps, step_size, duration_per_step_ms) do
    rps_levels = 0..max_rps//step_size |> Enum.to_list()

    Enum.map(rps_levels, fn target_rps ->
      Logger.debug("Benchmarking throughput at #{target_rps} RPS...")

      results =
        run_sustained_load_test(
          devices,
          target_rps,
          duration_per_step_ms,
          %{monitor_throughput: true, monitor_error_rates: true}
        )

      actual_rps = results.actual_throughput_rps
      error_rate = calculate_error_rate(length(results.errors), results.total_requests)

      %{
        target_rps: target_rps,
        actual_rps: actual_rps,
        efficiency: if(target_rps > 0, do: actual_rps / target_rps * 100, else: 0),
        error_rate: error_rate
      }
    end)
  end

  @doc """
  Tests memory usage patterns under different loads.
  """
  def analyze_memory_patterns(devices, test_scenarios) do
    Enum.map(test_scenarios, fn scenario ->
      Logger.debug("Analyzing memory patterns for scenario: #{scenario.name}")

      # Take initial memory snapshot
      initial_memory = get_current_memory_usage()

      # Run scenario
      results =
        run_sustained_load_test(
          devices,
          scenario.rps,
          scenario.duration_ms,
          %{monitor_resource_usage: true}
        )

      # Analyze memory usage
      memory_samples = results.memory_samples
      max_memory = Enum.max(memory_samples)
      avg_memory = Enum.sum(memory_samples) / length(memory_samples)
      final_memory = List.last(memory_samples)

      memory_growth = (final_memory - initial_memory) / initial_memory * 100

      %{
        scenario: scenario.name,
        initial_memory_mb: initial_memory / 1_048_576,
        max_memory_mb: max_memory / 1_048_576,
        avg_memory_mb: avg_memory / 1_048_576,
        final_memory_mb: final_memory / 1_048_576,
        memory_growth_percent: memory_growth
      }
    end)
  end

  @doc """
  Profiles CPU usage under load.
  """
  def profile_cpu_usage(_devices, duration_ms, sample_interval_ms) do
    samples = collect_cpu_samples(duration_ms, sample_interval_ms)

    avg_cpu = Enum.sum(samples) / length(samples)
    max_cpu = Enum.max(samples)
    min_cpu = Enum.min(samples)

    %{
      samples: samples,
      average_cpu_percent: avg_cpu,
      maximum_cpu_percent: max_cpu,
      minimum_cpu_percent: min_cpu,
      sample_count: length(samples)
    }
  end

  @doc """
  Measures scalability by testing performance at different device counts.
  """
  def measure_scalability(base_device_count, max_device_count, step_size, test_duration_ms) do
    device_counts = base_device_count..max_device_count//step_size |> Enum.to_list()

    Enum.map(device_counts, fn device_count ->
      Logger.debug("Testing scalability with #{device_count} devices...")

      # Create devices for this test
      devices = create_test_devices_for_scalability(device_count)

      # Run performance test
      start_time = System.monotonic_time(:millisecond)

      results =
        run_sustained_load_test(
          devices,
          # Fixed RPS for scalability testing
          100,
          test_duration_ms,
          %{
            monitor_response_times: true,
            monitor_resource_usage: true
          }
        )

      end_time = System.monotonic_time(:millisecond)

      # Calculate performance metrics
      {avg_latency, p95_latency, p99_latency} = analyze_response_times(results.response_times)
      error_rate = calculate_error_rate(length(results.errors), results.total_requests)

      # Memory efficiency
      memory_per_device =
        if length(results.memory_samples) > 0 do
          avg_memory = Enum.sum(results.memory_samples) / length(results.memory_samples)
          avg_memory / device_count
        else
          0
        end

      # Cleanup devices
      cleanup_test_devices(devices)

      %{
        device_count: device_count,
        avg_latency_ms: avg_latency,
        p95_latency_ms: p95_latency,
        p99_latency_ms: p99_latency,
        error_rate: error_rate,
        memory_per_device_bytes: memory_per_device,
        test_duration_ms: end_time - start_time
      }
    end)
  end

  @doc """
  Stress tests the system to find breaking points.
  """
  def find_breaking_point(devices, options \\ %{}) do
    initial_rps = Map.get(options, :initial_rps, 100)
    max_rps = Map.get(options, :max_rps, 10_000)
    increment = Map.get(options, :increment, 100)
    test_duration_ms = Map.get(options, :test_duration_ms, 30_000)
    # 5% error rate
    error_threshold = Map.get(options, :error_threshold, 5.0)
    # 1 second
    latency_threshold = Map.get(options, :latency_threshold, 1000.0)

    find_breaking_point_loop(
      devices,
      initial_rps,
      max_rps,
      increment,
      test_duration_ms,
      error_threshold,
      latency_threshold
    )
  end

  # Private helper functions

  defp find_breaking_point_loop(
         devices,
         current_rps,
         max_rps,
         increment,
         test_duration_ms,
         error_threshold,
         latency_threshold
       ) do
    if current_rps > max_rps do
      %{
        rps: max_rps,
        error_rate: 0.0,
        avg_latency_ms: 0.0,
        reason: :max_rps_reached
      }
    else
      Logger.debug("Testing breaking point at #{current_rps} RPS...")

      results =
        run_sustained_load_test(
          devices,
          current_rps,
          test_duration_ms,
          %{
            monitor_response_times: true,
            monitor_error_rates: true
          }
        )

      # Analyze results
      error_rate = calculate_error_rate(length(results.errors), results.total_requests)
      {avg_latency, _p95, _p99} = analyze_response_times(results.response_times)

      # Check if we've hit breaking point
      if error_rate > error_threshold or avg_latency > latency_threshold do
        %{
          rps: current_rps,
          error_rate: error_rate,
          avg_latency_ms: avg_latency,
          reason:
            cond do
              error_rate > error_threshold -> :high_error_rate
              avg_latency > latency_threshold -> :high_latency
              true -> :unknown
            end
        }
      else
        find_breaking_point_loop(
          devices,
          current_rps + increment,
          max_rps,
          increment,
          test_duration_ms,
          error_threshold,
          latency_threshold
        )
      end
    end
  end

  defp execute_sustained_load(devices, target_rps, duration_ms) do
    request_interval_ms = 1000 / target_rps
    end_time = System.monotonic_time(:millisecond) + duration_ms

    execute_load_loop(devices, request_interval_ms, end_time, 0, [])
  end

  defp execute_load_loop(devices, interval_ms, end_time, request_count, errors) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      total_duration_seconds =
        (current_time - (end_time - System.monotonic_time(:millisecond))) / 1000

      actual_rps =
        if total_duration_seconds > 0, do: request_count / total_duration_seconds, else: 0

      %{
        total_requests: request_count,
        actual_throughput_rps: actual_rps,
        errors: errors
      }
    else
      # Perform request
      device = Enum.random(devices)

      result =
        try do
          Device.get(device, "1.3.6.1.2.1.1.1.0")
        catch
          _type, error -> {:error, error}
        end

      new_errors =
        case result do
          {:ok, _} -> errors
          error -> [error | errors]
        end

      # Maintain target rate
      Process.sleep(round(interval_ms))

      execute_load_loop(devices, interval_ms, end_time, request_count + 1, new_errors)
    end
  end

  defp collect_response_times(devices, target_rps, duration_ms) do
    request_interval_ms = 1000 / target_rps
    end_time = System.monotonic_time(:millisecond) + duration_ms

    collect_response_times_loop(devices, request_interval_ms, end_time, [])
  end

  defp collect_response_times_loop(devices, interval_ms, end_time, response_times) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      response_times
    else
      device = Enum.random(devices)

      {response_time, _result} =
        measure_response_time(fn ->
          Device.get(device, "1.3.6.1.2.1.1.1.0")
        end)

      Process.sleep(round(interval_ms))

      collect_response_times_loop(devices, interval_ms, end_time, [response_time | response_times])
    end
  end

  defp measure_response_time(fun) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)
    response_time_ms = (end_time - start_time) / 1000

    {response_time_ms, result}
  end

  defp monitor_resource_usage_over_time(duration_ms) do
    # Sample every second
    sample_interval_ms = 1000
    end_time = System.monotonic_time(:millisecond) + duration_ms

    collect_memory_samples_loop(end_time, sample_interval_ms, [])
  end

  defp collect_memory_samples_loop(end_time, interval_ms, samples) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      Enum.reverse(samples)
    else
      memory_usage = get_current_memory_usage()
      new_samples = [memory_usage | samples]

      Process.sleep(interval_ms)
      collect_memory_samples_loop(end_time, interval_ms, new_samples)
    end
  end

  defp get_current_memory_usage do
    memory_info = :erlang.memory()
    memory_info[:total]
  end

  defp collect_cpu_samples(duration_ms, sample_interval_ms) do
    # This is a simplified CPU monitoring implementation
    # In a real system, you'd use proper CPU monitoring tools
    end_time = System.monotonic_time(:millisecond) + duration_ms

    collect_cpu_samples_loop(end_time, sample_interval_ms, [])
  end

  defp collect_cpu_samples_loop(end_time, interval_ms, samples) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      Enum.reverse(samples)
    else
      # Simplified CPU usage calculation
      # In reality, you'd use system tools or libraries for accurate CPU monitoring
      # Mock CPU usage
      cpu_usage = :rand.uniform(100)
      new_samples = [cpu_usage | samples]

      Process.sleep(interval_ms)
      collect_cpu_samples_loop(end_time, interval_ms, new_samples)
    end
  end

  defp create_test_devices_for_scalability(device_count) do
    # Create devices efficiently for scalability testing
    SnmpSim.TestHelpers.create_test_devices(count: device_count)
  end

  defp cleanup_test_devices(devices) do
    SnmpSim.TestHelpers.cleanup_devices(devices)
  end
end
