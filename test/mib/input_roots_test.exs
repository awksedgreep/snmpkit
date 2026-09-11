defmodule SnmpKit.MIB.InputRootsTest do
  # Mutates the :input_roots application env, so it must not overlap with
  # async tests that read walk files or MIBs from priv/.
  use ExUnit.Case, async: false

  alias SnmpKit.MIB.{Compiler, Error, Lint}

  @moduletag :tmp_dir

  @mib """
  ROOTS-TEST-MIB DEFINITIONS ::= BEGIN

  rootsTestNode OBJECT IDENTIFIER ::= { 1 3 6 1 4 1 99993 }

  END
  """

  setup %{tmp_dir: dir} do
    inside = Path.join(dir, "inside")
    outside = Path.join(dir, "outside")
    File.mkdir_p!(inside)
    File.mkdir_p!(outside)

    compiled = :erlang.term_to_binary(%{__type__: :compiled_mib, name: "ROOTS-TEST-MIB"})

    paths = %{
      in_mib: Path.join(inside, "ROOTS-TEST-MIB.mib"),
      out_mib: Path.join(outside, "ROOTS-TEST-MIB.mib"),
      in_bin: Path.join(inside, "ROOTS-TEST-MIB.bin"),
      out_bin: Path.join(outside, "ROOTS-TEST-MIB.bin")
    }

    File.write!(paths.in_mib, @mib)
    File.write!(paths.out_mib, @mib)
    File.write!(paths.in_bin, compiled)
    File.write!(paths.out_bin, compiled)

    previous = Application.get_env(:snmpkit, :input_roots)
    Application.put_env(:snmpkit, :input_roots, [inside])

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:snmpkit, :input_roots)
        roots -> Application.put_env(:snmpkit, :input_roots, roots)
      end
    end)

    paths
  end

  test "Compiler.compile/2 refuses a MIB outside the roots and compiles one inside", paths do
    assert {:error, [%Error{type: :file_rejected, message: message, context: context}]} =
             Compiler.compile(paths.out_mib)

    assert message =~ "input_roots"
    assert context == %{path: paths.out_mib, reason: :outside_allowed_roots}

    assert {:ok, %{name: "ROOTS-TEST-MIB"}} = Compiler.compile(paths.in_mib)
  end

  test "Compiler.compile_all/2 reports the rejection per file", paths do
    assert {:error, [{out, [%Error{type: :file_rejected}]}]} =
             Compiler.compile_all([paths.in_mib, paths.out_mib])

    assert out == paths.out_mib
  end

  test "Lint.check/2 refuses a path outside the roots and lints one inside", paths do
    assert {:error, :outside_allowed_roots} = Lint.check(paths.out_mib)
    assert {:ok, %{findings: findings}} = Lint.check(paths.in_mib)
    assert is_list(findings)
  end

  test "SnmpMgr.MIB.parse_mib_file/2 refuses a path outside the roots", paths do
    assert {:error, {:file_read_error, :outside_allowed_roots}} =
             SnmpKit.SnmpMgr.MIB.parse_mib_file(paths.out_mib)

    assert {:ok, %{parsed_objects: _}} = SnmpKit.SnmpMgr.MIB.parse_mib_file(paths.in_mib)
  end

  test "Compiler.load_compiled/1 refuses a compiled MIB outside the roots", paths do
    assert {:error, :outside_allowed_roots} = Compiler.load_compiled(paths.out_bin)
    assert {:ok, %{name: "ROOTS-TEST-MIB"}} = Compiler.load_compiled(paths.in_bin)
  end

  test "Compiler.load_compiled/1 keeps its own size cap ahead of the roots check", paths do
    Application.put_env(:snmpkit, :max_compiled_mib_bytes, 8)

    try do
      assert {:error, {:compiled_mib_too_large, _size, 8}} = Compiler.load_compiled(paths.in_bin)
      assert {:error, {:compiled_mib_too_large, _size, 8}} = Compiler.load_compiled(paths.out_bin)
    after
      Application.delete_env(:snmpkit, :max_compiled_mib_bytes)
    end
  end

  test "SnmpMgr.MIB.load_and_integrate_mib/2 refuses a MIB outside the roots", paths do
    assert {:error, {:snmp_lib_compilation_failed, [%Error{type: :file_rejected}]}} =
             SnmpKit.SnmpMgr.MIB.load_and_integrate_mib(paths.out_mib)
  end

  test "Parser.mibdirs/1 skips files outside the roots", paths do
    outside_dir = Path.dirname(paths.out_mib)
    results = SnmpKit.MIB.Parser.mibdirs([outside_dir])

    assert %{
             success: [],
             failures: [
               %{file: "ROOTS-TEST-MIB.mib", error: {:file_read_error, :outside_allowed_roots}}
             ]
           } = results[outside_dir]
  end
end
