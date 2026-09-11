defmodule Mix.Tasks.SnmpkitTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup_all do
    Mix.shell(Mix.Shell.IO)
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    port = 26_000 + :rand.uniform(5_000)
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: port)
    on_exit(fn -> if Process.alive?(device), do: GenServer.stop(device) end)
    %{target: "127.0.0.1:#{port}"}
  end

  defp run(task, args) do
    Mix.Task.reenable(task)
    capture_io(fn -> Mix.Task.run(task, args) end)
  end

  test "snmpkit.get prints one line per object", %{target: target} do
    out = run("snmpkit.get", [target, "sysDescr.0", "sysUpTime.0", "-t", "2000"])
    assert out =~ ~r/^sysDescr\.0 = OCTET STRING: "/m
    assert out =~ ~r/^sysUpTime\.0 = TIMETICKS: /m
  end

  test "snmpkit.get honours --numeric and --raw", %{target: target} do
    out = run("snmpkit.get", [target, "sysName.0", "--numeric", "--raw"])
    assert out =~ ~r/^1\.3\.6\.1\.2\.1\.1\.5\.0 = OCTET STRING: "/m
  end

  test "snmpkit.walk walks a subtree and prints tables", %{target: target} do
    out = run("snmpkit.walk", [target, "system"])
    assert out =~ ~r/^sysDescr\.0 = /m
    assert out =~ ~r/^sysName\.0 = /m

    out = run("snmpkit.walk", [target, "ifTable", "--table"])
    assert out =~ ~r/^index\s+ifAdminStatus/m
    assert out =~ ~r/GigabitEthernet0\/0/
  end

  test "snmpkit.walk --no-bulk uses GETNEXT", %{target: target} do
    out = run("snmpkit.walk", [target, "system", "--no-bulk", "-v", "1"])
    assert out =~ ~r/^sysDescr\.0 = /m
  end

  test "snmpkit.mib.compile reports warnings and a summary" do
    out =
      run("snmpkit.mib.compile", [
        "test/fixtures/mibs/working/IF-MIB.mib",
        "test/fixtures/mibs/topvision/PRIVATE_MIB_FILES/TOPVISION-CCMTS-MIB.mib"
      ])

    assert out =~ ~r/^compiled test\/fixtures\/mibs\/working\/IF-MIB\.mib \(\d+ symbols\)/m
    assert out =~ ~r/warning: /
    assert out =~ ~r/^2 compiled, 0 failed, \d+ warning\(s\)$/m
  end

  test "snmpkit.mib.lint prints findings and a summary, --strict fails on warnings" do
    out = run("snmpkit.mib.lint", ["test/fixtures/mibs/working/IF-MIB.mib"])
    assert out =~ ~r/^1 file\(s\), \d+ error\(s\), \d+ warning\(s\)$/m

    assert catch_exit(
             run("snmpkit.mib.lint", [
               "test/fixtures/mibs/topvision/PRIVATE_MIB_FILES/TOPVISION-CCMTS-MIB.mib",
               "--strict",
               "--quiet"
             ])
           ) == {:shutdown, 1}
  end

  test "snmpkit.mib.compile exits non-zero on failure" do
    path =
      Path.join(System.tmp_dir!(), "snmpkit-broken-#{System.unique_integer([:positive])}.mib")

    File.write!(path, "BROKEN-MIB DEFINITIONS ::= BEGIN\nfoo OBJECT-TYPE\nEND\n")
    on_exit(fn -> File.rm(path) end)

    assert catch_exit(run("snmpkit.mib.compile", [path, "--quiet"])) == {:shutdown, 1}
  end

  test "snmpkit.sim starts a bundled device and a sample config" do
    Application.put_env(:snmpkit, :sim_task_wait, 10)
    on_exit(fn -> Application.delete_env(:snmpkit, :sim_task_wait) end)

    port = 31_000 + :rand.uniform(2_000)
    out = run("snmpkit.sim", ["--device", "switch", "--port", "#{port}"])
    assert out =~ "switch listening on 127.0.0.1:#{port}"

    sample = Path.join(System.tmp_dir!(), "snmpkit-sample-#{port}.json")
    on_exit(fn -> File.rm(sample) end)
    out = run("snmpkit.sim", ["--sample", sample])
    assert out =~ "wrote #{sample}"
    assert File.exists?(sample)
  end

  test "usage errors are Mix errors" do
    Mix.Task.reenable("snmpkit.get")
    assert_raise Mix.Error, ~r/usage/, fn -> Mix.Task.run("snmpkit.get", []) end
    Mix.Task.reenable("snmpkit.get")

    assert_raise Mix.Error, ~r/unknown option/, fn ->
      Mix.Task.run("snmpkit.get", ["h", "o", "--bogus"])
    end
  end

  test "out-of-range option values are Mix errors naming the flag", %{target: target} do
    assert_raise Mix.Error, "--timeout must be at least 1, got 0", fn ->
      run("snmpkit.get", [target, "sysDescr.0", "--timeout", "0"])
    end

    assert_raise Mix.Error, "--port must be between 1 and 65535, got 99999", fn ->
      run("snmpkit.get", [target, "sysDescr.0", "-p", "99999"])
    end

    assert_raise Mix.Error, "--max-repetitions must be at least 1, got -5", fn ->
      run("snmpkit.walk", [target, "system", "--max-repetitions", "-5"])
    end

    assert_raise Mix.Error, "--retries must be at least 0, got -1", fn ->
      run("snmpkit.walk", [target, "system", "-r", "-1"])
    end

    assert_raise Mix.Error, "--walk-timeout must be at least 1, got 0", fn ->
      run("snmpkit.walk", [target, "system", "--walk-timeout", "0"])
    end

    assert_raise Mix.Error, "--port must be between 1 and 65535, got 0", fn ->
      run("snmpkit.sim", ["--device", "switch", "--port", "0"])
    end
  end

  test "snmpkit.walk rejects more than one OID instead of dropping the rest", %{target: target} do
    assert_raise Mix.Error, ~r/usage: mix snmpkit.walk.*one OID.*"ifTable"/s, fn ->
      run("snmpkit.walk", [target, "system", "ifTable"])
    end
  end

  test "snmpkit.sim --device typo lists the bundled devices and suggests the closest" do
    assert_raise Mix.Error,
                 ~r/unknown device "swtch" \(did you mean switch\?\).*cable_modem, router, switch/,
                 fn ->
                   run("snmpkit.sim", ["--device", "swtch"])
                 end

    assert_raise Mix.Error, ~r/unknown device "zzz"; --device takes cable_modem/, fn ->
      run("snmpkit.sim", ["--device", "zzz"])
    end

    assert_raise Mix.Error, ~r/expected one config file, got: a.json b.json/, fn ->
      run("snmpkit.sim", ["a.json", "b.json"])
    end
  end

  test "MIB directories: .txt is compiled, all-filtered and unreadable dirs are errors" do
    dir = Path.join(System.tmp_dir!(), "snmpkit-mibdir-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.chmod(dir, 0o755) && File.rm_rf(dir) end)

    File.write!(Path.join(dir, "notes.md"), "# not a MIB\n")
    File.write!(Path.join(dir, "IF-MIB.bin"), <<131, 106>>)

    assert_raise Mix.Error, ~r/^no MIB files in #{Regex.escape(dir)} \(.*\.bin.* skipped\)/, fn ->
      run("snmpkit.mib.lint", [dir])
    end

    File.cp!("test/fixtures/mibs/working/IF-MIB.mib", Path.join(dir, "IF-MIB.txt"))
    out = run("snmpkit.mib.compile", [dir, "--quiet"])
    assert out =~ ~r/^1 compiled, 0 failed/m

    File.chmod!(dir, 0o000)

    case File.ls(dir) do
      # root reads it anyway; nothing to test
      {:ok, _} ->
        :ok

      {:error, _} ->
        assert_raise Mix.Error,
                     ~r/cannot read directory #{Regex.escape(dir)}: permission denied/,
                     fn ->
                       run("snmpkit.mib.compile", [dir])
                     end
    end
  end

  test "snmpkit.mib.lint uses the shared option parser" do
    assert_raise Mix.Error, ~r/unknown option\(s\): --bogus/, fn ->
      run("snmpkit.mib.lint", ["test/fixtures/mibs/working/IF-MIB.mib", "--bogus"])
    end

    out =
      run("snmpkit.mib.lint", [
        "test/fixtures/mibs/working/IF-MIB.mib",
        "-q",
        "--context",
        "test/fixtures/mibs/working/SNMPv2-SMI.mib",
        "--context",
        "test/fixtures/mibs/working/SNMPv2-TC.mib"
      ])

    assert out =~ ~r/^1 file\(s\), \d+ error\(s\), \d+ warning\(s\)$/m
  end

  test "snmpkit.mib.compile -O writes a file load_compiled/1 reads back" do
    out_dir =
      Path.join(System.tmp_dir!(), "snmpkit-compiled-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(out_dir) end)

    out = run("snmpkit.mib.compile", ["test/fixtures/mibs/working/IF-MIB.mib", "-O", out_dir])
    path = Path.join(out_dir, "IF-MIB.bin")
    assert out =~ "wrote #{path}"

    assert {:ok, %{__type__: :compiled_mib, name: "IF-MIB", symbols: symbols}} =
             SnmpKit.MIB.Compiler.load_compiled(path)

    assert Map.has_key?(symbols, "ifDescr")
  end
end
