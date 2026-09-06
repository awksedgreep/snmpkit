defmodule SnmpKit.SnmpSim.Device.Metrics do
  @moduledoc """
  Uptime of a simulated device, derived from the monotonic clock at which
  the device started. Used for `sysUpTime.0`, `ifLastChange` and the
  `sysUpTime` carried by notifications the device sends.
  """

  @doc "Device uptime in milliseconds (0 when the state has no `uptime_start`)."
  @spec calculate_uptime(map()) :: non_neg_integer()
  def calculate_uptime(%{uptime_start: uptime_start}) when is_integer(uptime_start) do
    :erlang.convert_time_unit(:erlang.monotonic_time() - uptime_start, :native, :millisecond)
  end

  def calculate_uptime(_state), do: 0

  @doc "Device uptime as SNMP TimeTicks (centiseconds)."
  @spec calculate_uptime_ticks(map()) :: non_neg_integer()
  def calculate_uptime_ticks(state), do: div(calculate_uptime(state), 10)
end
