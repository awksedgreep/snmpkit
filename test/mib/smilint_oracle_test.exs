defmodule SnmpKit.MIB.SmilintOracleTest do
  @moduledoc """
  Cross-checks the native MIB parser against libsmi's `smilint`.

  Opt in with `mix test --include smilint test/mib/smilint_oracle_test.exs`.
  `smilint` is found on PATH or via the `SMILINT` environment variable; the
  test passes with a notice when it is absent. See docs/mib-parser-oracle.md.
  """
  use ExUnit.Case, async: false

  @moduletag :smilint
  @moduletag timeout: 300_000

  @fixture_dirs [
    "test/fixtures/mibs/working",
    "test/fixtures/mibs/docsis",
    "test/fixtures/mibs/topvision/STANDARD_MIB_FILES",
    "test/fixtures/mibs/topvision/PRIVATE_MIB_FILES",
    "test/fixtures/mibs/broken"
  ]

  setup_all do
    case System.get_env("SMILINT") || System.find_executable("smilint") do
      nil ->
        IO.puts("\nsmilint not found; oracle comparison skipped (see docs/mib-parser-oracle.md)")
        {:ok, results: nil}

      smilint ->
        {:ok, results: Enum.map(fixture_files(), &compare(smilint, &1))}
    end
  end

  test "every MIB smilint accepts syntactically also parses natively", %{results: results} do
    if results do
      mismatches =
        for %{file: f, smilint_syntax: [], ours: {:error, e}} <- results, do: "#{f}: #{e}"

      assert mismatches == [],
             "smilint accepts but SnmpKit rejects:\n" <> Enum.join(mismatches, "\n")
    end
  end

  test "SnmpKit is never stricter than smilint on syntax", %{results: results} do
    if results do
      stricter =
        for %{file: f, smilint_syntax: [], ours: {:error, _}} = r <- results,
            r.smilint_syntax == [],
            do: f

      assert stricter == [],
             "SnmpKit rejects files smilint parses:\n" <> Enum.join(stricter, "\n")

      rejected_by_both =
        for %{smilint_syntax: [_ | _], ours: {:error, _}} <- results, do: 1

      IO.puts(
        "\nsmilint oracle: #{length(results)} files, " <>
          "#{Enum.count(results, &match?(%{ours: {:ok, _}}, &1))} parsed natively, " <>
          "#{length(rejected_by_both)} rejected by both"
      )
    end
  end

  defp fixture_files do
    @fixture_dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*")))
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&(Path.extname(&1) in [".txt", ".log", ".bin"]))
    |> Enum.sort()
  end

  defp compare(smilint, file) do
    {out, _status} =
      System.cmd(smilint, ["-p", mib_path(smilint), "-s", "-l", "2", file],
        stderr_to_stdout: true
      )

    syntax =
      out
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, file <> ":"))
      |> Enum.filter(&String.contains?(&1, "syntax error"))

    ours =
      try do
        case SnmpKit.MIB.Parser.parse(File.read!(file)) do
          {:ok, _} -> {:ok, file}
          {:error, e} -> {:error, inspect(e) |> String.slice(0, 120)}
        end
      rescue
        e -> {:error, ("raised " <> Exception.message(e)) |> String.slice(0, 120)}
      end

    %{file: file, smilint_syntax: syntax, ours: ours}
  end

  # libsmi's own MIB tree (next to the binary) plus the fixture dirs, so that
  # IMPORTS resolve and smilint reports real syntax problems only.
  defp mib_path(smilint) do
    share = Path.join([Path.dirname(smilint), "..", "share", "mibs"])

    libsmi_dirs =
      for sub <- ["ietf", "iana", "irtf", "tubs"],
          dir = Path.join(share, sub),
          File.dir?(dir),
          do: dir

    Enum.join(libsmi_dirs ++ @fixture_dirs, ":")
  end
end
