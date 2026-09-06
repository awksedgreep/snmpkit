defmodule SnmpKit.TrapTest do
  use ExUnit.Case, async: false

  alias SnmpKit.Trap

  @link_down [1, 3, 6, 1, 6, 3, 1, 1, 5, 3]
  @link_up [1, 3, 6, 1, 6, 3, 1, 1, 5, 4]

  defp start_receiver(opts \\ []) do
    opts = Keyword.merge([port: 0, bind_address: "127.0.0.1", handler: self()], opts)
    {:ok, pid} = Trap.start_link(opts)
    on_exit(fn -> if Process.alive?(pid), do: Trap.stop(pid) end)
    {pid, "127.0.0.1:#{Trap.port(pid)}"}
  end

  test "receives an SNMPv2c trap with the trap OID, name and uptime lifted out" do
    {_pid, target} = start_receiver()

    assert :ok =
             SnmpKit.SNMP.send_trap(target, "linkDown", [{"ifIndex.3", :integer, 3}],
               community: "public",
               uptime: 4242,
               request_id: 77
             )

    assert_receive {:snmp_trap, n}, 2_000
    assert n.kind == :trap
    assert n.version == :v2c
    assert n.community == "public"
    assert n.trap_oid == @link_down
    assert n.trap_name == "linkDown"
    assert n.uptime == 4242
    assert n.request_id == 77
    assert {{127, 0, 0, 1}, _port} = n.source
    assert n.agent_address == {127, 0, 0, 1}
    assert %DateTime{} = n.received_at

    assert [
             %{name: "sysUpTime.0", type: :timeticks, value: 4242},
             %{name: "snmpTrapOID.0", type: :object_identifier, value: @link_down},
             %{name: "ifIndex.3", type: :integer, value: 3}
           ] = n.varbinds
  end

  test "acknowledges informs and send_inform returns :ok" do
    {pid, target} = start_receiver()

    assert :ok = SnmpKit.SNMP.send_inform(target, @link_up, [], timeout: 1_000, retries: 0)
    assert_receive {:snmp_trap, %{kind: :inform, trap_oid: @link_up}}, 2_000
    assert %{informs: 1, acknowledged: 1, traps: 0} = Trap.stats(pid)
  end

  test "send_inform times out when nothing answers" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)

    assert {:error, :timeout} =
             SnmpKit.SNMP.send_inform("127.0.0.1:#{port}", @link_up, [], timeout: 100, retries: 1)

    :gen_udp.close(socket)
  end

  test "receives an SNMPv1 generic trap" do
    {_pid, target} = start_receiver()

    assert :ok =
             SnmpKit.SNMP.send_trap(target, "linkUp", [],
               version: :v1,
               uptime: 9,
               agent_addr: {10, 1, 2, 3}
             )

    assert_receive {:snmp_trap, n}, 2_000
    assert n.version == :v1
    assert n.generic_trap == 3
    assert n.specific_trap == 0
    assert n.trap_oid == @link_up
    assert n.trap_name == "linkUp"
    assert n.agent_address == {10, 1, 2, 3}
    assert n.uptime == 9
    assert n.request_id == nil
  end

  test "maps an SNMPv1 enterprise-specific trap per RFC 3584" do
    {_pid, target} = start_receiver()

    assert :ok = SnmpKit.SNMP.send_trap(target, "1.3.6.1.4.1.9999.0.7", [], version: :v1)
    assert_receive {:snmp_trap, n}, 2_000
    assert n.enterprise == [1, 3, 6, 1, 4, 1, 9999]
    assert n.generic_trap == 6
    assert n.specific_trap == 7
    assert n.trap_oid == [1, 3, 6, 1, 4, 1, 9999, 0, 7]
  end

  test "filters communities and counts rejected and undecodable packets" do
    {pid, target} = start_receiver(communities: ["secret"])

    assert :ok = SnmpKit.SNMP.send_trap(target, "coldStart", [], community: "public")
    assert :ok = SnmpKit.SNMP.send_trap(target, "coldStart", [], community: "secret")

    {:ok, socket} = :gen_udp.open(0, [:binary])
    [_, port_string] = String.split(target, ":")
    :ok = :gen_udp.send(socket, {127, 0, 0, 1}, String.to_integer(port_string), "not snmp")
    :gen_udp.close(socket)

    assert_receive {:snmp_trap, %{community: "secret"}}, 2_000
    refute_receive {:snmp_trap, %{community: "public"}}, 200

    stats = Trap.stats(pid)
    assert stats.rejected_community == 1
    assert stats.decode_errors == 1
    assert stats.traps == 1
  end

  test "calls function and MFA handlers" do
    test_pid = self()
    {_pid, target} = start_receiver(handler: fn n -> send(test_pid, {:fun, n.trap_name}) end)
    assert :ok = SnmpKit.SNMP.send_trap(target, "warmStart")
    assert_receive {:fun, "warmStart"}, 2_000

    {_pid2, target2} = start_receiver(handler: {__MODULE__, :mfa_handler, [test_pid]})
    assert :ok = SnmpKit.SNMP.send_trap(target2, "authenticationFailure")
    assert_receive {:mfa, "authenticationFailure"}, 2_000
  end

  def mfa_handler(notification, pid), do: send(pid, {:mfa, notification.trap_name})

  test "a simulated device sends traps with its own community and uptime" do
    {_pid, target} = start_receiver()
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: 0, community: "lab")

    assert :ok =
             SnmpKit.Sim.send_trap(device, "linkDown", [{"ifIndex.1", :integer, 1}], to: target)

    assert_receive {:snmp_trap, n}, 2_000
    assert n.community == "lab"
    assert n.trap_name == "linkDown"
    assert is_integer(n.uptime)
    assert Enum.any?(n.varbinds, &(&1.name == "ifIndex.1"))
  end

  test "rejects unknown trap names and bad varbinds without sending" do
    {_pid, target} = start_receiver()

    assert {:error, {:invalid_oid, "noSuchTrap", _}} =
             SnmpKit.SNMP.send_trap(target, "noSuchTrap")

    assert {:error, {:invalid_varbind, _}} =
             SnmpKit.SNMP.send_trap(target, "linkUp", [{"ifIndex.1", 1}])

    refute_receive {:snmp_trap, _}, 100
  end
end
