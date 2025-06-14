defmodule SnmpMgr.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern implementation for SNMP device failure protection.
  
  This module implements the circuit breaker pattern to prevent cascading failures
  when SNMP devices become unresponsive. It provides automatic failure detection,
  recovery attempts, and configurable thresholds for different failure scenarios.
  """
  
  use GenServer
  require Logger
  
  @default_failure_threshold 5
  @default_recovery_timeout 30_000  # 30 seconds
  @default_timeout_threshold 10_000  # 10 seconds
  @default_half_open_max_calls 3
  
  defstruct [
    :name,
    :failure_threshold,
    :recovery_timeout,
    :timeout_threshold,
    :half_open_max_calls,
    :breakers,
    :metrics
  ]
  
  @doc """
  Starts the circuit breaker manager.
  
  ## Options
  - `:failure_threshold` - Number of failures before opening circuit (default: 5)
  - `:recovery_timeout` - Time to wait before attempting recovery in ms (default: 30000)
  - `:timeout_threshold` - Request timeout threshold in ms (default: 10000)
  - `:half_open_max_calls` - Max calls in half-open state (default: 3)
  
  ## Examples
  
      {:ok, cb} = SnmpMgr.CircuitBreaker.start_link(
        failure_threshold: 10,
        recovery_timeout: 60_000
      )
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Executes a function with circuit breaker protection.
  
  ## Parameters
  - `cb` - Circuit breaker PID or name
  - `target` - Target identifier (device address/name)
  - `fun` - Function to execute
  - `timeout` - Operation timeout in ms
  
  ## Examples
  
      result = SnmpMgr.CircuitBreaker.call(cb, "192.168.1.1", fn ->
        SnmpMgr.get("192.168.1.1", "sysDescr.0")
      end, 5000)
  """
  def call(cb, target, fun, timeout \\ 5000) do
    GenServer.call(cb, {:call, target, fun, timeout})
  end
  
  @doc """
  Records a successful operation for a target.
  """
  def record_success(cb, target) do
    GenServer.cast(cb, {:record_success, target})
  end
  
  @doc """
  Records a failure for a target.
  """
  def record_failure(cb, target, reason) do
    GenServer.cast(cb, {:record_failure, target, reason})
  end
  
  @doc """
  Gets the current state of a circuit breaker for a target.
  """
  def get_state(cb, target) do
    GenServer.call(cb, {:get_state, target})
  end
  
  @doc """
  Gets statistics for all circuit breakers.
  """
  def get_stats(cb) do
    GenServer.call(cb, :get_stats)
  end
  
  @doc """
  Manually opens a circuit breaker for a target.
  """
  def open_circuit(cb, target) do
    GenServer.cast(cb, {:open_circuit, target})
  end
  
  @doc """
  Manually closes a circuit breaker for a target.
  """
  def close_circuit(cb, target) do
    GenServer.cast(cb, {:close_circuit, target})
  end
  
  @doc """
  Resets all circuit breakers.
  """
  def reset_all(cb) do
    GenServer.cast(cb, :reset_all)
  end

  @doc """
  Resets a specific circuit breaker for a target.
  """
  def reset(cb, target) do
    GenServer.cast(cb, {:reset, target})
  end

  @doc """
  Configures circuit breaker settings.
  """
  def configure(cb, config) do
    GenServer.call(cb, {:configure, config})
  end

  @doc """
  Gets configuration for a specific target.
  """
  def get_config(cb, target) do
    GenServer.call(cb, {:get_config, target})
  end

  @doc """
  Configures settings for a specific target.
  """
  def configure_target(cb, target, config) do
    GenServer.call(cb, {:configure_target, target, config})
  end

  @doc """
  Forces a circuit breaker to open state.
  """
  def force_open(cb, target) do
    GenServer.cast(cb, {:force_open, target})
  end

  @doc """
  Forces a circuit breaker to half-open state.
  """
  def force_half_open(cb, target) do
    GenServer.cast(cb, {:force_half_open, target})
  end

  @doc """
  Gets all active targets.
  """
  def get_all_targets(cb) do
    GenServer.call(cb, :get_all_targets)
  end

  @doc """
  Gets statistics for a specific target.
  """
  def get_stats(cb, target) do
    GenServer.call(cb, {:get_stats, target})
  end

  @doc """
  Removes a target from the circuit breaker.
  """
  def remove_target(cb, target) do
    GenServer.cast(cb, {:remove_target, target})
  end

  @doc """
  Gets global circuit breaker statistics.
  """
  def get_global_stats(cb) do
    GenServer.call(cb, :get_global_stats)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__),
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      recovery_timeout: Keyword.get(opts, :recovery_timeout, @default_recovery_timeout),
      timeout_threshold: Keyword.get(opts, :timeout_threshold, @default_timeout_threshold),
      half_open_max_calls: Keyword.get(opts, :half_open_max_calls, @default_half_open_max_calls),
      breakers: %{},
      metrics: initialize_metrics()
    }
    
    Logger.info("SnmpMgr CircuitBreaker started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:call, target, fun, timeout}, _from, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    
    case breaker.state do
      :closed ->
        execute_with_breaker(state, target, breaker, fun, timeout)
      
      :open ->
        if should_attempt_reset?(breaker, state.recovery_timeout) do
          # Transition to half-open
          new_breaker = %{breaker | 
            state: :half_open,
            half_open_calls: 0,
            last_failure_time: System.monotonic_time(:millisecond)
          }
          
          new_breakers = Map.put(state.breakers, target, new_breaker)
          new_state = %{state | breakers: new_breakers}
          
          execute_with_breaker(new_state, target, new_breaker, fun, timeout)
        else
          # Circuit is open, fail fast
          metrics = update_metrics(state.metrics, :fast_failures, 1)
          new_state = %{state | metrics: metrics}
          {:reply, {:error, :circuit_breaker_open}, new_state}
        end
      
      :half_open ->
        if breaker.half_open_calls < state.half_open_max_calls do
          execute_with_breaker(state, target, breaker, fun, timeout)
        else
          # Too many calls in half-open, stay open
          new_breaker = %{breaker | state: :open}
          new_breakers = Map.put(state.breakers, target, new_breaker)
          new_state = %{state | breakers: new_breakers}
          
          metrics = update_metrics(new_state.metrics, :fast_failures, 1)
          new_state = %{new_state | metrics: metrics}
          
          {:reply, {:error, :circuit_breaker_open}, new_state}
        end
    end
  end
  
  @impl true
  def handle_call({:get_state, target}, _from, state) do
    breaker = Map.get(state.breakers, target)
    
    if breaker do
      breaker_info = %{
        state: breaker.state,
        failure_count: breaker.failure_count,
        success_count: breaker.success_count,
        last_failure_time: breaker.last_failure_time,
        last_success_time: breaker.last_success_time,
        half_open_calls: breaker.half_open_calls
      }
      {:reply, {:ok, breaker_info}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_breakers: map_size(state.breakers),
      breaker_states: get_breaker_states(state.breakers),
      metrics: state.metrics
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:configure, config}, _from, state) do
    new_state = %{state |
      failure_threshold: Keyword.get(config, :failure_threshold, state.failure_threshold),
      recovery_timeout: Keyword.get(config, :recovery_timeout, state.recovery_timeout),
      timeout_threshold: Keyword.get(config, :timeout_threshold, state.timeout_threshold),
      half_open_max_calls: Keyword.get(config, :half_open_max_calls, state.half_open_max_calls)
    }
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_config, target}, _from, state) do
    breaker = Map.get(state.breakers, target)
    if breaker do
      config = %{
        failure_threshold: state.failure_threshold,
        recovery_timeout: state.recovery_timeout,
        timeout_threshold: state.timeout_threshold,
        half_open_max_calls: state.half_open_max_calls
      }
      {:reply, {:ok, config}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:configure_target, _target, _config}, _from, state) do
    # For now, just acknowledge - could extend to per-target config
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_all_targets, _from, state) do
    targets = Map.keys(state.breakers)
    {:reply, {:ok, targets}, state}
  end

  @impl true
  def handle_call({:get_stats, target}, _from, state) do
    breaker = Map.get(state.breakers, target)
    if breaker do
      stats = %{
        state: breaker.state,
        failure_count: breaker.failure_count,
        success_count: breaker.success_count,
        last_failure_time: breaker.last_failure_time,
        last_success_time: breaker.last_success_time,
        last_failure_reason: breaker.last_failure_reason,
        half_open_calls: breaker.half_open_calls,
        created_at: breaker.created_at
      }
      {:reply, {:ok, stats}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:get_global_stats, _from, state) do
    total_targets = map_size(state.breakers)
    breaker_states = get_breaker_states(state.breakers)
    
    total_failures = Enum.reduce(state.breakers, 0, fn {_target, breaker}, acc ->
      acc + breaker.failure_count
    end)
    
    total_successes = Enum.reduce(state.breakers, 0, fn {_target, breaker}, acc ->
      acc + breaker.success_count
    end)
    
    global_stats = %{
      total_targets: total_targets,
      total_failures: total_failures,
      total_successes: total_successes,
      state_distribution: breaker_states,
      system_metrics: state.metrics
    }
    
    {:reply, {:ok, global_stats}, state}
  end
  
  @impl true
  def handle_cast({:record_success, target}, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    
    new_breaker = case breaker.state do
      :half_open ->
        # Successful call in half-open, increment success count
        updated = %{breaker | 
          success_count: breaker.success_count + 1,
          last_success_time: System.monotonic_time(:millisecond),
          half_open_calls: breaker.half_open_calls + 1
        }
        
        # If enough successes, close the circuit
        if updated.success_count >= 3 do
          Logger.info("Closing circuit breaker for #{target} after successful recovery")
          %{updated | 
            state: :closed,
            failure_count: 0,
            half_open_calls: 0
          }
        else
          updated
        end
      
      _ ->
        # Normal success
        %{breaker | 
          success_count: breaker.success_count + 1,
          last_success_time: System.monotonic_time(:millisecond)
        }
    end
    
    new_breakers = Map.put(state.breakers, target, new_breaker)
    metrics = update_metrics(state.metrics, :successes, 1)
    
    new_state = %{state | breakers: new_breakers, metrics: metrics}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_failure, target, reason}, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    
    new_breaker = %{breaker | 
      failure_count: breaker.failure_count + 1,
      last_failure_time: System.monotonic_time(:millisecond),
      last_failure_reason: reason
    }
    
    # Check if we should open the circuit
    new_breaker = if new_breaker.failure_count >= state.failure_threshold do
      Logger.warning("Opening circuit breaker for #{target} due to #{new_breaker.failure_count} failures")
      %{new_breaker | state: :open}
    else
      new_breaker
    end
    
    new_breakers = Map.put(state.breakers, target, new_breaker)
    metrics = update_metrics(state.metrics, :failures, 1)
    
    new_state = %{state | breakers: new_breakers, metrics: metrics}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:open_circuit, target}, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    new_breaker = %{breaker | state: :open}
    new_breakers = Map.put(state.breakers, target, new_breaker)
    
    Logger.info("Manually opened circuit breaker for #{target}")
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:close_circuit, target}, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    new_breaker = %{breaker | 
      state: :closed,
      failure_count: 0,
      half_open_calls: 0
    }
    new_breakers = Map.put(state.breakers, target, new_breaker)
    
    Logger.info("Manually closed circuit breaker for #{target}")
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast(:reset_all, state) do
    Logger.info("Resetting all circuit breakers")
    
    new_breakers = 
      Enum.map(state.breakers, fn {target, _breaker} ->
        {target, create_breaker()}
      end)
      |> Enum.into(%{})
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:reset, target}, state) do
    Logger.info("Resetting circuit breaker for #{target}")
    
    new_breaker = create_breaker()
    new_breakers = Map.put(state.breakers, target, new_breaker)
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:force_open, target}, state) do
    Logger.info("Forcing circuit breaker open for #{target}")
    
    breaker = get_or_create_breaker(state.breakers, target, state)
    new_breaker = %{breaker | 
      state: :open,
      last_failure_time: System.monotonic_time(:millisecond)
    }
    new_breakers = Map.put(state.breakers, target, new_breaker)
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:force_half_open, target}, state) do
    Logger.info("Forcing circuit breaker half-open for #{target}")
    
    breaker = get_or_create_breaker(state.breakers, target, state)
    new_breaker = %{breaker | 
      state: :half_open,
      half_open_calls: 0,
      last_failure_time: System.monotonic_time(:millisecond)
    }
    new_breakers = Map.put(state.breakers, target, new_breaker)
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove_target, target}, state) do
    Logger.info("Removing circuit breaker target #{target}")
    
    new_breakers = Map.delete(state.breakers, target)
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp initialize_metrics() do
    %{
      successes: 0,
      failures: 0,
      fast_failures: 0,
      timeouts: 0,
      circuit_opens: 0,
      circuit_closes: 0,
      last_reset: System.monotonic_time(:second)
    }
  end
  
  defp get_or_create_breaker(breakers, target, _state) do
    Map.get(breakers, target, create_breaker())
  end
  
  defp create_breaker() do
    %{
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      last_success_time: nil,
      last_failure_reason: nil,
      half_open_calls: 0,
      created_at: System.monotonic_time(:millisecond)
    }
  end
  
  defp execute_with_breaker(state, target, breaker, fun, timeout) do
    start_time = System.monotonic_time(:millisecond)
    
    # Execute with timeout
    task = Task.async(fun)
    
    case Task.yield(task, timeout) do
      {:ok, result} ->
        end_time = System.monotonic_time(:millisecond)
        _execution_time = end_time - start_time
        
        # Record success
        new_breaker = case breaker.state do
          :half_open ->
            updated = %{breaker | 
              success_count: breaker.success_count + 1,
              last_success_time: end_time,
              half_open_calls: breaker.half_open_calls + 1
            }
            
            # If enough successes in half-open, close circuit
            if updated.success_count >= 3 do
              Logger.info("Closing circuit breaker for #{target} after successful recovery")
              %{updated | 
                state: :closed,
                failure_count: 0,
                half_open_calls: 0
              }
            else
              updated
            end
          
          _ ->
            %{breaker | 
              success_count: breaker.success_count + 1,
              last_success_time: end_time
            }
        end
        
        new_breakers = Map.put(state.breakers, target, new_breaker)
        metrics = update_metrics(state.metrics, :successes, 1)
        
        new_state = %{state | breakers: new_breakers, metrics: metrics}
        
        {:reply, {:ok, result}, new_state}
      
      nil ->
        # Timeout or task crashed
        Task.shutdown(task)
        
        new_breaker = %{breaker | 
          failure_count: breaker.failure_count + 1,
          last_failure_time: System.monotonic_time(:millisecond),
          last_failure_reason: :timeout_or_crash
        }
        
        # Check if we should open circuit
        new_breaker = if new_breaker.failure_count >= state.failure_threshold do
          Logger.warning("Opening circuit breaker for #{target} due to timeout or crash")
          %{new_breaker | state: :open}
        else
          new_breaker
        end
        
        new_breakers = Map.put(state.breakers, target, new_breaker)
        metrics = update_metrics(state.metrics, :timeouts, 1)
        metrics = update_metrics(metrics, :failures, 1)
        
        new_state = %{state | breakers: new_breakers, metrics: metrics}
        
        {:reply, {:error, :timeout_or_crash}, new_state}
    end
  end
  
  defp should_attempt_reset?(breaker, recovery_timeout) do
    if breaker.last_failure_time do
      current_time = System.monotonic_time(:millisecond)
      (current_time - breaker.last_failure_time) >= recovery_timeout
    else
      true
    end
  end
  
  defp get_breaker_states(breakers) do
    breakers
    |> Enum.group_by(fn {_target, breaker} -> breaker.state end)
    |> Enum.map(fn {state, breakers_list} -> {state, length(breakers_list)} end)
    |> Enum.into(%{})
  end
  
  defp update_metrics(metrics, key, value) do
    Map.update(metrics, key, value, fn current -> current + value end)
  end
end