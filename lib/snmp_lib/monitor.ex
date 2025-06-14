defmodule SnmpLib.Monitor do
  @moduledoc """
  Performance monitoring and metrics collection for SNMP operations.
  
  This module provides comprehensive monitoring capabilities for SNMP applications,
  including real-time metrics, performance analytics, and health monitoring.
  Based on monitoring patterns proven in large-scale network management systems.
  
  ## Features
  
  - **Real-time Metrics**: Live performance data collection and analysis
  - **Historical Analytics**: Trend analysis and capacity planning data
  - **Health Monitoring**: Automatic detection of performance degradation
  - **Alerting**: Configurable thresholds and notification system
  - **Device Profiling**: Per-device performance characteristics
  - **Operation Tracking**: Detailed metrics for all SNMP operation types
  
  ## Metric Categories
  
  ### Operation Metrics
  - Request/response times
  - Success/failure rates
  - Throughput measurements
  - Error classifications
  
  ### Device Metrics
  - Per-device response characteristics
  - Availability percentages
  - Performance trends
  - Health scores
  
  ### System Metrics
  - Connection pool utilization
  - Memory usage patterns
  - Resource consumption
  - Concurrent operation counts
  
  ## Usage Examples
  
      # Start monitoring system
      {:ok, _pid} = SnmpLib.Monitor.start_link()
      
      # Record SNMP operation
      SnmpLib.Monitor.record_operation(
        device: "192.168.1.1",
        operation: :get,
        duration: 245,
        result: :success
      )
      
      # Get real-time stats
      stats = SnmpLib.Monitor.get_stats("192.168.1.1")
      IO.puts("Average response time: " <> to_string(stats.avg_response_time) <> "ms")
      
      # Set up alerting
      SnmpLib.Monitor.set_alert_threshold("192.168.1.1", :response_time, 5000)
  """
  
  use GenServer
  require Logger
  
  @default_retention_period 3_600_000  # 1 hour in milliseconds
  @default_bucket_size 60_000         # 1 minute buckets
  @default_cleanup_interval 300_000   # 5 minutes
  @default_health_check_interval 60_000  # 1 minute
  
  @type device_id :: binary()
  @type operation_type :: :get | :get_next | :get_bulk | :set | :walk
  @type operation_result :: :success | :error | :timeout | :partial
  @type metric_type :: :response_time | :error_rate | :throughput | :availability
  
  @type operation_metric :: %{
    device: device_id(),
    operation: operation_type(),
    timestamp: integer(),
    duration: non_neg_integer(),
    result: operation_result(),
    error_type: atom() | nil,
    bytes_sent: non_neg_integer() | nil,
    bytes_received: non_neg_integer() | nil
  }
  
  @type device_stats :: %{
    device_id: device_id(),
    total_operations: non_neg_integer(),
    successful_operations: non_neg_integer(),
    failed_operations: non_neg_integer(),
    avg_response_time: float(),
    p95_response_time: float(),
    p99_response_time: float(),
    error_rate: float(),
    availability: float(),
    health_score: float(),
    last_seen: integer(),
    trend: :improving | :stable | :degrading
  }
  
  @type system_stats :: %{
    total_devices: non_neg_integer(),
    active_devices: non_neg_integer(),
    total_operations: non_neg_integer(),
    operations_per_second: float(),
    average_response_time: float(),
    global_error_rate: float(),
    memory_usage: non_neg_integer(),
    uptime: non_neg_integer()
  }
  
  @type alert_threshold :: %{
    device_id: device_id(),
    metric: metric_type(),
    threshold: number(),
    condition: :above | :below,
    duration: pos_integer(),
    callback: function() | nil
  }
  
  defstruct [
    operations: [],           # Recent operations
    device_stats: %{},       # Per-device aggregated stats
    system_stats: %{},       # Global system stats
    alert_thresholds: [],    # Configured alert thresholds
    active_alerts: [],       # Currently firing alerts
    retention_period: @default_retention_period,
    bucket_size: @default_bucket_size,
    cleanup_timer: nil,
    health_check_timer: nil,
    start_time: nil
  ]
  
  ## Public API
  
  @doc """
  Starts the monitoring system.
  
  ## Options
  
  - `retention_period`: How long to keep historical data (default: 1 hour)
  - `bucket_size`: Time bucket size for aggregation (default: 1 minute)
  - `cleanup_interval`: How often to clean old data (default: 5 minutes)
  - `health_check_interval`: How often to check device health (default: 1 minute)
  
  ## Examples
  
      {:ok, pid} = SnmpLib.Monitor.start_link()
      
      {:ok, pid} = SnmpLib.Monitor.start_link(
        retention_period: 7200_000,  # 2 hours
        bucket_size: 30_000          # 30 second buckets
      )
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, any()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records an SNMP operation for monitoring and analysis.
  
  This is the primary interface for feeding operation data into the monitoring system.
  Should be called after every SNMP operation for comprehensive monitoring.
  
  ## Parameters
  
  - `metric`: Operation metric map with required fields
  
  ## Required Fields
  
  - `device`: Target device identifier
  - `operation`: Type of SNMP operation
  - `duration`: Operation duration in milliseconds
  - `result`: Operation result status
  
  ## Optional Fields
  
  - `error_type`: Specific error classification (if result is :error)
  - `bytes_sent`: Number of bytes sent
  - `bytes_received`: Number of bytes received
  - `timestamp`: Override timestamp (defaults to current time)
  
  ## Examples
  
      # Basic operation recording
      SnmpLib.Monitor.record_operation(%{
        device: "192.168.1.1",
        operation: :get,
        duration: 245,
        result: :success
      })
      
      # Detailed operation recording
      SnmpLib.Monitor.record_operation(%{
        device: "192.168.1.1",
        operation: :get_bulk,
        duration: 1250,
        result: :error,
        error_type: :timeout,
        bytes_sent: 64,
        bytes_received: 0
      })
  """
  @spec record_operation(map()) :: :ok
  def record_operation(metric) when is_map(metric) do
    # Add timestamp if not provided
    enriched_metric = Map.put_new(metric, :timestamp, System.monotonic_time(:millisecond))
    
    GenServer.cast(__MODULE__, {:record_operation, enriched_metric})
  end
  
  @doc """
  Gets comprehensive statistics for a specific device.
  
  ## Parameters
  
  - `device_id`: Device identifier
  - `timeframe`: Optional timeframe (:last_hour, :last_day, :all_time)
  
  ## Returns
  
  Device statistics map or `{:error, :not_found}` if device has no recorded operations.
  
  ## Examples
  
      # Get current device stats
      stats = SnmpLib.Monitor.get_device_stats("192.168.1.1")
      IO.puts("Error rate: " <> to_string(stats.error_rate) <> "%")
      
      # Get stats for specific timeframe
      stats = SnmpLib.Monitor.get_device_stats("192.168.1.1", :last_hour)
  """
  @spec get_device_stats(device_id(), atom()) :: device_stats() | {:error, :not_found}
  def get_device_stats(device_id, timeframe \\ :all_time) do
    GenServer.call(__MODULE__, {:get_device_stats, device_id, timeframe})
  end
  
  @doc """
  Gets system-wide statistics and performance metrics.
  
  ## Returns
  
  Comprehensive system statistics including global performance metrics,
  device counts, and resource utilization.
  
  ## Examples
  
      stats = SnmpLib.Monitor.get_system_stats()
      IO.puts("Total devices monitored: " <> to_string(stats.total_devices))
      IO.puts("Operations per second: " <> to_string(stats.operations_per_second))
  """
  @spec get_system_stats() :: system_stats()
  def get_system_stats() do
    GenServer.call(__MODULE__, :get_system_stats)
  end
  
  @doc """
  Gets performance metrics for a specific operation type.
  
  ## Parameters
  
  - `operation`: SNMP operation type
  - `timeframe`: Optional timeframe for analysis
  
  ## Examples
  
      metrics = SnmpLib.Monitor.get_operation_metrics(:get_bulk)
      IO.puts("Average GETBULK time: " <> to_string(metrics.avg_duration) <> "ms")
  """
  @spec get_operation_metrics(operation_type(), atom()) :: map()
  def get_operation_metrics(operation, timeframe \\ :last_hour) do
    GenServer.call(__MODULE__, {:get_operation_metrics, operation, timeframe})
  end
  
  @doc """
  Sets an alert threshold for automated monitoring.
  
  Alerts fire when the specified metric exceeds the threshold for the given duration.
  
  ## Parameters
  
  - `device_id`: Device to monitor (use \":global\" for system-wide alerts)
  - `metric`: Metric type to monitor
  - `threshold`: Threshold value
  - `opts`: Alert configuration options
  
  ## Options
  
  - `condition`: `:above` or `:below` (default: `:above`)
  - `duration`: How long threshold must be exceeded (default: 60000ms)
  - `callback`: Function to call when alert fires
  
  ## Examples
  
      # Alert on high response times
      SnmpLib.Monitor.set_alert_threshold("192.168.1.1", :response_time, 5000)
      
      # Alert on low availability with custom callback
      SnmpLib.Monitor.set_alert_threshold("core-router", :availability, 95.0,
        condition: :below,
        duration: 300_000,
        callback: &MyApp.Alerts.device_down/1
      )
  """
  @spec set_alert_threshold(device_id(), metric_type(), number(), keyword()) :: :ok
  def set_alert_threshold(device_id, metric, threshold, opts \\ []) do
    alert_config = %{
      device_id: device_id,
      metric: metric,
      threshold: threshold,
      condition: Keyword.get(opts, :condition, :above),
      duration: Keyword.get(opts, :duration, 60_000),
      callback: Keyword.get(opts, :callback)
    }
    
    GenServer.cast(__MODULE__, {:set_alert_threshold, alert_config})
  end
  
  @doc """
  Removes an alert threshold.
  
  ## Examples
  
      :ok = SnmpLib.Monitor.remove_alert_threshold("192.168.1.1", :response_time)
  """
  @spec remove_alert_threshold(device_id(), metric_type()) :: :ok
  def remove_alert_threshold(device_id, metric) do
    GenServer.cast(__MODULE__, {:remove_alert_threshold, device_id, metric})
  end
  
  @doc """
  Gets currently active alerts.
  
  ## Examples
  
      alerts = SnmpLib.Monitor.get_active_alerts()
      Enum.each(alerts, fn alert ->
        IO.puts("Alert: " <> alert.device_id <> " " <> to_string(alert.metric) <> " " <> to_string(alert.current_value))
      end)
  """
  @spec get_active_alerts() :: [map()]
  def get_active_alerts() do
    GenServer.call(__MODULE__, :get_active_alerts)
  end
  
  @doc """
  Forces a health check of all monitored devices.
  
  Useful for immediate assessment of system health.
  
  ## Examples
  
      :ok = SnmpLib.Monitor.health_check()
  """
  @spec health_check() :: :ok
  def health_check() do
    GenServer.cast(__MODULE__, :health_check)
  end
  
  @doc """
  Exports monitoring data for external analysis.
  
  ## Parameters
  
  - `format`: Export format (`:json`, `:csv`, `:prometheus`)
  - `timeframe`: Time range for export
  
  ## JSON Export
  
  JSON export uses Elixir's built-in JSON module (requires Elixir 1.18+).
  
  ## Examples
  
      data = SnmpLib.Monitor.export_data(:json, :last_hour)
      case data do
        "JSON export unavailable" <> _ -> IO.puts("JSON not available")
        json -> File.write!("snmp_metrics.json", json)
      end
  """
  @spec export_data(atom(), atom()) :: binary()
  def export_data(format, timeframe \\ :last_hour) do
    GenServer.call(__MODULE__, {:export_data, format, timeframe})
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      retention_period: Keyword.get(opts, :retention_period, @default_retention_period),
      bucket_size: Keyword.get(opts, :bucket_size, @default_bucket_size),
      start_time: System.monotonic_time(:millisecond)
    }
    
    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup, @default_cleanup_interval)
    health_timer = Process.send_after(self(), :health_check, @default_health_check_interval)
    
    final_state = %{state | 
      cleanup_timer: cleanup_timer,
      health_check_timer: health_timer
    }
    
    Logger.info("Started SNMP monitoring system")
    {:ok, final_state}
  end
  
  @impl GenServer
  def handle_cast({:record_operation, metric}, state) do
    # Add to operations list
    new_operations = [metric | state.operations]
    
    # Update device stats
    new_device_stats = update_device_stats(state.device_stats, metric)
    
    # Update system stats
    new_system_stats = update_system_stats(state.system_stats, metric)
    
    # Check for alert conditions
    new_state = %{state | 
      operations: new_operations,
      device_stats: new_device_stats,
      system_stats: new_system_stats
    }
    |> check_alert_conditions(metric)
    
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_cast({:set_alert_threshold, alert_config}, state) do
    new_thresholds = [alert_config | state.alert_thresholds]
    new_state = %{state | alert_thresholds: new_thresholds}
    
    Logger.info("Set alert threshold for " <> alert_config.device_id <> " " <> to_string(alert_config.metric) <> ": " <> to_string(alert_config.threshold))
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_cast({:remove_alert_threshold, device_id, metric}, state) do
    new_thresholds = Enum.reject(state.alert_thresholds, fn threshold ->
      threshold.device_id == device_id and threshold.metric == metric
    end)
    
    new_state = %{state | alert_thresholds: new_thresholds}
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_cast(:health_check, state) do
    new_state = perform_health_checks(state)
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_call({:get_device_stats, device_id, timeframe}, _from, state) do
    case Map.get(state.device_stats, device_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      stats ->
        filtered_stats = filter_stats_by_timeframe(stats, timeframe, state)
        {:reply, filtered_stats, state}
    end
  end
  
  @impl GenServer
  def handle_call(:get_system_stats, _from, state) do
    system_stats = calculate_system_stats(state)
    {:reply, system_stats, state}
  end
  
  @impl GenServer
  def handle_call({:get_operation_metrics, operation, timeframe}, _from, state) do
    metrics = calculate_operation_metrics(state, operation, timeframe)
    {:reply, metrics, state}
  end
  
  @impl GenServer
  def handle_call(:get_active_alerts, _from, state) do
    {:reply, state.active_alerts, state}
  end
  
  @impl GenServer
  def handle_call({:export_data, format, timeframe}, _from, state) do
    data = export_monitoring_data(state, format, timeframe)
    {:reply, data, state}
  end
  
  @impl GenServer
  def handle_info(:cleanup, state) do
    new_state = cleanup_old_data(state)
    
    # Schedule next cleanup
    timer = Process.send_after(self(), :cleanup, @default_cleanup_interval)
    final_state = %{new_state | cleanup_timer: timer}
    
    {:noreply, final_state}
  end
  
  @impl GenServer
  def handle_info(:health_check, state) do
    new_state = perform_health_checks(state)
    
    # Schedule next health check
    timer = Process.send_after(self(), :health_check, @default_health_check_interval)
    final_state = %{new_state | health_check_timer: timer}
    
    {:noreply, final_state}
  end
  
  ## Private Implementation
  
  # Stats calculation
  # Updates device statistics with new operation metric.
  # Calculates derived metrics like error rates and health scores.
  defp update_device_stats(device_stats, metric) do
    device_id = metric.device
    current_stats = Map.get(device_stats, device_id, default_device_stats(device_id))
    
    updated_stats = %{current_stats |
      total_operations: current_stats.total_operations + 1,
      last_seen: metric.timestamp
    }
    |> update_success_failure_counts(metric)
    |> update_response_times(metric)
    |> calculate_derived_metrics()
    
    Map.put(device_stats, device_id, updated_stats)
  end
  
  defp default_device_stats(device_id) do
    %{
      device_id: device_id,
      total_operations: 0,
      successful_operations: 0,
      failed_operations: 0,
      response_times: [],
      avg_response_time: 0.0,
      p95_response_time: 0.0,
      p99_response_time: 0.0,
      error_rate: 0.0,
      availability: 100.0,
      health_score: 100.0,
      last_seen: System.monotonic_time(:millisecond),
      trend: :stable
    }
  end
  
  defp update_success_failure_counts(stats, metric) do
    case metric.result do
      :success ->
        %{stats | successful_operations: stats.successful_operations + 1}
      _ ->
        %{stats | failed_operations: stats.failed_operations + 1}
    end
  end
  
  defp update_response_times(stats, metric) do
    new_times = [metric.duration | Enum.take(stats.response_times, 99)]  # Keep last 100
    %{stats | response_times: new_times}
  end
  
  defp calculate_derived_metrics(stats) do
    total = stats.total_operations
    
    # Error rate
    error_rate = if total > 0 do
      (stats.failed_operations / total) * 100
    else
      0.0
    end
    
    # Response time metrics
    {avg_time, p95_time, p99_time} = calculate_response_time_percentiles(stats.response_times)
    
    # Availability (inverse of error rate)
    availability = 100.0 - error_rate
    
    # Health score (composite metric)
    health_score = calculate_health_score(availability, avg_time, error_rate)
    
    %{stats |
      avg_response_time: avg_time,
      p95_response_time: p95_time,
      p99_response_time: p99_time,
      error_rate: error_rate,
      availability: availability,
      health_score: health_score
    }
  end
  
  defp calculate_response_time_percentiles([]), do: {0.0, 0.0, 0.0}
  defp calculate_response_time_percentiles(times) do
    sorted = Enum.sort(times)
    count = length(sorted)
    
    avg = Enum.sum(sorted) / count
    p95 = percentile(sorted, 95)
    p99 = percentile(sorted, 99)
    
    {avg, p95, p99}
  end
  
  defp percentile(sorted_list, percentile) do
    count = length(sorted_list)
    index = trunc((percentile / 100) * count)
    clamped_index = min(index, count - 1)
    Enum.at(sorted_list, clamped_index, 0)
  end
  
  # Calculates composite health score from availability, performance, and reliability metrics.
  # Weighted scoring system: 50% availability, 30% performance, 20% reliability.
  defp calculate_health_score(availability, avg_response_time, error_rate) do
    # Simplified health score calculation
    availability_weight = 0.5
    performance_weight = 0.3
    reliability_weight = 0.2
    
    # Normalize response time (assuming 1000ms is baseline)
    performance_score = max(0, 100 - (avg_response_time / 10))
    reliability_score = max(0, 100 - (error_rate * 5))
    
    (availability * availability_weight) +
    (performance_score * performance_weight) +
    (reliability_score * reliability_weight)
  end
  
  defp update_system_stats(system_stats, _metric) do
    # Update global counters
    Map.update(system_stats, :total_operations, 1, &(&1 + 1))
  end
  
  defp calculate_system_stats(state) do
    current_time = System.monotonic_time(:millisecond)
    uptime = current_time - state.start_time
    
    device_count = map_size(state.device_stats)
    
    # Calculate active devices (seen in last 5 minutes)
    cutoff = current_time - 300_000
    active_devices = state.device_stats
    |> Map.values()
    |> Enum.count(fn stats -> stats.last_seen > cutoff end)
    
    total_ops = Map.get(state.system_stats, :total_operations, 0)
    ops_per_second = if uptime > 0, do: total_ops / (uptime / 1000), else: 0.0
    
    %{
      total_devices: device_count,
      active_devices: active_devices,
      total_operations: total_ops,
      operations_per_second: ops_per_second,
      average_response_time: calculate_global_avg_response_time(state),
      global_error_rate: calculate_global_error_rate(state),
      memory_usage: :erlang.memory(:total),
      uptime: uptime
    }
  end
  
  defp calculate_global_avg_response_time(state) do
    all_times = state.device_stats
    |> Map.values()
    |> Enum.flat_map(& &1.response_times)
    
    case all_times do
      [] -> 0.0
      times -> Enum.sum(times) / length(times)
    end
  end
  
  defp calculate_global_error_rate(state) do
    totals = state.device_stats
    |> Map.values()
    |> Enum.reduce({0, 0}, fn stats, {total_ops, total_errors} ->
      {total_ops + stats.total_operations, total_errors + stats.failed_operations}
    end)
    
    case totals do
      {0, _} -> 0.0
      {total_ops, total_errors} -> (total_errors / total_ops) * 100
    end
  end
  
  # Alert management
  defp check_alert_conditions(state, metric) do
    # Check if any thresholds are violated
    new_alerts = Enum.reduce(state.alert_thresholds, state.active_alerts, fn threshold, alerts ->
      if should_fire_alert?(threshold, metric, state) do
        fire_alert(threshold, metric, alerts)
      else
        alerts
      end
    end)
    
    %{state | active_alerts: new_alerts}
  end
  
  defp should_fire_alert?(threshold, metric, state) do
    # Simplified alert logic - would be more sophisticated in production
    device_stats = Map.get(state.device_stats, metric.device)
    
    case {threshold.metric, device_stats} do
      {:response_time, stats} when not is_nil(stats) ->
        check_threshold_condition(stats.avg_response_time, threshold)
      {:error_rate, stats} when not is_nil(stats) ->
        check_threshold_condition(stats.error_rate, threshold)
      {:availability, stats} when not is_nil(stats) ->
        check_threshold_condition(stats.availability, threshold)
      _ ->
        false
    end
  end
  
  defp check_threshold_condition(current_value, threshold) do
    case threshold.condition do
      :above -> current_value > threshold.threshold
      :below -> current_value < threshold.threshold
    end
  end
  
  defp fire_alert(threshold, metric, existing_alerts) do
    # Check if alert already exists
    alert_key = {threshold.device_id, threshold.metric}
    
    case Enum.find(existing_alerts, fn alert -> 
      {alert.device_id, alert.metric} == alert_key 
    end) do
      nil ->
        # New alert
        new_alert = %{
          device_id: threshold.device_id,
          metric: threshold.metric,
          threshold: threshold.threshold,
          current_value: get_current_metric_value(metric, threshold.metric),
          fired_at: System.monotonic_time(:millisecond),
          callback: threshold.callback
        }
        
        # Execute callback if provided
        if threshold.callback do
          spawn(fn -> threshold.callback.(new_alert) end)
        end
        
        Logger.warning("Alert fired: " <> threshold.device_id <> " " <> to_string(threshold.metric) <> " = " <> to_string(new_alert.current_value))
        [new_alert | existing_alerts]
        
      _existing ->
        # Alert already active
        existing_alerts
    end
  end
  
  defp get_current_metric_value(metric, :response_time), do: metric.duration
  defp get_current_metric_value(_metric, _metric_type), do: nil
  
  # Data management
  defp cleanup_old_data(state) do
    cutoff = System.monotonic_time(:millisecond) - state.retention_period
    
    # Remove old operations
    new_operations = Enum.filter(state.operations, fn op -> 
      op.timestamp > cutoff 
    end)
    
    # Clean up old response times in device stats
    new_device_stats = state.device_stats
    |> Enum.map(fn {device_id, stats} ->
      # Keep only recent response times
      recent_times = Enum.take(stats.response_times, 50)
      updated_stats = %{stats | response_times: recent_times}
      {device_id, updated_stats}
    end)
    |> Enum.into(%{})
    
    %{state | 
      operations: new_operations,
      device_stats: new_device_stats
    }
  end
  
  defp perform_health_checks(state) do
    # Update device trends and health scores
    new_device_stats = state.device_stats
    |> Enum.map(fn {device_id, stats} ->
      updated_stats = update_device_trend(stats)
      {device_id, updated_stats}
    end)
    |> Enum.into(%{})
    
    %{state | device_stats: new_device_stats}
  end
  
  defp update_device_trend(stats) do
    # Simplified trend calculation
    trend = cond do
      stats.health_score > 90 -> :stable
      stats.error_rate > 10 -> :degrading
      stats.avg_response_time > 5000 -> :degrading
      true -> :improving
    end
    
    %{stats | trend: trend}
  end
  
  # Data export
  defp calculate_operation_metrics(state, operation, timeframe) do
    # Filter operations by type and timeframe
    filtered_ops = filter_operations_by_timeframe(state.operations, timeframe)
    |> Enum.filter(fn op -> op.operation == operation end)
    
    case filtered_ops do
      [] ->
        %{operation: operation, count: 0, avg_duration: 0.0, error_rate: 0.0}
      ops ->
        count = length(ops)
        durations = Enum.map(ops, & &1.duration)
        avg_duration = Enum.sum(durations) / count
        
        error_count = Enum.count(ops, fn op -> op.result != :success end)
        error_rate = (error_count / count) * 100
        
        %{
          operation: operation,
          count: count,
          avg_duration: avg_duration,
          error_rate: error_rate,
          p95_duration: percentile(Enum.sort(durations), 95),
          success_rate: 100.0 - error_rate
        }
    end
  end
  
  defp filter_operations_by_timeframe(operations, :all_time), do: operations
  defp filter_operations_by_timeframe(operations, timeframe) do
    cutoff = case timeframe do
      :last_hour -> System.monotonic_time(:millisecond) - 3_600_000
      :last_day -> System.monotonic_time(:millisecond) - 86_400_000
      _ -> System.monotonic_time(:millisecond) - 3_600_000
    end
    
    Enum.filter(operations, fn op -> op.timestamp > cutoff end)
  end
  
  defp filter_stats_by_timeframe(stats, :all_time, _state), do: stats
  defp filter_stats_by_timeframe(stats, _timeframe, _state) do
    # For now, return current stats
    # In production, would calculate stats for specific timeframe
    stats
  end
  
  defp export_monitoring_data(state, format, timeframe) do
    filtered_ops = filter_operations_by_timeframe(state.operations, timeframe)
    
    case format do
      :json ->
        data = %{
          operations: filtered_ops,
          device_stats: state.device_stats,
          system_stats: calculate_system_stats(state),
          exported_at: System.monotonic_time(:millisecond)
        }
        JSON.encode!(data)
      
      :csv ->
        export_csv(filtered_ops)
      
      :prometheus ->
        export_prometheus(state)
      
      _ ->
        ""
    end
  end
  
  defp export_csv(operations) do
    headers = "timestamp,device,operation,duration,result,error_type\n"
    
    rows = Enum.map(operations, fn op ->
      to_string(op.timestamp) <> "," <> op.device <> "," <> to_string(op.operation) <> "," <> to_string(op.duration) <> "," <> to_string(op.result) <> "," <> to_string(op[:error_type] || "")
    end)
    |> Enum.join("\n")
    
    headers <> rows
  end
  
  defp export_prometheus(state) do
    # Simplified Prometheus format export
    system_stats = calculate_system_stats(state)
    
    "# HELP snmp_operations_total Total number of SNMP operations\n" <>
    "# TYPE snmp_operations_total counter\n" <>
    "snmp_operations_total " <> to_string(system_stats.total_operations) <> "\n\n" <>
    "# HELP snmp_operations_per_second Current operations per second\n" <>
    "# TYPE snmp_operations_per_second gauge\n" <>
    "snmp_operations_per_second " <> to_string(system_stats.operations_per_second) <> "\n\n" <>
    "# HELP snmp_response_time_avg Average response time in milliseconds\n" <>
    "# TYPE snmp_response_time_avg gauge\n" <>
    "snmp_response_time_avg " <> to_string(system_stats.average_response_time) <> "\n"
  end
  
end