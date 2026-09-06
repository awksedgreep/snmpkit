defmodule SnmpKit.SnmpMgr.NamedTableTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    port = 24_000 + :rand.uniform(5_000)
    {:ok, device} = SnmpKit.Sim.start_device(profile, port: port)
    on_exit(fn -> if Process.alive?(device), do: GenServer.stop(device) end)
    %{target: "127.0.0.1:#{port}"}
  end

  test "get_table with named: true uses column names and decodes the index", %{target: target} do
    assert {:ok, table} = SnmpKit.SNMP.get_table(target, "ifTable", named: true)
    assert %{"ifIndex" => 1, "ifDescr" => descr, "ifType" => 117} = table[1]
    assert is_binary(descr)
    refute Map.has_key?(table[1], 2)
  end

  test "numeric columns stay the default", %{target: target} do
    assert {:ok, %{1 => %{1 => 1, 2 => _}}} = SnmpKit.SNMP.get_table(target, "ifTable")
  end

  test "table_layout describes the built-in ifTable" do
    assert {:ok,
            %{entry: "ifEntry", columns: columns, indexes: [%{name: "ifIndex", base: :integer}]}} =
             SnmpKit.SnmpMgr.MIB.table_layout("1.3.6.1.2.1.2.2")

    assert columns[2] == "ifDescr"
    assert columns[8] == "ifOperStatus"
  end

  test "a loaded MIB provides column names and a composite index" do
    mib = """
    NT-TEST-MIB DEFINITIONS ::= BEGIN
    IMPORTS OBJECT-TYPE, Integer32, IpAddress, enterprises FROM SNMPv2-SMI;

    ntTest OBJECT IDENTIFIER ::= { enterprises 99995 }

    ntPeerTable OBJECT-TYPE
      SYNTAX SEQUENCE OF NtPeerEntry
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "peers"
      ::= { ntTest 1 }

    ntPeerEntry OBJECT-TYPE
      SYNTAX NtPeerEntry
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "a peer"
      INDEX { ntPeerAddress, ntPeerPort }
      ::= { ntPeerTable 1 }

    NtPeerEntry ::= SEQUENCE {
      ntPeerAddress IpAddress,
      ntPeerPort Integer32,
      ntPeerState INTEGER
    }

    ntPeerAddress OBJECT-TYPE
      SYNTAX IpAddress
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "addr"
      ::= { ntPeerEntry 1 }

    ntPeerPort OBJECT-TYPE
      SYNTAX Integer32
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "port"
      ::= { ntPeerEntry 2 }

    ntPeerState OBJECT-TYPE
      SYNTAX INTEGER { idle(1), connected(2) }
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "state"
      ::= { ntPeerEntry 3 }
    END
    """

    {:ok, compiled} = SnmpKit.MIB.compile_string(mib)
    :ok = SnmpKit.MIB.load(compiled)

    assert {:ok,
            %{
              entry: "ntPeerEntry",
              indexes: [
                %{name: "ntPeerAddress", base: :ip_address},
                %{name: "ntPeerPort", base: :integer}
              ]
            }} =
             SnmpKit.SnmpMgr.MIB.table_layout("ntPeerTable")

    varbinds = [
      {"1.3.6.1.4.1.99995.1.1.3.10.0.0.1.179", :integer, 2},
      {"1.3.6.1.4.1.99995.1.1.3.10.0.0.2.179", :integer, 1}
    ]

    assert {:ok, table} = SnmpKit.SnmpMgr.Table.to_named_table(varbinds, "1.3.6.1.4.1.99995.1")

    assert %{"ntPeerAddress" => {10, 0, 0, 1}, "ntPeerPort" => 179, "ntPeerState" => 2} =
             table[[10, 0, 0, 1, 179]]
  end
end
