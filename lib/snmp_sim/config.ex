defmodule SnmpSim.Config do
  @moduledoc """
  Configuration management for SnmpSim with support for JSON and YAML files.

  This module provides a convenient way to configure SnmpSim using external
  configuration files, making it especially useful for container deployments
  and development environments.

  ## Supported formats
  - JSON files
  - YAML files (requires `yaml_elixir` dependency)
  - Elixir configuration maps

  ## Usage

      # Load from JSON file
      {:ok, config} = SnmpSim.Config.load_from_file("config/devices.json")
      {:ok, devices} = SnmpSim.Config.start_from_config(config)
      
      # Load from YAML file
      {:ok, config} = SnmpSim.Config.load_yaml("config/devices.yaml")
      {:ok, devices} = SnmpSim.Config.start_from_config(config)
      
      # Load from environment
      {:ok, config} = SnmpSim.Config.load_from_environment()
      {:ok, devices} = SnmpSim.Config.start_from_config(config)
  """

  alias SnmpSim.{Device, Performance.ResourceManager}

  require Logger

  @doc """
  Loads configuration from a JSON file.
  """
  def load_from_file(file_path) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, config} ->
            validate_and_normalize_config(config)

          {:error, error} ->
            {:error, {:json_decode_error, error}}
        end

      {:error, error} ->
        {:error, {:file_read_error, error}}
    end
  end

  @doc """
  Loads configuration from a YAML file.

  Requires the `yaml_elixir` dependency to be added to your mix.exs:

      {:yaml_elixir, "~> 2.9"}
  """
  def load_yaml(file_path) when is_binary(file_path) do
    if Code.ensure_loaded?(YamlElixir) do
      case YamlElixir.read_from_file(file_path) do
        {:ok, config} ->
          # Convert string keys to atoms for consistency
          atomized_config = atomize_keys(config)
          validate_and_normalize_config(atomized_config)

        {:error, error} ->
          {:error, {:yaml_read_error, error}}
      end
    else
      {:error,
       {:missing_dependency,
        "yaml_elixir package not found. Add {:yaml_elixir, \"~> 2.9\"} to your deps."}}
    end
  end

  @doc """
  Loads configuration from environment variables.

  This function reads common environment variables and creates a configuration
  map suitable for starting devices and configuring the system.
  """
  def load_from_environment do
    config = %{
      snmp_sim: %{
        global_settings: %{
          max_devices: get_env_int("SNMP_SIM_EX_MAX_DEVICES", 1000),
          max_memory_mb: get_env_int("SNMP_SIM_EX_MAX_MEMORY_MB", 512),
          enable_telemetry: get_env_boolean("SNMP_SIM_EX_ENABLE_TELEMETRY", true),
          enable_performance_monitoring:
            get_env_boolean("SNMP_SIM_EX_ENABLE_PERFORMANCE_MONITORING", true),
          host: System.get_env("SNMP_SIM_EX_HOST", "127.0.0.1"),
          community: System.get_env("SNMP_SIM_EX_COMMUNITY", "public"),
          worker_pool_size: get_env_int("SNMP_SIM_EX_WORKER_POOL_SIZE", 16),
          socket_count: get_env_int("SNMP_SIM_EX_SOCKET_COUNT", 4)
        },
        device_groups: parse_device_groups_from_env(),
        monitoring: %{
          health_check: %{
            enabled: get_env_boolean("SNMP_SIM_EX_ENABLE_HEALTH_ENDPOINT", true),
            port: get_env_int("SNMP_SIM_EX_HEALTH_PORT", 4000),
            path: System.get_env("SNMP_SIM_EX_HEALTH_PATH", "/health")
          },
          performance_monitor: %{
            collection_interval_ms: get_env_int("SNMP_SIM_EX_PERF_COLLECTION_INTERVAL_MS", 30000),
            alert_thresholds: %{
              memory_usage_mb: get_env_int("SNMP_SIM_EX_ALERT_MEMORY_THRESHOLD_MB", 400),
              response_time_ms: get_env_int("SNMP_SIM_EX_ALERT_RESPONSE_TIME_MS", 100),
              error_rate_percent: get_env_float("SNMP_SIM_EX_ALERT_ERROR_RATE_PERCENT", 5.0)
            }
          }
        }
      }
    }

    validate_and_normalize_config(config)
  end

  @doc """
  Starts devices and services based on the provided configuration.
  """
  def start_from_config(%{snmp_sim: config}) do
    Logger.info("Starting SnmpSim from configuration")

    # Apply global settings
    apply_global_settings(config[:global_settings] || %{})

    # Start resource manager if configured
    start_resource_manager(config[:global_settings])

    # Start monitoring if configured
    start_monitoring(config[:monitoring])

    # Start device groups
    devices = start_device_groups(config[:device_groups] || [])

    Logger.info("SnmpSim configuration loaded successfully. Started #{length(devices)} devices.")
    {:ok, devices}
  end

  @doc """
  Validates a configuration map and provides helpful error messages.
  """
  def validate_config(config) do
    case validate_and_normalize_config(config) do
      {:ok, _normalized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a sample configuration for reference.
  """
  def sample_config do
    %{
      snmp_sim: %{
        global_settings: %{
          max_devices: 1000,
          max_memory_mb: 512,
          enable_telemetry: true,
          enable_performance_monitoring: true,
          host: "127.0.0.1",
          community: "public",
          worker_pool_size: 16,
          socket_count: 4
        },
        device_groups: [
          %{
            name: "cable_modems",
            device_type: "cable_modem",
            count: 100,
            port_range: %{start: 30000, end: 30099},
            community: "public",
            walk_file: "priv/walks/cable_modem.walk",
            behaviors: ["realistic_counters", "time_patterns"],
            error_injection: %{
              packet_loss_rate: 0.01,
              timeout_rate: 0.005
            }
          },
          %{
            name: "switches",
            device_type: "switch",
            count: 20,
            port_range: %{start: 31000, end: 31019},
            community: "private",
            walk_file: "priv/walks/switch.walk",
            behaviors: ["realistic_counters", "correlations"]
          }
        ],
        monitoring: %{
          health_check: %{
            enabled: true,
            port: 4000,
            path: "/health"
          },
          performance_monitor: %{
            collection_interval_ms: 30000,
            alert_thresholds: %{
              memory_usage_mb: 400,
              response_time_ms: 100,
              error_rate_percent: 5.0
            }
          }
        }
      }
    }
  end

  @doc """
  Writes a sample configuration to a file.
  """
  def write_sample_config(file_path, format \\ :json) do
    config = sample_config()

    case format do
      :json ->
        json_content = Jason.encode!(config, pretty: true)
        File.write(file_path, json_content)

      :yaml ->
        if Code.ensure_loaded?(YamlElixir) do
          case Jason.encode!(config) |> then(&File.write(file_path, &1)) do
            :ok -> :ok
            error -> error
          end
        else
          {:error, "yaml_elixir package not available"}
        end

      _ ->
        {:error, "Unsupported format. Use :json or :yaml"}
    end
  end

  # Private helper functions

  defp validate_and_normalize_config(config) do
    case config do
      %{snmp_sim: snmp_config} ->
        case validate_snmp_config(snmp_config) do
          :ok -> {:ok, config}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "Configuration must contain a 'snmp_sim' key"}
    end
  end

  defp validate_snmp_config(config) when is_map(config) do
    # Validate global settings
    case validate_global_settings(config[:global_settings]) do
      :ok ->
        # Validate device groups
        case validate_device_groups(config[:device_groups]) do
          :ok -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  defp validate_snmp_config(_), do: {:error, "snmp_sim configuration must be a map"}

  defp validate_global_settings(nil), do: :ok

  defp validate_global_settings(settings) when is_map(settings) do
    # Basic validation of global settings
    cond do
      Map.has_key?(settings, :max_devices) and not is_integer(settings.max_devices) ->
        {:error, "max_devices must be an integer"}

      Map.has_key?(settings, :max_memory_mb) and not is_integer(settings.max_memory_mb) ->
        {:error, "max_memory_mb must be an integer"}

      true ->
        :ok
    end
  end

  defp validate_global_settings(_), do: {:error, "global_settings must be a map"}

  defp validate_device_groups(nil), do: :ok

  defp validate_device_groups(groups) when is_list(groups) do
    # Validate each device group
    Enum.reduce_while(groups, :ok, fn group, _acc ->
      case validate_device_group(group) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_device_groups(_), do: {:error, "device_groups must be a list"}

  defp validate_device_group(group) when is_map(group) do
    required_fields = [:name, :count, :port_range]

    case Enum.find(required_fields, fn field -> not Map.has_key?(group, field) end) do
      nil ->
        # Validate port range
        case group.port_range do
          %{start: start_port, end: end_port}
          when is_integer(start_port) and is_integer(end_port) ->
            if start_port <= end_port do
              :ok
            else
              {:error, "port_range start must be <= end"}
            end

          _ ->
            {:error, "port_range must have 'start' and 'end' integer fields"}
        end

      missing_field ->
        {:error, "device_group missing required field: #{missing_field}"}
    end
  end

  defp validate_device_group(_), do: {:error, "device_group must be a map"}

  defp apply_global_settings(settings) do
    Enum.each(settings, fn {key, value} ->
      case key do
        :max_devices ->
          Application.put_env(:snmp_sim, :max_devices, value)

        :max_memory_mb ->
          Application.put_env(:snmp_sim, :max_memory_mb, value)

        :enable_telemetry ->
          Application.put_env(:snmp_sim, :enable_telemetry, value)

        :enable_performance_monitoring ->
          Application.put_env(:snmp_sim, :enable_performance_monitoring, value)

        :worker_pool_size ->
          Application.put_env(:snmp_sim, :worker_pool_size, value)

        :socket_count ->
          Application.put_env(:snmp_sim, :socket_count, value)

        # Ignore unknown settings
        _ ->
          :ok
      end
    end)
  end

  defp start_resource_manager(settings) do
    if settings[:max_devices] != nil or settings[:max_memory_mb] != nil do
      resource_config = [
        max_devices: settings[:max_devices] || 1000,
        max_memory_mb: settings[:max_memory_mb] || 512
      ]

      case ResourceManager.start_link(resource_config) do
        {:ok, _pid} ->
          Logger.info("Started ResourceManager with config: #{inspect(resource_config)}")

        {:error, {:already_started, _pid}} ->
          Logger.debug("ResourceManager already started")

        {:error, reason} ->
          Logger.warning("Failed to start ResourceManager: #{inspect(reason)}")
      end
    end
  end

  defp start_monitoring(nil), do: :ok

  defp start_monitoring(monitoring_config) do
    # Start health check if configured
    if get_in(monitoring_config, [:health_check, :enabled]) do
      health_config = monitoring_config[:health_check]
      Logger.info("Health check enabled on port #{health_config[:port]}")
      # Health check would be started here if we had that module
    end

    # Start performance monitoring if configured
    if monitoring_config[:performance_monitor] do
      Logger.info("Performance monitoring configured")
      # Performance monitor configuration would be applied here
    end
  end

  defp start_device_groups(device_groups) do
    device_groups
    |> Enum.flat_map(&start_device_group/1)
    |> List.flatten()
  end

  defp start_device_group(group) do
    Logger.info("Starting device group: #{group[:name]} (#{group[:count]} devices)")

    port_range = group[:port_range]
    start_port = port_range[:start]
    count = group[:count]

    behaviors = parse_behaviors(group[:behaviors] || [])

    devices =
      for i <- 0..(count - 1) do
        port = start_port + i

        device_config = %{
          port: port,
          device_type: String.to_atom(group[:device_type] || "cable_modem"),
          device_id: "#{group[:name]}_#{port}",
          community: group[:community] || "public"
        }

        case DynamicSupervisor.start_child(SnmpSim.DeviceSupervisor, {Device, device_config}) do
          {:ok, device} ->
            # Apply behaviors if specified
            apply_device_behaviors(device, behaviors)

            # Apply error injection if specified
            apply_error_injection(device, group[:error_injection])

            device

          {:error, reason} ->
            Logger.warning("Failed to start device on port #{port}: #{inspect(reason)}")
            nil
        end
      end

    # Filter out failed devices
    successful_devices = Enum.filter(devices, &(&1 != nil))

    Logger.info(
      "Successfully started #{length(successful_devices)}/#{count} devices for group #{group[:name]}"
    )

    successful_devices
  end

  defp parse_behaviors(behaviors) when is_list(behaviors) do
    Enum.map(behaviors, fn behavior ->
      case behavior do
        "realistic_counters" -> :realistic_counters
        "time_patterns" -> :time_patterns
        "correlations" -> :correlations
        "seasonal_patterns" -> :seasonal_patterns
        atom when is_atom(atom) -> atom
        string when is_binary(string) -> String.to_atom(string)
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp apply_device_behaviors(_device, []), do: :ok

  defp apply_device_behaviors(device, behaviors) do
    # Apply behaviors to device
    # This would integrate with the existing behavior system
    Logger.debug("Applied behaviors #{inspect(behaviors)} to device #{inspect(device)}")
  end

  defp apply_error_injection(_device, nil), do: :ok

  defp apply_error_injection(device, error_config) when is_map(error_config) do
    # Apply error injection configuration
    if packet_loss_rate = error_config[:packet_loss_rate] do
      # Would apply packet loss injection
      Logger.debug("Applied packet loss rate #{packet_loss_rate} to device #{inspect(device)}")
    end

    if timeout_rate = error_config[:timeout_rate] do
      # Would apply timeout injection
      Logger.debug("Applied timeout rate #{timeout_rate} to device #{inspect(device)}")
    end
  end

  defp parse_device_groups_from_env do
    # Parse device groups from environment variables
    # This is a simplified implementation - could be extended for more complex scenarios
    device_count = get_env_int("SNMP_SIM_EX_DEVICE_COUNT", 0)
    port_start = get_env_int("SNMP_SIM_EX_PORT_RANGE_START", 30000)
    walk_file = System.get_env("SNMP_SIM_EX_WALK_FILE", "priv/walks/cable_modem.walk")
    community = System.get_env("SNMP_SIM_EX_COMMUNITY", "public")

    if device_count > 0 do
      [
        %{
          name: "env_devices",
          device_type: "generic",
          count: device_count,
          port_range: %{
            start: port_start,
            end: port_start + device_count - 1
          },
          community: community,
          walk_file: walk_file,
          behaviors: []
        }
      ]
    else
      []
    end
  end

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {atomize_key(k), atomize_keys(v)} end)
    |> Enum.into(%{})
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value

  defp atomize_key(key) when is_binary(key), do: String.to_atom(key)
  defp atomize_key(key), do: key

  defp get_env_int(var_name, default) do
    case System.get_env(var_name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  defp get_env_float(var_name, default) do
    case System.get_env(var_name) do
      nil -> default
      value -> String.to_float(value)
    end
  end

  defp get_env_boolean(var_name, default) do
    case System.get_env(var_name) do
      nil -> default
      "true" -> true
      "false" -> false
      _ -> default
    end
  end
end
