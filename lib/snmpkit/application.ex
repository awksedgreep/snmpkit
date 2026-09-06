defmodule Snmpkit.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Manager configuration (defaults, include_names/include_formatted, auto-start flag)
      SnmpKit.SnmpMgr.Config,
      # Remembers SNMPv3 engine ids and boots/time per target
      SnmpKit.SnmpLib.Security.EngineCache,
      # Shared profiles manager for memory-efficient device data
      SnmpKit.SnmpSim.MIB.SharedProfiles,
      # MIB resolution and compilation service
      SnmpKit.SnmpMgr.MIB,
      # Core supervisor for managing device processes
      {DynamicSupervisor, name: SnmpSim.DeviceSupervisor, strategy: :one_for_one},
      # Supervisor for the concurrent manager services (RequestIdGenerator,
      # Engine). They are started here rather than linked to
      # whichever caller happened to touch them first.
      {DynamicSupervisor, name: SnmpKit.SnmpMgr.ServiceSupervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Snmpkit.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      if SnmpKit.SnmpMgr.Config.get(:auto_start_services) != false do
        SnmpKit.SnmpMgr.ensure_started()
      end

      {:ok, pid}
    end
  end
end
