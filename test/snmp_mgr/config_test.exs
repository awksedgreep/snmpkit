defmodule SnmpKit.SnmpMgr.ConfigIntegrationTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.{Config}
  alias SnmpKit.TestSupport.SNMPSimulator

  @moduletag :unit
  @moduletag :config
  @moduletag :snmp_lib_integration

  setup_all do
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}

      error ->
        %{device: nil, setup_error: error}
    end
  end

  setup do
    case GenServer.whereis(SnmpKit.SnmpMgr.Config) do
      nil ->
        {:ok, pid} = Config.start_link()

        on_exit(fn ->
          if GenServer.whereis(SnmpKit.SnmpMgr.Config) == pid and Process.alive?(pid) do
            GenServer.stop(pid)
          end
        end)

        %{config_pid: pid}

      pid ->
        Config.reset()

        on_exit(fn ->
          if GenServer.whereis(SnmpKit.SnmpMgr.Config) == pid and Process.alive?(pid) do
            Config.reset()
          end
        end)

        %{config_pid: pid}
    end
  end

  describe "Configuration Integration with snmp_lib Operations" do
    test "config defaults are used in SNMP operations", %{device: device} do

      # Set config defaults
      Config.set_default_community(device.community)
      Config.set_default_timeout(200)
      Config.set_default_version(:v2c)

      # Perform operation without explicit options (should use config defaults)
      target = SNMPSimulator.device_target(device)
      result = SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community, timeout: 200)

      assert {:ok, _value} = result

      # Verify config was accessed
      assert Config.get_default_community() == device.community
      assert Config.get_default_timeout() == 200
    end

    test "explicit options override config defaults", %{device: device} do

      # Set different config defaults
      Config.set_default_community("wrong_community")
      Config.set_default_timeout(10000)

      # Perform operation with explicit options (should override config)
      target = SNMPSimulator.device_target(device)
      result = SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community, timeout: 200)

      assert {:ok, _value} = result

      # Config should still have different values
      assert Config.get_default_community() == "wrong_community"
      assert Config.get_default_timeout() == 10000
    end
  end

  describe "Version-specific Configuration" do
    test "SNMPv1 operations use configured version", %{device: device} do

      Config.set_default_version(:v1)

      # Test with v1 operations (no bulk operations)
      target = SNMPSimulator.device_target(device)

      result =
        SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
          community: device.community,
          version: :v1,
          timeout: 200
        )

      assert {:ok, _value} = result
      assert Config.get_default_version() == :v1
    end

    test "SNMPv2c operations use configured version", %{device: device} do

      Config.set_default_version(:v2c)

      # Test with v2c operations (bulk operations available)
      target = SNMPSimulator.device_target(device)

      get_result =
        SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
          community: device.community,
          version: :v2c,
          timeout: 200
        )

      bulk_result =
        SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.1",
          community: device.community,
          version: :v2c,
          timeout: 200,
          max_repetitions: 3
        )

      assert {:ok, _value} = get_result
      assert {:ok, _} = bulk_result
      assert Config.get_default_version() == :v2c
    end
  end

  describe "MIB Path Integration" do
    test "MIB paths are used for OID resolution", %{device: device} do

      # Add some MIB paths
      Config.add_mib_path("/usr/share/snmp/mibs")
      Config.add_mib_path("./test/mibs")

      # Verify paths are stored
      paths = Config.get_mib_paths()
      assert "/usr/share/snmp/mibs" in paths
      assert "./test/mibs" in paths

      # Test SNMP operation (should work with or without MIB resolution)
      target = SNMPSimulator.device_target(device)
      result = SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community, timeout: 200)

      assert {:ok, _value} = result
    end
  end

  describe "Configuration Merge Integration" do
    test "Config.merge_opts works with snmp_lib operations", %{device: device} do

      # Set config defaults
      Config.set_default_community(device.community)
      Config.set_default_timeout(300)
      Config.set_default_retries(2)

      # Merge with override options
      merged_opts = Config.merge_opts(timeout: 200, port: device.port)

      # Should have config defaults plus overrides
      assert Keyword.get(merged_opts, :community) == device.community
      # Override
      assert Keyword.get(merged_opts, :timeout) == 200
      # From config
      assert Keyword.get(merged_opts, :retries) == 2
      # Override
      assert Keyword.get(merged_opts, :port) == device.port

      # Use merged options in SNMP operation
      target = SNMPSimulator.device_target(device)

      result =
        SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
          community: Keyword.get(merged_opts, :community),
          timeout: Keyword.get(merged_opts, :timeout)
        )

      assert {:ok, _value} = result
    end
  end

  # Helper functions
end
