defmodule SnmpKit.SnmpMgr.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Configuration management
      {SnmpKit.SnmpMgr.Config, []},
      # MIB registry and management
      {SnmpKit.SnmpMgr.MIB, []},
      # Circuit breaker for fault tolerance
      {SnmpKit.SnmpMgr.CircuitBreaker, []}
    ]

    opts = [strategy: :one_for_one, name: SnmpKit.SnmpMgr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
