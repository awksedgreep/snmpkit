defmodule SnmpKit.SnmpSim.ErrorInjectorTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.{ErrorInjector}
  alias SnmpKit.SnmpKit.SnmpSim.Device
  alias SnmpKit.SnmpKit.SnmpSim.MIB.SharedProfiles
  alias SnmpKit.SnmpSim.{LazyDevicePool}
  alias SnmpKit.SnmpKit.SnmpSim.TestHelpers.PortHelper

  setup do
    # Start shared profiles for testing only if not already started
    case SharedProfiles.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Create a test device
    device_config = %{
      port: PortHelper.get_port(),
      device_type: :cable_modem,
      device_id: "test_device_#{:rand.uniform(10000)}",
      community: "public"
    }

    {:ok, device_pid} = Device.start_link(device_config)

    on_exit(fn ->
      if Process.alive?(device_pid) do
        Device.stop(device_pid)
      end
    end)

    %{device_pid: device_pid, device_config: device_config}
  end

  describe "ErrorInjector startup and basic operations" do
    test "starts and stops successfully", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Verify the injector is running
      assert Process.alive?(injector_pid)

      # Get initial statistics
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.total_injections == 0
      assert stats.burst_events == 0
      assert stats.device_failures == 0

      # Stop the injector
      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end

      refute Process.alive?(injector_pid)
    end

    test "tracks injection statistics", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Inject different types of errors
      :ok = ErrorInjector.inject_timeout(injector_pid, probability: 0.1)
      :ok = ErrorInjector.inject_packet_loss(injector_pid, loss_rate: 0.05)
      :ok = ErrorInjector.inject_snmp_error(injector_pid, :genErr, probability: 0.1)

      # Check statistics
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.total_injections == 3
      assert stats.injections_by_type.timeout == 1
      assert stats.injections_by_type.packet_loss == 1
      assert stats.injections_by_type.snmp_error == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end

    test "clears all error conditions", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Inject multiple errors
      :ok = ErrorInjector.inject_timeout(injector_pid, probability: 0.5)
      :ok = ErrorInjector.inject_packet_loss(injector_pid, loss_rate: 0.2)

      # Clear all errors
      :ok = ErrorInjector.clear_all_errors(injector_pid)

      # Verify device received clear message (we can't directly check device state)
      # But we can verify the injector cleared its conditions
      stats = ErrorInjector.get_error_statistics(injector_pid)
      # Still shows injection count
      assert stats.total_injections == 2

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end
  end

  describe "timeout injection" do
    test "injects timeout errors with configured probability", %{
      device_pid: device_pid,
      device_config: config
    } do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Inject timeout with high probability for testing
      :ok =
        ErrorInjector.inject_timeout(injector_pid,
          # Always timeout for testing
          probability: 1.0,
          duration_ms: 100,
          target_oids: :all
        )

      # Verify injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.timeout == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end

    test "supports burst timeout patterns", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Inject burst timeouts
      :ok =
        ErrorInjector.inject_timeout(injector_pid,
          probability: 0.5,
          duration_ms: 500,
          burst_probability: 0.1,
          burst_duration_ms: 2000
        )

      # Verify configuration was applied
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.total_injections == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end
  end

  describe "packet loss injection" do
    test "injects packet loss with configured rate", %{
      device_pid: device_pid,
      device_config: config
    } do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Inject packet loss
      :ok =
        ErrorInjector.inject_packet_loss(injector_pid,
          loss_rate: 0.1,
          burst_loss: false
        )

      # Verify injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.packet_loss == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end

    test "supports burst packet loss patterns", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Inject burst packet loss
      :ok =
        ErrorInjector.inject_packet_loss(injector_pid,
          loss_rate: 0.05,
          burst_loss: true,
          burst_size: 5,
          recovery_time_ms: 10000
        )

      # Verify configuration was applied
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.total_injections == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end
  end

  describe "SNMP error injection" do
    test "injects different SNMP error types", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Test different SNMP error types
      snmp_errors = [:noSuchName, :genErr, :tooBig, :badValue, :readOnly]

      Enum.each(snmp_errors, fn error_type ->
        :ok =
          ErrorInjector.inject_snmp_error(injector_pid, error_type,
            probability: 0.1,
            target_oids: ["1.3.6.1.2.1.1.1.0"]
          )
      end)

      # Verify all injections were recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.snmp_error == length(snmp_errors)

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end

    test "targets specific OIDs", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Target specific OIDs
      :ok =
        ErrorInjector.inject_snmp_error(injector_pid, :noSuchName,
          probability: 1.0,
          target_oids: ["1.3.6.1.2.1.2.2.1.10", "1.3.6.1.2.1.2.2.1.16"],
          error_index: 1
        )

      # Verify injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.snmp_error == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end
  end

  describe "malformed response injection" do
    test "injects different corruption types", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Test different corruption types
      corruption_types = [
        :truncated,
        :invalid_ber,
        :wrong_community,
        :invalid_pdu_type,
        :corrupted_varbinds
      ]

      Enum.each(corruption_types, fn corruption_type ->
        :ok =
          ErrorInjector.inject_malformed_response(injector_pid, corruption_type,
            probability: 0.1,
            corruption_severity: 0.5
          )
      end)

      # Verify all injections were recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.malformed == length(corruption_types)

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end
  end

  describe "device failure simulation" do
    @tag :slow
    test "simulates different failure types", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Test device reboot
      :ok =
        ErrorInjector.simulate_device_failure(injector_pid, :reboot,
          duration_ms: 1000,
          recovery_behavior: :reset_counters
        )

      # Verify injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.device_failure == 1

      # Wait for recovery
      Process.sleep(1100)

      # Check final statistics
      final_stats = ErrorInjector.get_error_statistics(injector_pid)
      assert final_stats.device_failures == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end

    test "simulates power failure", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Simulate power failure
      :ok =
        ErrorInjector.simulate_device_failure(injector_pid, :power_failure,
          duration_ms: 2000,
          failure_probability: 1.0
        )

      # Verify injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.device_failure == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end

    test "simulates network disconnect", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Simulate network disconnect
      :ok =
        ErrorInjector.simulate_device_failure(injector_pid, :network_disconnect,
          duration_ms: 1500,
          recovery_behavior: :gradual
        )

      # Verify injection was recorded
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.injections_by_type.device_failure == 1

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end
  end

  describe "error condition removal" do
    test "removes specific error types", %{device_pid: device_pid, device_config: config} do
      {:ok, injector_pid} = ErrorInjector.start_link(device_pid, config.port)

      # Inject multiple error types
      :ok = ErrorInjector.inject_timeout(injector_pid, probability: 0.1)
      :ok = ErrorInjector.inject_packet_loss(injector_pid, loss_rate: 0.05)
      :ok = ErrorInjector.inject_snmp_error(injector_pid, :genErr, probability: 0.1)

      # Remove specific error type
      :ok = ErrorInjector.remove_error_condition(injector_pid, :timeout)

      # Verify total injections remain but condition is removed
      stats = ErrorInjector.get_error_statistics(injector_pid)
      assert stats.total_injections == 3

      if Process.alive?(injector_pid) do
        GenServer.stop(injector_pid)
      end
    end
  end
end
