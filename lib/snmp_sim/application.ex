defmodule SnmpSim.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias SnmpSim.Config

  require Logger

  @impl true
  def start(_type, _args) do
    # Start the supervisor first
    children = [
      # Shared profiles manager for memory-efficient device data
      SnmpSim.MIB.SharedProfiles,
      # Core supervisor for managing device processes
      {DynamicSupervisor, name: SnmpSim.DeviceSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: SnmpSim.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Load and start devices from configuration after supervisor is running
        load_and_start_devices()
        {:ok, pid}

      error ->
        error
    end
  end

  defp load_and_start_devices do
    # Try to load configuration from various sources
    config_result = try_load_configuration()

    case config_result do
      {:ok, config} ->
        Logger.info("Loading SnmpSim configuration...")

        case Config.start_from_config(config) do
          {:ok, devices} ->
            Logger.info("Successfully started #{length(devices)} SNMP devices")
        end

      {:error, reason} ->
        Logger.warning("No configuration found or failed to load: #{inspect(reason)}")
        Logger.info("Starting SnmpSim with default settings...")
        start_default_devices()
    end
  end

  defp try_load_configuration do
    # Try loading from different sources in order of priority
    config_sources = [
      # 1. Environment variable pointing to config file
      fn ->
        case System.get_env("SNMP_SIM_EX_CONFIG_FILE") do
          nil -> {:error, :no_env_config}
          path -> Config.load_from_file(path)
        end
      end,
      # 2. Standard JSON config files
      fn -> Config.load_from_file("/app/test_config/hundred_devices.json") end,
      fn -> Config.load_from_file("/app/test_config/test_devices.json") end,
      fn -> Config.load_from_file("test_config/hundred_devices.json") end,
      fn -> Config.load_from_file("test_config/test_devices.json") end,
      fn -> Config.load_from_file("config/devices.json") end,
      # 3. Environment variables
      fn -> Config.load_from_environment() end
    ]

    Enum.reduce_while(config_sources, {:error, :no_config}, fn source_fn, _acc ->
      case source_fn.() do
        {:ok, config} -> {:halt, {:ok, config}}
        {:error, _reason} -> {:cont, {:error, :no_config}}
      end
    end)
  end

  defp start_default_devices do
    # Create minimal default configuration for testing
    device_count = get_env_int("SNMP_SIM_EX_DEVICE_COUNT", 10)
    port_start = get_env_int("SNMP_SIM_EX_PORT_RANGE_START", 30000)

    if device_count > 0 do
      config = %{
        snmp_sim: %{
          global_settings: %{
            max_devices: device_count,
            host: "0.0.0.0",
            community: "public"
          },
          device_groups: [
            %{
              name: "default_devices",
              device_type: "cable_modem",
              count: device_count,
              port_range: %{
                start: port_start,
                end: port_start + device_count - 1
              },
              community: "public",
              walk_file: "priv/walks/cable_modem.walk",
              behaviors: ["realistic_counters"]
            }
          ]
        }
      }

      case Config.start_from_config(config) do
        {:ok, devices} ->
          Logger.info(
            "Started #{length(devices)} default SNMP devices on ports #{port_start}-#{port_start + device_count - 1}"
          )
      end
    else
      Logger.info("No devices configured to start")
    end
  end

  defp get_env_int(var_name, default) do
    case System.get_env(var_name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {int_val, _} -> int_val
          :error -> default
        end
    end
  end
end
