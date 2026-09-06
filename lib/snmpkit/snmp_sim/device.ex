defmodule SnmpKit.SnmpSim.Device do
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

  alias SnmpKit.SnmpSim.{DeviceDistribution}
  alias SnmpKit.SnmpSim.Core.Server
  alias SnmpKit.SnmpSim.Device.ErrorConditions, as: ErrorInjector
  alias SnmpKit.SnmpSim.Device.OidHandler
  import SnmpKit.SnmpSim.Device.PduProcessor, only: [process_snmp_pdu: 2]

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
    :has_walk_data,
    # Manual OID map for devices created with {:manual, oid_map}
    :oid_map,
    # Tracks if a profile (of any source) was explicitly provided at start
    :profile_provided,
    # Manual device flag to force no shared profile usage
    :manual_device,
    # Modem firmware upgrade support (DOCSIS)
    :upgrade_enabled,
    :upgrade
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

      {:ok, device} = SnmpKit.SnmpSim.Device.start_link(device_config)

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
    # Find all processes running SnmpKit.SnmpSim.Device
    device_processes =
      Process.list()
      |> Enum.filter(fn pid ->
        try do
          case Process.info(pid, :dictionary) do
            {:dictionary, dict} ->
              # Check if this process is running SnmpKit.SnmpSim.Device
              Enum.any?(dict, fn
                {:"$initial_call", {SnmpKit.SnmpSim.Device, :init, 1}} ->
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
  Sends a trap from this device to a receiver, using the device's community
  and uptime. `opts` must include `to: target` (host, `"host:port"` or
  `{host, port}`, port 162 by default); the other options are those of
  `SnmpKit.SnmpMgr.Notify.send_trap/4`.

      :ok = SnmpKit.SnmpSim.Device.send_trap(device, "linkDown", [{"ifIndex.1", :integer, 1}], to: "127.0.0.1:1162")
  """
  @spec send_trap(pid(), term(), list(), keyword()) :: :ok | {:error, term()}
  def send_trap(device_pid, trap_oid, varbinds, opts) do
    GenServer.call(device_pid, {:send_trap, trap_oid, varbinds, opts})
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

        # Extract OID map from profile if provided
        {oid_map, has_walk_data} =
          case Map.get(device_config, :profile) do
            %{oid_map: oid_map} when is_map(oid_map) and map_size(oid_map) > 0 ->
              Logger.info(
                "Device #{device_id} loading #{map_size(oid_map)} OIDs from manual profile"
              )

              {oid_map, true}

            _ ->
              # Load walk file if provided and set flag
              walk_data_loaded =
                case Map.get(device_config, :walk_file) do
                  nil ->
                    false

                  walk_file ->
                    Logger.info(
                      "Loading walk file #{walk_file} for device type #{inspect(device_type)}"
                    )

                    case SnmpKit.SnmpSim.MIB.SharedProfiles.load_walk_profile(
                           device_type,
                           walk_file
                         ) do
                      :ok ->
                        Logger.info(
                          "Successfully loaded walk file #{walk_file} for device type #{inspect(device_type)}"
                        )

                        true

                      {:error, reason} ->
                        Logger.warning(
                          "Failed to load walk file #{walk_file} for device type #{inspect(device_type)}: #{inspect(reason)}"
                        )

                        false
                    end
                end

              {%{}, walk_data_loaded}
          end

        # Start the UDP server for this device
        case Server.start_link(port,
               community: community,
               bind_address: Map.get(device_config, :bind_address),
               v3_users: Map.get(device_config, :v3_users),
               engine_id: Map.get(device_config, :engine_id),
               device_id: device_id
             ) do
          {:ok, server_pid} ->
            # Initialize modem upgrade defaults
            upgrade_enabled =
              case device_type do
                :cable_modem -> Map.get(device_config, :upgrade_enabled, true)
                _ -> false
              end

            upgrade_opts = Map.get(device_config, :upgrade_opts, %{})

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
              has_walk_data: has_walk_data,
              oid_map: oid_map,
              profile_provided: Map.has_key?(device_config, :profile),
              manual_device: Map.get(device_config, :manual_device, false),
              upgrade_enabled: upgrade_enabled,
              upgrade: SnmpKit.SnmpSim.Device.ModemUpgrade.default_state(upgrade_opts)
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
  def handle_call({:send_trap, trap_oid, varbinds, opts}, _from, state) when is_map(state) do
    opts =
      opts
      |> Keyword.put_new(:community, state.community)
      |> Keyword.put_new(:uptime, SnmpKit.SnmpSim.Device.Metrics.calculate_uptime_ticks(state))

    result =
      SnmpKit.SnmpMgr.Notify.send_trap(Keyword.fetch!(opts, :to), trap_oid, varbinds, opts)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) when is_map(state) do
    oid_count = count_device_oids(state)

    info = %{
      device_id: state.device_id,
      port: state.port,
      device_type: state.device_type,
      mac_address: state.mac_address,
      uptime: SnmpKit.SnmpSim.Device.Metrics.calculate_uptime(state),
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
    started = System.monotonic_time()

    # Check for error injection conditions first
    {reply, result} =
      case ErrorInjector.check_error_conditions(pdu, state) do
        :continue ->
          # Process the PDU normally
          {{:ok, process_snmp_pdu(pdu, state)}, :ok}

        {:error, error_type} ->
          # Handle error injection
          {{:error, error_type}, :error_injected}
      end

    SnmpKit.Telemetry.execute([:sim, :request], %{duration: System.monotonic_time() - started}, %{
      device_id: Map.get(state, :device_id),
      port: Map.get(state, :port),
      pdu_type: Map.get(pdu, :type),
      result: result
    })

    {:reply, reply, state}
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
    result = SnmpKit.SnmpSim.Device.OidHandler.get_oid_value(oid, state)

    formatted_result =
      case result do
        # Return 3-tuple format consistently
        {:ok, {oid_string, type, value}} -> {:ok, {oid_string, type, value}}
        # Return {oid, type, value} for other formats
        {:ok, {type, value}} -> {:ok, {oid, type, value}}
        error -> error
      end

    new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    {:reply, formatted_result, new_state}
  end

  @impl true
  def handle_call({:get_next_oid, oid}, _from, state) do
    result = SnmpKit.SnmpSim.Device.OidHandler.get_next_oid_value(state.device_type, oid, state)

    formatted_result =
      case result do
        {:ok, {oid, type, value}} -> {:ok, {OidHandler.oid_to_string(oid), type, value}}
        error -> error
      end

    {:reply, formatted_result, state}
  end

  @impl true
  def handle_call({:get_bulk_oid, oids, non_repeaters, max_repetitions}, _from, state) do
    # Convert OIDs to varbind format expected by process_get_bulk_varbinds
    varbinds =
      case oids do
        oid when is_binary(oid) ->
          [{oid, :null}]

        oid_list when is_list(oid_list) ->
          Enum.map(oid_list, fn oid -> {oid, :null} end)

        _ ->
          [{oids, :null}]
      end

    result = process_get_bulk_varbinds(varbinds, non_repeaters, max_repetitions, state)

    Logger.debug(fn -> "GETBULK result from process_get_bulk_varbinds: #{inspect(result)}" end)

    formatted_result =
      Enum.map(result, fn
        {oid, type, value} -> {OidHandler.oid_to_string(oid), type, value}
        {oid, value} -> {OidHandler.oid_to_string(oid), :octet_string, value}
      end)

    Logger.debug(fn -> "GETBULK formatted_result: #{inspect(formatted_result)}" end)
    {:reply, {:ok, formatted_result}, state}
  end

  @impl true
  def handle_call({:walk_oid, oid}, _from, state) do
    case OidHandler.walk_oid_values(oid, state) do
      {:ok, results} ->
        # Convert OIDs to strings and sort them properly using numerical comparison
        sorted_results =
          results
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
            "last_change" => SnmpKit.SnmpSim.Device.Metrics.calculate_uptime(state)
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

  # Modem upgrade messages
  @impl true
  def handle_info({:modem_upgrade, {:set, field, value}}, state) do
    new_upgrade = SnmpKit.SnmpSim.Device.ModemUpgrade.apply_set(field, value, state.upgrade)
    {:noreply, %{state | upgrade: new_upgrade}}
  end

  @impl true
  def handle_info({:modem_upgrade, :trigger}, state) do
    # Start the upgrade state machine if enabled and not already running
    {maybe_msgs, new_upgrade} =
      SnmpKit.SnmpSim.Device.ModemUpgrade.trigger(state.upgrade,
        invalid_server_regex: Map.get(state.upgrade, :invalid_server_regex)
      )

    # Schedule phase messages
    Enum.each(maybe_msgs, fn {delay_ms, msg} -> Process.send_after(self(), msg, delay_ms) end)

    {:noreply, %{state | upgrade: new_upgrade}}
  end

  @impl true
  def handle_info({:modem_upgrade, {:phase, phase}}, state) do
    {maybe_msgs, new_upgrade} =
      SnmpKit.SnmpSim.Device.ModemUpgrade.advance_phase(state.upgrade, phase)

    Enum.each(maybe_msgs, fn {delay_ms, msg} -> Process.send_after(self(), msg, delay_ms) end)
    {:noreply, %{state | upgrade: new_upgrade}}
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
    # Manual devices force no shared profile usage
    if Map.get(state, :manual_device, false) do
      Logger.info("Device #{state.device_id} initialized as manual device with basic profile")

      {counters, gauges} = seed_dynamic_values(state)

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
    else
      # Try to load actual profile data from SharedProfiles
      profiles = SnmpKit.SnmpSim.MIB.SharedProfiles.list_profiles()

      Logger.info(
        "Device #{state.device_id} checking profiles: #{inspect(profiles)} for device_type: #{inspect(state.device_type)}"
      )

      case Enum.member?(profiles, state.device_type) do
        true ->
          Logger.info(
            "Device #{state.device_id} initialized with profile for device type: #{state.device_type}"
          )

          # Profile exists in SharedProfiles, device will use it via OidHandler
          {:ok, %{state | has_walk_data: true}}

        false ->
          # Fallback to basic implementation for testing
          Logger.info("Device #{state.device_id} initialized with basic profile for testing")

          {counters, gauges} = seed_dynamic_values(state)

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
  end

  # Dynamic counters and gauges for interface 1. A device built from a
  # profile (walk file, recording, manual map) keeps the profile's values;
  # only a bare device gets the historical test defaults, so a recorded
  # 1 Gbps ifSpeed is not replaced by 100 Mbps.
  defp seed_dynamic_values(state) do
    oid_map = Map.get(state, :oid_map) || %{}

    if map_size(oid_map) > 0 do
      {%{}, %{}}
    else
      {%{"1.3.6.1.2.1.2.2.1.10.1" => 0, "1.3.6.1.2.1.2.2.1.16.1" => 0},
       %{"1.3.6.1.2.1.2.2.1.5.1" => 100_000_000, "1.3.6.1.2.1.2.2.1.4.1" => 1500}}
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

  defp count_device_oids(state) do
    cond do
      is_map(Map.get(state, :oid_map)) and map_size(state.oid_map) > 0 ->
        map_size(state.oid_map)

      Map.get(state, :has_walk_data, false) ->
        case SnmpKit.SnmpSim.MIB.SharedProfiles.get_all_oids(state.device_type) do
          {:ok, oids} -> length(oids)
          _ -> 0
        end

      true ->
        map_size(state.counters) + map_size(state.gauges) + map_size(state.status_vars)
    end
  end

  defp process_get_bulk_varbinds(varbinds, non_repeaters, max_repetitions, state) do
    device_type = state.device_type
    max_repetitions = max(0, max_repetitions)
    # The device state carries the real uptime; the old per-varbind
    # %{uptime: 0} froze every traffic counter served over GETBULK.
    device_state = state

    {non_repeater_vars, repeater_vars} = Enum.split(varbinds, non_repeaters)

    Logger.debug(fn ->
      "GETBULK split varbinds: #{inspect({non_repeater_vars, repeater_vars})}"
    end)

    # For GETBULK, we need to get the NEXT OIDs, not the exact OIDs
    non_repeater_results =
      non_repeater_vars
      |> Enum.map(fn {oid, _} ->
        case SnmpKit.SnmpSim.Device.OidHandler.get_next_oid_value(device_type, oid, device_state) do
          {:ok, {next_oid, type, value}} -> {next_oid, type, value}
          {:error, _} -> {oid, :no_such_name, :null}
        end
      end)

    Logger.debug(fn -> "GETBULK non_repeater_results: #{inspect(non_repeater_results)}" end)

    repeater_results =
      repeater_vars
      |> Enum.flat_map(fn {oid, _} ->
        Enum.reduce_while(Enum.to_list(1..max_repetitions//1), [], fn _i, acc ->
          current_oid = if acc == [], do: oid, else: elem(List.last(acc), 0)
          Logger.debug(fn -> "GETBULK current_oid for iteration: #{inspect(current_oid)}" end)

          case SnmpKit.SnmpSim.Device.OidHandler.get_next_oid_value(
                 device_type,
                 current_oid,
                 device_state
               ) do
            {:ok, {next_oid, type, value}} ->
              result = {next_oid, type, value}
              Logger.debug(fn -> "GETBULK got next_oid result: #{inspect(result)}" end)
              {:cont, acc ++ [result]}

            {:error, reason} ->
              Logger.debug(fn -> "GETBULK error, halting: #{inspect(reason)}" end)
              {:halt, acc}
          end
        end)
      end)

    Logger.debug(fn -> "GETBULK repeater_results: #{inspect(repeater_results)}" end)

    non_repeater_results ++ repeater_results
  end
end
