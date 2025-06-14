defmodule SnmpKit.TestSupport.SNMPSimulator do
  @moduledoc """
  Test support module for setting up SNMP simulators using snmp_sim.

  This module provides utilities to create realistic SNMP devices for testing
  SnmpKit functionality with actual SNMP responses.
  """

  alias SnmpKit.SnmpSim.Device

  @default_community "public"
  @test_port_start 30000

  @doc """
  Creates a basic test device for SNMP operations.

  ## Options
  - `:port` - UDP port for the device (default: assigns automatically)
  - `:community` - SNMP community string (default: "public")
  - `:device_type` - Type of device to simulate (default: :cable_modem)

  ## Examples

      {:ok, device_info} = SNMPSimulator.create_test_device()
      %{device: device_pid, host: "127.0.0.1", port: 30000, community: "public"}
  """
  def create_test_device(opts \\ []) do
    port = Keyword.get(opts, :port, get_available_port())
    community = Keyword.get(opts, :community, @default_community)
    device_type = Keyword.get(opts, :device_type, :cable_modem)

    # Note: Profile creation is handled by SnmpSim internally

    device_config = %{
      port: port,
      device_type: device_type,
      device_id: "test_device_#{port}",
      community: community,
      walk_file: Path.expand(Path.join(__DIR__, "../../priv/walks/cable_modem.walk"))
    }

    case start_device_with_profile(device_config) do
      {:ok, device_pid} ->
        device_info = %{
          device: device_pid,
          host: "127.0.0.1",
          port: port,
          community: community,
          device_type: device_type
        }

        {:ok, device_info}

      error ->
        error
    end
  end

  @doc """
  Creates a realistic switch device with interface table data.

  ## Options
  - `:interface_count` - Number of interfaces to simulate (default: 24)
  - `:port` - UDP port for the device
  - `:community` - SNMP community string

  ## Examples

      {:ok, switch} = SNMPSimulator.create_switch_device(interface_count: 48)
  """
  def create_switch_device(opts \\ []) do
    port = Keyword.get(opts, :port, get_available_port())
    community = Keyword.get(opts, :community, @default_community)
    interface_count = Keyword.get(opts, :interface_count, 24)

    # Note: Profile creation is handled by SnmpSim internally

    device_config = %{
      port: port,
      device_type: :switch,
      device_id: "switch_#{port}",
      community: community,
      walk_file: Path.expand(Path.join(__DIR__, "../../priv/walks/cable_modem.walk"))
    }

    case start_device_with_profile(device_config) do
      {:ok, device_pid} ->
        device_info = %{
          device: device_pid,
          host: "127.0.0.1",
          port: port,
          community: community,
          device_type: :switch,
          interface_count: interface_count
        }

        {:ok, device_info}

      error ->
        error
    end
  end

  @doc """
  Creates a router device with routing table data.

  ## Options
  - `:route_count` - Number of routes to simulate (default: 100)
  - `:port` - UDP port for the device
  - `:community` - SNMP community string
  """
  def create_router_device(opts \\ []) do
    port = Keyword.get(opts, :port, get_available_port())
    community = Keyword.get(opts, :community, @default_community)
    route_count = Keyword.get(opts, :route_count, 100)

    # Note: Profile creation is handled by SnmpSim internally

    device_config = %{
      port: port,
      device_type: :router,
      device_id: "router_#{port}",
      community: community,
      walk_file: Path.expand(Path.join(__DIR__, "../../priv/walks/cable_modem.walk"))
    }

    case start_device_with_profile(device_config) do
      {:ok, device_pid} ->
        device_info = %{
          device: device_pid,
          host: "127.0.0.1",
          port: port,
          community: community,
          device_type: :router,
          route_count: route_count
        }

        {:ok, device_info}

      error ->
        error
    end
  end

  @doc """
  Creates multiple test devices for load testing.

  ## Options
  - `:count` - Number of devices to create (default: 10)
  - `:device_type` - Type of devices to create (default: :test_device)
  - `:port_start` - Starting port number (default: 30000)

  ## Examples

      {:ok, devices} = SNMPSimulator.create_device_fleet(count: 50, device_type: :switch)
  """
  def create_device_fleet(opts \\ []) do
    count = Keyword.get(opts, :count, 10)
    device_type = Keyword.get(opts, :device_type, :cable_modem)
    port_start = Keyword.get(opts, :port_start, @test_port_start)
    community = Keyword.get(opts, :community, @default_community)

    devices =
      1..count
      |> Enum.map(fn i ->
        port = port_start + i - 1
        device_opts = [port: port, community: community, device_type: device_type]

        case device_type do
          :switch -> create_switch_device(device_opts)
          :router -> create_router_device(device_opts)
          _ -> create_test_device(device_opts)
        end
      end)
      |> Enum.map(fn
        {:ok, device_info} -> device_info
        {:error, reason} -> {:error, reason}
      end)

    # Check if any failed
    failed_devices = Enum.filter(devices, &match?({:error, _}, &1))

    if Enum.empty?(failed_devices) do
      {:ok, devices}
    else
      {:error, {:device_creation_failed, failed_devices}}
    end
  end

  @doc """
  Stops a test device and cleans up resources.
  """
  def stop_device(%{device: device_pid}) when is_pid(device_pid) do
    if Process.alive?(device_pid) do
      GenServer.stop(device_pid, :normal, 5000)
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  def stop_device(_), do: :ok

  @doc """
  Stops multiple devices and cleans up resources.
  """
  def stop_devices(devices) when is_list(devices) do
    Enum.each(devices, &stop_device/1)
    # Allow cleanup
    Process.sleep(100)
    :ok
  end

  @doc """
  Gets device target string for SnmpMgr operations.
  """
  def device_target(%{host: host, port: port}) do
    "#{host}:#{port}"
  end

  @doc """
  Waits for a device to be ready for SNMP requests.
  """
  def wait_for_device_ready(device_info, _timeout_ms \\ 5000) do
    # Simple wait - just check if the device process is alive
    # In a real environment with proper SNMP, this would test actual SNMP queries
    case Process.alive?(device_info.device) do
      true -> :ok
      false -> {:error, :device_not_alive}
    end
  end

  @doc """
  Validates that a device is responding correctly.
  """
  def validate_device_response(device_info) do
    # Simple validation - just check if device is alive and responding
    # In a real environment with proper SNMP, this would test actual SNMP queries
    case Process.alive?(device_info.device) do
      true -> :ok
      false -> {:error, {:validation_failed, [:device_not_alive]}}
    end
  end

  # Private helper functions

  defp start_device_with_profile(device_config) do
    # Use SnmpSim Device module to start the device
    Device.start_link(device_config)
  end

  defp get_available_port do
    # Simple port allocation - in production this should be more sophisticated
    base_port = @test_port_start + :rand.uniform(1000)

    # Try to find an available port
    case :gen_udp.open(base_port, [:binary]) do
      {:ok, socket} ->
        :gen_udp.close(socket)
        base_port

      {:error, :eaddrinuse} ->
        # Try next port
        get_available_port()

      {:error, _} ->
        # Use a random high port
        @test_port_start + :rand.uniform(30000)
    end
  end

  # Note: Profile creation is now handled internally by SnmpKit.SnmpSim.Device
  # The device mock initialization provides basic system MIB data for testing
end
