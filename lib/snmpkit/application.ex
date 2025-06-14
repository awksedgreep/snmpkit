defmodule Snmpkit.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Shared profiles manager for memory-efficient device data
      SnmpKit.SnmpSim.MIB.SharedProfiles,
      # MIB resolution and compilation service
      SnmpKit.SnmpMgr.MIB,
      # Core supervisor for managing device processes
      {DynamicSupervisor, name: SnmpSim.DeviceSupervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Snmpkit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
