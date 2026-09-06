defmodule Mix.Tasks.Snmpkit.Mib.Compile do
  @shortdoc "Compile MIB files and report warnings"
  @moduledoc """
  Compiles MIB files or directories with the native compiler and prints the
  warnings the parser recorded (vendor constructs, bad literals, encoding).

      mix snmpkit.mib.compile PATH [PATH ...] [options]

      mix snmpkit.mib.compile priv/mibs
      mix snmpkit.mib.compile DOCS-IF-MIB.mib -O priv/compiled

  Options:

    * `-O`, `--output` - write the compiled MIBs (binary format) to this directory
    * `-q`, `--quiet` - only print failures and the summary

  Exits with a non-zero status when any file fails to compile.
  """
  use Mix.Task

  alias SnmpKit.CLI

  @impl true
  def run(argv) do
    {opts, paths} = CLI.parse(argv)

    if paths == [], do: Mix.raise("usage: mix snmpkit.mib.compile PATH [PATH ...] [options]")

    CLI.ensure_app_started()
    files = Enum.flat_map(paths, &expand/1)
    compile_opts = if opts[:output], do: [output_dir: opts[:output], format: :binary], else: []

    results =
      Enum.map(files, fn file ->
        case SnmpKit.MIB.Compiler.compile(file, compile_opts) do
          {:ok, compiled} ->
            unless opts[:quiet] do
              Mix.shell().info("compiled #{file} (#{map_size(compiled.symbols)} symbols)")

              Enum.each(compiled.warnings, fn {line, msg} ->
                Mix.shell().info("  #{file}:#{line}: warning: #{msg}")
              end)
            end

            {:ok, file, length(compiled.warnings)}

          {:error, errors} ->
            Mix.shell().error("failed  #{file}")

            Enum.each(List.wrap(errors), fn error ->
              Mix.shell().error("  " <> describe(error))
            end)

            {:error, file}
        end
      end)

    ok = Enum.count(results, &match?({:ok, _, _}, &1))

    warnings =
      results
      |> Enum.map(fn
        {:ok, _, w} -> w
        _ -> 0
      end)
      |> Enum.sum()

    failed = length(results) - ok

    Mix.shell().info("#{ok} compiled, #{failed} failed, #{warnings} warning(s)")
    if failed > 0, do: exit({:shutdown, 1})
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

  defp describe(%SnmpKit.MIB.Error{message: message, line: nil}), do: message
  defp describe(%SnmpKit.MIB.Error{message: message, line: line}), do: "line #{line}: #{message}"

  defp describe({:snmp_lib_compilation_failed, errors}),
    do: Enum.map_join(List.wrap(errors), "; ", &describe/1)

  defp describe(other), do: inspect(other)
end
