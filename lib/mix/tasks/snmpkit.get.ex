defmodule Mix.Tasks.Snmpkit.Get do
  @shortdoc "SNMP GET one or more objects from a device"
  @moduledoc """
  Retrieves objects from a device and prints them one per line.

      mix snmpkit.get HOST OID [OID ...] [options]

      mix snmpkit.get 192.168.1.1 sysDescr.0 sysUpTime.0
      mix snmpkit.get switch:1161 1.3.6.1.2.1.1.5.0 -c private -v 2c

  Several OIDs go into one PDU. Options:

    * `-c`, `--community` - community string (default from config)
    * `-v`, `--version` - `1`, `2c` or `3`
    * `-t`, `--timeout` - per-PDU timeout in milliseconds
    * `-r`, `--retries` - retries per PDU
    * `-p`, `--port` - UDP port (also accepted as `HOST:PORT`)
    * `--numeric` - print OIDs instead of names
    * `--raw` - print the raw value instead of the formatted one
  """
  use Mix.Task

  alias SnmpKit.CLI

  @impl true
  def run(argv) do
    {opts, positional} = CLI.parse(argv)

    case positional do
      [host, oid | more] ->
        CLI.ensure_app_started()
        oids = [oid | more]

        target = host

        result =
          if more == [],
            do: get_one(target, oid, opts),
            else: SnmpKit.SNMP.get(target, oids, CLI.snmp_opts(opts))

        result
        |> CLI.report("GET #{host}")
        |> case do
          {:ok, varbinds} -> Enum.each(varbinds, &Mix.shell().info(CLI.format_varbind(&1, opts)))
        end

      _ ->
        Mix.raise("usage: mix snmpkit.get HOST OID [OID ...] [options]")
    end
  end

  defp get_one(target, oid, opts) do
    case SnmpKit.SNMP.get(target, oid, CLI.snmp_opts(opts)) do
      {:ok, varbind} -> {:ok, [varbind]}
      error -> error
    end
  end
end
