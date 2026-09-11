defmodule SnmpKit.SnmpSim.SafeFile do
  @moduledoc false
  # Former name of `SnmpKit.SafeFile` (1.4.0); kept so existing callers work.

  defdelegate read(path, opts \\ []), to: SnmpKit.SafeFile
  defdelegate stream(path, opts \\ []), to: SnmpKit.SafeFile
  defdelegate check(path, opts \\ []), to: SnmpKit.SafeFile
  defdelegate configured_max_bytes(), to: SnmpKit.SafeFile
  defdelegate configured_roots(), to: SnmpKit.SafeFile
end
