defmodule SnmpKit.IPv6Test do
  use ExUnit.Case, async: false

  @loopback {0, 0, 0, 0, 0, 0, 0, 1}

  setup_all do
    case :gen_udp.open(0, [:binary, :inet6, {:ip, @loopback}]) do
      {:ok, socket} ->
        :gen_udp.close(socket)
        {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
        port = 27_000 + :rand.uniform(5_000)
        {:ok, device} = SnmpKit.Sim.start_device(profile, port: port, bind_address: "::1")
        on_exit(fn -> if Process.alive?(device), do: GenServer.stop(device) end)
        %{target: "[::1]:#{port}", port: port, ipv6: true}

      {:error, _} ->
        %{ipv6: false}
    end
  end

  test "IPv6 literals parse with and without brackets and ports" do
    assert {:ok, {@loopback, 1161}} = SnmpKit.SnmpLib.HostParser.parse("[::1]:1161")
    assert {:ok, {@loopback, 161}} = SnmpKit.SnmpLib.HostParser.parse("::1")
    assert %{host: @loopback, port: 1161} = SnmpKit.SnmpMgr.Target.resolve("[::1]:1161")
    assert {:ok, @loopback} = SnmpKit.SnmpLib.Transport.resolve_address("::1")
    assert :inet6 == SnmpKit.SnmpLib.Transport.family(@loopback)
  end

  test "single-target get and walk over IPv6", ctx do
    if ctx.ipv6 do
      assert {:ok, %{value: value}} = SnmpKit.SNMP.get(ctx.target, "sysDescr.0", timeout: 2_000)
      assert is_binary(value)
      assert {:ok, rows} = SnmpKit.SNMP.walk(ctx.target, "system", timeout: 2_000)
      assert length(rows) > 3

      assert {:ok, [%{name: "sysDescr.0"}, %{name: "sysName.0"}]} =
               SnmpKit.SNMP.get(ctx.target, ["sysDescr.0", "sysName.0"])
    end
  end

  test "multi-target calls use the engine's IPv6 socket", ctx do
    if ctx.ipv6 do
      assert [{:ok, [%{name: "sysDescr.0"}]}, {:ok, rows}] =
               SnmpKit.SNMP.get_multi([{ctx.target, "sysDescr.0"}, {ctx.target, "sysName.0"}],
                 timeout: 2_000
               )

      assert [%{name: "sysName.0"}] = rows

      assert [{:ok, walked}] = SnmpKit.SNMP.walk_multi([{ctx.target, "system"}], timeout: 2_000)
      assert length(walked) > 3
    end
  end

  test "traps travel over IPv6", ctx do
    if ctx.ipv6 do
      {:ok, receiver} = SnmpKit.Trap.start_link(port: 0, bind_address: "::1", handler: self())
      on_exit(fn -> if Process.alive?(receiver), do: SnmpKit.Trap.stop(receiver) end)
      target = "[::1]:#{SnmpKit.Trap.port(receiver)}"

      assert :ok = SnmpKit.SNMP.send_trap(target, "linkDown", [], community: "public")
      assert_receive {:snmp_trap, %{trap_name: "linkDown", source: {@loopback, _}}}, 2_000

      assert :ok = SnmpKit.SNMP.send_inform(target, "coldStart", [], timeout: 1_000, retries: 0)
      assert_receive {:snmp_trap, %{kind: :inform}}, 2_000
    end
  end
end
