ExUnit.start()

require Logger

# Configure logging level for tests
Logger.configure(level: :warning)

# Configure ExUnit
ExUnit.configure(
  # 10 seconds default timeout
  timeout: 10_000,
  # Increase parallelism
  max_cases: System.schedulers_online() * 2,
  exclude: [
    # Optional test categories - can be included with mix test --include tag_name
    # Slow running tests
    # :slow,
    # Integration tests
    # :integration,
    # Performance tests
    :performance,
    # DOCSIS-specific tests
    # :docsis,
    # Memory-intensive tests
    :memory,
    # Format compatibility tests
    # :format_compatibility,
    # Edge case parsing tests
    # :parsing_edge_cases,
    # Shell integration tests
    :shell_integration,

    # Optional tests
    :optional,
    # SNMP Manager integration tests
    :snmp_mgr,
    # Tests that require simulator
    :needs_simulator
  ]
)

# Note: SnmpKit uses its own SNMP implementation and does not require Erlang's :snmp application

# Start the snmpkit application to ensure all components are available
case Application.ensure_all_started(:snmpkit) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
  error -> Logger.debug("Warning: Could not start snmpkit application: #{inspect(error)}")
end

# SnmpKit uses its own SNMP implementation - no Erlang SNMP configuration needed

# SnmpKit handles its own logging configuration

# Ensure no processes are using common test ports before starting tests
for port <- [161, 1161, 4161] do
  System.cmd("lsof", ["-i", ":#{port}", "-t"])
  |> case do
    {output, 0} ->
      pids = String.split(output, "\n", trim: true)
      Enum.each(pids, fn pid -> System.cmd("kill", ["-9", pid]) end)

    _ ->
      :ok
  end
end

# Ensure test support modules are compiled
support_dir = Path.join(__DIR__, "support")

if File.exists?(support_dir) do
  support_dir
  |> File.ls!()
  |> Enum.filter(&String.ends_with?(&1, ".ex"))
  |> Enum.each(fn file ->
    Code.require_file(file, support_dir)
  end)
end

# SnmpKit provides clean test output without Erlang SNMP noise
