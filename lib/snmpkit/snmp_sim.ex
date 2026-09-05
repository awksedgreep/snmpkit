defmodule SnmpKit.SnmpSim do
  @moduledoc """
  Top-level API for the SNMP device simulator.

  The simulator can be driven two ways:

  * **Programmatically**, one device at a time, with `start_device/2` (or the
    `SnmpKit.Sim` facade) and a profile from `SnmpKit.SnmpSim.ProfileLoader`.
  * **From a configuration**, describing whole device groups, with `start/1`
    or `start_link/1`. The configuration is a map (see `sample_config/0`) or
    the path of a JSON / YAML file (see `load_config/1`).

  Devices started from a configuration run under the application's device
  supervisor (`SnmpSim.DeviceSupervisor`), so they survive the caller and can
  be inspected with `list_devices/0` and torn down with `stop/0`.

  ## Example

      config = %{
        snmp_sim: %{
          device_groups: [
            %{
              name: "cable_modems",
              device_type: "cable_modem",
              count: 10,
              port_range: %{start: 30_000, end: 30_009},
              community: "public",
              walk_file: "priv/walks/cable_modem.walk"
            }
          ]
        }
      }

      {:ok, _supervisor} = SnmpKit.SnmpSim.start(config)
      10 = SnmpKit.SnmpSim.device_count()
      {:ok, %{value: descr}} = SnmpKit.SNMP.get("127.0.0.1", "sysDescr.0", port: 30_000)
      :ok = SnmpKit.SnmpSim.stop()
  """

  alias SnmpKit.SnmpSim.{Config, Device, LazyDevicePool, ProfileLoader}

  @supervisor SnmpSim.DeviceSupervisor

  @type config :: map() | Path.t()
  @type device_info :: %{
          pid: pid(),
          device_id: binary() | nil,
          device_type: atom() | binary() | nil,
          port: non_neg_integer() | nil
        }

  ## Configuration-driven start-up

  @doc """
  Starts every device group in `config` under the device supervisor.

  `config` is a configuration map (with or without the top-level `:snmp_sim`
  key) or the path of a JSON / YAML file. Returns `{:ok, supervisor_pid}`; the
  started devices are available through `list_devices/0`.
  """
  @spec start(config()) :: {:ok, pid()} | {:error, term()}
  def start(config) do
    with {:ok, config_map} <- resolve_config(config),
         :ok <- Config.validate_config(config_map),
         {:ok, _devices} <- Config.start_from_config(config_map),
         {:ok, sup} <- supervisor() do
      {:ok, sup}
    end
  end

  @doc """
  Same as `start/1`.

  The name is kept for compatibility with the original draft of this module.
  Note that the devices are supervised by the application, not linked to the
  caller, so this is safe to call from any process.
  """
  @spec start_link(config()) :: {:ok, pid()} | {:error, term()}
  def start_link(config), do: start(config)

  @doc """
  Loads a configuration file. `.json` files are decoded with Jason; `.yaml` /
  `.yml` files require the optional `yaml_elixir` dependency.
  """
  @spec load_config(Path.t()) :: {:ok, map()} | {:error, term()}
  def load_config(path) when is_binary(path) do
    case Path.extname(path) |> String.downcase() do
      ".json" -> Config.load_from_file(path)
      ext when ext in [".yaml", ".yml"] -> Config.load_yaml(path)
      ext -> {:error, {:unsupported_config_format, ext}}
    end
  end

  @doc "Validates a configuration map without starting anything."
  @spec validate_config(map()) :: :ok | {:error, term()}
  def validate_config(config) when is_map(config) do
    with {:ok, config_map} <- resolve_config(config), do: Config.validate_config(config_map)
  end

  @doc "A complete example configuration, useful as a starting point."
  defdelegate sample_config(), to: Config

  @doc "Writes `sample_config/0` to `path` as `:json` or `:yaml`."
  defdelegate write_sample_config(path, format \\ :json), to: Config

  ## Single devices

  @doc """
  Starts one device from a `SnmpKit.SnmpSim.ProfileLoader` profile.

  Options: `:port` (required), `:device_id` (default `"<type>_<port>"`),
  `:community` (default `"public"`). The device is linked to the caller.

      profile = SnmpKit.SnmpSim.ProfileLoader.load_profile(:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"})
      {:ok, device} = SnmpKit.SnmpSim.start_device(profile, port: 9001)
  """
  @spec start_device(map(), keyword()) :: GenServer.on_start()
  def start_device(profile, opts \\ [])

  # A plain `%{objects: %{oid => value}}` map (as in the README quick start)
  # is turned into a manual profile first.
  def start_device(%{objects: objects} = profile, opts)
      when not is_map_key(profile, :device_type) do
    oid_map = Map.new(objects, fn {oid, value} -> {oid_key(oid), value} end)

    case ProfileLoader.load_profile(:custom, {:manual, oid_map}) do
      {:ok, loaded} -> start_device(loaded, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  def start_device(profile, opts) do
    port = Keyword.fetch!(opts, :port)
    device_type = profile.device_type

    device_config = %{
      port: port,
      device_type: device_type,
      device_id: Keyword.get(opts, :device_id, "#{device_type}_#{port}"),
      profile: profile,
      community: Keyword.get(opts, :community, "public")
    }

    # Linked to the caller: the device stops when the test or script that
    # started it exits. Devices started from a config (`start/1`) or by
    # `start_device_population/2` run under the device supervisor instead.
    Device.start_link(device_config)
  end

  @doc """
  Starts a population of devices with mixed types through `SnmpKit.SnmpSim.LazyDevicePool`.

      {:ok, devices} = SnmpKit.SnmpSim.start_device_population(
        [
          {:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"}, count: 1000},
          {:switch, {:walk_file, "priv/walks/switch.walk"}, count: 50}
        ],
        port_range: 30_000..39_999
      )
  """
  def start_device_population(device_configs, opts \\ [])

  def start_device_population([%{} | _] = device_configs, _opts) do
    # Explicit per-device maps: %{type: :router, port: 30001, community: "public"}
    results =
      Enum.map(device_configs, fn config ->
        type = Map.fetch!(config, :type)
        port = Map.fetch!(config, :port)

        with {:ok, profile} <- population_profile(config),
             {:ok, pid} <-
               start_device(profile, port: port, community: Map.get(config, :community, "public")) do
          {:ok, %{type: type, port: port, pid: pid, target: "127.0.0.1:#{port}"}}
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, device} -> device end)}
      error -> error
    end
  end

  def start_device_population(device_configs, opts) do
    # `{type, source, count: n}` tuples go through the lazy pool; devices are
    # pre-warmed unless `pre_warm: false` is given.
    opts = Keyword.put_new(opts, :pre_warm, true)

    with :ok <- ensure_pool_started(),
         {:ok, started} <- LazyDevicePool.start_device_population(device_configs, opts) do
      {:ok, describe_started(started, device_configs)}
    end
  end

  defp population_profile(%{profile: %ProfileLoader{} = profile}), do: {:ok, profile}

  defp population_profile(%{objects: objects}) do
    ProfileLoader.load_profile(
      :custom,
      {:manual, Map.new(objects, fn {k, v} -> {oid_key(k), v} end)}
    )
  end

  defp population_profile(%{type: type}), do: ProfileLoader.load_profile(type)

  defp ensure_pool_started do
    case Process.whereis(LazyDevicePool) do
      nil ->
        result =
          case supervisor() do
            {:ok, sup} -> DynamicSupervisor.start_child(sup, {LazyDevicePool, []})
            {:error, :not_started} -> LazyDevicePool.start_link()
          end

        case result do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> {:error, {:device_pool, reason}}
        end

      _pid ->
        :ok
    end
  end

  # pre_warm returns [{port, pid}] in config order; pair each with its type
  defp describe_started(:lazy_pool_configured, _configs), do: []

  defp describe_started(started, configs) when is_list(started) do
    types =
      Enum.flat_map(configs, fn {type, _source, config_opts} ->
        List.duplicate(type, Keyword.get(config_opts, :count, 1))
      end)

    started
    |> Enum.zip(types ++ List.duplicate(nil, max(length(started) - length(types), 0)))
    |> Enum.map(fn {{port, pid}, type} ->
      %{type: type, port: port, pid: pid, target: "127.0.0.1:#{port}"}
    end)
  end

  defp oid_key(oid) when is_list(oid), do: Enum.join(oid, ".")
  defp oid_key(oid) when is_binary(oid), do: oid

  ## Inspection and shutdown

  @doc "The device supervisor pid, or `{:error, :not_started}` if the application is not running."
  @spec supervisor() :: {:ok, pid()} | {:error, :not_started}
  def supervisor do
    case Process.whereis(@supervisor) do
      nil -> {:error, :not_started}
      pid -> {:ok, pid}
    end
  end

  @doc """
  Lists the devices running under the device supervisor.

  Each entry has `:pid`, `:device_id`, `:device_type` and `:port`; the last
  three are `nil` if a device did not answer its info call in time.
  """
  @spec list_devices() :: [device_info()]
  def list_devices do
    case supervisor() do
      {:error, :not_started} ->
        []

      {:ok, sup} ->
        sup
        |> DynamicSupervisor.which_children()
        |> Enum.flat_map(fn
          {_, pid, :worker, _} when is_pid(pid) -> [describe(pid)]
          _ -> []
        end)
        |> Enum.sort_by(& &1.port)
    end
  end

  @doc "Number of devices running under the device supervisor."
  @spec device_count() :: non_neg_integer()
  def device_count do
    case supervisor() do
      {:ok, sup} -> DynamicSupervisor.count_children(sup).active
      {:error, :not_started} -> 0
    end
  end

  @doc """
  Stops one device, given its pid or its UDP port.
  """
  @spec stop_device(pid() | non_neg_integer()) :: :ok | {:error, :not_found}
  def stop_device(pid) when is_pid(pid) do
    case supervisor() do
      {:ok, sup} ->
        case DynamicSupervisor.terminate_child(sup, pid) do
          :ok -> :ok
          # Not one of ours (started with start_device/2): stop it directly
          {:error, :not_found} -> Device.stop(pid)
        end

      {:error, :not_started} ->
        Device.stop(pid)
    end
  end

  def stop_device(port) when is_integer(port) do
    case Enum.find(list_devices(), &(&1.port == port)) do
      nil -> {:error, :not_found}
      %{pid: pid} -> stop_device(pid)
    end
  end

  @doc "Stops every device running under the device supervisor."
  @spec stop() :: :ok
  def stop do
    case supervisor() do
      {:ok, sup} ->
        for {_, pid, _, _} <- DynamicSupervisor.which_children(sup), is_pid(pid) do
          DynamicSupervisor.terminate_child(sup, pid)
        end

        :ok

      {:error, :not_started} ->
        :ok
    end
  end

  ## Private

  defp resolve_config(path) when is_binary(path), do: load_config(path)
  defp resolve_config(%{snmp_sim: _} = config), do: {:ok, config}
  defp resolve_config(config) when is_map(config), do: {:ok, %{snmp_sim: config}}
  defp resolve_config(other), do: {:error, {:invalid_config, other}}

  defp describe(pid) do
    info =
      try do
        Device.get_info(pid)
      catch
        :exit, _ -> %{}
      end

    %{
      pid: pid,
      device_id: Map.get(info, :device_id),
      device_type: Map.get(info, :device_type),
      port: Map.get(info, :port)
    }
  end
end
