ExUnit.start()

require Logger

# Configure logging level for tests
Logger.configure(level: :warning)

# Configure ExUnit
ExUnit.configure(
  timeout: 10_000,  # 10 seconds default timeout
  max_cases: System.schedulers_online() * 2,  # Increase parallelism
  exclude: [
    # Optional test categories - can be included with mix test --include tag_name
    :slow,              # Slow running tests
    :integration,       # Integration tests
    :performance,       # Performance tests
    :docsis,           # DOCSIS-specific tests
    :memory,           # Memory-intensive tests
    :format_compatibility,  # Format compatibility tests
    :parsing_edge_cases,   # Edge case parsing tests
    :shell_integration,    # Shell integration tests
    :erlang,              # Erlang SNMP integration tests
    :optional,            # Optional tests
    :snmp_mgr,            # SNMP Manager integration tests
    :needs_simulator      # Tests that require simulator
  ]
)

# Start SNMP application for integration tests
case Application.start(:snmp) do
  :ok -> :ok
  {:error, {:already_started, _}} -> :ok
  error -> Logger.debug("Warning: Could not start SNMP application: #{inspect(error)}")
end

# Start the snmpkit application to ensure all components are available
case Application.ensure_all_started(:snmpkit) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
  error -> Logger.debug("Warning: Could not start snmpkit application: #{inspect(error)}")
end

# Configure SNMP manager for silent operation during tests
Application.put_env(:snmp, :manager, [
  {:config, [{:dir, "/tmp"}, {:log_type, :none}]},
  {:server, [{:timeout, 30000}, {:verbosity, :silence}]},
  {:net_if, [{:verbosity, :silence}]},
  {:note_store, [{:verbosity, :silence}]},
  {:config, [{:verbosity, :silence}]},
  {:versions, [:v1, :v2, :v3]}
])

# Configure SNMP agent for silent operation
Application.put_env(:snmp, :agent, [
  {:config, [{:dir, "/tmp"}, {:log_type, :none}]},
  {:verbosity, :silence}
])

# Set SNMP manager logging to none
try do
  :snmpm.set_log_type(:none)
  :snmpm.set_verbosity(:silence)
  :snmpm.set_verbosity(:net_if, :silence)
  :snmpm.set_verbosity(:note_store, :silence)
  :snmpm.set_verbosity(:server, :silence)
catch
  _, _ -> :ok
end

# Set SNMP agent logging to none
try do
  :snmpa.set_log_type(:none)
  :snmpa.set_verbosity(:silence)
catch
  _, _ -> :ok
end

# Configure erlang logger to suppress snmp logs
:logger.set_module_level(:snmpm, :none)
:logger.set_module_level(:snmpa, :none)
:logger.set_module_level(:snmp, :none)
:logger.set_module_level(:snmpm_server, :none)
:logger.set_module_level(:snmpm_config, :none)
:logger.set_module_level(:snmpm_net_if, :none)

# Add logger filter to drop SNMP-related messages
:logger.add_primary_filter(
  :snmp_filter,
  {fn log_event, _filter_config ->
     case log_event do
       %{msg: {:string, msg}} when is_list(msg) ->
         msg_str = List.to_string(msg)
         if String.contains?(msg_str, "snmpm:") or String.contains?(msg_str, "mk_target_name") do
           :stop
         else
           :ignore
         end

       %{msg: {:report, report}} when is_map(report) ->
         if Map.has_key?(report, :snmpm) or
              (Map.has_key?(report, :label) and report.label == :snmpm) do
           :stop
         else
           :ignore
         end

       _ ->
         :ignore
     end
   end, %{}}
)

# Ensure no processes are using common test ports before starting tests
for port <- [161, 1161, 4161] do
  System.cmd("lsof", ["-i", ":#{port}", "-t"])
  |> case do
    {output, 0} ->
      pids = String.split(output, "\n", trim: true)
      Enum.each(pids, fn pid -> System.cmd("kill", ["-9", pid]) end)
    _ -> :ok
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

# Note: SNMP manager debug output (snmpm:mk_target_name messages) appears to be
# deeply embedded in the Erlang SNMP library and cannot be easily suppressed.
# These messages are informational only and do not affect test functionality.
# To filter them visually, you can pipe test output through grep:
# mix test 2>&1 | grep -v "snmpm:"