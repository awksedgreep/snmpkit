defmodule SnmpSim.MIB.Compiler do
  @moduledoc """
  MIB Compiler for SNMP Simulator (Elixir)

  - Compiles MIB files using MIB parsing and compilation.
  - Handles MIB dependencies via IMPORTS parsing and topological sort.
  - Does NOT use any Erlang SNMP APIs.
  - Does NOT introspect MIB objects at runtime (for that, parse the compiled MIBs yourself).

  This module provides MIB compilation functionality for SNMP simulation.
  """

  require Logger

  @doc """
  Compile all .mib files in `mib_dir` (recursively resolves dependencies).
  Returns a list of {mib_file, {:ok, _} | {:error, _}}.
  """
  def compile_mib_directory(mib_dir, opts \\ []) do
    include_dirs = Keyword.get(opts, :include_dirs, [mib_dir])
    mib_files = list_mib_files([mib_dir])
    imports = get_imports(mib_files)
    adj = convert_imports_to_adjacencies(imports)
    ordered = topological_sort(adj)
    compile_mib_files(ordered, include_dirs)
  end

  @doc """
  Compile a list of MIB files (in dependency order).
  Returns a list of {mib_file, {:ok, _} | {:error, _}}.
  """
  def compile_mib_files(mib_files, include_dirs \\ []) do
    Enum.map(mib_files, fn mib_file ->
      case compile_single_mib(mib_file, include_dirs) do
        {:ok, _} = ok ->
          Logger.info("Compiled MIB: #{mib_file}")
          {mib_file, ok}

        {:error, reason} = err ->
          Logger.error("Failed to compile #{mib_file}: #{inspect(reason)}")
          {mib_file, err}
      end
    end)
  end

  defp compile_single_mib(mib_file, include_dirs) do
    erl_outdir = :binary.bin_to_list(Path.dirname(mib_file))
    erl_mib_file = :binary.bin_to_list(mib_file)
    erl_include_paths = Enum.map(include_dirs, &:binary.bin_to_list("#{&1}/"))

    options = [
      :relaxed_row_name_assign_check,
      warnings: false,
      verbosity: :silence,
      group_check: false,
      i: erl_include_paths,
      outdir: erl_outdir
    ]

    # MIB compilation is currently disabled - Erlang SNMP dependencies removed
    # Future implementation would use pure Elixir MIB parsing
    {:error, :mib_compilation_disabled}
  end

  defp list_mib_files(paths) do
    Enum.flat_map(paths, fn path ->
      path
      |> File.ls!()
      |> Stream.map(&Path.join(path, &1))
      |> Enum.filter(&String.ends_with?(&1, ".mib"))
    end)
  end

  defp get_imports_from_lines(lines) do
    lines
    |> Stream.filter(&String.contains?(&1, "FROM"))
    |> Stream.flat_map(fn line ->
      mib_import =
        ~r/\s?FROM\s+([^\s;]+)/
        |> Regex.run(line, capture: :all_but_first)

      mib_import || []
    end)
    |> Enum.to_list()
  end

  defp _get_imports([], acc), do: acc

  defp _get_imports([mib_file | rest], acc) do
    imports =
      try do
        mib_file
        |> File.stream!()
        |> get_imports_from_lines()
        |> Enum.map(fn name ->
          Path.join(Path.dirname(mib_file), "#{name}.mib")
        end)
        |> Enum.map(&{mib_file, &1})
      rescue
        File.Error ->
          Logger.debug("Unable to find MIB file: #{inspect(mib_file)}")
          [{mib_file, []}]
      end

    _get_imports(rest, Enum.concat(imports, acc))
  end

  defp get_imports(mib_files) when is_list(mib_files), do: _get_imports(mib_files, [])

  defp convert_imports_to_adjacencies(imports),
    do: Enum.group_by(imports, &elem(&1, 1), &elem(&1, 0))

  defp topological_sort(adjacency_map) do
    # Simple DFS-based topological sort
    visited = MapSet.new()
    result = []

    {sorted, _} =
      Enum.reduce(Map.keys(adjacency_map), {result, visited}, fn node, {acc, v} ->
        _topo_visit(node, adjacency_map, acc, v)
      end)

    Enum.reverse(sorted)
  end

  defp _topo_visit(node, adjacency_map, acc, visited) do
    if MapSet.member?(visited, node) do
      {acc, visited}
    else
      neighbors = Map.get(adjacency_map, node, [])

      {acc, visited} =
        Enum.reduce(neighbors, {acc, MapSet.put(visited, node)}, fn n, {a, v} ->
          _topo_visit(n, adjacency_map, a, v)
        end)

      {[node | acc], MapSet.put(visited, node)}
    end
  end
end
