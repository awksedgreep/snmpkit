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

  # Integer switches with a meaningful range: {min, max | nil}.
  @ranges [
    timeout: {1, nil},
    retries: {0, nil},
    port: {1, 65_535},
    max_repetitions: {1, nil},
    walk_timeout: {1, nil}
  ]

  # Files a MIB directory may contain that are never MIB sources.
  @skipped_extensions [".log", ".bin", ".json", ".md"]

  @doc """
  Parses task arguments into `{opts, positional}`; unknown switches and
  out-of-range values abort the task. `extra` adds task-specific switches.
  """
  def parse(argv, extra \\ []) do
    {opts, positional, invalid} =
      OptionParser.parse(argv, strict: @switches ++ extra, aliases: @aliases)

    if invalid != [] do
      Mix.raise("unknown option(s): " <> Enum.map_join(invalid, ", ", fn {k, _} -> k end))
    end

    check_ranges!(opts)
    {opts, positional}
  end

  defp check_ranges!(opts) do
    Enum.each(@ranges, fn {key, {min, max}} ->
      case Keyword.fetch(opts, key) do
        {:ok, value} when value < min or (is_integer(max) and value > max) ->
          flag = "--" <> String.replace(Atom.to_string(key), "_", "-")
          range = if max, do: "between #{min} and #{max}", else: "at least #{min}"
          Mix.raise("#{flag} must be #{range}, got #{value}")

        _ ->
          :ok
      end
    end)
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

  @doc """
  Expands MIB file and directory arguments into a list of files.

  A directory contributes its regular files, sorted, minus obvious non-MIBs
  (`#{Enum.join(@skipped_extensions, ", ")}`). A missing path, an unreadable
  directory or a directory with no candidate files is a task error.
  """
  def expand_mib_paths(paths), do: Enum.flat_map(paths, &expand_mib_path/1)

  defp expand_mib_path(path) do
    cond do
      File.dir?(path) ->
        files =
          case File.ls(path) do
            {:ok, entries} ->
              entries
              |> Enum.sort()
              |> Enum.map(&Path.join(path, &1))
              |> Enum.filter(&File.regular?/1)
              |> Enum.reject(&(Path.extname(&1) in @skipped_extensions))

            {:error, reason} ->
              Mix.raise("cannot read directory #{path}: #{:file.format_error(reason)}")
          end

        if files == [] do
          Mix.raise(
            "no MIB files in #{path} (#{Enum.join(@skipped_extensions, ", ")} files are skipped)"
          )
        end

        files

      File.regular?(path) ->
        [path]

      true ->
        Mix.raise("no such file or directory: #{path}")
    end
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

  @doc """
  Returns the value of an `{:ok, value}` result; any other result is a Mix
  error naming the operation.
  """
  def unwrap!({:ok, value}, _what), do: value
  def unwrap!({:error, reason}, what), do: Mix.raise("#{what} failed: #{inspect(reason)}")
  def unwrap!(other, what), do: Mix.raise("#{what} returned #{inspect(other)}")
end
