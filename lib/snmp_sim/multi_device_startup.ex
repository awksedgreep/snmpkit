defmodule SnmpSim.MultiDeviceStartup do
  @moduledoc """
  Multi-Device Startup functionality for large-scale device population management.

  Features:
  - Bulk device population startup
  - Progress monitoring and reporting  
  - Parallel device creation for speed
  - Failure handling and recovery
  - Integration with LazyDevicePool and DeviceDistribution
  """

  require Logger
  alias SnmpSim.{LazyDevicePool, DeviceDistribution}

  @type device_spec :: {device_type :: atom(), count :: non_neg_integer()}
  @type startup_opts :: [
          port_range: Range.t(),
          parallel_workers: pos_integer(),
          timeout_ms: pos_integer(),
          progress_callback: function() | nil
        ]

  @default_parallel_workers 50
  @default_timeout_ms 30_000

  @doc """
  Start a large population of devices based on device specifications.

  ## Examples

      device_specs = [
        {:cable_modem, 1000},
        {:switch, 50}, 
        {:router, 10},
        {:cmts, 5}
      ]
      
      {:ok, result} = SnmpSim.MultiDeviceStartup.start_device_population(
        device_specs,
        port_range: 30_000..31_099,
        parallel_workers: 100
      )
      
  """
  @spec start_device_population([device_spec()], startup_opts()) ::
          {:ok, map()} | {:error, term()}
  def start_device_population(device_specs, opts \\ []) do
    port_range = Keyword.get(opts, :port_range, 30_000..39_999)
    parallel_workers = Keyword.get(opts, :parallel_workers, @default_parallel_workers)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    progress_callback = Keyword.get(opts, :progress_callback)

    Logger.info("Starting device population: #{inspect(device_specs)}")

    with :ok <- validate_device_specs(device_specs, port_range),
         {:ok, port_assignments} <- build_port_assignments(device_specs, port_range),
         :ok <- configure_lazy_pool(port_assignments),
         {:ok, startup_plan} <- create_startup_plan(device_specs, port_assignments),
         {:ok, results} <-
           execute_startup_plan(startup_plan, parallel_workers, timeout_ms, progress_callback) do
      Logger.info("Device population startup completed successfully")

      {:ok,
       %{
         total_devices: calculate_total_devices(device_specs),
         port_assignments: port_assignments,
         startup_results: results,
         pool_stats: LazyDevicePool.get_stats()
       }}
    else
      {:error, reason} ->
        Logger.error("Device population startup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Start devices using predefined device mix patterns.

  ## Examples

      {:ok, result} = SnmpSim.MultiDeviceStartup.start_device_mix(
        :cable_network,
        port_range: 30_000..39_999
      )
      
  """
  @spec start_device_mix(atom(), startup_opts()) :: {:ok, map()} | {:error, term()}
  def start_device_mix(mix_type, opts \\ []) do
    device_mix = DeviceDistribution.get_device_mix(mix_type)
    device_specs = Enum.map(device_mix, fn {type, count} -> {type, count} end)

    Logger.info("Starting device mix '#{mix_type}': #{inspect(device_specs)}")
    start_device_population(device_specs, opts)
  end

  @doc """
  Pre-warm a specified number of devices for immediate availability.
  """
  @spec pre_warm_devices([device_spec()], startup_opts()) :: {:ok, map()} | {:error, term()}
  def pre_warm_devices(device_specs, opts \\ []) do
    # Add pre_warm option to force immediate device creation
    opts_with_pre_warm = Keyword.put(opts, :pre_warm, true)
    start_device_population(device_specs, opts_with_pre_warm)
  end

  @doc """
  Get startup progress and statistics.
  """
  @type startup_status :: %{
          active_devices: non_neg_integer(),
          peak_devices: non_neg_integer(),
          devices_created: non_neg_integer(),
          devices_cleaned_up: non_neg_integer(),
          total_ports_configured: non_neg_integer()
        }

  @spec get_startup_status() :: startup_status()
  def get_startup_status do
    pool_stats = LazyDevicePool.get_stats()

    %{
      active_devices: pool_stats.active_count,
      peak_devices: pool_stats.peak_count,
      devices_created: pool_stats.devices_created,
      devices_cleaned_up: pool_stats.devices_cleaned_up,
      total_ports_configured: pool_stats.total_ports_configured
    }
  end

  @doc """
  Gracefully shutdown all devices in the population.
  """
  @spec shutdown_device_population() :: :ok
  def shutdown_device_population do
    Logger.info("Shutting down device population")
    LazyDevicePool.shutdown_all_devices()
    Logger.info("Device population shutdown complete")
    :ok
  end

  # Private Functions

  defp validate_device_specs(device_specs, port_range) do
    total_devices = calculate_total_devices(device_specs)
    available_ports = Enum.count(port_range)

    cond do
      total_devices == 0 ->
        {:error, :no_devices_specified}

      total_devices > available_ports ->
        {:error, {:insufficient_ports, total_devices, available_ports}}

      not all_valid_device_types?(device_specs) ->
        {:error, :invalid_device_types}

      true ->
        :ok
    end
  end

  defp calculate_total_devices(device_specs) do
    Enum.reduce(device_specs, 0, fn {_type, count}, acc -> acc + count end)
  end

  defp all_valid_device_types?(device_specs) do
    valid_types = [:cable_modem, :mta, :switch, :router, :cmts, :server]

    Enum.all?(device_specs, fn {type, count} ->
      type in valid_types and is_integer(count) and count >= 0
    end)
  end

  defp build_port_assignments(device_specs, port_range) do
    try do
      device_mix = Enum.into(device_specs, %{})
      port_assignments = DeviceDistribution.build_port_assignments(device_mix, port_range)

      case DeviceDistribution.validate_port_assignments(port_assignments) do
        :ok -> {:ok, port_assignments}
        {:error, reason} -> {:error, {:invalid_port_assignments, reason}}
      end
    rescue
      e in ArgumentError ->
        {:error, {:port_assignment_failed, e.message}}
    end
  end

  defp configure_lazy_pool(port_assignments) do
    case LazyDevicePool.configure_port_assignments(port_assignments) do
      :ok -> :ok
      {:error, reason} -> {:error, {:pool_configuration_failed, reason}}
    end
  end

  defp create_startup_plan(device_specs, port_assignments) do
    startup_tasks =
      device_specs
      |> Enum.flat_map(fn {device_type, count} ->
        case Map.get(port_assignments, device_type) do
          nil ->
            []

          port_range ->
            port_range
            |> Enum.take(count)
            |> Enum.map(fn port ->
              %{
                device_type: device_type,
                port: port,
                device_id: DeviceDistribution.generate_device_id(device_type, port)
              }
            end)
        end
      end)

    if length(startup_tasks) > 0 do
      {:ok, startup_tasks}
    else
      {:error, :no_startup_tasks_generated}
    end
  end

  defp execute_startup_plan(startup_tasks, parallel_workers, timeout_ms, progress_callback) do
    total_tasks = length(startup_tasks)
    Logger.info("Executing startup plan: #{total_tasks} devices with #{parallel_workers} workers")

    # Start progress tracking if callback provided
    _tracker_pid =
      if progress_callback do
        spawn_progress_tracker(progress_callback, total_tasks)
      end

    # Execute tasks in parallel batches
    startup_tasks
    |> Enum.chunk_every(parallel_workers)
    |> Enum.reduce({:ok, %{}}, fn batch, acc ->
      case acc do
        {:error, _} = error ->
          error

        {:ok, results} ->
          # execute_batch always returns {:ok, batch_results}
          {:ok, batch_results} = execute_batch(batch, timeout_ms)
          {:ok, Map.merge(results, batch_results)}
      end
    end)
  end

  defp execute_batch(tasks, timeout_ms) do
    # Execute tasks in parallel using async/await
    tasks
    |> Enum.map(fn task ->
      Task.async(fn -> start_single_device(task) end)
    end)
    |> Enum.map(fn task_ref ->
      try do
        case Task.await(task_ref, timeout_ms) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
          result -> {:error, {:unexpected_result, result}}
        end
      catch
        :exit, {:timeout, _} -> {:error, :timeout}
      end
    end)
    |> collect_batch_results()
  end

  defp start_single_device(%{port: port} = task) do
    case LazyDevicePool.get_or_create_device(port) do
      {:ok, device_pid} ->
        {:ok, task |> Map.put(:device_pid, device_pid) |> Map.put(:status, :started)}

      {:error, reason} ->
        {:error, task |> Map.put(:status, :failed) |> Map.put(:reason, reason)}
    end
  end

  defp collect_batch_results(results) do
    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))

    if length(failures) > 0 do
      # Log failures but continue - we want partial success
      failed_tasks = Enum.map(failures, fn {:error, task} -> task end)
      Logger.warning("#{length(failures)} devices failed to start: #{inspect(failed_tasks)}")
    end

    success_results =
      successes
      |> Enum.map(fn {:ok, result} -> result end)
      |> Enum.into(%{}, fn result -> {result.port, result} end)

    {:ok, success_results}
  end

  defp spawn_progress_tracker(callback, total_tasks) do
    spawn(fn ->
      track_progress(callback, total_tasks, 0, System.monotonic_time(:millisecond))
    end)
  end

  defp track_progress(callback, total_tasks, completed, start_time) do
    if completed < total_tasks do
      current_stats = LazyDevicePool.get_stats()
      current_completed = current_stats.devices_created

      if current_completed > completed do
        elapsed_ms = System.monotonic_time(:millisecond) - start_time
        progress = current_completed / total_tasks
        eta_ms = if progress > 0, do: trunc(elapsed_ms / progress - elapsed_ms), else: nil

        callback.(%{
          completed: current_completed,
          total: total_tasks,
          progress: progress,
          elapsed_ms: elapsed_ms,
          eta_ms: eta_ms
        })

        # Update every second
        :timer.sleep(1000)
        track_progress(callback, total_tasks, current_completed, start_time)
      else
        # Check more frequently if no progress
        :timer.sleep(100)
        track_progress(callback, total_tasks, completed, start_time)
      end
    end
  end

  @type progress_callback :: (%{
                                completed: non_neg_integer(),
                                total: non_neg_integer(),
                                progress: float(),
                                elapsed_ms: non_neg_integer(),
                                eta_ms: nil | non_neg_integer()
                              } ->
                                :ok)

  @doc """
  Create a simple progress callback that logs to console.
  """
  @spec console_progress_callback() :: progress_callback()
  def console_progress_callback do
    fn %{
         completed: completed,
         total: total,
         progress: progress,
         elapsed_ms: elapsed_ms,
         eta_ms: eta_ms
       } ->
      percentage = Float.round(progress * 100, 1)
      elapsed_s = div(elapsed_ms, 1000)
      eta_s = if eta_ms, do: div(eta_ms, 1000), else: "?"

      Logger.info(
        "Device startup progress: #{completed}/#{total} (#{percentage}%) - " <>
          "Elapsed: #{elapsed_s}s, ETA: #{eta_s}s"
      )

      :ok
    end
  end

  @doc """
  Start devices with console progress reporting.
  """
  @spec start_with_progress([device_spec()], startup_opts()) :: {:ok, map()} | {:error, term()}
  def start_with_progress(device_specs, opts \\ []) do
    opts_with_progress = Keyword.put(opts, :progress_callback, console_progress_callback())
    start_device_population(device_specs, opts_with_progress)
  end
end
