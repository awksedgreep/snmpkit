defmodule Mix.Tasks.Snmpkit.Sim do
  @shortdoc "Run simulated SNMP devices from a config file or a bundled profile"
  @moduledoc """
  Starts simulated devices and keeps them running until interrupted.

      mix snmpkit.sim CONFIG.json|CONFIG.yaml
      mix snmpkit.sim --device router --port 1161
      mix snmpkit.sim --sample sim.json

  Options:

    * `--device` - one bundled profile (`cable_modem`, `router`, `switch`) or
      a walk file path
    * `-p`, `--port` - UDP port for `--device` (default 1161)
    * `-c`, `--community` - community for `--device` (default `public`)
    * `--sample` - write an example configuration to this path and exit
      (`.json` or `.yaml`)

  A configuration file describes device groups, ports and behaviours; see
  `SnmpKit.SnmpSim.sample_config/0`. YAML files need the optional
  `yaml_elixir` dependency.
  """
  use Mix.Task

  alias SnmpKit.CLI

  @impl true
  def run(argv) do
    {opts, positional} = CLI.parse(argv)
    CLI.ensure_app_started()

    cond do
      opts[:sample] ->
        format = if Path.extname(opts[:sample]) in [".yaml", ".yml"], do: :yaml, else: :json

        :ok =
          SnmpKit.SnmpSim.write_sample_config(opts[:sample], format) |> CLI.report("write sample")

        Mix.shell().info("wrote #{opts[:sample]}")

      opts[:device] ->
        port = opts[:port] || 1161
        community = opts[:community] || "public"
        {:ok, profile} = load_profile(opts[:device]) |> CLI.report("load profile")

        {:ok, _pid} =
          SnmpKit.Sim.start_device(profile, port: port, community: community)
          |> CLI.report("start device")

        Mix.shell().info(
          "#{opts[:device]} listening on 127.0.0.1:#{port} (community #{community}); Ctrl-C to stop"
        )

        wait()

      positional != [] ->
        [config | _] = positional
        {:ok, _sup} = SnmpKit.SnmpSim.start(config) |> CLI.report("start #{config}")

        devices = SnmpKit.SnmpSim.list_devices()
        Mix.shell().info("started #{length(devices)} device(s) from #{config}; Ctrl-C to stop")

        Enum.each(devices, fn d ->
          Mix.shell().info("  #{d.device_id || "?"} (#{d.device_type}) on port #{d.port}")
        end)

        wait()

      true ->
        Mix.raise("usage: mix snmpkit.sim CONFIG | --device TYPE [--port P] | --sample PATH")
    end
  end

  defp load_profile(device) do
    if File.regular?(device) do
      SnmpKit.SnmpSim.ProfileLoader.load_profile(:recorded, {:walk_file, device})
    else
      case device do
        "cable_modem" -> SnmpKit.SnmpSim.ProfileLoader.load_profile(:cable_modem)
        "router" -> SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
        "switch" -> SnmpKit.SnmpSim.ProfileLoader.load_profile(:switch)
        other -> {:error, {:unknown_device, other}}
      end
    end
  end

  # Overridable in tests through the :snmpkit_sim_wait application env
  defp wait do
    case Application.get_env(:snmpkit, :sim_task_wait, :infinity) do
      :infinity -> Process.sleep(:infinity)
      ms -> Process.sleep(ms)
    end
  end
end
