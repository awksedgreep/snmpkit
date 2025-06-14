defmodule SnmpMgr.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Configuration management
      {SnmpMgr.Config, []},
      # MIB registry and management
      {SnmpMgr.MIB, []},
      # Circuit breaker for fault tolerance
      {SnmpMgr.CircuitBreaker, []}
    ]

    opts = [strategy: :one_for_one, name: SnmpMgr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
