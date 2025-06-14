defmodule SnmpMgr.Metrics do
  @moduledoc """
  Comprehensive metrics collection and monitoring for SNMP operations.
  
  This module provides real-time metrics collection, aggregation, and reporting
  for all SNMP operations including request latency, success rates, throughput,
  and resource utilization across engines, pools, and circuit breakers.
  """
  
  use GenServer
  require Logger
  
  @default_window_size 60  # 60 seconds
  @default_retention_period 3600  # 1 hour
  @default_collection_interval 1000  # 1 second
  
  defstruct [
    :name,
    :window_size,
    :retention_period,
    :collection_interval,
    :metrics,
    :time_windows,
    :collection_timer,
    :subscribers
  ]
  
  @doc """
  Starts the metrics collector.
  
  ## Options
  - `:window_size` - Metrics window size in seconds (default: 60)
  - `:retention_period` - How long to keep metrics in seconds (default: 3600)
  - `:collection_interval` - Collection frequency in ms (default: 1000)
  
  ## Examples
  
      {:ok, metrics} = SnmpMgr.Metrics.start_link(
        window_size: 120,
        retention_period: 7200
      )
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Records a counter metric.
  
  ## Parameters
  - `metrics` - Metrics PID or name
  - `metric_name` - Name of the metric
  - `value` - Value to add (default: 1)
  - `tags` - Optional tags for the metric
  
  ## Examples
  
      SnmpMgr.Metrics.counter(metrics, :requests_total, 1, %{target: "device1"})
  """
  def counter(metrics, metric_name, value \\ 1, tags \\ %{}) do
    GenServer.cast(metrics, {:counter, metric_name, value, tags, System.monotonic_time(:millisecond)})
  end
  
  @doc """
  Records a gauge metric (current value).
  
  ## Parameters
  - `metrics` - Metrics PID or name
  - `metric_name` - Name of the metric
  - `value` - Current value
  - `tags` - Optional tags for the metric
  
  ## Examples
  
      SnmpMgr.Metrics.gauge(metrics, :active_connections, 15, %{pool: "main"})
  """
  def gauge(metrics, metric_name, value, tags \\ %{}) do
    GenServer.cast(metrics, {:gauge, metric_name, value, tags, System.monotonic_time(:millisecond)})
  end
  
  @doc """
  Records a histogram metric (for latency/duration measurements).
  
  ## Parameters
  - `metrics` - Metrics PID or name
  - `metric_name` - Name of the metric
  - `value` - Value to record
  - `tags` - Optional tags for the metric
  
  ## Examples
  
      SnmpMgr.Metrics.histogram(metrics, :request_duration_ms, 150, %{operation: "get"})
  """
  def histogram(metrics, metric_name, value, tags \\ %{}) do
    GenServer.cast(metrics, {:histogram, metric_name, value, tags, System.monotonic_time(:millisecond)})
  end
  
  @doc """
  Records timing for a function execution.
  
  ## Parameters
  - `metrics` - Metrics PID or name
  - `metric_name` - Name of the metric
  - `fun` - Function to time
  - `tags` - Optional tags for the metric
  
  ## Examples
  
      result = SnmpMgr.Metrics.time(metrics, :snmp_get_duration, fn ->
        SnmpMgr.get("device1", "sysDescr.0")
      end, %{device: "device1"})
  """
  def time(metrics, metric_name, fun, tags \\ %{}) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = fun.()
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      histogram(metrics, metric_name, duration, tags)
      counter(metrics, :"#{metric_name}_total", 1, Map.put(tags, :status, :success))
      
      result
    catch
      kind, reason ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        histogram(metrics, metric_name, duration, tags)
        counter(metrics, :"#{metric_name}_total", 1, Map.put(tags, :status, :error))
        
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end
  
  @doc """
  Gets current metrics snapshot.
  """
  def get_metrics(metrics) do
    GenServer.call(metrics, :get_metrics)
  end
  
  @doc """
  Gets metrics for a specific time window.
  """
  def get_window_metrics(metrics, window_start, window_end) do
    GenServer.call(metrics, {:get_window_metrics, window_start, window_end})
  end
  
  @doc """
  Gets aggregated metrics summary.
  """
  def get_summary(metrics) do
    GenServer.call(metrics, :get_summary)
  end
  
  @doc """
  Subscribes to metrics updates.
  """
  def subscribe(metrics, subscriber_pid) do
    GenServer.cast(metrics, {:subscribe, subscriber_pid})
  end
  
  @doc """
  Unsubscribes from metrics updates.
  """
  def unsubscribe(metrics, subscriber_pid) do
    GenServer.cast(metrics, {:unsubscribe, subscriber_pid})
  end
  
  @doc """
  Resets all metrics.
  """
  def reset(metrics) do
    GenServer.cast(metrics, :reset)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    window_size = Keyword.get(opts, :window_size, @default_window_size)
    retention_period = Keyword.get(opts, :retention_period, @default_retention_period)
    collection_interval = Keyword.get(opts, :collection_interval, @default_collection_interval)
    
    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__),
      window_size: window_size,
      retention_period: retention_period,
      collection_interval: collection_interval,
      metrics: %{},
      time_windows: :queue.new(),
      collection_timer: nil,
      subscribers: MapSet.new()
    }
    
    # Start collection timer
    collection_timer = if collection_interval > 0 do
      Process.send_after(self(), :collect_metrics, collection_interval)
    end
    
    state = %{state | collection_timer: collection_timer}
    
    Logger.info("SnmpMgr Metrics started with window_size=#{window_size}s")
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:counter, metric_name, value, tags, timestamp}, state) do
    new_metrics = record_metric(state.metrics, :counter, metric_name, value, tags, timestamp)
    new_state = %{state | metrics: new_metrics}
    
    notify_subscribers(new_state, {:counter, metric_name, value, tags, timestamp})
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:gauge, metric_name, value, tags, timestamp}, state) do
    new_metrics = record_metric(state.metrics, :gauge, metric_name, value, tags, timestamp)
    new_state = %{state | metrics: new_metrics}
    
    notify_subscribers(new_state, {:gauge, metric_name, value, tags, timestamp})
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:histogram, metric_name, value, tags, timestamp}, state) do
    new_metrics = record_metric(state.metrics, :histogram, metric_name, value, tags, timestamp)
    new_state = %{state | metrics: new_metrics}
    
    notify_subscribers(new_state, {:histogram, metric_name, value, tags, timestamp})
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:subscribe, subscriber_pid}, state) do
    new_subscribers = MapSet.put(state.subscribers, subscriber_pid)
    new_state = %{state | subscribers: new_subscribers}
    
    Logger.debug("Added metrics subscriber: #{inspect(subscriber_pid)}")
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:unsubscribe, subscriber_pid}, state) do
    new_subscribers = MapSet.delete(state.subscribers, subscriber_pid)
    new_state = %{state | subscribers: new_subscribers}
    
    Logger.debug("Removed metrics subscriber: #{inspect(subscriber_pid)}")
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast(:reset, state) do
    Logger.info("Resetting all metrics")
    
    new_state = %{state | 
      metrics: %{},
      time_windows: :queue.new()
    }
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  @impl true
  def handle_call({:get_window_metrics, window_start, window_end}, _from, state) do
    window_metrics = extract_window_metrics(state.time_windows, window_start, window_end)
    {:reply, window_metrics, state}
  end
  
  @impl true
  def handle_call(:get_summary, _from, state) do
    summary = generate_summary(state.metrics, state.time_windows)
    {:reply, summary, state}
  end
  
  @impl true
  def handle_info(:collect_metrics, state) do
    new_state = collect_and_aggregate_metrics(state)
    
    # Schedule next collection
    collection_timer = if state.collection_interval > 0 do
      Process.send_after(self(), :collect_metrics, state.collection_interval)
    end
    
    new_state = %{new_state | collection_timer: collection_timer}
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead subscriber
    new_subscribers = MapSet.delete(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp record_metric(metrics, type, metric_name, value, tags, timestamp) do
    metric_key = {metric_name, tags}
    
    case Map.get(metrics, metric_key) do
      nil ->
        # Create new metric
        metric = create_metric(type, metric_name, value, tags, timestamp)
        Map.put(metrics, metric_key, metric)
      
      existing_metric ->
        # Update existing metric
        updated_metric = update_metric(existing_metric, type, value, timestamp)
        Map.put(metrics, metric_key, updated_metric)
    end
  end
  
  defp create_metric(type, name, value, tags, timestamp) do
    base_metric = %{
      type: type,
      name: name,
      tags: tags,
      created_at: timestamp,
      last_updated: timestamp
    }
    
    case type do
      :counter ->
        Map.merge(base_metric, %{
          value: value,
          total: value
        })
      
      :gauge ->
        Map.merge(base_metric, %{
          value: value
        })
      
      :histogram ->
        Map.merge(base_metric, %{
          values: [value],
          count: 1,
          sum: value,
          min: value,
          max: value,
          avg: value
        })
    end
  end
  
  defp update_metric(metric, type, value, timestamp) do
    base_update = %{metric | last_updated: timestamp}
    
    case type do
      :counter ->
        %{base_update | 
          value: metric.value + value,
          total: metric.total + value
        }
      
      :gauge ->
        %{base_update | value: value}
      
      :histogram ->
        new_values = [value | metric.values]
        new_count = metric.count + 1
        new_sum = metric.sum + value
        new_min = min(metric.min, value)
        new_max = max(metric.max, value)
        new_avg = new_sum / new_count
        
        %{base_update | 
          values: Enum.take(new_values, 1000),  # Keep last 1000 values
          count: new_count,
          sum: new_sum,
          min: new_min,
          max: new_max,
          avg: new_avg
        }
    end
  end
  
  defp collect_and_aggregate_metrics(state) do
    current_time = System.monotonic_time(:second)
    window_start = current_time - state.window_size
    
    # Create time window snapshot
    window_snapshot = %{
      timestamp: current_time,
      window_start: window_start,
      metrics: aggregate_metrics(state.metrics, window_start * 1000, current_time * 1000)
    }
    
    # Add to time windows queue
    new_windows = :queue.in(window_snapshot, state.time_windows)
    
    # Remove old windows
    cutoff_time = current_time - state.retention_period
    cleaned_windows = remove_old_windows(new_windows, cutoff_time)
    
    %{state | time_windows: cleaned_windows}
  end
  
  defp aggregate_metrics(metrics, window_start_ms, window_end_ms) do
    metrics
    |> Enum.filter(fn {_key, metric} ->
      metric.last_updated >= window_start_ms and metric.last_updated <= window_end_ms
    end)
    |> Enum.map(fn {key, metric} -> {key, summarize_metric(metric)} end)
    |> Enum.into(%{})
  end
  
  defp summarize_metric(metric) do
    case metric.type do
      :counter ->
        %{
          type: :counter,
          name: metric.name,
          tags: metric.tags,
          value: metric.value,
          total: metric.total
        }
      
      :gauge ->
        %{
          type: :gauge,
          name: metric.name,
          tags: metric.tags,
          value: metric.value
        }
      
      :histogram ->
        %{
          type: :histogram,
          name: metric.name,
          tags: metric.tags,
          count: metric.count,
          sum: metric.sum,
          avg: metric.avg,
          min: metric.min,
          max: metric.max,
          p50: calculate_percentile(metric.values, 50),
          p95: calculate_percentile(metric.values, 95),
          p99: calculate_percentile(metric.values, 99)
        }
    end
  end
  
  defp calculate_percentile(values, percentile) when length(values) > 0 do
    sorted = Enum.sort(values)
    count = length(sorted)
    index = max(0, round(count * percentile / 100) - 1)
    Enum.at(sorted, index)
  end
  
  defp calculate_percentile(_values, _percentile), do: 0
  
  defp remove_old_windows(windows, cutoff_time) do
    windows
    |> :queue.to_list()
    |> Enum.filter(fn window -> window.timestamp >= cutoff_time end)
    |> :queue.from_list()
  end
  
  defp extract_window_metrics(windows, window_start, window_end) do
    windows
    |> :queue.to_list()
    |> Enum.filter(fn window -> 
      window.timestamp >= window_start and window.timestamp <= window_end
    end)
    |> Enum.map(fn window -> window.metrics end)
  end
  
  defp generate_summary(metrics, time_windows) do
    current_metrics = summarize_current_metrics(metrics)
    window_count = :queue.len(time_windows)
    
    %{
      current_metrics: current_metrics,
      window_count: window_count,
      total_metric_types: count_metric_types(metrics),
      last_collection: System.monotonic_time(:second)
    }
  end
  
  defp summarize_current_metrics(metrics) do
    metrics
    |> Enum.group_by(fn {{name, _tags}, metric} -> {metric.type, name} end)
    |> Enum.map(fn {{type, name}, grouped_metrics} ->
      count = length(grouped_metrics)
      
      summary = case type do
        :counter ->
          total_value = grouped_metrics |> Enum.map(fn {_key, metric} -> metric.value end) |> Enum.sum()
          %{type: type, name: name, count: count, total_value: total_value}
        
        :gauge ->
          values = grouped_metrics |> Enum.map(fn {_key, metric} -> metric.value end)
          avg_value = if count > 0, do: Enum.sum(values) / count, else: 0
          %{type: type, name: name, count: count, avg_value: avg_value}
        
        :histogram ->
          total_count = grouped_metrics |> Enum.map(fn {_key, metric} -> metric.count end) |> Enum.sum()
          sum_durations = grouped_metrics |> Enum.map(fn {_key, metric} -> metric.avg end) |> Enum.sum()
          avg_duration = if count > 0, do: sum_durations / count, else: 0
          %{type: type, name: name, count: count, total_count: total_count, avg_duration: avg_duration}
      end
      
      {name, summary}
    end)
    |> Enum.into(%{})
  end
  
  defp count_metric_types(metrics) do
    metrics
    |> Enum.map(fn {_key, metric} -> metric.type end)
    |> Enum.frequencies()
  end
  
  defp notify_subscribers(state, metric_event) do
    Enum.each(state.subscribers, fn subscriber ->
      send(subscriber, {:metrics_event, metric_event})
    end)
  end
end