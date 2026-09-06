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
end
