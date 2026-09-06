defmodule Mix.Tasks.Snmpkit.Mib.Lint do
  @shortdoc "Check MIB files for semantic problems"
  @moduledoc """
  Runs `SnmpKit.MIB.Lint` over MIB files or directories and prints the
  findings, one per line, followed by a summary.

      mix snmpkit.mib.lint PATH [PATH ...] [options]

      mix snmpkit.mib.lint priv/mibs
      mix snmpkit.mib.lint VENDOR-MIB.mib --context priv/mibs/VENDOR-SMI.mib --strict

  Options:

    * `--context PATH` - MIB file or directory whose definitions satisfy
      imports (repeatable)
    * `--strict` - exit non-zero on warnings as well as errors
    * `-q`, `--quiet` - print only the summary

  Exits with status 1 when any file has errors (or warnings with `--strict`)
  or fails to parse.
  """
  use Mix.Task

  alias SnmpKit.CLI

  @impl true
  def run(argv) do
    {opts, paths, invalid} =
      OptionParser.parse(argv,
        strict: [context: :keep, strict: :boolean, quiet: :boolean],
        aliases: [q: :quiet]
      )

    if invalid != [],
      do: Mix.raise("unknown option(s): " <> Enum.map_join(invalid, ", ", &elem(&1, 0)))

    if paths == [], do: Mix.raise("usage: mix snmpkit.mib.lint PATH [PATH ...] [options]")

    CLI.ensure_app_started()

    context =
      opts
      |> Keyword.get_values(:context)
      |> Enum.flat_map(&expand/1)
      |> Enum.flat_map(fn file ->
        case SnmpKit.MIB.Compiler.compile(file, []) do
          {:ok, compiled} ->
            [compiled]

          {:error, _} ->
            Mix.shell().error("context file #{file} does not compile; ignored")
            []
        end
      end)

    results =
      paths
      |> Enum.flat_map(&expand/1)
      |> Enum.map(fn file ->
        case SnmpKit.MIB.Lint.check(file, context: context) do
          {:ok, report} ->
            unless opts[:quiet] do
              Enum.each(report.findings, &Mix.shell().info(SnmpKit.MIB.Lint.format(&1, file)))
            end

            {file, report.errors, report.warnings}

          {:error, reason} ->
            Mix.shell().error("#{file}: cannot check: #{describe(reason)}")
            {file, 1, 0}
        end
      end)

    errors = results |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    warnings = results |> Enum.map(&elem(&1, 2)) |> Enum.sum()
    Mix.shell().info("#{length(results)} file(s), #{errors} error(s), #{warnings} warning(s)")

    if errors > 0 or (opts[:strict] == true and warnings > 0), do: exit({:shutdown, 1})
  end

  defp expand(path) do
    cond do
      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.sort()
        |> Enum.map(&Path.join(path, &1))
        |> Enum.filter(&File.regular?/1)
        |> Enum.reject(&(Path.extname(&1) in [".txt", ".log", ".bin", ".json", ".md"]))

      File.regular?(path) ->
        [path]

      true ->
        Mix.raise("no such file or directory: #{path}")
    end
  end

  defp describe({:snmp_lib_compilation_failed, [%{message: message} | _]}), do: message
  defp describe(other), do: inspect(other)
end
