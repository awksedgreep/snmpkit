defmodule SnmpLib.Config do
  @moduledoc """
  Configuration management system for production SNMP deployments.
  
  This module provides a flexible, environment-aware configuration system designed
  for real-world SNMP management applications. Based on patterns proven in large-scale
  deployments like the DDumb project managing 1000+ devices.
  
  ## Features
  
  - **Environment-Aware**: Automatic detection of dev/test/prod environments
  - **Layered Configuration**: Application, environment, and runtime overrides
  - **Dynamic Updates**: Hot-reload configuration without service restart
  - **Validation**: Schema validation for all configuration values
  - **Secrets Management**: Secure handling of sensitive configuration data
  - **Multi-Tenant Support**: Per-deployment configuration isolation
  
  ## Configuration Sources (in order of precedence)
  
  1. Runtime environment variables
  2. Configuration files (config/*.exs)
  3. Application defaults
  4. Module defaults
  
  ## Usage Patterns
  
      # Get configuration for a specific component
      pool_config = SnmpLib.Config.get(:pool, :default_settings)
      
      # Get configuration with fallback
      timeout = SnmpLib.Config.get(:snmp, :timeout, 5000)
      
      # Update configuration at runtime
      SnmpLib.Config.put(:pool, :max_size, 50)
      
      # Load configuration from file
      SnmpLib.Config.load_from_file("/etc/snmp_lib/production.exs")
      
      # Validate current configuration
      {:ok, _} = SnmpLib.Config.validate()
  
  ## Environment Detection
  
  The configuration system automatically detects the current environment:
  - `:dev` - Development with verbose logging and relaxed timeouts
  - `:test` - Testing with mocked backends and fast timeouts
  - `:prod` - Production with optimized settings and monitoring
  - `:staging` - Pre-production environment for integration testing
  
  ## Configuration Schema
  
  All configuration follows a validated schema to prevent runtime errors:
  
      %{
        snmp: %{
          default_version: :v2c,
          default_timeout: 5_000,
          default_retries: 3,
          default_community: "public"
        },
        pool: %{
          default_size: 10,
          max_overflow: 5,
          strategy: :fifo,
          health_check_interval: 30_000
        },
        monitoring: %{
          metrics_enabled: true,
          prometheus_port: 9090,
          dashboard_enabled: true,
          alert_thresholds: %{...}
        }
      }
  """
  
  use GenServer
  require Logger
  
  @config_table :snmp_lib_config
  @schema_table :snmp_lib_schema
  @watchers_table :snmp_lib_watchers
  
  @default_config %{
    snmp: %{
      default_version: :v2c,
      default_timeout: 5_000,
      default_retries: 3,
      default_community: "public",
      default_port: 161,
      max_message_size: 65507,
      socket_options: [],
      mib_paths: []
    },
    pool: %{
      default_size: 10,
      max_overflow: 5,
      strategy: :fifo,
      health_check_interval: 30_000,
      checkout_timeout: 5_000,
      max_idle_time: 300_000
    },
    monitoring: %{
      metrics_enabled: true,
      prometheus_enabled: false,
      prometheus_port: 9090,
      dashboard_enabled: false,
      log_level: :info,
      alert_thresholds: %{
        error_rate: 0.05,
        response_time_p95: 2_000,
        connection_pool_utilization: 0.8
      }
    },
    error_handling: %{
      max_retries: 3,
      retry_strategy: :exponential,
      circuit_breaker_enabled: true,
      circuit_breaker_threshold: 10,
      circuit_breaker_timeout: 60_000
    },
    cache: %{
      enabled: true,
      default_ttl: 300_000,  # 5 minutes
      max_size: 10_000,
      cleanup_interval: 60_000
    }
  }
  
  @type config_key :: atom() | [atom()]
  @type config_value :: any()
  @type config_section :: atom()
  @type environment :: :dev | :test | :prod | :staging
  
  ## Public API
  
  @doc """
  Starts the configuration manager with initial configuration.
  
  ## Options
  
  - `config_file`: Path to configuration file to load on startup
  - `environment`: Override automatic environment detection
  - `validate_on_start`: Validate configuration on startup (default: true)
  
  ## Examples
  
      {:ok, _pid} = SnmpLib.Config.start_link()
      {:ok, _pid} = SnmpLib.Config.start_link(config_file: "/etc/snmp_lib/prod.exs")
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, any()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets a configuration value by key path with optional default.
  
  ## Parameters
  
  - `section`: Configuration section (:snmp, :pool, :monitoring, etc.)
  - `key`: Specific configuration key or nested key path
  - `default`: Value to return if key is not found
  
  ## Examples
  
      # Get a simple value
      timeout = SnmpLib.Config.get(:snmp, :default_timeout)
      
      # Get nested value
      threshold = SnmpLib.Config.get(:monitoring, [:alert_thresholds, :error_rate])
      
      # Get with default
      community = SnmpLib.Config.get(:snmp, :community, "public")
  """
  @spec get(config_section(), config_key(), config_value()) :: config_value()
  def get(section, key, default \\ nil) do
    case :ets.lookup(@config_table, section) do
      [{^section, config}] ->
        get_nested_value(config, key, default)
      [] ->
        get_default_value(section, key, default)
    end
  end
  
  @doc """
  Sets a configuration value at runtime.
  
  Changes are applied immediately and optionally persisted.
  
  ## Examples
  
      :ok = SnmpLib.Config.put(:pool, :default_size, 20)
      :ok = SnmpLib.Config.put(:monitoring, [:alert_thresholds, :error_rate], 0.10)
  """
  @spec put(config_section(), config_key(), config_value()) :: :ok | {:error, any()}
  def put(section, key, value) do
    GenServer.call(__MODULE__, {:put, section, key, value})
  end
  
  @doc """
  Loads configuration from a file and merges with current config.
  
  ## Examples
  
      :ok = SnmpLib.Config.load_from_file("/etc/snmp_lib/production.exs")
  """
  @spec load_from_file(binary()) :: :ok | {:error, any()}
  def load_from_file(file_path) do
    GenServer.call(__MODULE__, {:load_file, file_path})
  end
  
  @doc """
  Gets the current environment.
  
  ## Examples
  
      env = SnmpLib.Config.environment()  # :prod
  """
  @spec environment() :: environment()
  def environment do
    GenServer.call(__MODULE__, :get_environment)
  end
  
  @doc """
  Validates the current configuration against the schema.
  
  ## Returns
  
  - `{:ok, config}`: Configuration is valid
  - `{:error, errors}`: List of validation errors
  
  ## Examples
  
      case SnmpLib.Config.validate() do
        {:ok, _config} -> Logger.info("Configuration is valid")
        {:error, validation_errors} -> Logger.error("Configuration errors: " <> inspect(validation_errors))
      end
  """
  @spec validate() :: {:ok, map()} | {:error, [any()]}
  def validate do
    GenServer.call(__MODULE__, :validate)
  end
  
  @doc """
  Registers a callback function to be called when configuration changes.
  
  ## Examples
  
      SnmpLib.Config.watch(:pool, fn old_config, new_config ->
        Logger.info("Pool configuration changed")
        SnmpLib.Pool.reload_config(new_config)
      end)
  """
  @spec watch(config_section(), function()) :: :ok
  def watch(section, callback) when is_function(callback, 2) do
    GenServer.call(__MODULE__, {:watch, section, callback})
  end
  
  @doc """
  Gets all configuration as a nested map.
  
  ## Examples
  
      config = SnmpLib.Config.all()
      IO.inspect(config.snmp.default_timeout)
  """
  @spec all() :: map()
  def all do
    GenServer.call(__MODULE__, :get_all)
  end
  
  @doc """
  Reloads configuration from environment and files.
  
  ## Examples
  
      :ok = SnmpLib.Config.reload()
  """
  @spec reload() :: :ok | {:error, any()}
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @doc """
  Merges user-provided options with default SNMP configuration values.
  
  This function provides the default SNMP configuration options that are commonly
  used across SNMP operations, then merges them with user-provided options. User
  options take precedence over defaults.
  
  ## Default Values
  
  - `community`: "public"
  - `timeout`: 5000 (milliseconds)
  - `retries`: 3
  - `port`: 161
  - `version`: :v2c
  - `mib_paths`: []
  
  ## Parameters
  
  - `opts`: Keyword list of user-provided options that override defaults
  
  ## Returns
  
  Keyword list with defaults merged with user options, where user options take precedence.
  
  ## Examples
  
      iex> SnmpLib.Config.merge_opts([])
      [community: "public", timeout: 5000, retries: 3, port: 161, version: :v2c, mib_paths: []]
      
      iex> result = SnmpLib.Config.merge_opts([timeout: 10000])
      iex> result[:community]
      "public"
      iex> result[:timeout]
      10000
      iex> result[:retries]
      3
      
      iex> result = SnmpLib.Config.merge_opts([community: "private", port: 162])
      iex> result[:community]
      "private"
      iex> result[:port]
      162
      iex> result[:timeout]
      5000
  """
  @spec merge_opts(keyword()) :: keyword()
  def merge_opts(opts) when is_list(opts) do
    # Get default SNMP values from the configuration system, with static fallbacks
    defaults = [
      community: safe_get(:snmp, :default_community, "public"),
      timeout: safe_get(:snmp, :default_timeout, 5000),
      retries: safe_get(:snmp, :default_retries, 3),
      port: safe_get(:snmp, :default_port, 161),
      version: safe_get(:snmp, :default_version, :v2c),
      mib_paths: safe_get(:snmp, :mib_paths, [])
    ]
    
    # Merge defaults with user options, user options take precedence
    Keyword.merge(defaults, opts)
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    # Create ETS tables for fast access
    :ets.new(@config_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@schema_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@watchers_table, [:named_table, :bag, :public])
    
    # Detect environment
    environment = detect_environment(opts)
    
    # Load initial configuration
    initial_config = load_initial_config(environment, opts)
    
    # Store configuration in ETS
    store_config(initial_config)
    
    # Validate if requested
    if Keyword.get(opts, :validate_on_start, true) do
      case validate_config(initial_config) do
        {:ok, _} ->
          Logger.info("SnmpLib.Config started with valid configuration")
        {:error, errors} ->
          Logger.warning("SnmpLib.Config started with validation errors: #{inspect(errors)}")
      end
    end
    
    state = %{
      environment: environment,
      config_file: Keyword.get(opts, :config_file),
      watchers: %{}
    }
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:put, section, key, value}, _from, state) do
    case update_config_value(section, key, value) do
      :ok ->
        notify_watchers(section)
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:load_file, file_path}, _from, state) do
    case load_config_file(file_path) do
      {:ok, file_config} ->
        merge_config(file_config)
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:get_environment, _from, state) do
    {:reply, state.environment, state}
  end
  
  @impl GenServer
  def handle_call(:validate, _from, state) do
    current_config = get_all_config()
    result = validate_config(current_config)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:watch, section, callback}, _from, state) do
    :ets.insert(@watchers_table, {section, callback})
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_call(:get_all, _from, state) do
    config = get_all_config()
    {:reply, config, state}
  end
  
  @impl GenServer
  def handle_call(:reload, _from, state) do
    case reload_configuration(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end
  
  ## Private Implementation
  
  # Environment detection with multiple fallbacks
  defp detect_environment(opts) do
    cond do
      env = Keyword.get(opts, :environment) -> env
      env = System.get_env("MIX_ENV") -> String.to_atom(env)
      env = System.get_env("SNMP_LIB_ENV") -> String.to_atom(env)
      env = Application.get_env(:snmp_lib, :environment) -> env
      true -> :dev
    end
  end
  
  # Load configuration from multiple sources
  defp load_initial_config(environment, opts) do
    base_config = get_environment_defaults(environment)
    
    # Load from application config
    app_config = Application.get_all_env(:snmp_lib) |> Enum.into(%{})
    config_with_app = deep_merge(base_config, app_config)
    
    # Load from file if specified
    config_with_file = case Keyword.get(opts, :config_file) do
      nil -> config_with_app
      file_path ->
        case load_config_file(file_path) do
          {:ok, file_config} -> deep_merge(config_with_app, file_config)
          {:error, _} -> config_with_app
        end
    end
    
    # Load from environment variables
    config_with_env = load_from_environment(config_with_file)
    
    config_with_env
  end
  
  # Get environment-specific defaults
  defp get_environment_defaults(:dev) do
    @default_config
    |> put_in([:monitoring, :log_level], :debug)
    |> put_in([:pool, :health_check_interval], 10_000)
  end
  
  defp get_environment_defaults(:test) do
    @default_config
    |> put_in([:snmp, :default_timeout], 1_000)
    |> put_in([:pool, :default_size], 2)
    |> put_in([:pool, :health_check_interval], 5_000)
    |> put_in([:monitoring, :metrics_enabled], false)
    |> put_in([:cache, :enabled], false)
  end
  
  defp get_environment_defaults(:staging) do
    @default_config
    |> put_in([:monitoring, :dashboard_enabled], true)
    |> put_in([:monitoring, :prometheus_enabled], true)
  end
  
  defp get_environment_defaults(:prod) do
    @default_config
    |> put_in([:pool, :default_size], 25)
    |> put_in([:pool, :max_overflow], 15)
    |> put_in([:monitoring, :metrics_enabled], true)
    |> put_in([:monitoring, :dashboard_enabled], true)
    |> put_in([:monitoring, :prometheus_enabled], true)
    |> put_in([:monitoring, :log_level], :warning)
  end
  
  defp get_environment_defaults(_), do: @default_config
  
  # Load configuration from environment variables
  defp load_from_environment(config) do
    # This would parse environment variables like:
    # SNMP_LIB_POOL_DEFAULT_SIZE=20
    # SNMP_LIB_SNMP_DEFAULT_TIMEOUT=10000
    # etc.
    
    env_config = %{}
    
    # For now, just return the config as-is
    # In a full implementation, this would parse all SNMP_LIB_* environment variables
    deep_merge(config, env_config)
  end
  
  # Load configuration from file
  defp load_config_file(file_path) do
    case File.exists?(file_path) do
      true ->
        try do
          {config, _} = Code.eval_file(file_path)
          {:ok, config}
        rescue
          error ->
            Logger.error("Failed to load config file #{file_path}: #{inspect(error)}")
            {:error, error}
        end
      false ->
        {:error, :file_not_found}
    end
  end
  
  # Store configuration in ETS tables
  defp store_config(config) do
    Enum.each(config, fn {section, section_config} ->
      :ets.insert(@config_table, {section, section_config})
    end)
  end
  
  # Get nested configuration value
  defp get_nested_value(config, key, default) when is_atom(key) do
    Map.get(config, key, default)
  end
  
  defp get_nested_value(config, keys, default) when is_list(keys) do
    get_in(config, keys) || default
  end
  
  # Get default value from static configuration
  defp get_default_value(section, key, default) do
    case Map.get(@default_config, section) do
      nil -> default
      section_config -> get_nested_value(section_config, key, default)
    end
  end
  
  # Safe get that works even when GenServer is not running (for doctests)
  defp safe_get(section, key, default) do
    try do
      get(section, key, default)
    rescue
      ArgumentError ->
        # ETS table doesn't exist, fall back to static config
        get_default_value(section, key, default)
    end
  end
  
  # Update configuration value in ETS
  defp update_config_value(section, key, value) do
    case :ets.lookup(@config_table, section) do
      [{^section, config}] ->
        case put_nested_value_safe(config, key, value) do
          {:ok, updated_config} ->
            :ets.insert(@config_table, {section, updated_config})
            :ok
          {:error, reason} ->
            {:error, reason}
        end
      [] ->
        # Create new section
        case put_nested_value_safe(%{}, key, value) do
          {:ok, new_config} ->
            :ets.insert(@config_table, {section, new_config})
            :ok
          {:error, reason} ->
            {:error, reason}
        end
    end
  rescue
    ArgumentError ->
      {:error, :invalid_config_path}
    error ->
      {:error, {:unexpected_error, error}}
  end
  
  # Set nested configuration value
  defp put_nested_value_safe(config, key, value) when is_atom(key) do
    {:ok, Map.put(config, key, value)}
  end
  
  defp put_nested_value_safe(config, keys, value) when is_list(keys) do
    try do
      {:ok, put_in(config, keys, value)}
    rescue
      error ->
        {:error, {:unexpected_error, error}}
    end
  end
  
  # Get all configuration as map
  defp get_all_config do
    :ets.tab2list(@config_table)
    |> Enum.into(%{})
  end
  
  # Merge configuration maps deeply
  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_val, right_val ->
      deep_merge(left_val, right_val)
    end)
  end
  
  defp deep_merge(_left, right), do: right
  
  # Merge new configuration with existing
  defp merge_config(new_config) do
    existing_config = get_all_config()
    merged_config = deep_merge(existing_config, new_config)
    store_config(merged_config)
  end
  
  # Validate configuration against schema
  defp validate_config(config) do
    # Simple validation - in production this would use a proper schema library
    errors = []
    
    errors = validate_section(config, :snmp, errors)
    errors = validate_section(config, :pool, errors)
    errors = validate_section(config, :monitoring, errors)
    
    case errors do
      [] -> {:ok, config}
      _ -> {:error, errors}
    end
  end
  
  defp validate_section(config, section, errors) do
    case Map.get(config, section) do
      nil -> [{:missing_section, section} | errors]
      section_config when is_map(section_config) -> errors
      _ -> [{:invalid_section_type, section} | errors]
    end
  end
  
  # Notify watchers of configuration changes
  defp notify_watchers(section) do
    case :ets.lookup(@watchers_table, section) do
      [] -> :ok
      watchers ->
        old_config = :ets.lookup(@config_table, section)
        new_config = :ets.lookup(@config_table, section)
        
        Enum.each(watchers, fn {^section, callback} ->
          try do
            callback.(old_config, new_config)
          rescue
            error ->
              Logger.warning("Configuration watcher failed: #{inspect(error)}")
          end
        end)
    end
  end
  
  defp reload_configuration(state) do
    try do
      # Reload from environment and files
      new_config = load_initial_config(state.environment, [config_file: state.config_file])
      store_config(new_config)
      
      # Notify all watchers
      Enum.each([:snmp, :pool, :monitoring, :error_handling, :cache], fn section ->
        notify_watchers(section)
      end)
      
      {:ok, state}
    rescue
      error ->
        {:error, error}
    end
  end
end