defmodule SnmpSim.Performance.PerformanceMonitor do
  @moduledoc """
  Real-time performance monitoring and telemetry for SNMP simulator.
  Provides comprehensive metrics collection, alerting, and performance analytics.
  Integrates with :telemetry for external monitoring systems.
  """

  use GenServer
  require Logger

  alias SnmpSim.Performance.ResourceManager
  alias SnmpSim.Performance.OptimizedDevicePool

  # Telemetry event names
  @telemetry_prefix [:snmp_sim]
  @device_events [:device, :created] ++ [:device, :destroyed] ++ [:device, :request]
  @performance_events [:performance, :metrics] ++ [:performance, :alert]
  @resource_events [:resource, :usage] ++ [:resource, :limit_exceeded]

  # Monitoring intervals
  # 5 seconds
  @metrics_collection_interval 5_000
  # 30 seconds
  @resource_check_interval 30_000
  # 1 minute
  @performance_report_interval 60_000
  # 5 minutes
  @alert_throttle_interval 300_000

  # Performance thresholds
  @default_thresholds %{
    max_response_time_ms: 10,
    min_throughput_rps: 10_000,
    max_memory_usage_percent: 80,
    max_cpu_usage_percent: 80,
    max_device_count: 10_000,
    min_cache_hit_ratio: 85.0
  }

  defstruct [
    :thresholds,
    :metrics_timer,
    :resource_timer,
    :report_timer,
    :last_alert_times,
    :performance_history,
    :current_metrics,
    :baseline_metrics,
    :alert_callbacks
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current performance metrics snapshot.
  """
  def get_current_metrics() do
    GenServer.call(__MODULE__, :get_current_metrics)
  end

  @doc """
  Get performance history for trend analysis.
  """
  def get_performance_history(duration_minutes \\ 60) do
    GenServer.call(__MODULE__, {:get_performance_history, duration_minutes})
  end

  @doc """
  Update performance thresholds for alerts.
  """
  def update_thresholds(new_thresholds) do
    GenServer.call(__MODULE__, {:update_thresholds, new_thresholds})
  end

  @doc """
  Register callback for performance alerts.
  """
  def register_alert_callback(name, callback_fun) when is_function(callback_fun, 2) do
    GenServer.call(__MODULE__, {:register_alert_callback, name, callback_fun})
  end

  @doc """
  Force immediate performance analysis and reporting.
  """
  def force_performance_analysis() do
    GenServer.call(__MODULE__, :force_performance_analysis)
  end

  @doc """
  Record device request timing for performance tracking.
  """
  def record_request_timing(port, oid, duration_microseconds, success \\ true) do
    # Emit telemetry event
    try do
      :telemetry.execute(
        @telemetry_prefix ++ @device_events,
        %{duration: duration_microseconds, success: if(success, do: 1, else: 0)},
        %{port: port, oid: oid}
      )
    catch
      :error, :undef -> :ok
    end

    GenServer.cast(__MODULE__, {:record_request, port, oid, duration_microseconds, success})
  end

  @doc """
  Record device lifecycle events.
  """
  def record_device_event(event_type, port, device_type)
      when event_type in [:created, :destroyed] do
    try do
      :telemetry.execute(
        @telemetry_prefix ++ [:device, event_type],
        %{count: 1},
        %{port: port, device_type: device_type}
      )
    catch
      :error, :undef -> :ok
    end

    GenServer.cast(__MODULE__, {:device_event, event_type, port, device_type})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    thresholds = Keyword.get(opts, :thresholds, @default_thresholds)

    # Setup telemetry handlers
    setup_telemetry_handlers()

    # Schedule periodic monitoring
    metrics_timer = Process.send_after(self(), :collect_metrics, @metrics_collection_interval)
    resource_timer = Process.send_after(self(), :check_resources, @resource_check_interval)

    report_timer =
      Process.send_after(self(), :generate_performance_report, @performance_report_interval)

    state = %__MODULE__{
      thresholds: thresholds,
      metrics_timer: metrics_timer,
      resource_timer: resource_timer,
      report_timer: report_timer,
      last_alert_times: %{},
      performance_history: :queue.new(),
      current_metrics: initialize_metrics(),
      baseline_metrics: nil,
      alert_callbacks: %{}
    }

    Logger.info("PerformanceMonitor started with thresholds: #{inspect(thresholds)}")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_current_metrics, _from, state) do
    {:reply, state.current_metrics, state}
  end

  @impl true
  def handle_call({:get_performance_history, duration_minutes}, _from, state) do
    cutoff_time = System.monotonic_time(:millisecond) - duration_minutes * 60 * 1000

    history_list = :queue.to_list(state.performance_history)

    filtered_history =
      Enum.filter(history_list, fn {timestamp, _metrics} ->
        timestamp >= cutoff_time
      end)

    {:reply, filtered_history, state}
  end

  @impl true
  def handle_call({:update_thresholds, new_thresholds}, _from, state) do
    merged_thresholds = Map.merge(state.thresholds, new_thresholds)
    Logger.info("Performance thresholds updated: #{inspect(new_thresholds)}")

    {:reply, :ok, %{state | thresholds: merged_thresholds}}
  end

  @impl true
  def handle_call({:register_alert_callback, name, callback_fun}, _from, state) do
    new_callbacks = Map.put(state.alert_callbacks, name, callback_fun)
    Logger.info("Registered alert callback: #{name}")

    {:reply, :ok, %{state | alert_callbacks: new_callbacks}}
  end

  @impl true
  def handle_call(:force_performance_analysis, _from, state) do
    analysis_result = perform_performance_analysis(state.current_metrics, state.thresholds)

    case analysis_result do
      {:alerts, alerts} ->
        handle_performance_alerts(alerts, state.alert_callbacks)
        {:reply, {:alerts_generated, length(alerts)}, state}

      :normal ->
        {:reply, :performance_normal, state}
    end
  end

  @impl true
  def handle_cast({:record_request, port, oid, duration_microseconds, success}, state) do
    new_metrics =
      update_request_metrics(state.current_metrics, port, oid, duration_microseconds, success)

    {:noreply, %{state | current_metrics: new_metrics}}
  end

  @impl true
  def handle_cast({:device_event, event_type, port, device_type}, state) do
    new_metrics = update_device_metrics(state.current_metrics, event_type, port, device_type)
    {:noreply, %{state | current_metrics: new_metrics}}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect comprehensive system metrics
    system_metrics = collect_system_metrics()
    device_pool_metrics = collect_device_pool_metrics()
    resource_metrics = collect_resource_metrics()

    # Merge all metrics
    combined_metrics =
      Map.merge(state.current_metrics, %{
        system: system_metrics,
        device_pool: device_pool_metrics,
        resources: resource_metrics,
        timestamp: System.monotonic_time(:millisecond)
      })

    # Emit telemetry for external monitoring
    emit_performance_telemetry(combined_metrics)

    # Schedule next collection
    metrics_timer = Process.send_after(self(), :collect_metrics, @metrics_collection_interval)

    {:noreply, %{state | current_metrics: combined_metrics, metrics_timer: metrics_timer}}
  end

  @impl true
  def handle_info(:check_resources, state) do
    resource_stats = ResourceManager.get_resource_stats()

    # Check for resource threshold violations
    alerts = check_resource_thresholds(resource_stats, state.thresholds)

    if not Enum.empty?(alerts) do
      handle_resource_alerts(alerts, state.alert_callbacks, state.last_alert_times)
    end

    # Emit resource telemetry
    try do
      :telemetry.execute(
        @telemetry_prefix ++ @resource_events,
        resource_stats,
        %{source: :resource_manager}
      )
    catch
      :error, :undef -> :ok
    end

    # Schedule next check
    resource_timer = Process.send_after(self(), :check_resources, @resource_check_interval)

    {:noreply, %{state | resource_timer: resource_timer}}
  end

  @impl true
  def handle_info(:generate_performance_report, state) do
    # Generate comprehensive performance report
    report = generate_performance_report(state.current_metrics, state.baseline_metrics)

    # Add to performance history
    timestamp = System.monotonic_time(:millisecond)
    new_history = :queue.in({timestamp, state.current_metrics}, state.performance_history)

    # Keep only last 24 hours of history
    pruned_history = prune_old_history(new_history, 24 * 60 * 60 * 1000)

    # Emit performance report telemetry
    try do
      :telemetry.execute(
        @telemetry_prefix ++ [:performance, :report],
        report,
        %{interval_minutes: @performance_report_interval / 60_000}
      )
    catch
      :error, :undef -> :ok
    end

    # Log performance summary
    log_performance_summary(report)

    # Update baseline if this is the first report
    new_baseline = state.baseline_metrics || state.current_metrics

    # Schedule next report
    report_timer =
      Process.send_after(self(), :generate_performance_report, @performance_report_interval)

    {:noreply,
     %{
       state
       | performance_history: pruned_history,
         baseline_metrics: new_baseline,
         report_timer: report_timer
     }}
  end

  # Private functions

  defp setup_telemetry_handlers() do
    # Attach telemetry handlers for external monitoring integration
    try do
      :telemetry.attach_many(
        "snmp-sim-ex-performance-monitor",
        [
          @telemetry_prefix ++ @device_events,
          @telemetry_prefix ++ @performance_events,
          @telemetry_prefix ++ @resource_events
        ],
        &handle_telemetry_event/4,
        %{}
      )
    catch
      :error, :undef ->
        Logger.debug(
          "Telemetry not available, monitoring will continue without external telemetry integration"
        )

        :ok
    end
  end

  defp handle_telemetry_event(event, measurements, metadata, _config) do
    # Handle telemetry events for external monitoring systems
    Logger.debug(
      "Telemetry event: #{inspect(event)} - #{inspect(measurements)} - #{inspect(metadata)}"
    )
  end

  defp initialize_metrics() do
    %{
      requests: %{
        total_count: 0,
        success_count: 0,
        error_count: 0,
        avg_response_time_us: 0,
        max_response_time_us: 0,
        min_response_time_us: :infinity,
        requests_per_second: 0
      },
      devices: %{
        total_created: 0,
        total_destroyed: 0,
        currently_active: 0,
        by_type: %{}
      },
      cache: %{
        hit_count: 0,
        miss_count: 0,
        hit_ratio: 0.0
      },
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp collect_system_metrics() do
    memory_info = :erlang.memory()

    %{
      memory_total_mb: div(memory_info[:total], 1024 * 1024),
      memory_processes_mb: div(memory_info[:processes], 1024 * 1024),
      memory_system_mb: div(memory_info[:system], 1024 * 1024),
      memory_atom_mb: div(memory_info[:atom], 1024 * 1024),
      memory_binary_mb: div(memory_info[:binary], 1024 * 1024),
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      cpu_utilization: get_cpu_utilization(),
      scheduler_utilization: get_scheduler_utilization()
    }
  end

  defp collect_device_pool_metrics() do
    case OptimizedDevicePool.get_performance_stats() do
      stats when is_map(stats) -> stats
      _ -> %{}
    end
  end

  defp collect_resource_metrics() do
    case ResourceManager.get_resource_stats() do
      stats when is_map(stats) -> stats
      _ -> %{}
    end
  end

  # Get the current CPU utilization as a percentage.
  # Returns a float between 0.0 and 100.0
  @spec get_cpu_utilization() :: float()
  defp get_cpu_utilization() do
    if Code.ensure_loaded?(:cpu_sup) and function_exported?(:cpu_sup, :util, 0) do
      try do
        case :cpu_sup.util() do
          # Handle direct percentage value (float or integer)
          percent when is_number(percent) ->
            percent * 1.0

          # Handle any other case
          _ ->
            0.0
        end
      catch
        _, _ -> 0.0
      end
    else
      0.0
    end
  end

  # Estimate scheduler utilization using :erlang.statistics(:scheduler_wall_time)
  defp get_scheduler_utilization() do
    case :erlang.statistics(:scheduler_wall_time) do
      :undefined ->
        nil

      schedulers when is_list(schedulers) ->
        # schedulers is a list of {id, active, total} tuples
        {active, total} =
          Enum.reduce(schedulers, {0, 0}, fn {_id, active, total}, {a_acc, t_acc} ->
            {a_acc + active, t_acc + total}
          end)

        if total > 0 do
          Float.round(active / total * 100, 2)
        else
          0.0
        end
    end
  end

  defp update_request_metrics(current_metrics, _port, _oid, duration_us, success) do
    requests = current_metrics.requests

    new_total = requests.total_count + 1
    new_success = if success, do: requests.success_count + 1, else: requests.success_count
    new_error = if success, do: requests.error_count, else: requests.error_count + 1

    # Update response time statistics
    new_avg = (requests.avg_response_time_us * requests.total_count + duration_us) / new_total
    new_max = max(requests.max_response_time_us, duration_us)

    new_min =
      if requests.min_response_time_us == :infinity do
        duration_us
      else
        min(requests.min_response_time_us, duration_us)
      end

    # Calculate requests per second (simple moving average)
    time_diff_s = (System.monotonic_time(:millisecond) - current_metrics.timestamp) / 1000
    new_rps = if time_diff_s > 0, do: new_total / time_diff_s, else: 0

    new_requests = %{
      requests
      | total_count: new_total,
        success_count: new_success,
        error_count: new_error,
        avg_response_time_us: new_avg,
        max_response_time_us: new_max,
        min_response_time_us: new_min,
        requests_per_second: new_rps
    }

    %{current_metrics | requests: new_requests}
  end

  defp update_device_metrics(current_metrics, event_type, _port, device_type) do
    devices = current_metrics.devices

    {new_created, new_destroyed, new_active} =
      case event_type do
        :created ->
          {devices.total_created + 1, devices.total_destroyed, devices.currently_active + 1}

        :destroyed ->
          {devices.total_created, devices.total_destroyed + 1, devices.currently_active - 1}
      end

    # Update device type counts
    new_by_type =
      Map.update(
        devices.by_type,
        device_type,
        if(event_type == :created, do: 1, else: -1),
        &(&1 + if(event_type == :created, do: 1, else: -1))
      )

    new_devices = %{
      devices
      | total_created: new_created,
        total_destroyed: new_destroyed,
        currently_active: new_active,
        by_type: new_by_type
    }

    %{current_metrics | devices: new_devices}
  end

  defp emit_performance_telemetry(metrics) do
    try do
      :telemetry.execute(
        @telemetry_prefix ++ @performance_events,
        %{
          response_time_avg: metrics.requests.avg_response_time_us,
          response_time_max: metrics.requests.max_response_time_us,
          requests_per_second: metrics.requests.requests_per_second,
          success_ratio: calculate_success_ratio(metrics.requests),
          memory_usage_mb: metrics.system.memory_total_mb,
          device_count: metrics.devices.currently_active
        },
        %{source: :performance_monitor}
      )
    catch
      :error, :undef ->
        Logger.debug("Telemetry not available, skipping telemetry emission")
        :ok
    end
  end

  defp calculate_success_ratio(requests) do
    if requests.total_count > 0 do
      requests.success_count / requests.total_count * 100
    else
      100.0
    end
  end

  defp check_resource_thresholds(resource_stats, thresholds) do
    alerts = []

    # Check device count threshold
    alerts =
      if resource_stats.device_count > thresholds.max_device_count do
        [
          {:device_count_exceeded, resource_stats.device_count, thresholds.max_device_count}
          | alerts
        ]
      else
        alerts
      end

    # Check memory threshold
    memory_percent = resource_stats.memory_utilization * 100

    alerts =
      if memory_percent > thresholds.max_memory_usage_percent do
        [{:memory_usage_exceeded, memory_percent, thresholds.max_memory_usage_percent} | alerts]
      else
        alerts
      end

    alerts
  end

  defp perform_performance_analysis(metrics, thresholds) do
    alerts = []

    # Check response time threshold
    avg_response_ms = metrics.requests.avg_response_time_us / 1000

    alerts =
      if avg_response_ms > thresholds.max_response_time_ms do
        [{:response_time_exceeded, avg_response_ms, thresholds.max_response_time_ms} | alerts]
      else
        alerts
      end

    # Check throughput threshold
    alerts =
      if metrics.requests.requests_per_second < thresholds.min_throughput_rps do
        [
          {:throughput_below_threshold, metrics.requests.requests_per_second,
           thresholds.min_throughput_rps}
          | alerts
        ]
      else
        alerts
      end

    if Enum.empty?(alerts) do
      :normal
    else
      {:alerts, alerts}
    end
  end

  defp handle_performance_alerts(alerts, alert_callbacks) do
    Enum.each(alerts, fn alert ->
      Logger.warning("Performance alert: #{inspect(alert)}")

      # Execute registered callbacks
      Enum.each(alert_callbacks, fn {name, callback_fun} ->
        try do
          callback_fun.(:performance_alert, alert)
        rescue
          error ->
            Logger.error("Alert callback #{name} failed: #{inspect(error)}")
        end
      end)
    end)
  end

  defp handle_resource_alerts(alerts, alert_callbacks, last_alert_times) do
    current_time = System.monotonic_time(:millisecond)

    Enum.each(alerts, fn alert ->
      alert_key = elem(alert, 0)

      # Throttle alerts to prevent spam
      if should_send_alert?(alert_key, current_time, last_alert_times) do
        Logger.warning("Resource alert: #{inspect(alert)}")

        # Execute registered callbacks
        Enum.each(alert_callbacks, fn {name, callback_fun} ->
          try do
            callback_fun.(:resource_alert, alert)
          rescue
            error ->
              Logger.error("Alert callback #{name} failed: #{inspect(error)}")
          end
        end)
      end
    end)
  end

  defp should_send_alert?(alert_key, current_time, last_alert_times) do
    case Map.get(last_alert_times, alert_key) do
      nil -> true
      last_time -> current_time - last_time > @alert_throttle_interval
    end
  end

  defp generate_performance_report(current_metrics, baseline_metrics) do
    %{
      timestamp: current_metrics.timestamp,
      requests: current_metrics.requests,
      devices: current_metrics.devices,
      system: current_metrics.system,
      trends: calculate_trends(current_metrics, baseline_metrics),
      health_score: calculate_health_score(current_metrics)
    }
  end

  defp calculate_trends(current_metrics, baseline_metrics) do
    if baseline_metrics do
      %{
        response_time_trend:
          trend_percentage(
            current_metrics.requests.avg_response_time_us,
            baseline_metrics.requests.avg_response_time_us
          ),
        throughput_trend:
          trend_percentage(
            current_metrics.requests.requests_per_second,
            baseline_metrics.requests.requests_per_second
          ),
        device_count_trend:
          trend_percentage(
            current_metrics.devices.currently_active,
            baseline_metrics.devices.currently_active
          ),
        memory_trend:
          trend_percentage(
            current_metrics.system.memory_total_mb,
            baseline_metrics.system.memory_total_mb
          )
      }
    else
      %{}
    end
  end

  defp trend_percentage(current, baseline) when baseline > 0 do
    Float.round((current - baseline) / baseline * 100, 2)
  end

  defp trend_percentage(_, _), do: 0.0

  defp calculate_health_score(metrics) do
    # Simple health score based on key metrics
    success_ratio = calculate_success_ratio(metrics.requests)
    response_time_score = min(100, 10000 / max(1, metrics.requests.avg_response_time_us) * 100)

    # Combine scores (weighted average)
    Float.round(success_ratio * 0.5 + response_time_score * 0.5, 1)
  end

  defp prune_old_history(history_queue, max_age_ms) do
    cutoff_time = System.monotonic_time(:millisecond) - max_age_ms

    :queue.filter(
      fn {timestamp, _metrics} ->
        timestamp >= cutoff_time
      end,
      history_queue
    )
  end

  defp log_performance_summary(report) do
    Logger.info(
      "Performance Report - " <>
        "RPS: #{Float.round(report.requests.requests_per_second, 1)}, " <>
        "Avg Response: #{Float.round(report.requests.avg_response_time_us / 1000, 2)}ms, " <>
        "Devices: #{report.devices.currently_active}, " <>
        "Memory: #{report.system.memory_total_mb}MB, " <>
        "Health: #{report.health_score}%"
    )
  end
end
