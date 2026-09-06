defmodule SnmpKit.SnmpMgr.MultiOidTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    port = 22_000 + :rand.uniform(10_000)
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: port)
    on_exit(fn -> if Process.alive?(device), do: GenServer.stop(device) end)
    %{target: "127.0.0.1:#{port}"}
  end

  test "get with a list of OIDs returns one enriched map per OID in order", %{target: target} do
    assert {:ok, [descr, name, uptime]} =
             SnmpKit.SNMP.get(target, [
               "sysDescr.0",
               "1.3.6.1.2.1.1.5.0",
               [1, 3, 6, 1, 2, 1, 1, 3, 0]
             ])

    assert %{name: "sysDescr.0", type: :octet_string, value: value} = descr
    assert is_binary(value)
    assert %{name: "sysName.0", type: :octet_string} = name
    assert %{name: "sysUpTime.0", type: :timeticks} = uptime
  end

  test "exceptions are reported per element on SNMPv2c", %{target: target} do
    assert {:ok, [ok, missing]} = SnmpKit.SNMP.get(target, ["sysDescr.0", "1.3.6.1.2.1.1.99.0"])
    assert ok.type == :octet_string
    assert %{type: :no_such_object, value: nil, formatted: "noSuchObject"} = missing
  end

  test "SNMPv1 answers the whole PDU with noSuchName", %{target: target} do
    assert {:error, :no_such_name} =
             SnmpKit.SNMP.get(target, ["sysDescr.0", "1.3.6.1.2.1.1.99.0"], version: :v1)
  end

  test "a single-element list still works and an empty list is rejected", %{target: target} do
    assert {:ok, [%{name: "sysDescr.0"}]} = SnmpKit.SNMP.get(target, ["sysDescr.0"])
    assert {:error, :empty_oids} = SnmpKit.SNMP.get(target, [])
  end

  test "unknown names fail before anything is sent", %{target: target} do
    assert {:error, {:invalid_oid, "noSuchName", _}} =
             SnmpKit.SNMP.get(target, ["sysDescr.0", "noSuchName"])
  end

  test "get_multi accepts a list of OIDs per request", %{target: target} do
    assert [{:ok, [%{name: "sysDescr.0"}, %{name: "sysName.0"}]}, {:ok, [%{name: "sysUpTime.0"}]}] =
             SnmpKit.SNMP.get_multi([
               {target, ["sysDescr.0", "sysName.0"]},
               {target, "sysUpTime.0"}
             ])
  end

  test "set_many sends one SET PDU and reports the agent's answer", %{target: target} do
    # simulated devices are read-only; the answer proves the multi-varbind SET round-trips
    assert {:error, :not_writable} =
             SnmpKit.SNMP.set_many(target, [
               {"sysContact.0", "ops"},
               {"sysLocation.0", {:string, "rack 4"}}
             ])

    assert {:error, :empty_varbinds} = SnmpKit.SNMP.set_many(target, [])
  end

  test "one PDU carries all varbinds" do
    pdu =
      SnmpKit.SnmpLib.PDU.build_set_request_multi(
        [{[1, 3, 6, 1, 2, 1, 1, 4, 0], :string, "a"}, {"1.3.6.1.2.1.1.6.0", :string, "b"}],
        9
      )

    assert pdu.type == :set_request

    assert [
             {[1, 3, 6, 1, 2, 1, 1, 4, 0], :string, "a"},
             {[1, 3, 6, 1, 2, 1, 1, 6, 0], :string, "b"}
           ] = pdu.varbinds
  end
end
