defmodule SnmpSim.Performance.ResourceManager do
  @moduledoc """
  System resource management for SNMP simulator.
  Enforces memory limits, device limits, and automatic cleanup.
  Optimizes resource utilization for high-scale scenarios.
  """

  use GenServer
  require Logger

  alias SnmpSim.Device

  # Resource limits configuration
  @default_max_devices 10_000
  @default_max_memory_mb 1024
  # 1 minute
  @default_cleanup_interval 60_000
  # 10 minutes
  @default_idle_threshold 600_000
  # 30 seconds
  @memory_check_interval 30_000

  defstruct [
    :max_devices,
    :max_memory_mb,
    :cleanup_interval,
    :idle_threshold,
    :device_count,
    :memory_usage_mb,
    :last_cleanup,
    :active_devices,
    :resource_stats,
    :cleanup_timer,
    :memory_timer
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if we can allocate a new device within resource limits.
  """
  def can_allocate_device?() do
    GenServer.call(__MODULE__, :can_allocate_device)
  end

  @doc """
  Register a new device allocation.
  """
  def register_device(device_pid, device_type) do
    GenServer.cast(__MODULE__, {:register_device, device_pid, device_type})
  end

  @doc """
  Unregister a device that has been stopped.
  """
  def unregister_device(device_pid) do
    GenServer.cast(__MODULE__, {:unregister_device, device_pid})
  end

  @doc """
  Get current resource usage statistics.
  """
  def get_resource_stats() do
    GenServer.call(__MODULE__, :get_resource_stats)
  end

  @doc """
  Force immediate cleanup of idle devices.
  """
  def force_cleanup() do
    GenServer.call(__MODULE__, :force_cleanup)
  end

  @doc """
  Update resource limits dynamically.
  """
  def update_limits(opts) do
    GenServer.call(__MODULE__, {:update_limits, opts})
  end

  @doc """
  Check if memory usage is within limits.
  """
  def check_memory_limit() do
    GenServer.call(__MODULE__, :check_memory_limit)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    max_devices = Keyword.get(opts, :max_devices, @default_max_devices)
    max_memory_mb = Keyword.get(opts, :max_memory_mb, @default_max_memory_mb)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)
    idle_threshold = Keyword.get(opts, :idle_threshold, @default_idle_threshold)

    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_idle_devices, cleanup_interval)
    memory_timer = Process.send_after(self(), :check_memory, @memory_check_interval)

    state = %__MODULE__{
      max_devices: max_devices,
      max_memory_mb: max_memory_mb,
      cleanup_interval: cleanup_interval,
      idle_threshold: idle_threshold,
      device_count: 0,
      memory_usage_mb: 0,
      last_cleanup: System.monotonic_time(:millisecond),
      active_devices: %{},
      resource_stats: initialize_stats(),
      cleanup_timer: cleanup_timer,
      memory_timer: memory_timer
    }

    Logger.info(
      "ResourceManager started with limits: #{max_devices} devices, #{max_memory_mb}MB memory"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:can_allocate_device, _from, state) do
    can_allocate =
      state.device_count < state.max_devices and
        memory_within_limits?(state)

    unless can_allocate do
      Logger.warning(
        "Device allocation denied: #{state.device_count}/#{state.max_devices} devices, #{state.memory_usage_mb}/#{state.max_memory_mb}MB memory"
      )
    end

    {:reply, can_allocate, state}
  end

  @impl true
  def handle_call(:get_resource_stats, _from, state) do
    current_memory = get_current_memory_usage()

    stats = %{
      device_count: state.device_count,
      max_devices: state.max_devices,
      memory_usage_mb: current_memory,
      max_memory_mb: state.max_memory_mb,
      device_utilization: state.device_count / state.max_devices,
      memory_utilization: current_memory / state.max_memory_mb,
      active_devices_by_type: get_device_type_counts(state),
      last_cleanup: state.last_cleanup,
      uptime: System.monotonic_time(:millisecond) - state.last_cleanup,
      resource_stats: state.resource_stats
    }

    {:reply, stats, %{state | memory_usage_mb: current_memory}}
  end

  @impl true
  def handle_call(:force_cleanup, _from, state) do
    {cleaned_count, new_state} = perform_cleanup(state)

    Logger.info("Force cleanup completed: removed #{cleaned_count} idle devices")

    {:reply, {:ok, cleaned_count}, new_state}
  end

  @impl true
  def handle_call({:update_limits, opts}, _from, state) do
    new_state = %{
      state
      | max_devices: Keyword.get(opts, :max_devices, state.max_devices),
        max_memory_mb: Keyword.get(opts, :max_memory_mb, state.max_memory_mb),
        cleanup_interval: Keyword.get(opts, :cleanup_interval, state.cleanup_interval),
        idle_threshold: Keyword.get(opts, :idle_threshold, state.idle_threshold)
    }

    Logger.info(
      "Resource limits updated: #{new_state.max_devices} devices, #{new_state.max_memory_mb}MB memory"
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:check_memory_limit, _from, state) do
    current_memory = get_current_memory_usage()
    within_limits = current_memory <= state.max_memory_mb

    unless within_limits do
      Logger.warning("Memory limit exceeded: #{current_memory}MB > #{state.max_memory_mb}MB")
    end

    {:reply, within_limits, %{state | memory_usage_mb: current_memory}}
  end

  @impl true
  def handle_cast({:register_device, device_pid, device_type}, state) do
    # Monitor the device process
    Process.monitor(device_pid)

    new_active_devices =
      Map.put(state.active_devices, device_pid, %{
        type: device_type,
        registered_at: System.monotonic_time(:millisecond),
        last_activity: System.monotonic_time(:millisecond)
      })

    new_stats = update_allocation_stats(state.resource_stats, device_type)

    new_state = %{
      state
      | device_count: state.device_count + 1,
        active_devices: new_active_devices,
        resource_stats: new_stats
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:unregister_device, device_pid}, state) do
    case Map.get(state.active_devices, device_pid) do
      nil ->
        {:noreply, state}

      device_info ->
        new_active_devices = Map.delete(state.active_devices, device_pid)
        new_stats = update_deallocation_stats(state.resource_stats, device_info.type)

        new_state = %{
          state
          | device_count: state.device_count - 1,
            active_devices: new_active_devices,
            resource_stats: new_stats
        }

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:cleanup_idle_devices, state) do
    {cleaned_count, new_state} = perform_cleanup(state)

    if cleaned_count > 0 do
      Logger.info("Cleanup completed: removed #{cleaned_count} idle devices")
    end

    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_idle_devices, new_state.cleanup_interval)

    {:noreply, %{new_state | cleanup_timer: cleanup_timer}}
  end

  @impl true
  def handle_info(:check_memory, state) do
    current_memory = get_current_memory_usage()

    # Log warning if memory usage is high
    if current_memory > state.max_memory_mb * 0.9 do
      Logger.warning(
        "High memory usage: #{current_memory}MB (#{Float.round(current_memory / state.max_memory_mb * 100, 1)}%)"
      )

      # Force cleanup if memory is critically high
      if current_memory > state.max_memory_mb do
        {cleaned_count, _} = perform_cleanup(state)

        Logger.warning(
          "Emergency cleanup triggered due to memory pressure: removed #{cleaned_count} devices"
        )
      end
    end

    # Schedule next memory check
    memory_timer = Process.send_after(self(), :check_memory, @memory_check_interval)

    {:noreply, %{state | memory_usage_mb: current_memory, memory_timer: memory_timer}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, device_pid, _reason}, state) do
    # Device process died, clean it up
    case Map.get(state.active_devices, device_pid) do
      nil ->
        {:noreply, state}

      device_info ->
        new_active_devices = Map.delete(state.active_devices, device_pid)
        new_stats = update_deallocation_stats(state.resource_stats, device_info.type)

        new_state = %{
          state
          | device_count: state.device_count - 1,
            active_devices: new_active_devices,
            resource_stats: new_stats
        }

        {:noreply, new_state}
    end
  end

  # Helper functions

  defp memory_within_limits?(state) do
    current_memory = get_current_memory_usage()
    current_memory <= state.max_memory_mb
  end

  # Get the current memory usage in MB.
  # Uses process memory as a fallback if os_mon is not available
  @spec get_current_memory_usage() :: non_neg_integer()
  defp get_current_memory_usage() do
    try do
      # Get memory data and handle the result
      memory_data = :memsup.get_memory_data()

      # If we get a keyword list, try to extract memory info
      if is_list(memory_data) do
        system_memory = Keyword.get(memory_data, :system_total_memory, 0)
        free_memory = Keyword.get(memory_data, :free_memory, 0)
        used_memory = system_memory - free_memory
        round(used_memory / (1024 * 1024))
      else
        # Fall back to process memory for any other case
        process_memory = :erlang.memory(:total)
        round(process_memory / (1024 * 1024))
      end
    catch
      _type, _error ->
        # os_mon not available, use process memory as fallback
        process_memory = :erlang.memory(:total)
        round(process_memory / (1024 * 1024))
    end
  end

  defp perform_cleanup(state) do
    current_time = System.monotonic_time(:millisecond)
    idle_devices = find_idle_devices(state.active_devices, current_time, state.idle_threshold)

    cleaned_count =
      Enum.reduce(idle_devices, 0, fn {device_pid, device_info}, acc ->
        case Device.stop(device_pid) do
          :ok ->
            Logger.debug("Cleaned up idle #{device_info.type} device: #{inspect(device_pid)}")
            acc + 1

          {:error, reason} ->
            Logger.warning("Failed to clean up device #{inspect(device_pid)}: #{inspect(reason)}")
            acc
        end
      end)

    # Update state to remove cleaned devices
    remaining_devices =
      Enum.reduce(idle_devices, state.active_devices, fn {device_pid, _}, acc ->
        Map.delete(acc, device_pid)
      end)

    new_stats = update_cleanup_stats(state.resource_stats, cleaned_count)

    new_state = %{
      state
      | device_count: state.device_count - cleaned_count,
        active_devices: remaining_devices,
        last_cleanup: current_time,
        resource_stats: new_stats
    }

    {cleaned_count, new_state}
  end

  defp find_idle_devices(active_devices, current_time, idle_threshold) do
    Enum.filter(active_devices, fn {_pid, device_info} ->
      idle_time = current_time - device_info.last_activity
      idle_time > idle_threshold
    end)
  end

  defp get_device_type_counts(state) do
    Enum.reduce(state.active_devices, %{}, fn {_pid, device_info}, acc ->
      Map.update(acc, device_info.type, 1, &(&1 + 1))
    end)
  end

  defp initialize_stats() do
    %{
      total_allocated: 0,
      total_deallocated: 0,
      total_cleanups: 0,
      devices_cleaned: 0,
      allocations_by_type: %{},
      peak_device_count: 0,
      peak_memory_mb: 0
    }
  end

  defp update_allocation_stats(stats, device_type) do
    new_total = stats.total_allocated + 1
    new_by_type = Map.update(stats.allocations_by_type, device_type, 1, &(&1 + 1))

    %{
      stats
      | total_allocated: new_total,
        allocations_by_type: new_by_type,
        peak_device_count: max(stats.peak_device_count, new_total - stats.total_deallocated)
    }
  end

  defp update_deallocation_stats(stats, _device_type) do
    %{stats | total_deallocated: stats.total_deallocated + 1}
  end

  defp update_cleanup_stats(stats, cleaned_count) do
    %{
      stats
      | total_cleanups: stats.total_cleanups + 1,
        devices_cleaned: stats.devices_cleaned + cleaned_count
    }
  end
end
