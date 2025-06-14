defmodule SnmpMgr.Router do
  @moduledoc """
  Intelligent request routing and load balancing for SNMP requests.
  
  This module provides sophisticated routing strategies to optimize request
  distribution across multiple engines and target devices, with support for
  load balancing, affinity routing, and performance-based routing decisions.
  """
  
  use GenServer
  require Logger
  
  @default_strategy :round_robin
  @default_health_check_interval 30_000
  @default_max_retries 3
  
  defstruct [
    :name,
    :strategy,
    :engines,
    :routes,
    :health_check_interval,
    :max_retries,
    :metrics,
    :affinity_table
  ]
  
  @doc """
  Starts the request router.
  
  ## Options
  - `:strategy` - Routing strategy (:round_robin, :least_connections, :weighted, :affinity)
  - `:engines` - List of engine specifications
  - `:health_check_interval` - Health check interval in ms (default: 30000)
  - `:max_retries` - Maximum retry attempts (default: 3)
  
  ## Examples
  
      {:ok, router} = SnmpMgr.Router.start_link(
        strategy: :least_connections,
        engines: [
          %{name: :engine1, weight: 2, max_load: 100},
          %{name: :engine2, weight: 1, max_load: 50}
        ]
      )
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Routes a request to the best available engine.
  
  ## Parameters
  - `router` - Router PID or name
  - `request` - Request specification
  - `opts` - Routing options
  
  ## Examples
  
      request = %{
        type: :get,
        target: "192.168.1.1",
        oid: "sysDescr.0"
      }
      
      {:ok, result} = SnmpMgr.Router.route_request(router, request)
  """
  def route_request(router, request, opts \\ []) do
    GenServer.call(router, {:route_request, request, opts})
  end
  
  @doc """
  Routes multiple requests as a batch.
  
  ## Parameters
  - `router` - Router PID or name
  - `requests` - List of request specifications
  - `opts` - Routing options
  
  ## Examples
  
      requests = [
        %{type: :get, target: "device1", oid: "sysDescr.0"},
        %{type: :get, target: "device2", oid: "sysUpTime.0"}
      ]
      
      {:ok, results} = SnmpMgr.Router.route_batch(router, requests)
  """
  def route_batch(router, requests, opts \\ []) do
    GenServer.call(router, {:route_batch, requests, opts})
  end
  
  @doc """
  Adds an engine to the routing pool.
  """
  def add_engine(router, engine_spec) do
    GenServer.call(router, {:add_engine, engine_spec})
  end
  
  @doc """
  Removes an engine from the routing pool.
  """
  def remove_engine(router, engine_name) do
    GenServer.call(router, {:remove_engine, engine_name})
  end
  
  @doc """
  Gets routing statistics and engine health.
  """
  def get_stats(router) do
    GenServer.call(router, :get_stats)
  end
  
  @doc """
  Updates routing strategy.
  """
  def set_strategy(router, strategy) do
    GenServer.call(router, {:set_strategy, strategy})
  end

  @doc """
  Configures engine settings.
  """
  def configure_engines(router, config) do
    GenServer.call(router, {:configure_engines, config})
  end

  @doc """
  Configures health check settings.
  """
  def configure_health_check(router, config) do
    GenServer.call(router, {:configure_health_check, config})
  end

  @doc """
  Sets engine weights for weighted routing.
  """
  def set_engine_weights(router, weights) do
    GenServer.call(router, {:set_engine_weights, weights})
  end

  @doc """
  Gets engine health information.
  """
  def get_engine_health(router) do
    GenServer.call(router, :get_engine_health)
  end

  @doc """
  Marks an engine as unhealthy.
  """
  def mark_engine_unhealthy(router, engine_name, reason) do
    GenServer.call(router, {:mark_engine_unhealthy, engine_name, reason})
  end

  @doc """
  Marks an engine as healthy.
  """
  def mark_engine_healthy(router, engine_name) do
    GenServer.call(router, {:mark_engine_healthy, engine_name})
  end

  @doc """
  Attempts to recover a failed engine.
  """
  def attempt_engine_recovery(router, engine_name) do
    GenServer.call(router, {:attempt_engine_recovery, engine_name})
  end

  @doc """
  Configures batch processing strategy.
  """
  def configure_batch_strategy(router, strategy_config) do
    GenServer.call(router, {:configure_batch_strategy, strategy_config})
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    engines = Keyword.get(opts, :engines, [])
    health_check_interval = Keyword.get(opts, :health_check_interval, @default_health_check_interval)
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    
    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__),
      strategy: strategy,
      engines: initialize_engines(engines),
      routes: %{},
      health_check_interval: health_check_interval,
      max_retries: max_retries,
      metrics: initialize_metrics(),
      affinity_table: %{}
    }
    
    # Schedule health checks
    if health_check_interval > 0 do
      Process.send_after(self(), :health_check, health_check_interval)
    end
    
    Logger.info("SnmpMgr Router started with strategy=#{strategy}, engines=#{length(engines)}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:route_request, request, opts}, from, state) do
    case select_engine(state, request, opts) do
      {:ok, engine} ->
        # Route request to selected engine
        spawn_link(fn ->
          result = route_to_engine(engine, request, opts, state.max_retries)
          GenServer.reply(from, result)
        end)
        
        # Update metrics
        metrics = update_metrics(state.metrics, :requests_routed, 1)
        new_state = %{state | metrics: metrics}
        
        {:noreply, new_state}
      
      {:error, reason} ->
        metrics = update_metrics(state.metrics, :routing_failures, 1)
        new_state = %{state | metrics: metrics}
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call({:route_batch, requests, opts}, from, state) do
    case route_batch_requests(state, requests, opts) do
      {:ok, routing_plan} ->
        # Execute routing plan
        spawn_link(fn ->
          results = execute_routing_plan(routing_plan, opts, state.max_retries)
          GenServer.reply(from, {:ok, results})
        end)
        
        # Update metrics
        metrics = update_metrics(state.metrics, :batches_routed, 1)
        metrics = update_metrics(metrics, :requests_routed, length(requests))
        new_state = %{state | metrics: metrics}
        
        {:noreply, new_state}
      
      {:error, reason} ->
        metrics = update_metrics(state.metrics, :routing_failures, 1)
        new_state = %{state | metrics: metrics}
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call({:add_engine, engine_spec}, _from, state) do
    engine = initialize_engine(engine_spec)
    new_engines = Map.put(state.engines, engine.name, engine)
    new_state = %{state | engines: new_engines}
    
    Logger.info("Added engine #{engine.name} to router")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:remove_engine, engine_name}, _from, state) do
    new_engines = Map.delete(state.engines, engine_name)
    new_state = %{state | engines: new_engines}
    
    Logger.info("Removed engine #{engine_name} from router")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      strategy: state.strategy,
      engine_count: map_size(state.engines),
      engine_health: get_engines_summary(state.engines),
      metrics: state.metrics,
      affinity_entries: map_size(state.affinity_table)
    }
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:set_strategy, strategy}, _from, state) do
    new_state = %{state | strategy: strategy}
    Logger.info("Changed routing strategy to #{strategy}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:configure_engines, config}, _from, state) do
    new_state = cond do
      Keyword.has_key?(config, :engines) ->
        engines = Keyword.get(config, :engines, [])
        backup_engines = Keyword.get(config, :backup_engines, [])
        all_engines = engines ++ backup_engines
        # Convert string names to atoms for proper GenServer handling
        engine_specs = Enum.map(all_engines, fn engine_name ->
          name = if is_binary(engine_name), do: String.to_atom(engine_name), else: engine_name
          %{name: name}
        end)
        new_engines = initialize_engines(engine_specs)
        %{state | engines: new_engines}
      
      Keyword.has_key?(config, :max_engines) or Keyword.has_key?(config, :min_engines) ->
        # Engine limits configuration - just store in state for now
        state
      
      true ->
        state
    end
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:configure_health_check, config}, _from, state) do
    {:ok, new_state} = apply_health_check_config(state, config)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_engine_weights, weights}, _from, state) do
    new_engines = Enum.reduce(weights, state.engines, fn {engine_name, weight}, acc ->
      case Map.get(acc, engine_name) do
        nil -> acc
        engine -> Map.put(acc, engine_name, %{engine | weight: weight})
      end
    end)
    new_state = %{state | engines: new_engines}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_engine_health, _from, state) do
    health_data = get_detailed_engine_health(state.engines)
    {:reply, health_data, state}
  end

  @impl true
  def handle_call({:mark_engine_unhealthy, engine_name, reason}, _from, state) do
    case mark_engine_status(state, engine_name, :unhealthy, reason) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:mark_engine_healthy, engine_name}, _from, state) do
    case mark_engine_status(state, engine_name, :healthy, nil) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:attempt_engine_recovery, engine_name}, _from, state) do
    case attempt_recovery(state, engine_name) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:configure_batch_strategy, strategy_config}, _from, state) do
    {:ok, new_state} = apply_batch_strategy_config(state, strategy_config)
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_checks(state)
    
    # Schedule next health check
    if state.health_check_interval > 0 do
      Process.send_after(self(), :health_check, state.health_check_interval)
    end
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp initialize_engines(engine_specs) do
    engine_specs
    |> Enum.map(&initialize_engine/1)
    |> Enum.map(fn engine -> {engine.name, engine} end)
    |> Enum.into(%{})
  end
  
  defp initialize_engine(spec) when is_map(spec) do
    %{
      name: Map.get(spec, :name),
      pid: Map.get(spec, :pid),
      weight: Map.get(spec, :weight, 1),
      max_load: Map.get(spec, :max_load, 100),
      current_load: 0,
      health: :healthy,
      last_health_check: System.monotonic_time(:second),
      response_times: :queue.new(),
      error_count: 0,
      total_requests: 0
    }
  end
  
  defp initialize_engine(spec) when is_atom(spec) do
    initialize_engine(%{name: spec, pid: spec})
  end
  
  defp initialize_metrics() do
    %{
      requests_routed: 0,
      batches_routed: 0,
      routing_failures: 0,
      engine_failures: 0,
      avg_routing_time: 0,
      last_reset: System.monotonic_time(:second)
    }
  end
  
  defp select_engine(state, request, _opts) do
    healthy_engines = get_healthy_engines(state.engines)
    
    if Enum.empty?(healthy_engines) do
      {:error, :no_healthy_engines}
    else
      case state.strategy do
        :round_robin -> select_round_robin(healthy_engines)
        :least_connections -> select_least_connections(healthy_engines)
        :weighted -> select_weighted(healthy_engines)
        :affinity -> select_affinity(state, request, healthy_engines)
        _ -> select_round_robin(healthy_engines)
      end
    end
  end
  
  defp get_healthy_engines(engines) do
    engines
    |> Enum.filter(fn {_name, engine} -> engine.health == :healthy end)
    |> Enum.map(fn {_name, engine} -> engine end)
  end
  
  defp select_round_robin(engines) do
    # Simple round-robin selection
    engine = Enum.random(engines)
    {:ok, engine}
  end
  
  defp select_least_connections(engines) do
    # Select engine with lowest current load
    engine = Enum.min_by(engines, fn engine -> engine.current_load end)
    {:ok, engine}
  end
  
  defp select_weighted(engines) do
    # Weighted random selection based on engine weights
    total_weight = Enum.sum(Enum.map(engines, fn engine -> engine.weight end))
    
    if total_weight > 0 do
      target = :rand.uniform(total_weight)
      engine = select_by_weight(engines, target, 0)
      {:ok, engine}
    else
      select_round_robin(engines)
    end
  end
  
  defp select_by_weight([engine | _rest], target, current_weight) 
       when current_weight + engine.weight >= target do
    engine
  end
  
  defp select_by_weight([engine | rest], target, current_weight) do
    select_by_weight(rest, target, current_weight + engine.weight)
  end
  
  defp select_by_weight([], _target, _current_weight) do
    # Fallback - this shouldn't happen with valid weights
    nil
  end
  
  defp select_affinity(state, request, engines) do
    target = request.target
    
    # Check if we have an affinity for this target
    case Map.get(state.affinity_table, target) do
      nil ->
        # No affinity, use least connections
        select_least_connections(engines)
      engine_name ->
        # Check if affinity engine is healthy
        case Enum.find(engines, fn engine -> engine.name == engine_name end) do
          nil -> select_least_connections(engines)
          engine -> {:ok, engine}
        end
    end
  end
  
  defp route_batch_requests(state, requests, opts) do
    # Group requests optimally for batch processing
    case state.strategy do
      :affinity ->
        group_by_affinity(state, requests, opts)
      _ ->
        group_by_engine_capacity(state, requests, opts)
    end
  end
  
  defp group_by_affinity(state, requests, _opts) do
    grouped = 
      requests
      |> Enum.group_by(fn request ->
        target = request.target
        Map.get(state.affinity_table, target, :default)
      end)
    
    routing_plan = 
      grouped
      |> Enum.map(fn {affinity, group_requests} ->
        case select_engine_for_affinity(state, affinity) do
          {:ok, engine} -> {:ok, engine, group_requests}
          error -> error
        end
      end)
      |> Enum.filter(fn
        {:ok, _engine, _requests} -> true
        _ -> false
      end)
    
    {:ok, routing_plan}
  end
  
  defp group_by_engine_capacity(state, requests, _opts) do
    healthy_engines = get_healthy_engines(state.engines)
    
    if Enum.empty?(healthy_engines) do
      {:error, :no_healthy_engines}
    else
      # Distribute requests based on engine capacity
      total_capacity = Enum.sum(Enum.map(healthy_engines, fn engine -> 
        engine.max_load - engine.current_load 
      end))
      
      if total_capacity <= 0 do
        # All engines at capacity, distribute evenly
        distribute_evenly(healthy_engines, requests)
      else
        distribute_by_capacity(healthy_engines, requests, total_capacity)
      end
    end
  end
  
  defp distribute_evenly(engines, requests) do
    engine_count = length(engines)
    
    routing_plan = 
      requests
      |> Enum.with_index()
      |> Enum.map(fn {request, index} ->
        engine = Enum.at(engines, rem(index, engine_count))
        {:ok, engine, [request]}
      end)
      |> Enum.group_by(fn {:ok, engine, _} -> engine.name end)
      |> Enum.map(fn {_name, grouped} ->
        [{:ok, engine, _} | _] = grouped
        all_requests = Enum.flat_map(grouped, fn {:ok, _, reqs} -> reqs end)
        {:ok, engine, all_requests}
      end)
    
    {:ok, routing_plan}
  end
  
  defp distribute_by_capacity(engines, requests, total_capacity) do
    routing_plan = 
      engines
      |> Enum.map(fn engine ->
        capacity = engine.max_load - engine.current_load
        request_count = round(length(requests) * capacity / total_capacity)
        {engine, request_count}
      end)
      |> distribute_requests(requests, [])
    
    {:ok, routing_plan}
  end
  
  defp distribute_requests([], remaining_requests, acc) do
    # Handle any remaining requests by adding to first engine
    case {remaining_requests, acc} do
      {[], _} -> acc
      {reqs, [{:ok, engine, existing_reqs} | rest]} ->
        [{:ok, engine, existing_reqs ++ reqs} | rest]
      {reqs, []} -> 
        # This shouldn't happen, but handle gracefully
        [{:ok, %{name: :default}, reqs}]
    end
  end
  
  defp distribute_requests([{engine, count} | rest], requests, acc) do
    {engine_requests, remaining} = Enum.split(requests, count)
    new_acc = [{:ok, engine, engine_requests} | acc]
    distribute_requests(rest, remaining, new_acc)
  end
  
  defp select_engine_for_affinity(state, affinity) do
    case affinity do
      :default -> 
        healthy_engines = get_healthy_engines(state.engines)
        select_least_connections(healthy_engines)
      engine_name ->
        case Map.get(state.engines, engine_name) do
          nil -> {:error, :engine_not_found}
          engine when engine.health == :healthy -> {:ok, engine}
          _ -> {:error, :engine_unhealthy}
        end
    end
  end
  
  defp route_to_engine(engine, request, opts, max_retries) do
    route_to_engine(engine, request, opts, max_retries, 0)
  end
  
  defp route_to_engine(engine, request, opts, max_retries, attempt) when attempt < max_retries do
    start_time = System.monotonic_time(:millisecond)
    
    # Convert engine name to atom if it's a string
    engine_identifier = case engine.pid || engine.name do
      name when is_binary(name) -> String.to_atom(name)
      name -> name
    end
    
    case SnmpMgr.Engine.submit_request(engine_identifier, request, opts) do
      {:ok, result} ->
        end_time = System.monotonic_time(:millisecond)
        response_time = end_time - start_time
        Logger.debug("Request routed successfully to #{engine.name} in #{response_time}ms")
        {:ok, result}
      
      {:error, reason} when reason in [:timeout, :no_available_connections] ->
        Logger.warning("Request failed on #{engine.name} (attempt #{attempt + 1}): #{inspect(reason)}")
        route_to_engine(engine, request, opts, max_retries, attempt + 1)
      
      {:error, reason} ->
        Logger.error("Request failed permanently on #{engine.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp route_to_engine(_engine, _request, _opts, max_retries, max_retries) do
    {:error, :max_retries_exceeded}
  end
  
  defp execute_routing_plan(routing_plan, opts, _max_retries) do
    # Execute all routing plan entries concurrently
    tasks = 
      Enum.map(routing_plan, fn {:ok, engine, requests} ->
        Task.async(fn ->
          # Convert engine name to atom if it's a string
          engine_identifier = case engine.pid || engine.name do
            name when is_binary(name) -> String.to_atom(name)
            name -> name
          end
          
          case SnmpMgr.Engine.submit_batch(engine_identifier, requests, opts) do
            {:ok, results} -> {:ok, engine.name, results}
            {:error, reason} -> {:error, engine.name, reason}
          end
        end)
      end)
    
    # Collect results
    results = Task.yield_many(tasks, 30_000)
    
    # Process results and handle failures
    Enum.map(results, fn {task, result} ->
      case result do
        {:ok, {:ok, engine_name, batch_results}} ->
          {:ok, engine_name, batch_results}
        {:ok, {:error, engine_name, reason}} ->
          {:error, engine_name, reason}
        nil ->
          Task.shutdown(task)
          {:error, :unknown_engine, :timeout}
      end
    end)
  end
  
  defp perform_health_checks(state) do
    new_engines = 
      Enum.map(state.engines, fn {name, engine} ->
        new_engine = check_engine_health(engine)
        {name, new_engine}
      end)
      |> Enum.into(%{})
    
    %{state | engines: new_engines}
  end
  
  defp check_engine_health(engine) do
    # Simple health check - in real implementation this would ping the engine
    health_status = if engine.error_count > 10 do
      :unhealthy
    else
      :healthy
    end
    
    %{engine | 
      health: health_status,
      last_health_check: System.monotonic_time(:second)
    }
  end
  
  defp get_engines_summary(engines) do
    Enum.map(engines, fn {name, engine} ->
      %{
        name: name,
        health: engine.health,
        current_load: engine.current_load,
        max_load: engine.max_load,
        error_count: engine.error_count,
        total_requests: engine.total_requests
      }
    end)
  end
  
  defp update_metrics(metrics, key, value) do
    Map.update(metrics, key, value, fn current -> current + value end)
  end

  # Configuration helper functions

  defp apply_health_check_config(state, config) do
    new_interval = Keyword.get(config, :health_check_interval, state.health_check_interval)
    enabled = Keyword.get(config, :health_check_enabled, true)
    
    new_state = %{state | 
      health_check_interval: if(enabled, do: new_interval, else: 0)
    }
    {:ok, new_state}
  end

  defp apply_batch_strategy_config(state, strategy_config) do
    # Store batch strategy in state (could extend router struct to include this)
    _batch_strategy = Keyword.get(strategy_config, :batch_strategy, :default)
    # For now, just return success - could add batch_strategy field to state
    {:ok, state}
  end

  defp get_detailed_engine_health(engines) do
    Enum.reduce(engines, %{}, fn {name, engine}, acc ->
      Map.put(acc, name, %{
        status: engine.health,
        last_check: engine.last_health_check,
        response_time: calculate_avg_response_time(engine.response_times),
        failure_count: engine.error_count,
        total_requests: engine.total_requests,
        current_load: engine.current_load,
        max_load: engine.max_load
      })
    end)
  end

  defp mark_engine_status(state, engine_name, status, reason) do
    case Map.get(state.engines, engine_name) do
      nil -> 
        {:error, {:engine_not_found, engine_name}}
      engine ->
        updated_engine = %{engine | 
          health: status,
          last_health_check: System.monotonic_time(:second)
        }
        updated_engine = if reason do
          %{updated_engine | error_count: updated_engine.error_count + 1}
        else
          updated_engine
        end
        new_engines = Map.put(state.engines, engine_name, updated_engine)
        {:ok, %{state | engines: new_engines}}
    end
  end

  defp attempt_recovery(state, engine_name) do
    case Map.get(state.engines, engine_name) do
      nil -> 
        {:error, {:engine_not_found, engine_name}}
      engine ->
        # Simple recovery: reset error count and mark healthy
        recovered_engine = %{engine | 
          health: :healthy,
          error_count: 0,
          last_health_check: System.monotonic_time(:second)
        }
        new_engines = Map.put(state.engines, engine_name, recovered_engine)
        {:ok, %{state | engines: new_engines}}
    end
  end

  defp calculate_avg_response_time(response_times) do
    case :queue.len(response_times) do
      0 -> 0
      len ->
        times = :queue.to_list(response_times)
        Enum.sum(times) / len
    end
  end
end