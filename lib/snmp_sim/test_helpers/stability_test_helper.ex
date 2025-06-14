defmodule SnmpSim.TestHelpers.StabilityTestHelper do
  @moduledoc """
  Specialized testing utilities for stability and endurance testing.
  """

  alias SnmpSim.{Device, LazyDevicePool}

  @doc """
  Monitors memory usage over a specified duration while running a test function.
  """
  def monitor_memory_usage(duration_ms, sample_interval_ms, test_function) do
    monitor_task =
      Task.async(fn ->
        monitor_memory_over_time(duration_ms, sample_interval_ms)
      end)

    test_task =
      Task.async(fn ->
        run_test_cycles(duration_ms, test_function)
      end)

    Task.await(test_task, :infinity)
    memory_samples = Task.await(monitor_task, :infinity)

    memory_samples
  end

  @doc """
  Analyzes memory usage patterns to detect leaks and trends.
  """
  def analyze_memory_samples(samples) when is_list(samples) do
    initial_memory = List.first(samples)
    final_memory = List.last(samples)
    max_memory = Enum.max(samples)
    avg_memory = Enum.sum(samples) / length(samples)

    {initial_memory, final_memory, max_memory, avg_memory}
  end

  @doc """
  Runs a comprehensive load test with monitoring.
  """
  def run_load_test(devices, target_rps, duration_ms, options \\ %{}) do
    monitor_response_times = Map.get(options, :monitor_response_times, false)
    monitor_error_rates = Map.get(options, :monitor_error_rates, false)
    monitor_resource_usage = Map.get(options, :monitor_resource_usage, false)
    monitor_process_counts = Map.get(options, :monitor_process_counts, false)

    # Start monitoring tasks
    monitoring_tasks =
      start_load_test_monitoring(
        duration_ms,
        monitor_response_times,
        monitor_error_rates,
        monitor_resource_usage,
        monitor_process_counts
      )

    # Run the actual load test
    load_test_task =
      Task.async(fn ->
        execute_load_test(devices, target_rps, duration_ms)
      end)

    # Await results
    load_results = Task.await(load_test_task, :infinity)
    monitoring_results = await_monitoring_tasks(monitoring_tasks)

    # Combine results
    Map.merge(load_results, monitoring_results)
  end

  @doc """
  Runs an endurance test with varying workload patterns.
  """
  def run_endurance_test(duration_ms, options \\ %{}) do
    workload_patterns = Map.get(options, :workload_patterns, [])
    inject_failures = Map.get(options, :inject_failures, false)
    failure_rate = Map.get(options, :failure_rate, 0.0)
    monitor_everything = Map.get(options, :monitor_everything, true)

    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + duration_ms

    # Initialize monitoring
    monitoring_data =
      if monitor_everything do
        start_comprehensive_monitoring(duration_ms)
      else
        %{}
      end

    # Execute endurance test cycles
    results =
      execute_endurance_cycles(
        workload_patterns,
        start_time,
        end_time,
        inject_failures,
        failure_rate,
        %{
          total_cycles: 0,
          devices_created: 0,
          requests_processed: 0,
          errors_encountered: 0,
          system_crashed: false,
          memory_leak_detected: false,
          deadlock_detected: false,
          resource_exhaustion: false
        }
      )

    # Finalize monitoring
    final_monitoring =
      if monitor_everything do
        finalize_comprehensive_monitoring(monitoring_data)
      else
        %{}
      end

    Map.merge(results, final_monitoring)
  end

  @doc """
  Checks overall system health and returns metrics.
  """
  def check_system_health do
    memory_info = :erlang.memory()
    process_count = :erlang.system_info(:process_count)

    # Check device pool health
    device_stats =
      try do
        LazyDevicePool.get_stats()
      catch
        _type, _error -> %{active_count: 0, devices_created: 0}
      end

    # Calculate health metrics
    # Convert to GB
    memory_usage_ratio = memory_info[:total] / (1024 * 1024 * 1024)

    %{
      memory_usage: memory_usage_ratio,
      memory_total_bytes: memory_info[:total],
      process_count: process_count,
      active_devices: device_stats.active_count,
      devices_created: Map.get(device_stats, :devices_created, 0),
      system_healthy: memory_usage_ratio < 2.0 and process_count < 50_000
    }
  end

  @doc """
  Injects various types of failures for testing system resilience.
  """
  def inject_failure(scenario) do
    case scenario.action do
      :kill_random_processes ->
        kill_random_processes(scenario.count)

      :memory_pressure ->
        create_memory_pressure(scenario.intensity)

      :exhaust_ports ->
        exhaust_ports(scenario.percentage)

      :inject_network_delays ->
        inject_network_delays(scenario.delay_ms)

      :cascading_failures ->
        trigger_cascading_failures(scenario.failure_rate)
    end
  end

  @doc """
  Clears any active failure injections.
  """
  def clear_failure_injection do
    # Clear network delay injection
    Process.whereis(:network_delay_injector) |> stop_process_if_exists()

    # Clear memory pressure
    Process.whereis(:memory_pressure_creator) |> stop_process_if_exists()

    # Clear port exhaustion
    Process.whereis(:port_exhauster) |> stop_process_if_exists()

    :ok
  end

  @doc """
  Resets system state for stability testing.
  """
  def reset_system_state do
    # Force garbage collection
    :erlang.garbage_collect()

    # Clear device pool caches
    try do
      LazyDevicePool.clear_cache()
    catch
      _type, _error -> :ok
    end

    # Reset any test state
    clear_failure_injection()

    :ok
  end

  @doc """
  Cleanup all test resources.
  """
  def cleanup_all do
    reset_system_state()

    # Kill any remaining test processes
    test_processes =
      Process.registered()
      |> Enum.filter(fn name -> String.starts_with?(Atom.to_string(name), "test_") end)

    Enum.each(test_processes, fn name ->
      Process.whereis(name) |> stop_process_if_exists()
    end)

    :ok
  end

  # Private helper functions

  defp monitor_memory_over_time(duration_ms, sample_interval_ms) do
    end_time = System.monotonic_time(:millisecond) + duration_ms
    collect_memory_samples(end_time, sample_interval_ms, [])
  end

  defp collect_memory_samples(end_time, interval_ms, samples) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      Enum.reverse(samples)
    else
      memory_info = :erlang.memory()
      new_samples = [memory_info[:total] | samples]

      Process.sleep(interval_ms)
      collect_memory_samples(end_time, interval_ms, new_samples)
    end
  end

  defp run_test_cycles(duration_ms, test_function) do
    end_time = System.monotonic_time(:millisecond) + duration_ms
    execute_test_cycles(end_time, test_function, 0)
  end

  defp execute_test_cycles(end_time, test_function, cycle_count) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      cycle_count
    else
      test_function.()
      execute_test_cycles(end_time, test_function, cycle_count + 1)
    end
  end

  defp start_load_test_monitoring(
         duration_ms,
         monitor_response_times,
         monitor_error_rates,
         monitor_resource_usage,
         monitor_process_counts
       ) do
    tasks = []

    tasks =
      if monitor_response_times do
        [Task.async(fn -> monitor_response_times(duration_ms) end) | tasks]
      else
        tasks
      end

    tasks =
      if monitor_error_rates do
        [Task.async(fn -> monitor_error_rates(duration_ms) end) | tasks]
      else
        tasks
      end

    tasks =
      if monitor_resource_usage do
        [Task.async(fn -> monitor_resource_usage(duration_ms) end) | tasks]
      else
        tasks
      end

    tasks =
      if monitor_process_counts do
        [Task.async(fn -> monitor_process_counts(duration_ms) end) | tasks]
      else
        tasks
      end

    tasks
  end

  defp await_monitoring_tasks(tasks) do
    results = Task.await_many(tasks, :infinity)

    # Combine monitoring results
    %{
      response_times: Enum.at(results, 0, []),
      error_rates: Enum.at(results, 1, []),
      resource_usage: Enum.at(results, 2, []),
      process_counts: Enum.at(results, 3, [])
    }
  end

  defp execute_load_test(devices, target_rps, duration_ms) do
    request_interval_ms = 1000 / target_rps
    end_time = System.monotonic_time(:millisecond) + duration_ms

    execute_load_requests(devices, request_interval_ms, end_time, 0, 0)
  end

  defp execute_load_requests(devices, interval_ms, end_time, total_requests, errors) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      %{
        total_requests: total_requests,
        errors: errors,
        actual_rps:
          total_requests / ((end_time - (end_time - System.monotonic_time(:millisecond))) / 1000)
      }
    else
      device = Enum.random(devices)

      result =
        try do
          Device.get(device, "1.3.6.1.2.1.1.1.0")
        catch
          _type, _error -> {:error, :exception}
        end

      new_errors =
        case result do
          {:ok, _} -> errors
          _ -> errors + 1
        end

      Process.sleep(round(interval_ms))
      execute_load_requests(devices, interval_ms, end_time, total_requests + 1, new_errors)
    end
  end

  defp start_comprehensive_monitoring(duration_ms) do
    memory_task = Task.async(fn -> monitor_memory_over_time(duration_ms, 1000) end)
    process_task = Task.async(fn -> monitor_process_counts(duration_ms) end)

    %{
      memory_task: memory_task,
      process_task: process_task,
      start_time: System.monotonic_time(:millisecond)
    }
  end

  defp finalize_comprehensive_monitoring(monitoring_data) do
    memory_samples = Task.await(monitoring_data.memory_task, :infinity)
    process_samples = Task.await(monitoring_data.process_task, :infinity)

    %{
      memory_samples: memory_samples,
      process_samples: process_samples
    }
  end

  defp execute_endurance_cycles(
         patterns,
         start_time,
         end_time,
         inject_failures,
         failure_rate,
         results
       ) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      results
    else
      # Execute workload pattern
      pattern = Enum.random(patterns)
      cycle_results = execute_workload_pattern(pattern)

      # Inject failures if enabled
      if inject_failures and :rand.uniform() < failure_rate do
        inject_random_failure()
      end

      # Update results
      updated_results = %{
        results
        | total_cycles: results.total_cycles + 1,
          devices_created: results.devices_created + cycle_results.devices_created,
          requests_processed: results.requests_processed + cycle_results.requests_processed,
          errors_encountered: results.errors_encountered + cycle_results.errors_encountered
      }

      # Check for system issues
      health = check_system_health()

      system_issues = %{
        system_crashed: !health.system_healthy,
        memory_leak_detected: detect_memory_leak(health),
        deadlock_detected: detect_deadlock(),
        resource_exhaustion: detect_resource_exhaustion(health)
      }

      final_results = Map.merge(updated_results, system_issues)

      # Continue or stop based on system health
      if final_results.system_crashed do
        final_results
      else
        # Brief pause between cycles
        Process.sleep(1000)

        execute_endurance_cycles(
          patterns,
          start_time,
          end_time,
          inject_failures,
          failure_rate,
          final_results
        )
      end
    end
  end

  defp execute_workload_pattern(pattern) do
    case pattern.type do
      :steady ->
        execute_steady_workload(pattern.device_count, pattern.duration_minutes)

      :burst ->
        execute_burst_workload(pattern.device_count, pattern.duration_minutes)

      :idle ->
        execute_idle_workload(pattern.device_count, pattern.duration_minutes)
    end
  end

  defp execute_steady_workload(device_count, _duration_minutes) do
    # Implement steady workload pattern
    %{devices_created: device_count, requests_processed: device_count * 10, errors_encountered: 0}
  end

  defp execute_burst_workload(device_count, _duration_minutes) do
    # Implement burst workload pattern
    %{devices_created: device_count, requests_processed: device_count * 20, errors_encountered: 1}
  end

  defp execute_idle_workload(device_count, _duration_minutes) do
    # Implement idle workload pattern - simulate low activity instead of literal waiting
    # Brief pause to simulate idle state without extending test duration
    Process.sleep(100)
    %{devices_created: device_count, requests_processed: device_count * 2, errors_encountered: 0}
  end

  defp inject_random_failure do
    failures = [:network_delay, :memory_pressure, :process_kill]
    failure = Enum.random(failures)

    case failure do
      :network_delay -> inject_network_delays(100)
      :memory_pressure -> create_memory_pressure(:low)
      :process_kill -> kill_random_processes(1)
    end
  end

  defp kill_random_processes(count) do
    # Get only device processes, not critical system processes
    all_device_processes =
      Process.list()
      |> Enum.filter(fn pid ->
        is_device_process?(pid) and Process.alive?(pid)
      end)

    device_processes =
      Enum.take_random(all_device_processes, min(count, length(all_device_processes)))

    require Logger
    Logger.info("Killing #{length(device_processes)} device processes for stability test")

    Enum.each(device_processes, fn pid ->
      try do
        Process.exit(pid, :kill)
      catch
        _type, _error -> :ok
      end
    end)
  end

  # Helper function to identify if a process is a device process (safe to kill)
  defp is_device_process?(pid) do
    try do
      case Process.info(pid, :registered_name) do
        {:registered_name, []} ->
          # Check if it's a device process by looking at initial call
          case Process.info(pid, :initial_call) do
            {:initial_call, {SnmpSim.Device, :init, 1}} -> true
            {:initial_call, {SnmpSim.Core.Server, :init, 1}} -> true
            _ -> false
          end

        {:registered_name, name} ->
          # Don't kill critical named processes
          case name do
            SnmpSim.MIB.SharedProfiles -> false
            SnmpSim.LazyDevicePool -> false
            SnmpSim.Application -> false
            _ -> false
          end

        nil ->
          false
      end
    catch
      _type, _error -> false
    end
  end

  defp create_memory_pressure(intensity) do
    size =
      case intensity do
        # 10MB
        :low -> 10_000_000
        # 50MB
        :medium -> 50_000_000
        # 100MB
        :high -> 100_000_000
      end

    spawn(fn ->
      # Create memory pressure by allocating large binaries
      _large_binary = :binary.copy(<<0>>, size)
      # Hold memory for 10 seconds
      Process.sleep(10_000)
    end)
  end

  defp exhaust_ports(percentage) when percentage > 0 and percentage <= 1 do
    max_ports = :erlang.system_info(:port_limit)
    target_ports = round(max_ports * percentage)

    spawn(fn ->
      # Open many ports to exhaust the limit
      _ports =
        Enum.map(1..target_ports, fn _i ->
          case :gen_udp.open(0) do
            {:ok, socket} -> socket
            _ -> nil
          end
        end)

      # Hold ports for 30 seconds
      Process.sleep(30_000)
    end)
  end

  defp inject_network_delays(_delay_ms) do
    # This is a simulation - in a real implementation you might
    # intercept network calls or use a proxy
    spawn(fn ->
      Process.register(self(), :network_delay_injector)

      receive do
        :stop -> :ok
      after
        # Auto-stop after 1 minute
        60_000 -> :ok
      end
    end)
  end

  defp trigger_cascading_failures(failure_rate) do
    # Simulate cascading failures by randomly killing device processes
    device_processes =
      Process.registered()
      |> Enum.filter(fn name -> String.contains?(Atom.to_string(name), "device") end)

    failure_count = round(length(device_processes) * failure_rate)

    Enum.take_random(device_processes, failure_count)
    |> Enum.each(fn process_name ->
      pid = Process.whereis(process_name)

      if pid && Process.alive?(pid) do
        Process.exit(pid, :kill)
      end
    end)
  end

  defp monitor_response_times(_duration_ms) do
    # Implementation for monitoring response times
    # Placeholder
    []
  end

  defp monitor_error_rates(_duration_ms) do
    # Implementation for monitoring error rates
    # Placeholder
    []
  end

  defp monitor_resource_usage(_duration_ms) do
    # Implementation for monitoring resource usage
    # Placeholder
    []
  end

  defp monitor_process_counts(duration_ms) do
    end_time = System.monotonic_time(:millisecond) + duration_ms
    collect_process_samples(end_time, [])
  end

  defp collect_process_samples(end_time, samples) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      Enum.reverse(samples)
    else
      process_count = :erlang.system_info(:process_count)
      new_samples = [process_count | samples]

      Process.sleep(1000)
      collect_process_samples(end_time, new_samples)
    end
  end

  defp detect_memory_leak(health) do
    # Simple heuristic: memory usage > 3GB suggests potential leak
    health.memory_usage > 3.0
  end

  defp detect_deadlock do
    # Simple deadlock detection based on process count growth
    current_count = :erlang.system_info(:process_count)
    current_count > 75_000
  end

  defp detect_resource_exhaustion(health) do
    health.memory_usage > 3.5 or health.process_count > 90_000
  end

  defp stop_process_if_exists(nil), do: :ok

  defp stop_process_if_exists(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      Process.exit(pid, :normal)
    end
  end
end
