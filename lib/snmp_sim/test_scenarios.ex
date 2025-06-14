defmodule SnmpSim.TestScenarios do
  @moduledoc """
  Pre-built test scenarios for common network conditions.

  Simplify complex error injection patterns with realistic network scenarios
  that test SNMP polling systems under various failure conditions.

  ## Scenario Categories

  - **Network Outages**: Complete connectivity loss and recovery patterns
  - **Signal Degradation**: DOCSIS/wireless signal quality issues  
  - **High Load**: Network congestion and overload conditions
  - **Device Failures**: Equipment failures, reboots, and recovery
  - **Intermittent Issues**: Flapping, sporadic failures, timing issues
  - **Environmental**: Weather, power, temperature-related problems

  ## Usage

      # Apply network outage scenario to all devices
      TestScenarios.network_outage_scenario(devices, duration_seconds: 300)
      
      # Simulate signal degradation for cable modems
      TestScenarios.signal_degradation_scenario(cable_modems, 
        snr_degradation: 10, duration_minutes: 15
      )
      
      # Test high load conditions
      TestScenarios.high_load_scenario(devices, utilization_percent: 95)
      
  """

  require Logger
  alias SnmpSim.ErrorInjector

  @type device_list :: list(pid()) | list({:device_type, integer()})
  @type scenario_result :: %{
          scenario_id: String.t(),
          start_time: DateTime.t(),
          devices_affected: integer(),
          conditions_applied: list(map()),
          estimated_duration_ms: integer()
        }

  ## Network Outage Scenarios

  @doc """
  Simulate complete network outage affecting all devices.

  Tests poller behavior during total connectivity loss and recovery.

  ## Options

  - `duration_seconds`: Outage duration (default: 300)
  - `recovery_type`: `:immediate` | `:gradual` | `:sporadic` (default: :gradual)
  - `affected_percentage`: Percentage of devices affected (default: 1.0)

  ## Examples

      # 5-minute complete outage
      TestScenarios.network_outage_scenario(devices, duration_seconds: 300)
      
      # Gradual recovery affecting 80% of devices
      TestScenarios.network_outage_scenario(devices,
        duration_seconds: 600,
        recovery_type: :gradual,
        affected_percentage: 0.8
      )
      
  """
  @spec network_outage_scenario(device_list(), keyword()) :: scenario_result()
  def network_outage_scenario(devices, opts \\ []) do
    duration_seconds = Keyword.get(opts, :duration_seconds, 300)
    recovery_type = Keyword.get(opts, :recovery_type, :gradual)
    affected_percentage = Keyword.get(opts, :affected_percentage, 1.0)

    scenario_id = generate_scenario_id("network_outage")
    Logger.info("Starting network outage scenario #{scenario_id} for #{length(devices)} devices")

    # Select affected devices
    affected_devices = select_affected_devices(devices, affected_percentage)

    # Apply outage conditions
    conditions =
      case recovery_type do
        :immediate ->
          apply_immediate_outage(affected_devices, duration_seconds)

        :gradual ->
          apply_gradual_outage(affected_devices, duration_seconds)

        :sporadic ->
          apply_sporadic_outage(affected_devices, duration_seconds)
      end

    %{
      scenario_id: scenario_id,
      start_time: DateTime.utc_now(),
      devices_affected: length(affected_devices),
      conditions_applied: conditions,
      estimated_duration_ms: duration_seconds * 1000
    }
  end

  @doc """
  Simulate signal degradation for wireless/cable devices.

  Models weather-related signal issues, interference, or equipment problems.

  ## Options

  - `snr_degradation`: SNR reduction in dB (default: 5)
  - `power_variation`: Power level variation in dBmV (default: 3)
  - `duration_minutes`: Degradation duration (default: 30)
  - `pattern`: `:steady` | `:fluctuating` | `:progressive` (default: :fluctuating)

  ## Examples

      # Weather-related signal degradation
      TestScenarios.signal_degradation_scenario(cable_modems,
        snr_degradation: 10,
        power_variation: 5,
        duration_minutes: 45,
        pattern: :progressive
      )
      
  """
  @spec signal_degradation_scenario(device_list(), keyword()) :: scenario_result()
  def signal_degradation_scenario(devices, opts \\ []) do
    snr_degradation = Keyword.get(opts, :snr_degradation, 5)
    power_variation = Keyword.get(opts, :power_variation, 3)
    duration_minutes = Keyword.get(opts, :duration_minutes, 30)
    pattern = Keyword.get(opts, :pattern, :fluctuating)

    scenario_id = generate_scenario_id("signal_degradation")
    Logger.info("Starting signal degradation scenario #{scenario_id}")

    conditions =
      apply_signal_degradation(devices, %{
        snr_degradation: snr_degradation,
        power_variation: power_variation,
        duration_ms: duration_minutes * 60 * 1000,
        pattern: pattern
      })

    %{
      scenario_id: scenario_id,
      start_time: DateTime.utc_now(),
      devices_affected: length(devices),
      conditions_applied: conditions,
      estimated_duration_ms: duration_minutes * 60 * 1000
    }
  end

  @doc """
  Simulate high network load and congestion conditions.

  Tests poller behavior under network stress with increased latency,
  packet loss, and timeout conditions.

  ## Options

  - `utilization_percent`: Network utilization level (default: 85)
  - `duration_minutes`: Load duration (default: 60)
  - `congestion_type`: `:steady` | `:bursty` | `:cascade` (default: :bursty)
  - `error_rate_multiplier`: Error rate increase factor (default: 5.0)

  ## Examples

      # Sustained high load
      TestScenarios.high_load_scenario(devices,
        utilization_percent: 95,
        duration_minutes: 120,
        congestion_type: :steady
      )
      
      # Bursty congestion with high error rates
      TestScenarios.high_load_scenario(devices,
        utilization_percent: 90,
        congestion_type: :bursty,
        error_rate_multiplier: 10.0
      )
      
  """
  @spec high_load_scenario(device_list(), keyword()) :: scenario_result()
  def high_load_scenario(devices, opts \\ []) do
    utilization_percent = Keyword.get(opts, :utilization_percent, 85)
    duration_minutes = Keyword.get(opts, :duration_minutes, 60)
    congestion_type = Keyword.get(opts, :congestion_type, :bursty)
    error_rate_multiplier = Keyword.get(opts, :error_rate_multiplier, 5.0)

    scenario_id = generate_scenario_id("high_load")

    Logger.info(
      "Starting high load scenario #{scenario_id} with #{utilization_percent}% utilization"
    )

    conditions =
      apply_high_load_conditions(devices, %{
        utilization_percent: utilization_percent,
        duration_ms: duration_minutes * 60 * 1000,
        congestion_type: congestion_type,
        error_rate_multiplier: error_rate_multiplier
      })

    %{
      scenario_id: scenario_id,
      start_time: DateTime.utc_now(),
      devices_affected: length(devices),
      conditions_applied: conditions,
      estimated_duration_ms: duration_minutes * 60 * 1000
    }
  end

  @doc """
  Simulate device flapping - intermittent connectivity issues.

  Models unstable devices that repeatedly go offline and come back online.

  ## Options

  - `flap_interval_seconds`: Time between state changes (default: 30)
  - `down_duration_seconds`: How long device stays down (default: 10)
  - `total_duration_minutes`: Total scenario duration (default: 30)
  - `flap_pattern`: `:regular` | `:irregular` | `:degrading` (default: :irregular)

  ## Examples

      # Regular flapping every 60 seconds
      TestScenarios.device_flapping_scenario(devices,
        flap_interval_seconds: 60,
        down_duration_seconds: 15,
        flap_pattern: :regular
      )
      
      # Irregular flapping with degrading stability
      TestScenarios.device_flapping_scenario(devices,
        flap_pattern: :degrading,
        total_duration_minutes: 45
      )
      
  """
  @spec device_flapping_scenario(device_list(), keyword()) :: scenario_result()
  def device_flapping_scenario(devices, opts \\ []) do
    flap_interval_seconds = Keyword.get(opts, :flap_interval_seconds, 30)
    down_duration_seconds = Keyword.get(opts, :down_duration_seconds, 10)
    total_duration_minutes = Keyword.get(opts, :total_duration_minutes, 30)
    flap_pattern = Keyword.get(opts, :flap_pattern, :irregular)

    scenario_id = generate_scenario_id("device_flapping")
    Logger.info("Starting device flapping scenario #{scenario_id}")

    conditions =
      apply_flapping_conditions(devices, %{
        flap_interval_seconds: flap_interval_seconds,
        down_duration_seconds: down_duration_seconds,
        total_duration_ms: total_duration_minutes * 60 * 1000,
        flap_pattern: flap_pattern
      })

    %{
      scenario_id: scenario_id,
      start_time: DateTime.utc_now(),
      devices_affected: length(devices),
      conditions_applied: conditions,
      estimated_duration_ms: total_duration_minutes * 60 * 1000
    }
  end

  @doc """
  Simulate cascading failure - devices fail in sequence.

  Models scenarios where initial failures trigger subsequent failures,
  testing system resilience under escalating conditions.

  ## Options

  - `initial_failure_percentage`: Initial devices that fail (default: 0.1)
  - `cascade_delay_seconds`: Time between cascade waves (default: 60)
  - `cascade_growth_factor`: How much each wave grows (default: 1.5)
  - `max_affected_percentage`: Maximum devices affected (default: 0.8)

  ## Examples

      # Start with 5% failure, cascade every 30 seconds
      TestScenarios.cascading_failure_scenario(devices,
        initial_failure_percentage: 0.05,
        cascade_delay_seconds: 30,
        cascade_growth_factor: 2.0
      )
      
  """
  @spec cascading_failure_scenario(device_list(), keyword()) :: scenario_result()
  def cascading_failure_scenario(devices, opts \\ []) do
    initial_failure_percentage = Keyword.get(opts, :initial_failure_percentage, 0.1)
    cascade_delay_seconds = Keyword.get(opts, :cascade_delay_seconds, 60)
    cascade_growth_factor = Keyword.get(opts, :cascade_growth_factor, 1.5)
    max_affected_percentage = Keyword.get(opts, :max_affected_percentage, 0.8)

    scenario_id = generate_scenario_id("cascading_failure")
    Logger.info("Starting cascading failure scenario #{scenario_id}")

    conditions =
      apply_cascading_failure(devices, %{
        initial_failure_percentage: initial_failure_percentage,
        cascade_delay_seconds: cascade_delay_seconds,
        cascade_growth_factor: cascade_growth_factor,
        max_affected_percentage: max_affected_percentage
      })

    estimated_duration =
      calculate_cascade_duration(
        length(devices),
        initial_failure_percentage,
        cascade_growth_factor,
        max_affected_percentage,
        cascade_delay_seconds
      )

    %{
      scenario_id: scenario_id,
      start_time: DateTime.utc_now(),
      devices_affected: length(devices),
      conditions_applied: conditions,
      estimated_duration_ms: estimated_duration * 1000
    }
  end

  @doc """
  Simulate environmental conditions affecting network equipment.

  Models weather, power, or temperature-related issues that affect
  multiple devices simultaneously.

  ## Options

  - `condition_type`: `:weather` | `:power` | `:temperature` | `:interference`
  - `severity`: `:mild` | `:moderate` | `:severe` (default: :moderate)
  - `duration_hours`: Condition duration (default: 2)
  - `geographic_pattern`: `:random` | `:clustered` | `:linear` (default: :clustered)

  ## Examples

      # Severe weather affecting clustered devices
      TestScenarios.environmental_scenario(devices,
        condition_type: :weather,
        severity: :severe,
        duration_hours: 4,
        geographic_pattern: :clustered
      )
      
      # Power instability
      TestScenarios.environmental_scenario(devices,
        condition_type: :power,
        severity: :moderate,
        duration_hours: 1
      )
      
  """
  @spec environmental_scenario(device_list(), keyword()) :: scenario_result()
  def environmental_scenario(devices, opts \\ []) do
    condition_type = Keyword.get(opts, :condition_type, :weather)
    severity = Keyword.get(opts, :severity, :moderate)
    duration_hours = Keyword.get(opts, :duration_hours, 2)
    geographic_pattern = Keyword.get(opts, :geographic_pattern, :clustered)

    scenario_id = generate_scenario_id("environmental_#{condition_type}")
    Logger.info("Starting environmental scenario #{scenario_id}: #{condition_type} - #{severity}")

    conditions =
      apply_environmental_conditions(devices, %{
        condition_type: condition_type,
        severity: severity,
        duration_ms: duration_hours * 60 * 60 * 1000,
        geographic_pattern: geographic_pattern
      })

    %{
      scenario_id: scenario_id,
      start_time: DateTime.utc_now(),
      devices_affected: length(devices),
      conditions_applied: conditions,
      estimated_duration_ms: duration_hours * 60 * 60 * 1000
    }
  end

  @doc """
  Apply multiple scenarios simultaneously for complex testing.

  Combines different failure patterns to test system behavior under
  realistic multi-factor conditions.

  ## Examples

      scenarios = [
        {:signal_degradation, [snr_degradation: 8, duration_minutes: 60]},
        {:high_load, [utilization_percent: 90, duration_minutes: 45]},
        {:device_flapping, [flap_interval_seconds: 120]}
      ]
      
      TestScenarios.multi_scenario_test(devices, scenarios)
      
  """
  @spec multi_scenario_test(device_list(), list({atom(), keyword()})) :: list(scenario_result())
  def multi_scenario_test(devices, scenarios) do
    multi_scenario_id = generate_scenario_id("multi_scenario")

    Logger.info(
      "Starting multi-scenario test #{multi_scenario_id} with #{length(scenarios)} scenarios"
    )

    # Apply scenarios with staggered start times
    Enum.with_index(scenarios)
    |> Enum.map(fn {{scenario_type, opts}, index} ->
      # Stagger scenario starts by 30 seconds each
      start_delay = index * 30 * 1000

      Process.send_after(self(), {:start_scenario, scenario_type, devices, opts}, start_delay)

      # Return immediate result placeholder
      %{
        scenario_id: "#{multi_scenario_id}_#{scenario_type}_#{index}",
        start_time: DateTime.add(DateTime.utc_now(), start_delay, :millisecond),
        devices_affected: length(devices),
        conditions_applied: [],
        estimated_duration_ms: Keyword.get(opts, :duration_seconds, 600) * 1000
      }
    end)
  end

  ## Scenario Application Functions

  defp apply_immediate_outage(devices, duration_seconds) do
    Enum.map(devices, fn device ->
      # Complete packet loss for duration
      {:ok, injector} = ErrorInjector.start_link(device, get_device_port(device))
      ErrorInjector.inject_packet_loss(injector, loss_rate: 1.0)

      # Schedule recovery
      Process.send_after(self(), {:recover_device, injector}, duration_seconds * 1000)

      %{
        device: device,
        condition: :complete_outage,
        injector: injector,
        recovery_time: DateTime.add(DateTime.utc_now(), duration_seconds, :second)
      }
    end)
  end

  defp apply_gradual_outage(devices, duration_seconds) do
    # Devices fail and recover at different times
    # 30% spread in recovery times
    recovery_spread = duration_seconds * 0.3

    Enum.with_index(devices)
    |> Enum.map(fn {device, index} ->
      {:ok, injector} = ErrorInjector.start_link(device, get_device_port(device))

      # Stagger outage start
      # 5 seconds between failures
      outage_delay = index * 5 * 1000
      Process.send_after(self(), {:start_outage, injector}, outage_delay)

      # Stagger recovery
      base_recovery = duration_seconds * 1000
      recovery_variation = trunc(recovery_spread * 1000 * (:rand.uniform() - 0.5))
      recovery_time = base_recovery + recovery_variation
      Process.send_after(self(), {:recover_device, injector}, recovery_time)

      %{
        device: device,
        condition: :gradual_outage,
        injector: injector,
        outage_delay_ms: outage_delay,
        recovery_time: DateTime.add(DateTime.utc_now(), recovery_time, :millisecond)
      }
    end)
  end

  defp apply_sporadic_outage(devices, duration_seconds) do
    # Devices have intermittent connectivity
    Enum.map(devices, fn device ->
      {:ok, injector} = ErrorInjector.start_link(device, get_device_port(device))

      # Random packet loss with bursts
      ErrorInjector.inject_packet_loss(injector,
        loss_rate: 0.3,
        burst_loss: true,
        burst_size: 10,
        recovery_time_ms: 15000
      )

      # Add occasional timeouts
      ErrorInjector.inject_timeout(injector,
        probability: 0.4,
        duration_ms: 8000,
        burst_probability: 0.2
      )

      # Schedule complete recovery
      Process.send_after(self(), {:recover_device, injector}, duration_seconds * 1000)

      %{
        device: device,
        condition: :sporadic_outage,
        injector: injector,
        recovery_time: DateTime.add(DateTime.utc_now(), duration_seconds, :second)
      }
    end)
  end

  defp apply_signal_degradation(devices, config) do
    Enum.map(devices, fn device ->
      {:ok, injector} = ErrorInjector.start_link(device, get_device_port(device))

      case config.pattern do
        :steady ->
          # Constant degradation
          apply_steady_signal_degradation(injector, config)

        :fluctuating ->
          # Variable signal quality
          apply_fluctuating_signal_degradation(injector, config)

        :progressive ->
          # Gradually worsening signal
          apply_progressive_signal_degradation(injector, config)
      end

      %{
        device: device,
        condition: :signal_degradation,
        pattern: config.pattern,
        injector: injector
      }
    end)
  end

  defp apply_steady_signal_degradation(injector, _config) do
    # Increase error rates due to poor signal
    ErrorInjector.inject_snmp_error(injector, :genErr,
      probability: 0.1,
      target_oids: :all
    )

    # Occasional timeouts from poor connectivity
    ErrorInjector.inject_timeout(injector,
      probability: 0.05,
      duration_ms: 3000
    )
  end

  defp apply_fluctuating_signal_degradation(injector, _config) do
    # Variable packet loss
    ErrorInjector.inject_packet_loss(injector,
      loss_rate: 0.08,
      burst_loss: true,
      burst_size: 3,
      recovery_time_ms: 20000
    )

    # Intermittent timeouts
    ErrorInjector.inject_timeout(injector,
      probability: 0.15,
      duration_ms: 5000,
      burst_probability: 0.3
    )
  end

  defp apply_progressive_signal_degradation(injector, config) do
    # Start with mild issues, progressively worsen
    duration_ms = config.duration_ms

    # Phase 1: Mild degradation (first third)
    ErrorInjector.inject_packet_loss(injector,
      loss_rate: 0.02
    )

    # Schedule Phase 2: Moderate degradation
    phase2_delay = div(duration_ms, 3)
    Process.send_after(self(), {:escalate_degradation, injector, :moderate}, phase2_delay)

    # Schedule Phase 3: Severe degradation
    phase3_delay = div(duration_ms * 2, 3)
    Process.send_after(self(), {:escalate_degradation, injector, :severe}, phase3_delay)
  end

  defp apply_high_load_conditions(devices, config) do
    Enum.map(devices, fn device ->
      {:ok, injector} = ErrorInjector.start_link(device, get_device_port(device))

      case config.congestion_type do
        :steady ->
          apply_steady_high_load(injector, config)

        :bursty ->
          apply_bursty_high_load(injector, config)

        :cascade ->
          apply_cascade_high_load(injector, config)
      end

      %{
        device: device,
        condition: :high_load,
        type: config.congestion_type,
        injector: injector
      }
    end)
  end

  defp apply_steady_high_load(injector, config) do
    # Sustained high latency
    ErrorInjector.inject_timeout(injector,
      probability: 0.2,
      duration_ms: 2000
    )

    # Increased error rates
    ErrorInjector.inject_snmp_error(injector, :genErr,
      probability: 0.05 * config.error_rate_multiplier
    )
  end

  defp apply_bursty_high_load(injector, _config) do
    # Burst packet loss
    ErrorInjector.inject_packet_loss(injector,
      loss_rate: 0.1,
      burst_loss: true,
      burst_size: 8,
      recovery_time_ms: 10000
    )

    # Burst timeouts
    ErrorInjector.inject_timeout(injector,
      probability: 0.3,
      duration_ms: 5000,
      burst_probability: 0.4,
      burst_duration_ms: 20000
    )
  end

  defp apply_cascade_high_load(injector, _config) do
    # Progressively worsening conditions
    # 1 minute intervals
    base_delay = 60000

    # Schedule escalating load conditions
    for phase <- 1..5 do
      delay = phase * base_delay
      Process.send_after(self(), {:escalate_load, injector, phase}, delay)
    end
  end

  defp apply_flapping_conditions(devices, config) do
    Enum.with_index(devices)
    |> Enum.map(fn {device, index} ->
      {:ok, injector} = ErrorInjector.start_link(device, get_device_port(device))

      case config.flap_pattern do
        :regular ->
          apply_regular_flapping(injector, config, index)

        :irregular ->
          apply_irregular_flapping(injector, config, index)

        :degrading ->
          apply_degrading_flapping(injector, config, index)
      end

      %{
        device: device,
        condition: :flapping,
        pattern: config.flap_pattern,
        injector: injector
      }
    end)
  end

  defp apply_regular_flapping(injector, config, _index) do
    # Predictable on/off cycles
    flap_interval = config.flap_interval_seconds * 1000
    down_duration = config.down_duration_seconds * 1000

    schedule_flap_cycle(injector, flap_interval, down_duration, config.total_duration_ms)
  end

  defp apply_irregular_flapping(injector, config, index) do
    # Random flapping with some devices more unstable
    base_interval = config.flap_interval_seconds * 1000
    # Stagger devices and add randomness
    variation = trunc(base_interval * (0.5 + :rand.uniform() * 1.0))
    actual_interval = base_interval + variation + index * 5000

    down_duration = config.down_duration_seconds * 1000
    down_variation = trunc(down_duration * (0.5 + :rand.uniform()))
    actual_down = down_duration + down_variation

    schedule_flap_cycle(injector, actual_interval, actual_down, config.total_duration_ms)
  end

  defp apply_degrading_flapping(injector, config, index) do
    # Flapping becomes more frequent over time
    initial_interval = config.flap_interval_seconds * 1000

    # Start flapping, then accelerate
    schedule_degrading_flaps(
      injector,
      initial_interval,
      config.down_duration_seconds * 1000,
      config.total_duration_ms,
      index
    )
  end

  defp apply_cascading_failure(devices, config) do
    total_devices = length(devices)
    initial_count = trunc(total_devices * config.initial_failure_percentage)
    max_affected = trunc(total_devices * config.max_affected_percentage)

    # Start with initial failures
    {initial_devices, remaining_devices} = Enum.split(devices, initial_count)

    conditions =
      Enum.map(initial_devices, fn device ->
        {:ok, injector} = ErrorInjector.start_link(device, get_device_port(device))
        ErrorInjector.simulate_device_failure(injector, :power_failure, duration_ms: 5000)

        %{device: device, condition: :cascade_failure, wave: 1, injector: injector}
      end)

    # Schedule cascade waves
    schedule_cascade_waves(remaining_devices, config, initial_count, max_affected, 1)

    conditions
  end

  defp apply_environmental_conditions(devices, config) do
    affected_devices =
      case config.geographic_pattern do
        :random ->
          Enum.shuffle(devices)

        :clustered ->
          # Simulate geographic clustering
          cluster_size = div(length(devices), 3)
          Enum.take(devices, cluster_size)

        :linear ->
          # Simulate linear progression (like weather front)
          devices
      end

    Enum.with_index(affected_devices)
    |> Enum.map(fn {device, index} ->
      {:ok, injector} = ErrorInjector.start_link(device, get_device_port(device))

      apply_environmental_effects(injector, config, index)

      %{
        device: device,
        condition: :environmental,
        type: config.condition_type,
        severity: config.severity,
        injector: injector
      }
    end)
  end

  defp apply_environmental_effects(injector, config, index) do
    case {config.condition_type, config.severity} do
      {:weather, :mild} ->
        ErrorInjector.inject_packet_loss(injector, loss_rate: 0.02)

      {:weather, :moderate} ->
        ErrorInjector.inject_packet_loss(injector, loss_rate: 0.08)
        ErrorInjector.inject_timeout(injector, probability: 0.1, duration_ms: 3000)

      {:weather, :severe} ->
        ErrorInjector.inject_packet_loss(injector, loss_rate: 0.25)
        ErrorInjector.inject_timeout(injector, probability: 0.3, duration_ms: 8000)
        ErrorInjector.inject_snmp_error(injector, :genErr, probability: 0.15)

      {:power, severity} ->
        apply_power_effects(injector, severity, index)

      {:temperature, severity} ->
        apply_temperature_effects(injector, severity, index)

      {:interference, severity} ->
        apply_interference_effects(injector, severity, index)
    end
  end

  ## Helper Functions

  defp generate_scenario_id(scenario_type) do
    timestamp = :os.system_time(:millisecond)
    random_suffix = :rand.uniform(1000)
    "#{scenario_type}_#{timestamp}_#{random_suffix}"
  end

  defp select_affected_devices(devices, percentage) do
    count = trunc(length(devices) * percentage)

    devices
    |> Enum.shuffle()
    |> Enum.take(count)
  end

  defp get_device_port(device_pid) when is_pid(device_pid) do
    # Get port from device process (would need device state access)
    # For now, generate a port based on pid
    pid_hash = :erlang.phash2(device_pid)
    30000 + rem(pid_hash, 10000)
  end

  defp get_device_port({:device_type, port}) when is_integer(port) do
    port
  end

  defp calculate_cascade_duration(
         total_devices,
         initial_percentage,
         growth_factor,
         max_percentage,
         delay_seconds
       ) do
    initial_count = trunc(total_devices * initial_percentage)
    max_count = trunc(total_devices * max_percentage)

    # Calculate waves needed
    waves = calculate_cascade_waves(initial_count, max_count, growth_factor)
    waves * delay_seconds
  end

  defp calculate_cascade_waves(current_count, max_count, _growth_factor)
       when current_count >= max_count do
    0
  end

  defp calculate_cascade_waves(current_count, max_count, growth_factor) do
    next_count = trunc(current_count * growth_factor)
    # Ensure we always make progress to prevent infinite loops
    next_count = max(next_count, current_count + 1)
    1 + calculate_cascade_waves(next_count, max_count, growth_factor)
  end

  defp schedule_flap_cycle(injector, interval, down_duration, total_duration)
       when total_duration > 0 do
    # Schedule device to go down
    Process.send_after(self(), {:flap_down, injector}, interval)

    # Schedule device to come back up
    Process.send_after(self(), {:flap_up, injector}, interval + down_duration)

    # Schedule next cycle
    next_total = total_duration - interval - down_duration

    if next_total > interval do
      Process.send_after(
        self(),
        {:schedule_next_flap, injector, interval, down_duration, next_total},
        interval + down_duration
      )
    end
  end

  defp schedule_flap_cycle(_injector, _interval, _down_duration, _total_duration), do: :ok

  defp schedule_degrading_flaps(
         injector,
         current_interval,
         down_duration,
         remaining_duration,
         wave
       ) do
    if remaining_duration > current_interval do
      # Schedule this flap
      Process.send_after(self(), {:flap_down, injector}, current_interval)
      Process.send_after(self(), {:flap_up, injector}, current_interval + down_duration)

      # Schedule next flap with shorter interval (degrading)
      # 20% faster each time
      next_interval = trunc(current_interval * 0.8)
      next_remaining = remaining_duration - current_interval - down_duration

      Process.send_after(
        self(),
        {:schedule_degrading_flap, injector, next_interval, down_duration, next_remaining,
         wave + 1},
        current_interval + down_duration
      )
    end
  end

  defp schedule_cascade_waves(_remaining_devices, _config, current_count, max_affected, _wave)
       when current_count >= max_affected do
    :ok
  end

  defp schedule_cascade_waves(remaining_devices, config, current_count, max_affected, wave) do
    next_count = trunc(current_count * config.cascade_growth_factor)
    devices_to_fail = min(next_count - current_count, length(remaining_devices))

    if devices_to_fail > 0 do
      delay = wave * config.cascade_delay_seconds * 1000

      Process.send_after(
        self(),
        {:cascade_wave, remaining_devices, devices_to_fail, wave + 1},
        delay
      )

      # Schedule next wave
      {_failed, next_remaining} = Enum.split(remaining_devices, devices_to_fail)
      schedule_cascade_waves(next_remaining, config, next_count, max_affected, wave + 1)
    end
  end

  defp apply_power_effects(injector, :mild, _index) do
    # Brief power fluctuations
    ErrorInjector.inject_timeout(injector, probability: 0.05, duration_ms: 1000)
  end

  defp apply_power_effects(injector, :moderate, index) do
    # Intermittent power issues
    ErrorInjector.inject_timeout(injector, probability: 0.15, duration_ms: 3000)

    # Stagger some device reboots
    # 10 seconds apart
    reboot_delay = index * 10000
    Process.send_after(self(), {:schedule_reboot, injector}, reboot_delay)
  end

  defp apply_power_effects(injector, :severe, _index) do
    # Major power instability
    ErrorInjector.inject_packet_loss(injector, loss_rate: 0.4)
    ErrorInjector.simulate_device_failure(injector, :power_failure, duration_ms: 3000)
  end

  defp apply_temperature_effects(injector, severity, _index) do
    case severity do
      :mild ->
        ErrorInjector.inject_snmp_error(injector, :genErr, probability: 0.02)

      :moderate ->
        ErrorInjector.inject_snmp_error(injector, :genErr, probability: 0.08)
        ErrorInjector.inject_timeout(injector, probability: 0.1, duration_ms: 2000)

      :severe ->
        ErrorInjector.inject_packet_loss(injector, loss_rate: 0.15)
        ErrorInjector.simulate_device_failure(injector, :overload, duration_ms: 4000)
    end
  end

  defp apply_interference_effects(injector, severity, _index) do
    case severity do
      :mild ->
        ErrorInjector.inject_packet_loss(injector, loss_rate: 0.03)

      :moderate ->
        ErrorInjector.inject_packet_loss(injector,
          loss_rate: 0.12,
          burst_loss: true,
          burst_size: 5
        )

      :severe ->
        ErrorInjector.inject_packet_loss(injector,
          loss_rate: 0.3,
          burst_loss: true,
          burst_size: 15,
          recovery_time_ms: 5000
        )
    end
  end
end
