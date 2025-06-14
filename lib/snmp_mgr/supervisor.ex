defmodule SnmpMgr.Supervisor do
  @moduledoc """
  Main supervisor for the SnmpMgr streaming PDU engine infrastructure.
  
  This supervisor manages all Phase 5 components including engines, routers,
  connection pools, circuit breakers, and metrics collection.
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, SnmpMgr.EngineSupervisor)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end
  
  @impl true
  def init(opts) do
    # Configuration
    engine_config = Keyword.get(opts, :engine, [])
    router_config = Keyword.get(opts, :router, [])
    _pool_config = Keyword.get(opts, :pool, [])
    circuit_breaker_config = Keyword.get(opts, :circuit_breaker, [])
    metrics_config = Keyword.get(opts, :metrics, [])
    
    children = [
      # Metrics collection (start first)
      {SnmpMgr.Metrics, metrics_config},
      
      # Circuit breaker
      {SnmpMgr.CircuitBreaker, circuit_breaker_config},
      
      # Connection pool (temporarily disabled - not yet implemented)
      # {SnmpMgr.Pool, pool_config},
      
      # Main engines (can have multiple)
      Supervisor.child_spec({SnmpMgr.Engine, Keyword.put(engine_config, :name, :engine_1)}, id: :engine_1),
      Supervisor.child_spec({SnmpMgr.Engine, Keyword.put(engine_config, :name, :engine_2)}, id: :engine_2),
      
      # Router (coordinates engines)
      {SnmpMgr.Router, 
        Keyword.merge(router_config, [
          engines: [
            %{name: :engine_1, weight: 1, max_load: 100},
            %{name: :engine_2, weight: 1, max_load: 100}
          ]
        ])}
    ]
    
    Logger.info("Starting SnmpMgr Phase 5 infrastructure")
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end