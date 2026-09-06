defmodule SnmpKit.CLI do
  @moduledoc false
  # Shared plumbing for the `mix snmpkit.*` tasks: option parsing and the
  # `snmpwalk`-style output line.

  @switches [
    community: :string,
    version: :string,
    timeout: :integer,
    retries: :integer,
    port: :integer,
    max_repetitions: :integer,
    bulk: :boolean,
    table: :boolean,
    raw: :boolean,
    numeric: :boolean,
    output: :string,
    quiet: :boolean,
    sample: :string,
    device: :string,
    root: :string,
    walk_timeout: :integer
  ]

  @aliases [c: :community, v: :version, t: :timeout, r: :retries, p: :port, O: :output, q: :quiet]

  @doc "Parses task arguments into `{opts, positional}`; unknown switches abort the task."
  def parse(argv) do
    {opts, positional, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    if invalid != [] do
      Mix.raise("unknown option(s): " <> Enum.map_join(invalid, ", ", fn {k, _} -> k end))
    end

    {opts, positional}
  end

  @doc "Translates parsed CLI options into `SnmpKit.SNMP` call options."
  def snmp_opts(opts) do
    opts
    |> Keyword.take([:community, :timeout, :retries, :port, :max_repetitions, :walk_timeout])
    |> Keyword.merge(version_opt(opts[:version]))
    |> Keyword.merge(if opts[:numeric], do: [include_names: false], else: [])
  end

  defp version_opt(nil), do: []
  defp version_opt("1"), do: [version: :v1]
  defp version_opt("v1"), do: [version: :v1]
  defp version_opt("2c"), do: [version: :v2c]
  defp version_opt("v2c"), do: [version: :v2c]
  defp version_opt("2"), do: [version: :v2c]
  defp version_opt("3"), do: [version: :v3]
  defp version_opt("v3"), do: [version: :v3]

  defp version_opt(other),
    do: Mix.raise("unknown SNMP version #{inspect(other)} (use 1, 2c or 3)")

  @doc "Starts the application so the MIB registry and engine are available."
  def ensure_app_started do
    Mix.Task.run("app.start", [])
  end

  @doc ~S"""
  One line per varbind, like `snmpwalk`: `ifDescr.1 = OCTET STRING: "eth0"`.
  With `raw: true` the value is printed instead of the formatted text.
  """
  def format_varbind(%{} = vb, opts \\ []) do
    label = if opts[:numeric] || is_nil(Map.get(vb, :name)), do: vb.oid, else: vb.name
    type = vb.type |> Atom.to_string() |> String.upcase() |> String.replace("_", " ")

    value =
      cond do
        opts[:raw] -> inspect(vb.value)
        Map.has_key?(vb, :formatted) -> quote_if_string(vb.type, vb.formatted, vb.value)
        true -> inspect(vb.value)
      end

    "#{label} = #{type}: #{value}"
  end

  defp quote_if_string(:octet_string, formatted, value) when formatted == value,
    do: inspect(formatted)

  defp quote_if_string(_type, formatted, _value), do: formatted

  @doc "Prints a result or raises a Mix error with the reason."
  def report({:error, reason}, what), do: Mix.raise("#{what} failed: #{inspect(reason)}")
  def report(other, _what), do: other
end
