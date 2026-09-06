defmodule SnmpKit.SnmpSim.Recorder do
  @moduledoc """
  Records a real device into the walk-file format the simulator loads, so a
  device can be captured once and replayed with
  `SnmpKit.SnmpSim.ProfileLoader.load_profile(type, {:walk_file, path})`.

      :ok = SnmpKit.Sim.record("192.168.1.1", "test/fixtures/core-switch.walk", community: "public")

  The file uses net-snmp's numeric `snmpwalk -On` style, one line per object:

      .1.3.6.1.2.1.1.1.0 = STRING: "Cisco IOS Software"
      .1.3.6.1.2.1.2.2.1.6.1 = Hex-STRING: 00 1A 2B 3C 4D 5E
      .1.3.6.1.2.1.1.3.0 = Timeticks: (123456) 0:20:34.56

  ## Options

  - `:root` - subtree to record (default `"1.3.6.1.2.1"`, mib-2; use
    `"1.3.6.1"` for everything the agent has, enterprise objects included)
  - `:community`, `:version`, `:timeout`, `:retries`, `:walk_timeout` - as
    for `SnmpKit.SNMP.bulk_walk/3`
  """

  @type record_result :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Walks `target` from `root` and writes the objects to `path`. Returns
  `{:ok, count}` with the number of objects written.
  """
  @spec record(term(), Path.t(), keyword()) :: record_result()
  def record(target, path, opts \\ []) do
    {root, walk_opts} = Keyword.pop(opts, :root, "1.3.6.1.2.1")
    walk_opts = Keyword.merge(walk_opts, include_names: false, include_formatted: false)

    with {:ok, varbinds} <- SnmpKit.SNMP.bulk_walk(target, root, walk_opts),
         {:ok, lines} <- to_lines(varbinds),
         :ok <- File.write(path, lines) do
      {:ok, length(varbinds)}
    end
  end

  @doc "Renders enriched varbinds (as returned by walks) as walk-file text."
  @spec to_lines([map()]) :: {:ok, iodata()} | {:error, term()}
  def to_lines(varbinds) when is_list(varbinds) do
    lines =
      varbinds
      |> Enum.flat_map(fn vb ->
        case line(vb) do
          nil -> []
          text -> [text, "\n"]
        end
      end)

    {:ok, lines}
  end

  @doc "One walk-file line for a varbind, or `nil` for values that cannot be recorded."
  @spec line(map()) :: String.t() | nil
  def line(%{oid: oid, type: type, value: value}) do
    case render(type, value) do
      nil -> nil
      rendered -> "." <> to_string(oid) <> " = " <> rendered
    end
  end

  defp render(:integer, v) when is_integer(v), do: "INTEGER: #{v}"
  defp render(:counter32, v) when is_integer(v), do: "Counter32: #{v}"
  defp render(:counter64, v) when is_integer(v), do: "Counter64: #{v}"
  defp render(:gauge32, v) when is_integer(v), do: "Gauge32: #{v}"
  defp render(:unsigned32, v) when is_integer(v), do: "Gauge32: #{v}"

  defp render(:timeticks, v) when is_integer(v),
    do: "Timeticks: (#{v}) #{SnmpKit.SnmpMgr.Format.uptime(v)}"

  defp render(:ip_address, <<a, b, c, d>>), do: "IpAddress: #{a}.#{b}.#{c}.#{d}"
  defp render(:ip_address, {a, b, c, d}), do: "IpAddress: #{a}.#{b}.#{c}.#{d}"
  defp render(:ip_address, v) when is_binary(v), do: "IpAddress: #{v}"

  defp render(:object_identifier, v) when is_list(v), do: "OID: ." <> Enum.join(v, ".")

  defp render(:object_identifier, v) when is_binary(v),
    do: "OID: ." <> String.trim_leading(v, ".")

  defp render(type, v) when type in [:octet_string, :opaque, :bits] and is_binary(v) do
    if type == :octet_string and String.valid?(v) and String.printable?(v) and
         not String.contains?(v, "\"") do
      "STRING: \"#{v}\""
    else
      "Hex-STRING: " <>
        (v
         |> Base.encode16()
         |> String.graphemes()
         |> Enum.chunk_every(2)
         |> Enum.map_join(" ", &Enum.join/1))
    end
  end

  defp render(:null, _), do: nil
  defp render(_exception_or_unknown, _), do: nil
end
