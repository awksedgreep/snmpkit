defmodule SnmpSim.TestHelpers do
  @moduledoc """
  Comprehensive SNMP testing utilities for SnmpSim.

  This module provides a rich set of testing utilities for SNMP simulation,
  performance testing, stability testing, and production validation.
  """

  require Logger
  alias SnmpSim.{Device, LazyDevicePool}

  @doc """
  Creates test devices with various configurations.

  ## Options
  - `:count` - Number of devices to create (default: 10)
  - `:community` - SNMP community string (default: "public")
  - `:host` - Host address (default: "127.0.0.1")
  - `:port_start` - Starting port number (default: 30000)
  - `:walk_file` - SNMP walk file to use (default: "priv/walks/cable_modem.walk")
  - `:batch_size` - Create devices in batches (default: 10)
  - `:delay_between_batches` - Delay between batches in ms (default: 100)

  ## Examples
      devices = TestHelpers.create_test_devices(count: 50)
      devices = TestHelpers.create_test_devices(count: 100, community: "private")
  """
  def create_test_devices(opts \\ []) do
    count = Keyword.get(opts, :count, 10)
    community = Keyword.get(opts, :community, "public")
    host = Keyword.get(opts, :host, "127.0.0.1")
    port_start = Keyword.get(opts, :port_start, 30000)
    walk_file = Keyword.get(opts, :walk_file, "priv/walks/cable_modem.walk")
    batch_size = Keyword.get(opts, :batch_size, 10)
    delay_between_batches = Keyword.get(opts, :delay_between_batches, 100)

    1..count
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.flat_map(fn {batch, batch_index} ->
      devices =
        Enum.map(batch, fn i ->
          device_config = %{
            community: community,
            host: host,
            port: port_start + i,
            device_type: :cable_modem,
            device_id: "test_device_#{port_start + i}",
            walk_file: walk_file
          }

          {:ok, device} = Device.start_link(device_config)
          device
        end)

      # Delay between batches except for the first batch
      if batch_index > 0 do
        Process.sleep(delay_between_batches)
      end

      devices
    end)
  end

  @doc """
  Performs various SNMP operations on a device for testing.
  """
  def perform_test_operations(device, operations \\ [:get, :get_next, :get_bulk, :walk]) do
    Enum.map(operations, fn operation ->
      case operation do
        :get ->
          {operation, Device.get(device, "1.3.6.1.2.1.1.1.0")}

        :get_next ->
          {operation, Device.get_next(device, "1.3.6.1.2.1.1")}

        :get_bulk ->
          {operation, Device.get_bulk(device, ["1.3.6.1.2.1.1"], 0, 5)}

        :walk ->
          {operation, Device.walk(device, "1.3.6.1.2.1.1")}
      end
    end)
  end

  @doc """
  Measures the response time of an operation.
  """
  def measure_response_time(fun) when is_function(fun, 0) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)
    response_time_ms = (end_time - start_time) / 1000

    {response_time_ms, result}
  end

  @doc """
  Runs a load test against a set of devices.

  ## Options
  - `:duration_ms` - Test duration in milliseconds
  - `:requests_per_second` - Target requests per second
  - `:operation` - SNMP operation to perform (:get, :get_next, :get_bulk, :walk)
  - `:monitor_memory` - Whether to monitor memory usage
  - `:monitor_processes` - Whether to monitor process count
  """
  def run_load_test(devices, opts \\ []) do
    duration_ms = Keyword.get(opts, :duration_ms, 60_000)
    requests_per_second = Keyword.get(opts, :requests_per_second, 100)
    operation = Keyword.get(opts, :operation, :get)
    monitor_memory = Keyword.get(opts, :monitor_memory, true)
    monitor_processes = Keyword.get(opts, :monitor_processes, true)

    interval_ms = 1000 / requests_per_second
    end_time = System.monotonic_time(:millisecond) + duration_ms

    # Start monitoring tasks
    monitor_tasks = start_monitoring_tasks(monitor_memory, monitor_processes, duration_ms)

    # Run load test
    results = run_load_test_loop(devices, operation, end_time, interval_ms, [])

    # Collect monitoring results
    monitoring_data = collect_monitoring_results(monitor_tasks)

    %{
      total_requests: length(results),
      successful_requests: count_successful_results(results),
      failed_requests: count_failed_results(results),
      response_times: extract_response_times(results),
      errors: extract_errors(results),
      monitoring_data: monitoring_data
    }
  end

  @doc """
  Analyzes response time statistics.
  """
  def analyze_response_times(response_times) when is_list(response_times) do
    sorted_times = Enum.sort(response_times)
    count = length(sorted_times)

    avg = Enum.sum(sorted_times) / count
    min = Enum.min(sorted_times)
    max = Enum.max(sorted_times)

    p50 = percentile(sorted_times, 0.5)
    p95 = percentile(sorted_times, 0.95)
    p99 = percentile(sorted_times, 0.99)

    %{
      count: count,
      average: avg,
      minimum: min,
      maximum: max,
      p50: p50,
      p95: p95,
      p99: p99
    }
  end

  @doc """
  Calculates error rate as a percentage.
  """
  def calculate_error_rate(error_count, total_count) when total_count > 0 do
    error_count / total_count * 100
  end

  def calculate_error_rate(_error_count, 0), do: 0.0

  @doc """
  Monitors system health metrics.
  """
  def check_system_health do
    {:ok, memory_info} = :erlang.system_info(:memory)
    process_count = :erlang.system_info(:process_count)

    # Get device pool stats if available
    device_stats =
      try do
        LazyDevicePool.get_stats()
      catch
        _type, _error -> %{active_devices: 0, total_requests: 0}
      end

    %{
      memory_usage: memory_info[:total],
      memory_usage_mb: memory_info[:total] / 1_048_576,
      process_count: process_count,
      active_devices: device_stats.active_devices,
      total_requests: device_stats.total_requests
    }
  end

  @doc """
  Waits for a condition to be met within a timeout.
  """
  def wait_for_condition(condition_fun, timeout_ms \\ 30_000) do
    end_time = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_condition_loop(condition_fun, end_time)
  end

  @doc """
  Cleans up test devices and resources with enhanced error handling.
  """
  def cleanup_devices(devices) do
    cleanup_results =
      Enum.map(devices, fn device ->
        cleanup_single_device(device)
      end)

    successful_cleanups = Enum.count(cleanup_results, &(&1 == :ok))
    failed_cleanups = length(cleanup_results) - successful_cleanups

    if failed_cleanups > 0 do
      Logger.warning("#{failed_cleanups} device cleanups failed, attempting global cleanup")
      Device.cleanup_all_devices()
    end

    # Wait for cleanup to complete
    Process.sleep(1000)

    %{
      total: length(devices),
      successful: successful_cleanups,
      failed: failed_cleanups
    }
  end

  @doc """
  Cleanup a single device with robust error handling.
  """
  def cleanup_single_device(device) do
    cond do
      is_pid(device) ->
        Device.stop(device)

      is_map(device) ->
        Device.stop(device)

      true ->
        try do
          GenServer.stop(device, :normal, 5000)
        catch
          :exit, {:noproc, _} ->
            :ok

          :exit, {:normal, _} ->
            :ok

          :exit, {:shutdown, _} ->
            :ok

          :exit, {:timeout, _} ->
            try do
              if is_pid(device) and Process.alive?(device) do
                Process.exit(device, :kill)
              end

              :ok
            catch
              _, _ -> :ok
            end

          :exit, _reason ->
            :ok

          _, _ ->
            :ok
        end
    end
  end

  @doc """
  Resets system state for testing.
  """
  def reset_system_state do
    # Clear any cached data
    try do
      LazyDevicePool.clear_cache()
    catch
      _type, _error -> :ok
    end

    # Clean up any orphaned devices
    try do
      Device.cleanup_all_devices()
    catch
      _type, _error -> :ok
    end

    # Force garbage collection
    :erlang.garbage_collect()

    # Clear ETS tables if any
    clear_test_ets_tables()

    :ok
  end

  @doc """
  Create test devices with monitoring and automatic cleanup tracking.
  Returns devices with monitor references for better cleanup handling.
  """
  def create_monitored_test_devices(opts \\ []) do
    count = Keyword.get(opts, :count, 10)
    community = Keyword.get(opts, :community, "public")
    host = Keyword.get(opts, :host, "127.0.0.1")
    port_start = Keyword.get(opts, :port_start, 30000)
    walk_file = Keyword.get(opts, :walk_file, "priv/walks/cable_modem.walk")
    batch_size = Keyword.get(opts, :batch_size, 10)
    delay_between_batches = Keyword.get(opts, :delay_between_batches, 100)

    1..count
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.flat_map(fn {batch, batch_index} ->
      devices =
        Enum.map(batch, fn i ->
          device_config = %{
            community: community,
            host: host,
            port: port_start + i,
            walk_file: walk_file,
            device_id: "test_device_#{port_start + i}",
            device_type: :cable_modem
          }

          case Device.start_link_monitored(device_config) do
            {:ok, {device_pid, monitor_ref}} ->
              %{
                pid: device_pid,
                monitor_ref: monitor_ref,
                port: port_start + i,
                device_id: "test_device_#{port_start + i}"
              }

            {:error, reason} ->
              Logger.error("Failed to create test device #{i}: #{inspect(reason)}")
              nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

      # Delay between batches except for the first batch
      if batch_index > 0 do
        Process.sleep(delay_between_batches)
      end

      devices
    end)
  end

  @doc """
  Cleanup monitored devices with enhanced tracking.
  """
  def cleanup_monitored_devices(monitored_devices) do
    cleanup_results =
      Enum.map(monitored_devices, fn device_info ->
        # Demonitor first to avoid getting DOWN messages
        if Map.has_key?(device_info, :monitor_ref) do
          Process.demonitor(device_info.monitor_ref, [:flush])
        end

        # Then cleanup the device
        cleanup_single_device(device_info)
      end)

    successful_cleanups = Enum.count(cleanup_results, &(&1 == :ok))
    failed_cleanups = length(cleanup_results) - successful_cleanups

    if failed_cleanups > 0 do
      Logger.warning(
        "#{failed_cleanups} monitored device cleanups failed, attempting global cleanup"
      )

      Device.cleanup_all_devices()
    end

    # Wait for cleanup to complete
    Process.sleep(1000)

    %{
      total: length(monitored_devices),
      successful: successful_cleanups,
      failed: failed_cleanups
    }
  end

  @doc """
  Creates test SNMP walk data for testing.
  """
  def create_test_walk_data(oid_count \\ 100) do
    base_oid = "1.3.6.1.2.1.1"

    1..oid_count
    |> Enum.map(fn i ->
      oid = "#{base_oid}.#{i}.0"
      value = generate_test_value(i)
      "#{oid} = #{value}"
    end)
    |> Enum.join("\n")
  end

  @doc """
  Validates SNMP response format.
  """
  def validate_snmp_response({:ok, response}) do
    case response do
      %{oid: oid, value: value} when is_binary(oid) and is_binary(value) -> :valid
      _ -> {:invalid, "Malformed response structure"}
    end
  end

  def validate_snmp_response({:error, reason}) do
    {:error, reason}
  end

  def validate_snmp_response(other) do
    {:invalid, "Unexpected response format: #{inspect(other)}"}
  end

  @doc """
  Injects artificial delays for testing timeout scenarios.
  """
  def inject_delay(delay_ms) do
    Process.sleep(delay_ms)
  end

  @doc """
  Simulates network conditions (packet loss, delays).
  """
  def simulate_network_conditions(opts \\ []) do
    packet_loss_rate = Keyword.get(opts, :packet_loss_rate, 0.0)
    delay_ms = Keyword.get(opts, :delay_ms, 0)
    jitter_ms = Keyword.get(opts, :jitter_ms, 0)

    # Simulate packet loss
    if :rand.uniform() < packet_loss_rate do
      {:error, :timeout}
    else
      # Simulate delay and jitter
      total_delay = delay_ms + :rand.uniform(jitter_ms + 1) - 1

      if total_delay > 0 do
        Process.sleep(total_delay)
      end

      :ok
    end
  end

  @doc """
  Generates test data for bulk operations.
  """
  def generate_bulk_test_data(device_count, operations_per_device) do
    1..device_count
    |> Enum.map(fn device_id ->
      operations =
        1..operations_per_device
        |> Enum.map(fn op_id ->
          %{
            device_id: device_id,
            operation_id: op_id,
            oid: "1.3.6.1.2.1.1.#{op_id}.0",
            operation: Enum.random([:get, :get_next, :get_bulk])
          }
        end)

      %{device_id: device_id, operations: operations}
    end)
  end

  @doc """
  Validates system invariants during testing.
  """
  def validate_system_invariants do
    health = check_system_health()

    invariants = [
      {:memory_reasonable, health.memory_usage_mb < 4096},
      {:processes_reasonable, health.process_count < 100_000},
      {:devices_trackable, health.active_devices >= 0}
    ]

    failed_invariants = Enum.filter(invariants, fn {_name, condition} -> !condition end)

    case failed_invariants do
      [] -> :ok
      failures -> {:error, {:invariant_violations, failures}}
    end
  end

  # Private helper functions

  defp start_monitoring_tasks(monitor_memory, monitor_processes, duration_ms) do
    tasks = []

    tasks =
      if monitor_memory do
        [Task.async(fn -> monitor_memory_usage(duration_ms) end) | tasks]
      else
        tasks
      end

    tasks =
      if monitor_processes do
        [Task.async(fn -> monitor_process_count(duration_ms) end) | tasks]
      else
        tasks
      end

    tasks
  end

  defp monitor_memory_usage(duration_ms) do
    end_time = System.monotonic_time(:millisecond) + duration_ms
    monitor_memory_loop(end_time, [])
  end

  defp monitor_memory_loop(end_time, samples) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      samples
    else
      {:ok, memory_info} = :erlang.system_info(:memory)
      new_samples = [memory_info[:total] | samples]

      # Sample every second
      Process.sleep(1000)
      monitor_memory_loop(end_time, new_samples)
    end
  end

  defp monitor_process_count(duration_ms) do
    end_time = System.monotonic_time(:millisecond) + duration_ms
    monitor_process_loop(end_time, [])
  end

  defp monitor_process_loop(end_time, samples) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      samples
    else
      process_count = :erlang.system_info(:process_count)
      new_samples = [process_count | samples]

      # Sample every second
      Process.sleep(1000)
      monitor_process_loop(end_time, new_samples)
    end
  end

  defp collect_monitoring_results(tasks) do
    Task.await_many(tasks, :infinity)
    |> Enum.zip([:memory_samples, :process_samples])
    |> Enum.into(%{})
  end

  defp run_load_test_loop(devices, operation, end_time, interval_ms, results) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      results
    else
      device = Enum.random(devices)

      {response_time, result} =
        measure_response_time(fn ->
          perform_single_operation(device, operation)
        end)

      new_result = %{
        timestamp: current_time,
        response_time: response_time,
        result: result
      }

      # Maintain target rate
      Process.sleep(round(interval_ms))

      run_load_test_loop(devices, operation, end_time, interval_ms, [new_result | results])
    end
  end

  defp perform_single_operation(device, operation) do
    case operation do
      :get -> Device.get(device, "1.3.6.1.2.1.1.1.0")
      :get_next -> Device.get_next(device, "1.3.6.1.2.1.1")
      :get_bulk -> Device.get_bulk(device, ["1.3.6.1.2.1.1"], 0, 5)
      :walk -> Device.walk(device, "1.3.6.1.2.1.1")
    end
  end

  defp count_successful_results(results) do
    Enum.count(results, fn %{result: result} ->
      match?({:ok, _}, result)
    end)
  end

  defp count_failed_results(results) do
    Enum.count(results, fn %{result: result} ->
      match?({:error, _}, result)
    end)
  end

  defp extract_response_times(results) do
    Enum.map(results, fn %{response_time: response_time} -> response_time end)
  end

  defp extract_errors(results) do
    results
    |> Enum.filter(fn %{result: result} -> match?({:error, _}, result) end)
    |> Enum.map(fn %{result: {:error, reason}} -> reason end)
  end

  defp percentile(sorted_list, percentile) when percentile >= 0 and percentile <= 1 do
    count = length(sorted_list)
    index = round(percentile * (count - 1))
    Enum.at(sorted_list, index)
  end

  defp wait_for_condition_loop(condition_fun, end_time) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      {:error, :timeout}
    else
      case condition_fun.() do
        true ->
          :ok

        false ->
          Process.sleep(100)
          wait_for_condition_loop(condition_fun, end_time)
      end
    end
  end

  defp clear_test_ets_tables do
    # Clear any test-specific ETS tables
    # This is a placeholder for test-specific cleanup
    :ok
  end

  defp generate_test_value(index) do
    case rem(index, 4) do
      0 -> "STRING: Test device #{index}"
      1 -> "INTEGER: #{index * 100}"
      2 -> "Counter32: #{index * 1000}"
      3 -> "Gauge32: #{index * 10}"
    end
  end
end
