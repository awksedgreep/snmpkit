defmodule SnmpSim.LazyDevicePool do
  @moduledoc """
  Lazy Device Pool Manager for on-demand device creation and lifecycle management.
  Supports 10K+ devices with minimal memory footprint through lazy instantiation.

  Features:
  - On-demand device creation when first accessed
  - Automatic cleanup of idle devices to conserve resources
  - Port-based device type determination
  - Efficient tracking of active devices and last access times
  - Resource monitoring and cleanup scheduling
  """
  use GenServer
  require Logger

  alias SnmpSim.Device

  defstruct [
    # Map: port -> device_pid
    :active_devices,
    # Map: port -> device_config
    :device_configs,
    # Map: port -> timestamp
    :last_access,
    # Periodic cleanup timer
    :cleanup_timer,
    # Device type port ranges
    :port_assignments,
    # Idle timeout before cleanup
    :idle_timeout_ms,
    # Maximum concurrent devices
    :max_devices,
    # Statistics tracking
    :stats
  ]

  # 30 minutes
  @default_idle_timeout_ms 30 * 60 * 1000
  @default_max_devices 100
  # 5 minutes
  @cleanup_interval_ms 5 * 60 * 1000

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get or create a device for the specified port.
  Creates the device on first access if it doesn't exist.
  """
  def get_or_create_device(port) when is_integer(port) do
    GenServer.call(__MODULE__, {:get_or_create_device, port})
  end

  @doc """
  Configure device types for specific port ranges.
  """
  def configure_port_assignments(port_assignments) do
    GenServer.call(__MODULE__, {:configure_port_assignments, port_assignments})
  end

  @doc """
  Get statistics about the device pool.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Force cleanup of idle devices immediately.
  """
  def cleanup_idle_devices do
    GenServer.cast(__MODULE__, :cleanup_idle_devices)
  end

  @doc """
  Shutdown a specific device.
  """
  def shutdown_device(port) do
    GenServer.call(__MODULE__, {:shutdown_device, port})
  end

  @doc """
  Shutdown all devices and reset the pool.
  """
  def shutdown_all_devices do
    GenServer.call(__MODULE__, :shutdown_all_devices)
  end

  @doc """
  Clear the device cache - alias for shutdown_all_devices for compatibility.
  """
  def clear_cache do
    shutdown_all_devices()
  end

  # Legacy API for backward compatibility
  def start_device_population(device_configs, opts \\ []) do
    port_range = Keyword.get(opts, :port_range, 9001..9100)

    # Configure port assignments based on device configs
    port_assignments = build_port_assignments(device_configs, port_range)
    configure_port_assignments(port_assignments)

    # Pre-warm devices if requested
    if Keyword.get(opts, :pre_warm, false) do
      pre_warm_devices(device_configs, port_range)
    else
      {:ok, :lazy_pool_configured}
    end
  end

  # GenServer Callbacks

  def init(opts) do
    idle_timeout_ms = Keyword.get(opts, :idle_timeout_ms, @default_idle_timeout_ms)
    max_devices = Keyword.get(opts, :max_devices, @default_max_devices)

    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_idle_devices, @cleanup_interval_ms)

    state = %__MODULE__{
      active_devices: %{},
      device_configs: %{},
      last_access: %{},
      cleanup_timer: cleanup_timer,
      port_assignments: default_port_assignments(),
      idle_timeout_ms: idle_timeout_ms,
      max_devices: max_devices,
      stats: %{
        devices_created: 0,
        devices_cleaned_up: 0,
        active_count: 0,
        peak_count: 0
      }
    }

    {:ok, state}
  end

  def handle_call({:get_or_create_device, port}, _from, state) do
    case Map.get(state.active_devices, port) do
      nil ->
        # Device doesn't exist, create it
        case create_device(port, state) do
          {:ok, device_pid, new_state} ->
            {:reply, {:ok, device_pid}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      device_pid ->
        # Device exists, check if it's still alive
        if Process.alive?(device_pid) do
          # Update last access time
          new_state = update_last_access(state, port)
          {:reply, {:ok, device_pid}, new_state}
        else
          # Device died, remove it and create a new one
          cleaned_state = remove_dead_device(state, port)

          case create_device(port, cleaned_state) do
            {:ok, device_pid, new_state} ->
              {:reply, {:ok, device_pid}, new_state}

            {:error, reason} ->
              {:reply, {:error, reason}, cleaned_state}
          end
        end
    end
  end

  def handle_call({:configure_port_assignments, port_assignments}, _from, state) do
    new_state = %{state | port_assignments: port_assignments}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    current_stats =
      Map.merge(state.stats, %{
        active_count: map_size(state.active_devices),
        total_ports_configured: count_configured_ports(state.port_assignments)
      })

    {:reply, current_stats, state}
  end

  def handle_call({:shutdown_device, port}, _from, state) do
    case Map.get(state.active_devices, port) do
      nil ->
        {:reply, {:error, :not_found}, state}

      device_pid ->
        :ok = Device.stop(device_pid)
        new_state = remove_device(state, port)
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:shutdown_all_devices, _from, state) do
    # Shutdown all active devices
    Enum.each(state.active_devices, fn {_port, device_pid} ->
      if Process.alive?(device_pid) do
        Device.stop(device_pid)
      end
    end)

    # Reset state
    new_state = %{
      state
      | active_devices: %{},
        device_configs: %{},
        last_access: %{},
        stats: %{state.stats | active_count: 0}
    }

    {:reply, :ok, new_state}
  end

  def handle_cast(:cleanup_idle_devices, state) do
    new_state = cleanup_idle_devices_impl(state)
    {:noreply, new_state}
  end

  def handle_info(:cleanup_idle_devices, state) do
    new_state = cleanup_idle_devices_impl(state)

    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_idle_devices, @cleanup_interval_ms)
    new_state = %{new_state | cleanup_timer: cleanup_timer}

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, device_pid, _reason}, state) do
    # Handle device process death
    port = find_port_by_pid(state.active_devices, device_pid)

    if port do
      new_state = remove_device(state, port)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # Private Functions

  defp create_device(port, state) do
    if map_size(state.active_devices) >= state.max_devices do
      {:error, :max_devices_reached}
    else
      device_type = determine_device_type(port, state.port_assignments)
      Logger.debug("LazyDevicePool: Creating device for port #{port}, device_type: #{inspect(device_type)}")

      case device_type do
        nil ->
          Logger.error("LazyDevicePool: Unknown port range for port #{port}")
          {:error, :unknown_port_range}

        device_type ->
          device_config = %{
            port: port,
            device_type: device_type,
            device_id: generate_device_id(device_type, port),
            community: "public"
          }
          
          # Add walk_file for cable_modem devices
          device_config = if device_type == :cable_modem do
            Map.put(device_config, :walk_file, "priv/walks/cable_modem.walk")
          else
            device_config
          end

          case Device.start_link(device_config) do
            {:ok, device_pid} ->
              # Monitor the device process
              Process.monitor(device_pid)

              # Update state
              new_state = %{
                state
                | active_devices: Map.put(state.active_devices, port, device_pid),
                  device_configs: Map.put(state.device_configs, port, device_config),
                  last_access:
                    Map.put(state.last_access, port, System.monotonic_time(:millisecond)),
                  stats: %{
                    state.stats
                    | devices_created: state.stats.devices_created + 1,
                      active_count: map_size(state.active_devices) + 1,
                      peak_count: max(state.stats.peak_count, map_size(state.active_devices) + 1)
                  }
              }

              {:ok, device_pid, new_state}

            {:error, reason} ->
              {:error, reason}
          end
      end
    end
  end

  defp determine_device_type(port, port_assignments) do
    Enum.find_value(port_assignments, fn {device_type, ranges} ->
      if port_in_ranges?(port, ranges), do: device_type, else: nil
    end)
  end

  defp port_in_ranges?(port, ranges) when is_list(ranges) do
    Enum.any?(ranges, fn range -> port in range end)
  end

  defp port_in_ranges?(port, range) do
    port in range
  end

  defp generate_device_id(device_type, port) do
    "#{device_type}_#{port}"
  end

  defp update_last_access(state, port) do
    new_last_access = Map.put(state.last_access, port, System.monotonic_time(:millisecond))
    %{state | last_access: new_last_access}
  end

  defp cleanup_idle_devices_impl(state) do
    current_time = System.monotonic_time(:millisecond)
    idle_threshold = current_time - state.idle_timeout_ms

    idle_ports =
      Enum.filter(state.last_access, fn {_port, last_access} ->
        last_access < idle_threshold
      end)
      |> Enum.map(fn {port, _} -> port end)

    # Shutdown idle devices
    cleanup_count =
      Enum.reduce(idle_ports, 0, fn port, acc ->
        case Map.get(state.active_devices, port) do
          nil ->
            acc

          device_pid ->
            if Process.alive?(device_pid) do
              Device.stop(device_pid)
              acc + 1
            else
              acc
            end
        end
      end)

    # Remove idle devices from state
    new_active_devices = Map.drop(state.active_devices, idle_ports)
    new_device_configs = Map.drop(state.device_configs, idle_ports)
    new_last_access = Map.drop(state.last_access, idle_ports)

    %{
      state
      | active_devices: new_active_devices,
        device_configs: new_device_configs,
        last_access: new_last_access,
        stats: %{
          state.stats
          | devices_cleaned_up: state.stats.devices_cleaned_up + cleanup_count,
            active_count: map_size(new_active_devices)
        }
    }
  end

  defp remove_device(state, port) do
    %{
      state
      | active_devices: Map.delete(state.active_devices, port),
        device_configs: Map.delete(state.device_configs, port),
        last_access: Map.delete(state.last_access, port),
        stats: %{state.stats | active_count: map_size(state.active_devices) - 1}
    }
  end

  defp remove_dead_device(state, port) do
    %{
      state
      | active_devices: Map.delete(state.active_devices, port),
        device_configs: Map.delete(state.device_configs, port),
        last_access: Map.delete(state.last_access, port)
    }
  end

  defp find_port_by_pid(active_devices, target_pid) do
    Enum.find_value(active_devices, fn {port, pid} ->
      if pid == target_pid, do: port, else: nil
    end)
  end

  defp count_configured_ports(port_assignments) do
    Enum.reduce(port_assignments, 0, fn {_type, ranges}, acc ->
      acc + count_ports_in_ranges(ranges)
    end)
  end

  defp count_ports_in_ranges(ranges) when is_list(ranges) do
    Enum.reduce(ranges, 0, fn range, acc -> acc + Enum.count(range) end)
  end

  defp count_ports_in_ranges(range) do
    Enum.count(range)
  end

  defp build_port_assignments(device_configs, port_range) do
    port_list = Enum.to_list(port_range)

    {port_assignments, _} =
      Enum.reduce(device_configs, {%{}, port_list}, fn
        {device_type, _source, opts}, {assignments, remaining_ports} ->
          count = Keyword.get(opts, :count, 1)
          {assigned_ports, new_remaining} = Enum.split(remaining_ports, count)

          if length(assigned_ports) > 0 do
            range = Enum.min(assigned_ports)..Enum.max(assigned_ports)
            {Map.put(assignments, device_type, range), new_remaining}
          else
            {assignments, new_remaining}
          end
      end)

    port_assignments
  end

  defp pre_warm_devices(device_configs, port_range) do
    Enum.reduce(device_configs, {:ok, []}, fn {_device_type, _source, opts}, acc ->
      case acc do
        {:error, _} = error ->
          error

        {:ok, devices} ->
          count = Keyword.get(opts, :count, 1)
          start_port = Enum.at(Enum.to_list(port_range), length(devices))

          new_devices =
            Enum.map(0..(count - 1), fn i ->
              port = start_port + i

              case get_or_create_device(port) do
                {:ok, pid} -> {port, pid}
                {:error, reason} -> {:error, {port, reason}}
              end
            end)

          case Enum.find(new_devices, &match?({:error, _}, &1)) do
            nil -> {:ok, devices ++ new_devices}
            error -> error
          end
      end
    end)
  end

  defp default_port_assignments do
    %{
      # Port ranges to match test expectations
      cable_modem: 30_000..37_999,      # 8000 ports for cable modems
      mta: 38_000..38_499,              # 500 ports for MTAs
      router: 39_000..39_499,           # 500 ports for routers
      switch: 39_500..39_899,           # 400 ports for switches  
      cmts: 39_950..39_999,             # 50 ports for CMTS (as expected by test)
      server: 38_500..38_999            # 500 ports for servers
    }
  end
end
