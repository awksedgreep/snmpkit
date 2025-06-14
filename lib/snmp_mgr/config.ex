defmodule SnmpMgr.Config do
  @moduledoc """
  Configuration management for SnmpMgr.
  
  Provides global defaults and configuration options that can be set
  application-wide and used by all SNMP operations.
  """

  use GenServer

  @default_config %{
    community: "public",
    timeout: 5000,
    retries: 1,
    port: 161,
    version: :v1,
    mib_paths: []
  }

  ## Public API

  @doc """
  Starts the configuration GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sets the default community string for SNMP requests.

  ## Examples

      iex> SnmpMgr.Config.set_default_community("private")
      :ok
  """
  def set_default_community(community) when is_binary(community) do
    GenServer.call(__MODULE__, {:set, :community, community})
  end

  @doc """
  Gets the default community string.

  ## Examples

      iex> SnmpMgr.Config.get_default_community()
      "public"
  """
  def get_default_community do
    GenServer.call(__MODULE__, {:get, :community})
  end

  @doc """
  Sets the default timeout for SNMP requests in milliseconds.

  ## Examples

      iex> SnmpMgr.Config.set_default_timeout(10000)
      :ok
  """
  def set_default_timeout(timeout) when is_integer(timeout) and timeout > 0 do
    GenServer.call(__MODULE__, {:set, :timeout, timeout})
  end

  @doc """
  Gets the default timeout.
  """
  def get_default_timeout do
    GenServer.call(__MODULE__, {:get, :timeout})
  end

  @doc """
  Sets the default number of retries for SNMP requests.

  ## Examples

      iex> SnmpMgr.Config.set_default_retries(3)
      :ok
  """
  def set_default_retries(retries) when is_integer(retries) and retries >= 0 do
    GenServer.call(__MODULE__, {:set, :retries, retries})
  end

  @doc """
  Gets the default number of retries.
  """
  def get_default_retries do
    GenServer.call(__MODULE__, {:get, :retries})
  end

  @doc """
  Sets the default port for SNMP requests.

  ## Examples

      iex> SnmpMgr.Config.set_default_port(1161)
      :ok
  """
  def set_default_port(port) when is_integer(port) and port > 0 and port <= 65535 do
    GenServer.call(__MODULE__, {:set, :port, port})
  end

  @doc """
  Gets the default port.
  """
  def get_default_port do
    GenServer.call(__MODULE__, {:get, :port})
  end

  @doc """
  Sets the default SNMP version.

  ## Examples

      iex> SnmpMgr.Config.set_default_version(:v2c)
      :ok
  """
  def set_default_version(version) when version in [:v1, :v2c] do
    GenServer.call(__MODULE__, {:set, :version, version})
  end

  @doc """
  Gets the default SNMP version.
  """
  def get_default_version do
    GenServer.call(__MODULE__, {:get, :version})
  end

  @doc """
  Adds a directory to the MIB search paths.

  ## Examples

      iex> SnmpMgr.Config.add_mib_path("/usr/share/snmp/mibs")
      :ok
  """
  def add_mib_path(path) when is_binary(path) do
    GenServer.call(__MODULE__, {:add_mib_path, path})
  end

  @doc """
  Sets the MIB search paths (replaces existing paths).

  ## Examples

      iex> SnmpMgr.Config.set_mib_paths(["/usr/share/snmp/mibs", "./mibs"])
      :ok
  """
  def set_mib_paths(paths) when is_list(paths) do
    GenServer.call(__MODULE__, {:set, :mib_paths, paths})
  end

  @doc """
  Gets the current MIB search paths.
  """
  def get_mib_paths do
    GenServer.call(__MODULE__, {:get, :mib_paths})
  end

  @doc """
  Gets all current configuration as a map.

  ## Examples

      iex> SnmpMgr.Config.get_all()
      %{
        community: "public",
        timeout: 5000,
        retries: 1,
        port: 161,
        version: :v1,
        mib_paths: []
      }
  """
  def get_all do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc """
  Resets configuration to defaults.

  ## Examples

      iex> SnmpMgr.Config.reset()
      :ok
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Gets configuration value with fallback to application config.

  This is the main function used by other modules to get configuration values.
  It first checks the GenServer state, then falls back to application config,
  then to module defaults.

  ## Examples

      iex> SnmpMgr.Config.get(:community)
      "public"

      iex> SnmpMgr.Config.get(:timeout)
      5000
  """
  def get(key) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        # GenServer not started, use application config or defaults
        get_from_app_config(key)
      _pid ->
        GenServer.call(__MODULE__, {:get, key})
    end
  end

  @doc """
  Merges the current configuration with provided opts, giving priority to opts.

  This is useful for functions that want to use global defaults but allow
  per-request overrides.

  ## Examples

      iex> SnmpMgr.Config.merge_opts(community: "private", timeout: 10000)
      [community: "private", timeout: 10000, retries: 1, port: 161]
  """
  def merge_opts(opts) do
    config = case GenServer.whereis(__MODULE__) do
      nil -> 
        # Config server not running, use defaults
        @default_config
      pid when is_pid(pid) -> 
        # Config server running, get current config with timeout
        case GenServer.call(pid, :get_all, 1000) do
          config when is_map(config) -> config
          _ -> @default_config
        end
    end
    
    merged = 
      config
      |> Map.to_list()
      |> Keyword.merge(opts)
    
    merged
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    # Start with defaults, then merge application environment, then passed options
    app_env_config = %{
      community: Application.get_env(:snmp_mgr, :community, @default_config.community),
      timeout: Application.get_env(:snmp_mgr, :timeout, @default_config.timeout),
      retries: Application.get_env(:snmp_mgr, :retries, @default_config.retries),
      port: Application.get_env(:snmp_mgr, :port, @default_config.port),
      version: Application.get_env(:snmp_mgr, :version, @default_config.version),
      mib_paths: Application.get_env(:snmp_mgr, :mib_paths, @default_config.mib_paths)
    }
    
    config = 
      @default_config
      |> Map.merge(app_env_config)
      |> Map.merge(Enum.into(opts, %{}))
    
    {:ok, config}
  end

  @impl true
  def handle_call({:set, key, value}, _from, config) do
    new_config = Map.put(config, key, value)
    {:reply, :ok, new_config}
  end

  @impl true
  def handle_call({:get, key}, _from, config) do
    value = Map.get(config, key, get_from_app_config(key))
    {:reply, value, config}
  end

  @impl true
  def handle_call({:add_mib_path, path}, _from, config) do
    current_paths = Map.get(config, :mib_paths, [])
    new_paths = if path in current_paths do
      current_paths
    else
      current_paths ++ [path]
    end
    new_config = Map.put(config, :mib_paths, new_paths)
    {:reply, :ok, new_config}
  end

  @impl true
  def handle_call(:get_all, _from, config) do
    {:reply, config, config}
  end

  @impl true
  def handle_call(:reset, _from, _config) do
    {:reply, :ok, @default_config}
  end

  @impl true
  def handle_call(msg, _from, config) do
    {:reply, {:error, {:unknown_call, msg}}, config}
  end

  ## Private Functions

  defp get_from_app_config(key) do
    case Application.get_env(:snmp_mgr, key) do
      nil -> Map.get(@default_config, key)
      value -> value
    end
  end
end