defmodule SnmpSim.Device do
  @moduledoc """
  Lightweight Device GenServer for handling SNMP requests.
  Uses shared profiles and minimal device-specific state for scalability.

  Features:
  - Dynamic value generation with realistic patterns
  - Shared profile system for memory efficiency
  - Counter and gauge simulation with proper incrementing
  - Comprehensive error handling and fallback mechanisms
  - Support for SNMP walk operations
  """

  use GenServer
  require Logger

  alias SnmpSim.{DeviceDistribution}
  alias SnmpSim.Core.Server
  alias SnmpSim.Device.ErrorInjector
  alias SnmpSim.Device.OidHandler
  import SnmpSim.Device.OidHandler
  import SnmpSim.Device.PduProcessor, only: [process_snmp_pdu: 2]


  defstruct [
    :device_id,
    :port,
    :device_type,
    :server_pid,
    :mac_address,
    :uptime_start,
    # Device-specific counter state
    :counters,
    # Device-specific gauge state
    :gauges,
    # Device-specific status variables
    :status_vars,
    :community,
    # For tracking access time
    :last_access,
    # Active error injection conditions
    :error_conditions,
    # Flag indicating if device has walk data loaded
    :has_walk_data
  ]

  @default_community "public"

  @doc """
  Start a device with the given device configuration.

  ## Device Config

  Device config should contain:
  - `:port` - UDP port for the device (required)
  - `:device_type` - Type of device (:cable_modem, :switch, etc.)
  - `:device_id` - Unique device identifier
  - `:community` - SNMP community string (default: "public")
  - `:mac_address` - MAC address (auto-generated if not provided)

  ## Examples

      device_config = %{
        port: 9001,
        device_type: :cable_modem,
        device_id: "cable_modem_9001",
        community: "public"
      }

      {:ok, device} = SnmpSim.Device.start_link(device_config)

  """
  def start_link(device_config) when is_map(device_config) do
    GenServer.start_link(__MODULE__, device_config)
  end

  @doc """
  Stop a device gracefully with resilient error handling.
  """
  def stop(device_pid) when is_pid(device_pid) do
    case Process.alive?(device_pid) do
      false ->
        :ok

      true ->
        try do
          GenServer.stop(device_pid, :normal, 5000)
        catch
          :exit, {:noproc, _} ->
            :ok

          :exit, {:normal, _} ->
            :ok

          :exit, {:shutdown, _} ->
            :ok

          :exit, {:timeout, _} ->
            # Process didn't stop gracefully, force kill
            Process.exit(device_pid, :kill)
            :ok

          :exit, _reason ->
            :ok
        end
    end
  end

  def stop(%{pid: device_pid}) when is_pid(device_pid) do
    stop(device_pid)
  end

  def stop(device_info) when is_map(device_info) do
    cond do
      Map.has_key?(device_info, :pid) -> stop(device_info.pid)
      Map.has_key?(device_info, :device_pid) -> stop(device_info.device_pid)
      true -> {:error, :no_pid_found}
    end
  end

  @doc """
  Cleanup all orphaned SNMP simulator device processes.
  Useful for test cleanup when devices may have been left running.
  """
  def cleanup_all_devices do
    # Find all processes running SnmpSim.Device
    device_processes =
      Process.list()
      |> Enum.filter(fn pid ->
        try do
          case Process.info(pid, :dictionary) do
            {:dictionary, dict} ->
              # Check if this process is running SnmpSim.Device
              Enum.any?(dict, fn
                {:"$initial_call", {SnmpSim.Device, :init, 1}} ->
                  true

                {:"$ancestors", ancestors} when is_list(ancestors) ->
                  Enum.any?(ancestors, fn ancestor ->
                    is_atom(ancestor) and Atom.to_string(ancestor) =~ "SnmpSim"
                  end)

                _ ->
                  false
              end)

            _ ->
              false
          end
        catch
          _, _ -> false
        end
      end)

    # Stop each device process
    cleanup_count =
      Enum.reduce(device_processes, 0, fn pid, acc ->
        case stop(pid) do
          :ok -> acc + 1
          _ -> acc
        end
      end)

    Logger.info("Cleaned up #{cleanup_count} orphaned device processes")
    {:ok, cleanup_count}
  end

  @doc """
  Monitor a device process and get notified when it dies.
  Returns a monitor reference that can be used with Process.demonitor/1.
  """
  def monitor_device(device_pid) when is_pid(device_pid) do
    Process.monitor(device_pid)
  end

  @doc """
  Create a device with monitoring enabled.
  Returns {:ok, {device_pid, monitor_ref}} or {:error, reason}.
  """
  def start_link_monitored(device_config) when is_map(device_config) do
    case start_link(device_config) do
      {:ok, device_pid} ->
        monitor_ref = monitor_device(device_pid)
        {:ok, {device_pid, monitor_ref}}

      error ->
        error
    end
  end

  @doc """
  Get device information and statistics.
  """
  def get_info(device_pid) do
    GenServer.call(device_pid, :get_info)
  end

  @doc """
  Update device counters manually (useful for testing).
  """
  def update_counter(device_pid, oid, increment) do
    GenServer.call(device_pid, {:update_counter, oid, increment})
  end

  @doc """
  Set a gauge value manually (useful for testing).
  """
  def set_gauge(device_pid, oid, value) do
    GenServer.call(device_pid, {:set_gauge, oid, value})
  end

  @doc """
  Get an OID value from the device (for testing).
  """
  def get(device_pid, oid) do
    GenServer.call(device_pid, {:get_oid, oid})
  end

  @doc """
  Get the next OID value from the device (for testing).
  """
  def get_next(device_pid, oid) do
    GenServer.call(device_pid, {:get_next_oid, oid})
  end

  @doc """
  Get bulk OID values from the device (for testing).
  """
  def get_bulk(device_pid, oids, max_repetitions) do
    get_bulk(device_pid, oids, 0, max_repetitions)
  end

  def get_bulk(device_pid, oids, non_repeaters, max_repetitions) do
    GenServer.call(device_pid, {:get_bulk_oid, oids, non_repeaters, max_repetitions})
  end

  @doc """
  Walk OID values from the device (for testing).
  """
  def walk(device_pid, oid) do
    GenServer.call(device_pid, {:walk_oid, oid})
  end

  @doc """
  Simulate a device reboot.
  """
  def reboot(device_pid) do
    GenServer.call(device_pid, :reboot)
  end

  # GenServer callbacks

  @impl true
  def init(device_config) when is_map(device_config) do
    case Map.fetch(device_config, :device_id) do
      :error ->
        raise "Missing required :device_id in device init args"

      {:ok, device_id} ->
        port = Map.fetch!(device_config, :port)
        device_type = Map.fetch!(device_config, :device_type)
        community = Map.get(device_config, :community, @default_community)

        mac_address =
          Map.get(device_config, :mac_address, generate_mac_address(device_type, port))

        # Load walk file if provided and set flag
        has_walk_data = case Map.get(device_config, :walk_file) do
          nil ->
            false

          walk_file ->
            Logger.info("Loading walk file #{walk_file} for device type #{inspect(device_type)}")
            case SnmpSim.MIB.SharedProfiles.load_walk_profile(device_type, walk_file) do
              :ok ->
                Logger.info("Successfully loaded walk file #{walk_file} for device type #{inspect(device_type)}")
                true

              {:error, reason} ->
                Logger.warning("Failed to load walk file #{walk_file} for device type #{inspect(device_type)}: #{inspect(reason)}")
                false
            end
        end

        # Start the UDP server for this device
        case Server.start_link(port, community: community) do
          {:ok, server_pid} ->
            state = %__MODULE__{
              device_id: device_id,
              port: port,
              device_type: device_type,
              server_pid: server_pid,
              mac_address: mac_address,
              uptime_start: :erlang.monotonic_time(),
              counters: %{},
              gauges: %{},
              status_vars: %{},
              community: community,
              last_access: System.monotonic_time(:millisecond),
              error_conditions: %{},
              has_walk_data: has_walk_data
            }

            # Set up the SNMP handler for this device
            device_pid = self()

            handler_fn = fn pdu, context ->
              GenServer.call(device_pid, {:handle_snmp, pdu, context})
            end

            :ok = Server.set_device_handler(server_pid, handler_fn)

            # Initialize device state from shared profile
            {:ok, initialized_state} = initialize_device_state(state)
            Logger.info("Device #{device_id} started on port #{port}")
            {:ok, initialized_state}

          {:error, reason} ->
            Logger.error(
              "Failed to start UDP server for device #{device_id} on port #{port}: #{inspect(reason)}"
            )

            {:stop, reason}
        end
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) when is_map(state) do
    # Get OID count (simplified for testing)
    # Mock value for testing
    oid_count = 100

    info = %{
      device_id: state.device_id,
      port: state.port,
      device_type: state.device_type,
      mac_address: state.mac_address,
      uptime: calculate_uptime(state),
      oid_count: oid_count,
      counters: map_size(state.counters),
      gauges: map_size(state.gauges),
      status_vars: map_size(state.status_vars),
      last_access: state.last_access,
      has_walk_data: state.has_walk_data
    }

    # Update last access time
    new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    {:reply, info, new_state}
  end

  @impl true
  def handle_call({:handle_snmp, pdu, _context}, _from, state) do
    # Check for error injection conditions first
    case ErrorInjector.check_error_conditions(pdu, state) do
      :continue ->
        # Process the PDU normally
        response = process_snmp_pdu(pdu, state)
        {:reply, {:ok, response}, state}

      {:error, error_type} ->
        # Handle error injection
        {:reply, {:error, error_type}, state}
    end
  end

  @impl true
  def handle_call({:update_counter, oid, increment}, _from, state) do
    new_counters = Map.update(state.counters, oid, increment, &(&1 + increment))
    new_state = %{state | counters: new_counters}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_gauge, oid, value}, _from, state) do
    new_gauges = Map.put(state.gauges, oid, value)
    new_state = %{state | gauges: new_gauges}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_oid, oid}, _from, state) do
    result = SnmpSim.Device.OidHandler.get_oid_value(oid, state)
    formatted_result = case result do
      {:ok, {oid_string, type, value}} -> {:ok, {oid_string, type, value}}  # Return 3-tuple format consistently
      {:ok, {type, value}} -> {:ok, {oid, type, value}}   # Return {oid, type, value} for other formats
      {:ok, value} -> {:ok, {oid, :octet_string, value}}  # Default to octet_string type
      error -> error
    end
    new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    {:reply, formatted_result, new_state}
  end

  @impl true
  def handle_call({:get_next_oid, oid}, _from, state) do
    result = SnmpSim.Device.OidHandler.get_next_oid_value(state.device_type, oid, state)
    formatted_result = case result do
      {:ok, {oid, type, value}} -> {:ok, {OidHandler.oid_to_string(oid), type, value}}
      {:ok, {oid, value}} -> {:ok, {OidHandler.oid_to_string(oid), :octet_string, value}}
      {:ok, value} -> {:ok, value}
      error -> error
    end
    {:reply, formatted_result, state}
  end

  @impl true
  def handle_call({:get_bulk_oid, oids, non_repeaters, max_repetitions}, _from, state) do
    # Convert OIDs to varbind format expected by process_get_bulk_varbinds
    varbinds = case oids do
      oid when is_binary(oid) -> [{oid, :null}]
      oid_list when is_list(oid_list) ->
        Enum.map(oid_list, fn oid -> {oid, :null} end)
      _ -> [{oids, :null}]
    end

    result = process_get_bulk_varbinds(varbinds, non_repeaters, max_repetitions, state.device_type)
    IO.inspect(result, label: "GETBULK result from process_get_bulk_varbinds")
    formatted_result = Enum.map(result, fn
      {oid, type, value} -> {OidHandler.oid_to_string(oid), type, value}
      {oid, value} -> {OidHandler.oid_to_string(oid), :octet_string, value}
    end)
    IO.inspect(formatted_result, label: "GETBULK formatted_result")
    {:reply, {:ok, formatted_result}, state}
  end

  @impl true
  def handle_call({:walk_oid, oid}, _from, state) do
    case OidHandler.walk_oid_values(oid, state) do
      {:ok, results} ->
        # Convert OIDs to strings and sort them properly using numerical comparison
        sorted_results = results
        |> Enum.map(fn {oid, {type, value}} ->
          oid_string = OidHandler.oid_to_string(oid)
          {oid_string, type, value}
        end)
        |> Enum.sort_by(fn {oid_string, _type, _value} ->
          # Convert OID string to list of integers for proper numerical sorting
          oid_string
          |> String.split(".")
          |> Enum.map(&String.to_integer/1)
        end)
        |> Enum.map(fn {oid_string, type, value} -> {oid_string, type, value} end)

        new_state = %{state | last_access: System.monotonic_time(:millisecond)}
        {:reply, {:ok, sorted_results}, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:reboot, _from, state) do
    Logger.info("Device #{state.device_id} rebooting")

    new_state = %{
      state
      | uptime_start: :erlang.monotonic_time(),
        counters: %{},
        gauges: %{},
        status_vars: %{},
        error_conditions: %{},
        has_walk_data: false
    }

    {:ok, initialized_state} = initialize_device_state(new_state)
    {:reply, :ok, initialized_state}
  end

  # Error injection message handlers
  @impl true
  def handle_info({:error_injection, :timeout, config}, state) do
    Logger.debug("Applying timeout error injection to device #{state.device_id}")
    new_error_conditions = Map.put(state.error_conditions, :timeout, config)
    {:noreply, %{state | error_conditions: new_error_conditions}}
  end

  @impl true
  def handle_info({:error_injection, :packet_loss, config}, state) do
    Logger.debug("Applying packet loss error injection to device #{state.device_id}")
    new_error_conditions = Map.put(state.error_conditions, :packet_loss, config)
    {:noreply, %{state | error_conditions: new_error_conditions}}
  end

  @impl true
  def handle_info({:error_injection, :snmp_error, config}, state) do
    Logger.debug("Applying SNMP error injection to device #{state.device_id}")
    new_error_conditions = Map.put(state.error_conditions, :snmp_error, config)
    {:noreply, %{state | error_conditions: new_error_conditions}}
  end

  @impl true
  def handle_info({:error_injection, :malformed, config}, state) do
    Logger.debug("Applying malformed response error injection to device #{state.device_id}")
    new_error_conditions = Map.put(state.error_conditions, :malformed, config)
    {:noreply, %{state | error_conditions: new_error_conditions}}
  end

  @impl true
  def handle_info({:error_injection, :device_failure, config}, state) do
    Logger.info(
      "Applying device failure error injection to device #{state.device_id}: #{config.failure_type}"
    )

    new_error_conditions = Map.put(state.error_conditions, :device_failure, config)

    case config.failure_type do
      :reboot ->
        # Schedule device recovery after duration
        Process.send_after(self(), {:error_injection, :recovery, config}, config.duration_ms)
        {:noreply, %{state | error_conditions: new_error_conditions}}

      :power_failure ->
        # Simulate complete power loss - device becomes unreachable
        # down
        new_status_vars = Map.put(state.status_vars, "oper_status", 2)

        {:noreply,
         %{state | error_conditions: new_error_conditions, status_vars: new_status_vars}}

      :network_disconnect ->
        # Simulate network connectivity loss
        # administratively down
        new_status_vars = Map.put(state.status_vars, "admin_status", 2)

        {:noreply,
         %{state | error_conditions: new_error_conditions, status_vars: new_status_vars}}

      _ ->
        {:noreply, %{state | error_conditions: new_error_conditions}}
    end
  end

  @impl true
  def handle_info({:error_injection, :recovery, config}, state) do
    Logger.info("Device #{state.device_id} recovering from #{config.failure_type}")

    # Remove device failure condition
    new_error_conditions = Map.delete(state.error_conditions, :device_failure)

    # Restore device status based on recovery behavior
    case config[:recovery_behavior] do
      :reset_counters ->
        # Reset counters and restore status
        new_state = %{
          state
          | error_conditions: new_error_conditions,
            counters: %{},
            status_vars: %{"admin_status" => 1, "oper_status" => 1, "last_change" => 0},
            has_walk_data: false
        }

        {:noreply, new_state}

      :gradual ->
        # Gradual recovery - restore status but keep some impact
        new_status_vars =
          Map.merge(state.status_vars, %{
            "admin_status" => 1,
            "oper_status" => 1,
            "last_change" => calculate_uptime(state)
          })

        {:noreply,
         %{state | error_conditions: new_error_conditions, status_vars: new_status_vars}}

      _ ->
        # Normal recovery
        new_status_vars =
          Map.merge(state.status_vars, %{
            "admin_status" => 1,
            "oper_status" => 1
          })

        {:noreply,
         %{state | error_conditions: new_error_conditions, status_vars: new_status_vars}}
    end
  end

  @impl true
  def handle_info({:error_injection, :clear_all}, state) do
    Logger.info("Clearing all error conditions for device #{state.device_id}")
    {:noreply, %{state | error_conditions: %{}}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Device #{state.device_id} received unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %{server_pid: server_pid, device_id: device_id} = _state)
      when is_pid(server_pid) do
    GenServer.stop(server_pid)
    Logger.info("Device #{device_id} terminated: #{inspect(reason)}")
    :ok
  end

  def terminate(reason, %{device_id: device_id} = _state) do
    Logger.info("Device #{device_id} terminated: #{inspect(reason)}")
    :ok
  end

  def terminate(reason, state) do
    Logger.info(
      "Device terminated with invalid state: #{inspect(reason)}, state: #{inspect(state)}"
    )

    :ok
  end

  # Private functions

  defp initialize_device_state(state) do
    # Try to load actual profile data from SharedProfiles
    profiles = SnmpSim.MIB.SharedProfiles.list_profiles()
    Logger.info("Device #{state.device_id} checking profiles: #{inspect(profiles)} for device_type: #{inspect(state.device_type)}")

    case Enum.member?(profiles, state.device_type) do
      true ->
        Logger.info("Device #{state.device_id} initialized with profile for device type: #{state.device_type}")
        # Profile exists in SharedProfiles, device will use it via OidHandler
        {:ok, %{state | has_walk_data: true}}

      false ->
        # Fallback to mock implementation for testing
        Logger.info("Device #{state.device_id} initialized with mock profile for testing")

        # Initialize basic counters and gauges for testing
        counters = %{
          # ifInOctets
          "1.3.6.1.2.1.2.2.1.10.1" => 0,
          # ifOutOctets
          "1.3.6.1.2.1.2.2.1.16.1" => 0
        }

        gauges = %{
          # ifSpeed
          "1.3.6.1.2.1.2.2.1.5.1" => 100_000_000,
          # ifMtu
          "1.3.6.1.2.1.2.2.1.4.1" => 1500
        }

        status_vars = initialize_status_vars(state)

        {:ok,
         %{
           state
           | counters: counters,
             gauges: gauges,
             status_vars: status_vars,
             error_conditions: state.error_conditions,
             has_walk_data: false
         }}
    end
  end

  defp generate_mac_address(device_type, port) do
    # Generate MAC address using DeviceDistribution module
    DeviceDistribution.generate_device_id(device_type, port, format: :mac_based)
  end

  defp initialize_status_vars(_state) do
    # Initialize device-specific status variables
    %{
      # up
      "admin_status" => 1,
      # up
      "oper_status" => 1,
      "last_change" => 0
    }
  end

  defp process_get_bulk_varbinds(varbinds, non_repeaters, max_repetitions, device_type) do
    IO.inspect({varbinds, non_repeaters, max_repetitions, device_type}, label: "GETBULK input params")
    {non_repeater_vars, repeater_vars} = Enum.split(varbinds, non_repeaters)
    IO.inspect({non_repeater_vars, repeater_vars}, label: "GETBULK split varbinds")

    # For GETBULK, we need to get the NEXT OIDs, not the exact OIDs
    non_repeater_results =
      non_repeater_vars
      |> Enum.map(fn {oid, _} ->
        device_state = %{device_type: device_type, uptime: 0}
        case SnmpSim.Device.OidHandler.get_next_oid_value(device_type, oid, device_state) do
          {:ok, {next_oid, type, value}} -> {next_oid, type, value}
          {:ok, {next_oid, value}} -> {next_oid, :octet_string, value}
          {:ok, value} -> {oid, :octet_string, value}
          {:error, _} -> {oid, :no_such_name, :null}
        end
      end)
    IO.inspect(non_repeater_results, label: "GETBULK non_repeater_results")

    repeater_results =
      repeater_vars
      |> Enum.flat_map(fn {oid, _} ->
        1..max_repetitions
        |> Enum.reduce_while([], fn _i, acc ->
          current_oid = if acc == [], do: oid, else: elem(List.last(acc), 0)
          IO.inspect(current_oid, label: "GETBULK current_oid for iteration")

          device_state = %{device_type: device_type, uptime: 0}
          case SnmpSim.Device.OidHandler.get_next_oid_value(device_type, current_oid, device_state) do
            {:ok, {next_oid, type, value}} ->
              result = {next_oid, type, value}
              IO.inspect(result, label: "GETBULK got next_oid result")
              {:cont, acc ++ [result]}
            {:ok, {next_oid, value}} ->
              result = {next_oid, :octet_string, value}
              IO.inspect(result, label: "GETBULK got next_oid result (2-tuple)")
              {:cont, acc ++ [result]}
            {:ok, value} ->
              result = {current_oid, :octet_string, value}
              IO.inspect(result, label: "GETBULK got value result")
              {:cont, acc ++ [result]}
            {:error, reason} ->
              IO.inspect(reason, label: "GETBULK error, halting")
              {:halt, acc}
          end
        end)
      end)
    IO.inspect(repeater_results, label: "GETBULK repeater_results")

    non_repeater_results ++ repeater_results
  end
end
