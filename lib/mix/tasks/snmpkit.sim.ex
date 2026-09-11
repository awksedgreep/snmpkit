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

  @usage "usage: mix snmpkit.sim CONFIG | --device TYPE [--port P] | --sample PATH"
  @bundled ["cable_modem", "router", "switch"]

  @impl true
  def run(argv) do
    {opts, positional} = CLI.parse(argv)
    CLI.ensure_app_started()

    cond do
      opts[:sample] ->
        format = if Path.extname(opts[:sample]) in [".yaml", ".yml"], do: :yaml, else: :json

        case SnmpKit.SnmpSim.write_sample_config(opts[:sample], format) do
          :ok -> Mix.shell().info("wrote #{opts[:sample]}")
          {:error, reason} -> Mix.raise("write sample failed: #{inspect(reason)}")
        end

      opts[:device] ->
        port = opts[:port] || 1161
        community = opts[:community] || "public"
        profile = load_profile(opts[:device]) |> CLI.unwrap!("load profile")

        SnmpKit.Sim.start_device(profile, port: port, community: community)
        |> CLI.unwrap!("start device")

        Mix.shell().info(
          "#{opts[:device]} listening on 127.0.0.1:#{port} (community #{community}); Ctrl-C to stop"
        )

        wait()

      match?([_], positional) ->
        [config] = positional
        SnmpKit.SnmpSim.start(config) |> CLI.unwrap!("start #{config}")

        devices = SnmpKit.SnmpSim.list_devices()
        Mix.shell().info("started #{length(devices)} device(s) from #{config}; Ctrl-C to stop")

        Enum.each(devices, fn d ->
          Mix.shell().info("  #{d.device_id || "?"} (#{d.device_type}) on port #{d.port}")
        end)

        wait()

      positional != [] ->
        Mix.raise("#{@usage}\n\nexpected one config file, got: #{Enum.join(positional, " ")}")

      true ->
        Mix.raise(@usage)
    end
  end

  defp load_profile(device) do
    cond do
      File.regular?(device) ->
        SnmpKit.SnmpSim.ProfileLoader.load_profile(:recorded, {:walk_file, device})

      device in @bundled ->
        SnmpKit.SnmpSim.ProfileLoader.load_profile(String.to_existing_atom(device))

      true ->
        Mix.raise(
          "unknown device #{inspect(device)}#{did_you_mean(device)}; " <>
            "--device takes #{Enum.join(@bundled, ", ")} or the path of a walk file"
        )
    end
  end

  defp did_you_mean(device) do
    {closest, distance} =
      @bundled
      |> Enum.map(&{&1, String.jaro_distance(device, &1)})
      |> Enum.max_by(&elem(&1, 1))

    if distance >= 0.75, do: " (did you mean #{closest}?)", else: ""
  end

  # Overridable in tests through the :snmpkit_sim_wait application env
  defp wait do
    case Application.get_env(:snmpkit, :sim_task_wait, :infinity) do
      :infinity -> Process.sleep(:infinity)
      ms -> Process.sleep(ms)
    end
  end
end
