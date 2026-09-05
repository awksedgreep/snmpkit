defmodule SnmpKit.MIB.OracleHelper do
  @moduledoc false
  # Shared plumbing for the libsmi and net-snmp oracle tests.

  @fixture_dirs [
    "test/fixtures/mibs/working",
    "test/fixtures/mibs/docsis",
    "test/fixtures/mibs/topvision/STANDARD_MIB_FILES",
    "test/fixtures/mibs/topvision/PRIVATE_MIB_FILES",
    "test/fixtures/mibs/broken"
  ]

  def fixture_dirs, do: @fixture_dirs

  def fixture_files do
    @fixture_dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*")))
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&(Path.extname(&1) in [".txt", ".log", ".bin"]))
    |> Enum.sort()
  end

  def native_parse(file) do
    case SnmpKit.MIB.Parser.parse(File.read!(file)) do
      {:ok, _} -> {:ok, file}
      {:error, e} -> {:error, e |> inspect() |> String.slice(0, 120)}
    end
  rescue
    e -> {:error, "raised " <> (e |> Exception.message() |> String.slice(0, 120))}
  end

  def find_tool(env_var, name) do
    System.get_env(env_var) || System.find_executable(name)
  end

  def report(label, results) do
    parsed = Enum.count(results, &match?(%{ours: {:ok, _}}, &1))
    both = Enum.count(results, &match?(%{oracle_errors: [_ | _], ours: {:error, _}}, &1))

    IO.puts(
      "\n#{label} oracle: #{length(results)} files, #{parsed} parsed natively, #{both} rejected by both"
    )
  end

  def assert_not_stricter(results, label) do
    stricter =
      for %{file: f, oracle_errors: [], ours: {:error, e}} <- results, do: "#{f}: #{e}"

    ExUnit.Assertions.assert(
      stricter == [],
      "#{label} accepts but SnmpKit rejects:\n" <> Enum.join(stricter, "\n")
    )
  end
end

defmodule SnmpKit.MIB.SmilintOracleTest do
  @moduledoc """
  Cross-checks the native MIB parser against libsmi's `smilint`.

  Opt in with `mix test --include mib_oracle test/mib/smilint_oracle_test.exs`.
  `smilint` is found on PATH or via `SMILINT`; the test passes with a notice
  when it is absent. See docs/mib-parser-oracle.md.
  """
  use ExUnit.Case, async: false
  alias SnmpKit.MIB.OracleHelper, as: H

  @moduletag :mib_oracle
  @moduletag timeout: 300_000

  setup_all do
    case H.find_tool("SMILINT", "smilint") do
      nil ->
        IO.puts("\nsmilint not found; libsmi oracle skipped (see docs/mib-parser-oracle.md)")
        {:ok, results: nil}

      smilint ->
        results = Enum.map(H.fixture_files(), &compare(smilint, &1))
        H.report("libsmi", results)
        {:ok, results: results}
    end
  end

  test "SnmpKit is never stricter than smilint on syntax", %{results: results} do
    if results, do: H.assert_not_stricter(results, "smilint")
  end

  defp compare(smilint, file) do
    {out, _} =
      System.cmd(smilint, ["-p", mib_path(smilint), "-s", "-l", "2", file],
        stderr_to_stdout: true
      )

    errors =
      out
      |> String.split("\n")
      |> Enum.filter(
        &(String.starts_with?(&1, file <> ":") and String.contains?(&1, "syntax error"))
      )

    %{file: file, oracle_errors: errors, ours: H.native_parse(file)}
  end

  # libsmi's own MIB tree (next to the binary) plus the fixture dirs, so that
  # IMPORTS resolve and smilint reports real syntax problems only.
  defp mib_path(smilint) do
    share = Path.join([Path.dirname(smilint), "..", "share", "mibs"])

    dirs =
      for sub <- ["ietf", "iana", "irtf", "tubs"],
          dir = Path.join(share, sub),
          File.dir?(dir),
          do: dir

    Enum.join(dirs ++ H.fixture_dirs(), ":")
  end
end

defmodule SnmpKit.MIB.NetSnmpOracleTest do
  @moduledoc """
  Cross-checks the native MIB parser against net-snmp's parser via
  `snmptranslate` (found on PATH or via `SNMPTRANSLATE`). net-snmp is the
  most permissive parser in common use, so anything it loads we must load.
  """
  use ExUnit.Case, async: false
  alias SnmpKit.MIB.OracleHelper, as: H

  @moduletag :mib_oracle
  @moduletag timeout: 300_000

  setup_all do
    case H.find_tool("SNMPTRANSLATE", "snmptranslate") do
      nil ->
        IO.puts(
          "\nsnmptranslate not found; net-snmp oracle skipped (see docs/mib-parser-oracle.md)"
        )

        {:ok, results: nil}

      tool ->
        results = Enum.map(H.fixture_files(), &compare(tool, &1))
        H.report("net-snmp", results)
        {:ok, results: results}
    end
  end

  test "SnmpKit is never stricter than net-snmp", %{results: results} do
    if results, do: H.assert_not_stricter(results, "net-snmp")
  end

  defp compare(tool, file) do
    abs = Path.expand(file)

    {out, _} =
      System.cmd(tool, ["-M", mib_path(tool), "-m", abs, "-Le", ".1.3"],
        stderr_to_stdout: true,
        env: [{"MIBS", ""}]
      )

    # Parse errors are reported as "<message>: At line N in <file>"; linkage
    # problems ("Undefined identifier", "Unlinked OID") are not syntax.
    errors =
      out
      |> String.split("\n")
      |> Enum.filter(&String.ends_with?(&1, " in " <> abs))
      |> Enum.filter(&String.contains?(&1, ": At line "))

    %{file: file, oracle_errors: errors, ours: H.native_parse(file)}
  end

  defp mib_path(tool) do
    share = Path.join([Path.dirname(tool), "..", "share", "snmp", "mibs"])
    dirs = if File.dir?(share), do: [share], else: []
    Enum.join(Enum.map(dirs ++ H.fixture_dirs(), &Path.expand/1), ":")
  end
end
