defmodule Mix.Tasks.Snmpkit.Walk do
  @shortdoc "Walk a subtree or table on a device"
  @moduledoc """
  Walks a subtree and prints every object, like `snmpwalk`.

      mix snmpkit.walk HOST [OID] [options]

      mix snmpkit.walk 192.168.1.1 system
      mix snmpkit.walk 192.168.1.1 ifTable --table
      mix snmpkit.walk switch:1161 1.3.6.1.2.1.2 --no-bulk -v 1

  `OID` defaults to `system`. Options:

    * `-c`, `--community`, `-v`, `--version`, `-t`, `--timeout`, `-r`, `--retries`,
      `-p`, `--port` - as for `mix snmpkit.get`
    * `--no-bulk` - use GETNEXT instead of GETBULK (SNMPv1 agents)
    * `--max-repetitions` - GETBULK repetitions per request
    * `--walk-timeout` - cap on the whole walk, milliseconds
    * `--table` - print the subtree as a table with named columns
    * `--numeric`, `--raw` - as for `mix snmpkit.get`
  """
  use Mix.Task

  alias SnmpKit.CLI

  @usage "usage: mix snmpkit.walk HOST [OID] [options]"

  @impl true
  def run(argv) do
    {opts, positional} = CLI.parse(argv)

    case positional do
      [host] ->
        walk(host, "system", opts)

      [host, oid] ->
        walk(host, oid, opts)

      [_host, _oid | extra] ->
        Mix.raise("#{@usage}\n\nwalk takes one OID; extra: #{inspect(extra)}")

      [] ->
        Mix.raise(@usage)
    end
  end

  defp walk(host, oid, opts) do
    CLI.ensure_app_started()
    snmp_opts = CLI.snmp_opts(opts)

    cond do
      opts[:table] ->
        SnmpKit.SNMP.get_table(host, oid, Keyword.put(snmp_opts, :named, true))
        |> CLI.unwrap!("walk #{host}")
        |> print_table()

      opts[:bulk] == false ->
        SnmpKit.SNMP.walk(host, oid, snmp_opts)
        |> CLI.unwrap!("walk #{host}")
        |> Enum.each(&Mix.shell().info(CLI.format_varbind(&1, opts)))

      true ->
        SnmpKit.SNMP.bulk_walk(host, oid, snmp_opts)
        |> CLI.unwrap!("walk #{host}")
        |> Enum.each(&Mix.shell().info(CLI.format_varbind(&1, opts)))
    end
  end

  defp print_table(table) when map_size(table) == 0, do: Mix.shell().info("(empty table)")

  defp print_table(table) do
    columns =
      table
      |> Map.values()
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()
      |> Enum.sort_by(&to_string/1)

    header = ["index" | Enum.map(columns, &to_string/1)]

    rows =
      table
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {index, row} ->
        [inspect(index) | Enum.map(columns, &cell(Map.get(row, &1)))]
      end)

    widths =
      [header | rows]
      |> Enum.zip_with(fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)

    Enum.each([header | rows], fn cells ->
      cells
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing(cell, width) end)
      |> Mix.shell().info()
    end)
  end

  defp cell(nil), do: ""

  defp cell(value) when is_binary(value),
    do: if(String.printable?(value), do: value, else: inspect(value))

  defp cell(value), do: inspect(value)
end
