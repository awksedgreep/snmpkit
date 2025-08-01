defmodule SnmpKit.SnmpMgr.EngineV2 do
  @moduledoc """
  Pure response correlator for SNMP operations.
  
  This engine focuses solely on correlating SNMP responses back to their
  originating processes. It does not handle sending - that is done directly
  by Tasks using the shared socket from SocketManager.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :name,
    :pending_requests,
    :metrics,
    :timeout_refs
  ]
  
  @doc """
  Starts the Engine response correlator.
  
  ## Options
  - `:name` - Process name (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Registers a request for response correlation.
  
  ## Parameters
  - `engine` - Engine PID or name
  - `request_id` - Unique request identifier
  - `caller_pid` - Process to send response to
  - `timeout_ms` - Timeout in milliseconds (optional)
  
  ## Examples
  
      SnmpKit.SnmpMgr.EngineV2.register_request(engine, 12345, self(), 5000)
  """
  def register_request(engine, request_id, caller_pid, timeout_ms \\ 5000) do
    GenServer.cast(engine, {:register_request, request_id, caller_pid, timeout_ms})
  end
  
  @doc """
  Unregisters a request (used when caller times out locally).
  
  ## Parameters  
  - `engine` - Engine PID or name
  - `request_id` - Request identifier to unregister
  """
  def unregister_request(engine, request_id) do
    GenServer.cast(engine, {:unregister_request, request_id})
  end
  
  @doc """
  Gets engine statistics and metrics.
  """
  def get_stats(engine) do
    GenServer.call(engine, :get_stats)
  end
  
  @doc """
  Gets the number of pending requests.
  """
  def pending_count(engine) do
    GenServer.call(engine, :pending_count)
  end
  
  @doc """
  Gracefully shuts down the engine.
  """
  def stop(engine) do
    GenServer.call(engine, :stop)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    Logger.info("EngineV2 (Response Correlator) starting")
    
    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__),
      pending_requests: %{},
      metrics: initialize_metrics(),
      timeout_refs: %{}
    }
    
    Logger.info("EngineV2 started successfully")
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:register_request, request_id, caller_pid, timeout_ms}, state) do
    # Register the request for correlation
    pending_requests = Map.put(state.pending_requests, request_id, %{
      caller_pid: caller_pid,
      registered_at: System.monotonic_time(:millisecond)
    })
    
    # Schedule timeout
    timeout_ref = Process.send_after(self(), {:request_timeout, request_id}, timeout_ms)
    timeout_refs = Map.put(state.timeout_refs, request_id, timeout_ref)
    
    # Update metrics
    metrics = update_metrics(state.metrics, :requests_registered, 1)
    
    new_state = %{state |
      pending_requests: pending_requests,
      timeout_refs: timeout_refs,
      metrics: metrics
    }
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:unregister_request, request_id}, state) do
    new_state = remove_request(state, request_id)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      pending_requests: map_size(state.pending_requests),
      metrics: state.metrics
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:pending_count, _from, state) do
    count = map_size(state.pending_requests)
    {:reply, count, state}
  end
  
  @impl true
  def handle_call(:stop, _from, state) do
    # Cancel all pending timeouts
    Enum.each(state.timeout_refs, fn {_id, ref} ->
      Process.cancel_timer(ref)
    end)
    
    {:stop, :normal, :ok, state}
  end
  
  @impl true
  def handle_info({:udp, _socket, ip, port, data}, state) do
    # Handle incoming UDP responses
    Logger.debug("EngineV2 received UDP response from #{:inet.ntoa(ip)}:#{port}, #{byte_size(data)} bytes")
    
    case decode_snmp_response(data) do
      {:ok, request_id, response_data} ->
        new_state = handle_correlated_response(state, request_id, response_data)
        {:noreply, new_state}
        
      {:error, reason} ->
        Logger.warning("Failed to decode SNMP response: #{inspect(reason)}")
        metrics = update_metrics(state.metrics, :decode_failures, 1)
        {:noreply, %{state | metrics: metrics}}
    end
  end
  
  @impl true
  def handle_info({:request_timeout, request_id}, state) do
    # Handle request timeout
    case Map.get(state.pending_requests, request_id) do
      nil ->
        # Request already completed
        {:noreply, state}
        
      request_info ->
        # Send timeout to caller
        send(request_info.caller_pid, {:snmp_timeout, request_id})
        
        # Remove the request
        new_state = remove_request(state, request_id)
        
        # Update metrics
        metrics = update_metrics(new_state.metrics, :requests_timeout, 1)
        new_state = %{new_state | metrics: metrics}
        
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info({:mock_response, request_id, response_data}, state) do
    # Handle mock response for testing
    new_state = handle_correlated_response(state, request_id, response_data)
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp initialize_metrics() do
    %{
      requests_registered: 0,
      requests_completed: 0,
      requests_timeout: 0,
      decode_failures: 0,
      unknown_responses: 0,
      avg_response_time: 0,
      last_reset: System.monotonic_time(:second)
    }
  end
  
  defp handle_correlated_response(state, request_id, response_data) do
    case Map.get(state.pending_requests, request_id) do
      nil ->
        Logger.warning("Received response for unknown request ID: #{request_id}")
        metrics = update_metrics(state.metrics, :unknown_responses, 1)
        %{state | metrics: metrics}
        
      request_info ->
        # Send response to caller
        send(request_info.caller_pid, {:snmp_response, request_id, response_data})
        
        # Calculate response time
        response_time = System.monotonic_time(:millisecond) - request_info.registered_at
        
        # Remove the request
        new_state = remove_request(state, request_id)
        
        # Update metrics
        metrics = update_metrics(new_state.metrics, :requests_completed, 1)
        metrics = update_avg_response_time(metrics, response_time)
        
        %{new_state | metrics: metrics}
    end
  end
  
  defp remove_request(state, request_id) do
    # Remove from pending requests
    pending_requests = Map.delete(state.pending_requests, request_id)
    
    # Cancel and remove timeout
    case Map.get(state.timeout_refs, request_id) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end
    timeout_refs = Map.delete(state.timeout_refs, request_id)
    
    %{state | 
      pending_requests: pending_requests,
      timeout_refs: timeout_refs
    }
  end
  
  defp decode_snmp_response(data) do
    case SnmpKit.SnmpLib.PDU.decode_message(data) do
      {:ok, message} ->
        request_id = message.pdu.request_id
        response_data = extract_response_data(message.pdu)
        {:ok, request_id, response_data}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp extract_response_data(pdu) do
    # Extract meaningful data from PDU
    case pdu do
      %{varbinds: varbinds} -> 
        Enum.map(varbinds, &format_varbind/1)
      %{"varbinds" => varbinds} -> 
        Enum.map(varbinds, &format_varbind/1)
      _ -> 
        pdu
    end
  end
  
  defp format_varbind(varbind) do
    case varbind do
      {oid, type, value} -> {oid, type, value}
      %{oid: oid, type: type, value: value} -> {oid, type, value}
      _ -> varbind
    end
  end
  
  defp update_metrics(metrics, key, increment) do
    Map.update(metrics, key, increment, fn current -> current + increment end)
  end
  
  defp update_avg_response_time(metrics, new_time) do
    current_avg = metrics.avg_response_time
    completed = metrics.requests_completed
    
    new_avg = 
      if completed <= 1 do
        new_time
      else
        (current_avg * (completed - 1) + new_time) / completed
      end
    
    Map.put(metrics, :avg_response_time, new_avg)
  end
end