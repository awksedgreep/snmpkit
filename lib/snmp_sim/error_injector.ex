defmodule SnmpSim.ErrorInjector do
  @moduledoc """
  Inject realistic error conditions for comprehensive testing.

  Supports timeouts, packet loss, malformed responses, and device failures
  for testing SNMP polling systems under realistic network conditions.

  ## Features

  - Network timeouts with configurable probability and duration
  - Packet loss simulation with burst patterns
  - SNMP protocol errors (noSuchName, genErr, tooBig)
  - Malformed response corruption for robustness testing
  - Device failure and reboot simulation
  - Statistical tracking of all injected errors

  ## Usage

      # Inject timeout condition
      SnmpSim.ErrorInjector.inject_timeout(device_pid, probability: 0.1, duration: 5000)
      
      # Simulate packet loss
      SnmpSim.ErrorInjector.inject_packet_loss(device_pid, loss_rate: 0.05)
      
      # Generate SNMP errors
      SnmpSim.ErrorInjector.inject_snmp_error(device_pid, :noSuchName, ["1.3.6.1.2.1.2.2.1.99"])
      
  """

  use GenServer
  require Logger

  @type error_type :: :timeout | :packet_loss | :snmp_error | :malformed | :device_failure
  @type error_config :: %{
          probability: float(),
          duration_ms: integer(),
          burst_patterns: boolean(),
          target_oids: list(String.t()) | :all,
          error_details: map()
        }

  defstruct [
    :device_pid,
    :device_port,
    # Map of active error conditions
    :error_conditions,
    # Statistics tracking
    :error_statistics,
    # Current burst error state
    :burst_state,
    # Scheduled error timers
    :schedule_timers
  ]

  ## Public API

  @doc """
  Start error injection monitoring for a device.
  """
  @spec start_link(pid(), integer()) :: {:ok, pid()} | {:error, term()}
  def start_link(device_pid, device_port) do
    GenServer.start_link(__MODULE__, {device_pid, device_port}, [])
  end

  @doc """
  Inject timeout conditions with specified probability and duration.

  ## Options

  - `probability`: Float 0.0-1.0, chance each request times out
  - `duration_ms`: Timeout duration in milliseconds
  - `burst_probability`: Chance of timeout bursts (default: 0.1)
  - `burst_duration_ms`: Duration of timeout bursts (default: 10000)

  ## Examples

      # 10% chance of 5-second timeouts
      ErrorInjector.inject_timeout(device, probability: 0.1, duration_ms: 5000)
      
      # Burst timeouts - 20% of requests timeout for 30 seconds when burst occurs
      ErrorInjector.inject_timeout(device, 
        probability: 0.2, 
        duration_ms: 30000,
        burst_probability: 0.05,
        burst_duration_ms: 60000
      )
      
  """
  @spec inject_timeout(pid(), keyword()) :: :ok | {:error, term()}
  def inject_timeout(injector_pid, opts \\ []) do
    config = %{
      type: :timeout,
      probability: Keyword.get(opts, :probability, 0.1),
      duration_ms: Keyword.get(opts, :duration_ms, 5000),
      burst_probability: Keyword.get(opts, :burst_probability, 0.1),
      burst_duration_ms: Keyword.get(opts, :burst_duration_ms, 10000),
      target_oids: Keyword.get(opts, :target_oids, :all)
    }

    GenServer.call(injector_pid, {:inject_error, config})
  end

  @doc """
  Inject packet loss with configurable loss rates and patterns.

  ## Options

  - `loss_rate`: Float 0.0-1.0, percentage of packets to drop
  - `burst_loss`: Enable burst loss patterns (default: false)
  - `burst_size`: Number of consecutive packets to drop in burst (default: 5)
  - `recovery_time_ms`: Time between bursts (default: 30000)

  ## Examples

      # 5% random packet loss
      ErrorInjector.inject_packet_loss(device, loss_rate: 0.05)
      
      # Burst packet loss - lose 10 consecutive packets occasionally
      ErrorInjector.inject_packet_loss(device,
        loss_rate: 0.02,
        burst_loss: true,
        burst_size: 10,
        recovery_time_ms: 60000
      )
      
  """
  @spec inject_packet_loss(pid(), keyword()) :: :ok | {:error, term()}
  def inject_packet_loss(injector_pid, opts \\ []) do
    config = %{
      type: :packet_loss,
      loss_rate: Keyword.get(opts, :loss_rate, 0.05),
      burst_loss: Keyword.get(opts, :burst_loss, false),
      burst_size: Keyword.get(opts, :burst_size, 5),
      recovery_time_ms: Keyword.get(opts, :recovery_time_ms, 30000),
      target_oids: Keyword.get(opts, :target_oids, :all)
    }

    GenServer.call(injector_pid, {:inject_error, config})
  end

  @doc """
  Inject SNMP protocol errors for specific OIDs or patterns.

  ## Error Types

  - `:noSuchName` - OID does not exist
  - `:genErr` - General error
  - `:tooBig` - Response too large for UDP packet
  - `:badValue` - Invalid value in SET request
  - `:readOnly` - Attempt to SET read-only variable

  ## Examples

      # Generate noSuchName errors for specific OIDs
      ErrorInjector.inject_snmp_error(device, :noSuchName, 
        target_oids: ["1.3.6.1.2.1.2.2.1.99"],
        probability: 1.0
      )
      
      # Random genErr responses
      ErrorInjector.inject_snmp_error(device, :genErr,
        probability: 0.05,
        target_oids: :all
      )
      
  """
  @spec inject_snmp_error(pid(), atom(), keyword()) :: :ok | {:error, term()}
  def inject_snmp_error(injector_pid, error_type, opts \\ []) do
    config = %{
      type: :snmp_error,
      snmp_error_type: error_type,
      probability: Keyword.get(opts, :probability, 0.1),
      target_oids: Keyword.get(opts, :target_oids, :all),
      error_index: Keyword.get(opts, :error_index, 1)
    }

    GenServer.call(injector_pid, {:inject_error, config})
  end

  @doc """
  Inject malformed response packets to test client robustness.

  ## Corruption Types

  - `:truncated` - Cut off response packets
  - `:invalid_ber` - Corrupt BER/DER encoding
  - `:wrong_community` - Incorrect community string
  - `:invalid_pdu_type` - Invalid PDU type field
  - `:corrupted_varbinds` - Corrupt variable bindings

  ## Examples

      # Randomly truncate 2% of responses
      ErrorInjector.inject_malformed_response(device, :truncated,
        probability: 0.02,
        corruption_severity: 0.3
      )
      
      # Corrupt BER encoding occasionally
      ErrorInjector.inject_malformed_response(device, :invalid_ber,
        probability: 0.01
      )
      
  """
  @spec inject_malformed_response(pid(), atom(), keyword()) :: :ok | {:error, term()}
  def inject_malformed_response(injector_pid, corruption_type, opts \\ []) do
    config = %{
      type: :malformed,
      corruption_type: corruption_type,
      probability: Keyword.get(opts, :probability, 0.05),
      corruption_severity: Keyword.get(opts, :corruption_severity, 0.5),
      target_oids: Keyword.get(opts, :target_oids, :all)
    }

    GenServer.call(injector_pid, {:inject_error, config})
  end

  @doc """
  Simulate device reboot or failure scenarios.

  ## Failure Types

  - `:reboot` - Device becomes unreachable then recovers
  - `:power_failure` - Complete device failure
  - `:network_disconnect` - Network connectivity lost
  - `:firmware_crash` - Device crash with recovery
  - `:overload` - Device overloaded, slow responses

  ## Examples

      # Simulate device reboot (30 seconds downtime)
      ErrorInjector.simulate_device_failure(device, :reboot,
        duration_ms: 30000,
        recovery_behavior: :reset_counters
      )
      
      # Network disconnect with gradual recovery
      ErrorInjector.simulate_device_failure(device, :network_disconnect,
        duration_ms: 60000,
        recovery_behavior: :gradual
      )
      
  """
  @spec simulate_device_failure(pid(), atom(), keyword()) :: :ok | {:error, term()}
  def simulate_device_failure(injector_pid, failure_type, opts \\ []) do
    config = %{
      type: :device_failure,
      failure_type: failure_type,
      duration_ms: Keyword.get(opts, :duration_ms, 3000),
      recovery_behavior: Keyword.get(opts, :recovery_behavior, :normal),
      failure_probability: Keyword.get(opts, :failure_probability, 1.0)
    }

    GenServer.call(injector_pid, {:inject_error, config})
  end

  @doc """
  Get statistics for all injected errors.
  """
  @spec get_error_statistics(pid()) :: map()
  def get_error_statistics(injector_pid) do
    GenServer.call(injector_pid, :get_statistics)
  end

  @doc """
  Clear all error conditions and reset device to normal operation.
  """
  @spec clear_all_errors(pid()) :: :ok
  def clear_all_errors(injector_pid) do
    GenServer.call(injector_pid, :clear_all_errors)
  end

  @doc """
  Remove specific error condition.
  """
  @spec remove_error_condition(pid(), error_type()) :: :ok
  def remove_error_condition(injector_pid, error_type) do
    GenServer.call(injector_pid, {:remove_error, error_type})
  end

  ## GenServer Implementation

  @impl true
  def init({device_pid, device_port}) do
    Logger.info("Starting error injector for device on port #{device_port}")

    state = %__MODULE__{
      device_pid: device_pid,
      device_port: device_port,
      error_conditions: %{},
      error_statistics: initialize_statistics(),
      burst_state: %{},
      schedule_timers: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:inject_error, config}, _from, state) do
    Logger.debug("Injecting #{config.type} error for device #{state.device_port}")

    # Add error condition to device
    error_id = generate_error_id(config.type)
    updated_conditions = Map.put(state.error_conditions, error_id, config)

    # Start scheduled timers if needed
    updated_timers = maybe_schedule_error_timers(config, error_id, state.schedule_timers)

    # Update statistics
    updated_stats = update_injection_statistics(state.error_statistics, config.type)

    # Apply error condition to device
    case apply_error_condition(state.device_pid, config) do
      :ok ->
        new_state = %{
          state
          | error_conditions: updated_conditions,
            schedule_timers: updated_timers,
            error_statistics: updated_stats
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to inject error: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    {:reply, state.error_statistics, state}
  end

  @impl true
  def handle_call(:clear_all_errors, _from, state) do
    Logger.info("Clearing all error conditions for device #{state.device_port}")

    # Clear all timers
    Enum.each(state.schedule_timers, fn {_id, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    # Reset device to normal operation
    :ok = clear_device_errors(state.device_pid)
    cleared_state = %{state | error_conditions: %{}, schedule_timers: %{}, burst_state: %{}}
    {:reply, :ok, cleared_state}
  end

  @impl true
  def handle_call({:remove_error, error_type}, _from, state) do
    # Find and remove error conditions of specified type
    {removed_conditions, remaining_conditions} =
      Enum.split_with(state.error_conditions, fn {_id, config} ->
        config.type == error_type
      end)

    # Cancel associated timers
    updated_timers =
      Enum.reduce(removed_conditions, state.schedule_timers, fn {error_id, _config}, timers ->
        case Map.get(timers, error_id) do
          nil ->
            timers

          timer_ref ->
            Process.cancel_timer(timer_ref)
            Map.delete(timers, error_id)
        end
      end)

    new_state = %{
      state
      | error_conditions: Map.new(remaining_conditions),
        schedule_timers: updated_timers
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:scheduled_error, error_id, action}, state) do
    case Map.get(state.error_conditions, error_id) do
      nil ->
        # Error condition was removed
        {:noreply, state}

      config ->
        case action do
          :activate_burst ->
            handle_burst_activation(error_id, config, state)

          :deactivate_burst ->
            handle_burst_deactivation(error_id, config, state)

          :device_recovery ->
            handle_device_recovery(error_id, config, state)

          _ ->
            Logger.warning("Unknown scheduled error action: #{action}")
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in ErrorInjector: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp initialize_statistics do
    %{
      total_injections: 0,
      injections_by_type: %{
        timeout: 0,
        packet_loss: 0,
        snmp_error: 0,
        malformed: 0,
        device_failure: 0
      },
      errors_triggered: %{},
      burst_events: 0,
      device_failures: 0,
      last_injection: nil,
      start_time: DateTime.utc_now()
    }
  end

  defp generate_error_id(type) do
    timestamp = :os.system_time(:microsecond)
    "#{type}_#{timestamp}_#{:rand.uniform(1000)}"
  end

  defp update_injection_statistics(stats, error_type) do
    %{
      stats
      | total_injections: stats.total_injections + 1,
        injections_by_type: Map.update(stats.injections_by_type, error_type, 1, &(&1 + 1)),
        last_injection: DateTime.utc_now()
    }
  end

  defp apply_error_condition(device_pid, config) do
    case config.type do
      :timeout ->
        apply_timeout_condition(device_pid, config)

      :packet_loss ->
        apply_packet_loss_condition(device_pid, config)

      :snmp_error ->
        apply_snmp_error_condition(device_pid, config)

      :malformed ->
        apply_malformed_condition(device_pid, config)

      :device_failure ->
        apply_device_failure_condition(device_pid, config)

      _ ->
        {:error, {:unknown_error_type, config.type}}
    end
  end

  defp apply_timeout_condition(device_pid, config) do
    # Send timeout configuration to device
    timeout_config = %{
      probability: config.probability,
      duration_ms: config.duration_ms,
      target_oids: config.target_oids
    }

    send(device_pid, {:error_injection, :timeout, timeout_config})
    :ok
  end

  defp apply_packet_loss_condition(device_pid, config) do
    # Send packet loss configuration to device
    loss_config = %{
      loss_rate: config.loss_rate,
      burst_loss: config[:burst_loss] || false,
      burst_size: config[:burst_size] || 5,
      target_oids: config.target_oids
    }

    send(device_pid, {:error_injection, :packet_loss, loss_config})
    :ok
  end

  defp apply_snmp_error_condition(device_pid, config) do
    # Send SNMP error configuration to device
    snmp_config = %{
      error_type: config.snmp_error_type,
      probability: config.probability,
      target_oids: config.target_oids,
      error_index: config[:error_index] || 1
    }

    send(device_pid, {:error_injection, :snmp_error, snmp_config})
    :ok
  end

  defp apply_malformed_condition(device_pid, config) do
    # Send malformed response configuration to device
    malformed_config = %{
      corruption_type: config.corruption_type,
      probability: config.probability,
      corruption_severity: config[:corruption_severity] || 0.5,
      target_oids: config.target_oids
    }

    send(device_pid, {:error_injection, :malformed, malformed_config})
    :ok
  end

  defp apply_device_failure_condition(device_pid, config) do
    # Send device failure configuration to device
    failure_config = %{
      failure_type: config.failure_type,
      duration_ms: config.duration_ms,
      recovery_behavior: config[:recovery_behavior] || :normal,
      failure_probability: config[:failure_probability] || 1.0
    }

    send(device_pid, {:error_injection, :device_failure, failure_config})
    :ok
  end

  defp clear_device_errors(device_pid) do
    send(device_pid, {:error_injection, :clear_all})
    :ok
  end

  defp maybe_schedule_error_timers(config, error_id, current_timers) do
    case config.type do
      :timeout ->
        if Map.get(config, :burst_probability, 0) > 0 do
          schedule_burst_timers(config, error_id, current_timers)
        else
          current_timers
        end

      :packet_loss ->
        if Map.get(config, :burst_loss, false) do
          schedule_burst_timers(config, error_id, current_timers)
        else
          current_timers
        end

      :device_failure ->
        schedule_recovery_timer(config, error_id, current_timers)

      _ ->
        current_timers
    end
  end

  defp schedule_burst_timers(config, error_id, timers) do
    # Schedule burst activation
    burst_interval = Map.get(config, :recovery_time_ms, 30000)

    timer_ref =
      Process.send_after(self(), {:scheduled_error, error_id, :activate_burst}, burst_interval)

    Map.put(timers, error_id, timer_ref)
  end

  defp schedule_recovery_timer(config, error_id, timers) do
    # Schedule device recovery
    timer_ref =
      Process.send_after(
        self(),
        {:scheduled_error, error_id, :device_recovery},
        config.duration_ms
      )

    Map.put(timers, error_id, timer_ref)
  end

  defp handle_burst_activation(error_id, config, state) do
    Logger.debug("Activating burst error for #{error_id}")

    # Update burst state
    updated_burst =
      Map.put(state.burst_state, error_id, %{
        active: true,
        start_time: DateTime.utc_now(),
        packets_affected: 0
      })

    # Schedule burst deactivation
    burst_duration = Map.get(config, :burst_duration_ms, 10000)

    timer_ref =
      Process.send_after(self(), {:scheduled_error, error_id, :deactivate_burst}, burst_duration)

    updated_timers = Map.put(state.schedule_timers, "#{error_id}_deactivate", timer_ref)

    # Update statistics
    updated_stats = %{
      state.error_statistics
      | burst_events: state.error_statistics.burst_events + 1
    }

    new_state = %{
      state
      | burst_state: updated_burst,
        schedule_timers: updated_timers,
        error_statistics: updated_stats
    }

    {:noreply, new_state}
  end

  defp handle_burst_deactivation(error_id, _config, state) do
    Logger.debug("Deactivating burst error for #{error_id}")

    # Remove burst state
    updated_burst = Map.delete(state.burst_state, error_id)

    # Remove deactivation timer
    updated_timers = Map.delete(state.schedule_timers, "#{error_id}_deactivate")

    new_state = %{state | burst_state: updated_burst, schedule_timers: updated_timers}

    {:noreply, new_state}
  end

  defp handle_device_recovery(error_id, config, state) do
    Logger.info("Device recovery from #{config.failure_type} failure")

    # Send recovery message to device
    recovery_config = %{
      failure_type: config.failure_type,
      recovery_behavior: config[:recovery_behavior] || :normal
    }

    send(state.device_pid, {:error_injection, :recovery, recovery_config})

    # Remove error condition
    updated_conditions = Map.delete(state.error_conditions, error_id)
    updated_timers = Map.delete(state.schedule_timers, error_id)

    # Update statistics
    updated_stats = %{
      state.error_statistics
      | device_failures: state.error_statistics.device_failures + 1
    }

    new_state = %{
      state
      | error_conditions: updated_conditions,
        schedule_timers: updated_timers,
        error_statistics: updated_stats
    }

    {:noreply, new_state}
  end
end
