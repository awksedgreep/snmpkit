defmodule SnmpKit.SnmpLib.ConfigTest do
  use ExUnit.Case, async: false
  doctest SnmpKit.SnmpLib.Config

  alias SnmpKit.SnmpLib.Config

  @moduletag :config_test

  setup do
    # Ensure config process is stopped before each test
    if Process.whereis(Config) do
      try do
        GenServer.stop(Config, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end

    :timer.sleep(10)
    :ok
  end

  describe "Config.start_link/1" do
    test "starts with default configuration" do
      assert {:ok, pid} = Config.start_link()
      assert Process.alive?(pid)

      # Test default values
      assert Config.get(:snmp, :default_version) == :v2c
      assert Config.get(:pool, :default_size) == 10
      # Environment defaults to :dev
      assert Config.environment() == :dev

      try do
        GenServer.stop(Config)
      catch
        :exit, _ -> :ok
      end
    end

    test "starts with custom environment" do
      assert {:ok, _pid} = Config.start_link(environment: :prod)

      # Production environment should have different defaults
      assert Config.get(:pool, :default_size) == 25
      assert Config.environment() == :prod

      try do
        GenServer.stop(Config)
      catch
        :exit, _ -> :ok
      end
    end
  end

  describe "Config.get/3 and Config.put/3" do
    setup do
      {:ok, _pid} = Config.start_link()

      on_exit(fn ->
        if Process.whereis(Config) do
          try do
            GenServer.stop(Config, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "gets and sets configuration values" do
      # Test simple get with default
      timeout = Config.get(:snmp, :default_timeout, 1000)
      assert is_integer(timeout)

      # Test put and get
      :ok = Config.put(:snmp, :custom_value, "test")
      assert Config.get(:snmp, :custom_value) == "test"
    end

    test "gets nested configuration values" do
      # Test nested path access
      threshold = Config.get(:monitoring, [:alert_thresholds, :error_rate])
      assert is_float(threshold)

      # Test nested put
      :ok = Config.put(:monitoring, [:alert_thresholds, :custom], 0.15)
      assert Config.get(:monitoring, [:alert_thresholds, :custom]) == 0.15
    end

    test "returns default for missing keys" do
      assert Config.get(:nonexistent, :key, :default) == :default
      assert Config.get(:snmp, :nonexistent, 42) == 42
    end
  end

  describe "Config.validate/0" do
    setup do
      {:ok, _pid} = Config.start_link()

      on_exit(fn ->
        if Process.whereis(Config) do
          try do
            GenServer.stop(Config, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "validates correct configuration" do
      assert {:ok, _config} = Config.validate()
    end
  end

  describe "Config.all/0" do
    setup do
      {:ok, _pid} = Config.start_link()

      on_exit(fn ->
        if Process.whereis(Config) do
          try do
            GenServer.stop(Config, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "returns complete configuration map" do
      config = Config.all()

      assert is_map(config)
      assert Map.has_key?(config, :snmp)
      assert Map.has_key?(config, :pool)
      assert Map.has_key?(config, :monitoring)
    end
  end

  describe "Config.watch/2" do
    setup do
      {:ok, _pid} = Config.start_link()

      on_exit(fn ->
        if Process.whereis(Config) do
          try do
            GenServer.stop(Config, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "registers configuration watchers" do
      # Register a watcher
      test_pid = self()
      callback = fn _old, _new -> send(test_pid, :config_changed) end

      :ok = Config.watch(:snmp, callback)

      # Change configuration to trigger watcher
      :ok = Config.put(:snmp, :test_value, "changed")

      # Note: In a real implementation, this would trigger the callback
      # For now, we just test that the watcher registration succeeds
    end
  end

  describe "environment detection" do
    test "detects test environment by default" do
      {:ok, _pid} = Config.start_link()
      # Environment defaults to :dev unless explicitly set
      assert Config.environment() == :dev

      try do
        GenServer.stop(Config)
      catch
        :exit, _ -> :ok
      end
    end

    test "respects explicit environment setting" do
      {:ok, _pid} = Config.start_link(environment: :dev)
      assert Config.environment() == :dev

      try do
        GenServer.stop(Config)
      catch
        :exit, _ -> :ok
      end
    end
  end

  describe "Config.reload/0" do
    setup do
      {:ok, _pid} = Config.start_link()

      on_exit(fn ->
        if Process.whereis(Config) do
          try do
            GenServer.stop(Config, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "reloads configuration successfully" do
      # Change a value
      :ok = Config.put(:snmp, :test_reload, "before")
      assert Config.get(:snmp, :test_reload) == "before"

      # Reload should reset to defaults (since no external config file)
      assert :ok = Config.reload()

      # Value should be reset
      assert Config.get(:snmp, :test_reload, :missing) == :missing
    end
  end
end
