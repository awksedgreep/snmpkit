defmodule SnmpKit.SnmpMgr.MIBStubsTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.MIB

  @moduletag :unit
  @moduletag :mib_stubs

  setup do
    # Ensure MIB registry is started
    case GenServer.whereis(SnmpKit.SnmpMgr.MIB) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.MIB.start_link()
        :ok
      _pid ->
        :ok
    end

    :ok
  end

  describe "system group object resolution" do
    test "resolves basic system objects" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1]} = MIB.resolve("sysDescr")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 2]} = MIB.resolve("sysObjectID")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 3]} = MIB.resolve("sysUpTime")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 4]} = MIB.resolve("sysContact")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 5]} = MIB.resolve("sysName")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 6]} = MIB.resolve("sysLocation")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 7]} = MIB.resolve("sysServices")
    end

    test "resolves system objects with instances" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = MIB.resolve("sysDescr.0")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 3, 0]} = MIB.resolve("sysUpTime.0")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 5, 0]} = MIB.resolve("sysName.0")
    end

    test "resolves system objects with multiple instances" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 123, 456]} = MIB.resolve("sysDescr.123.456")
    end
  end

  describe "interface group object resolution" do
    test "resolves standard interface objects" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 1]} = MIB.resolve("ifNumber")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2]} = MIB.resolve("ifTable")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1]} = MIB.resolve("ifEntry")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 1]} = MIB.resolve("ifIndex")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 2]} = MIB.resolve("ifDescr")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 3]} = MIB.resolve("ifType")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 5]} = MIB.resolve("ifSpeed")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 7]} = MIB.resolve("ifAdminStatus")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 8]} = MIB.resolve("ifOperStatus")
    end

    test "resolves interface counter objects" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 10]} = MIB.resolve("ifInOctets")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 11]} = MIB.resolve("ifInUcastPkts")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 16]} = MIB.resolve("ifOutOctets")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 17]} = MIB.resolve("ifOutUcastPkts")
    end

    test "resolves interface objects with instances" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1]} = MIB.resolve("ifDescr.1")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 2]} = MIB.resolve("ifOperStatus.2")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 5]} = MIB.resolve("ifInOctets.5")
    end
  end

  describe "interface extensions (ifX) object resolution" do
    test "resolves ifX table objects" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1]} = MIB.resolve("ifXTable")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1]} = MIB.resolve("ifXEntry")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 1]} = MIB.resolve("ifName")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 18]} = MIB.resolve("ifAlias")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 15]} = MIB.resolve("ifHighSpeed")
    end

    test "resolves ifX high-capacity counters" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 6]} = MIB.resolve("ifHCInOctets")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 7]} = MIB.resolve("ifHCInUcastPkts")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 10]} = MIB.resolve("ifHCOutOctets")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 11]} = MIB.resolve("ifHCOutUcastPkts")
    end

    test "resolves ifX multicast/broadcast counters" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 2]} = MIB.resolve("ifInMulticastPkts")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 3]} = MIB.resolve("ifInBroadcastPkts")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 4]} = MIB.resolve("ifOutMulticastPkts")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 5]} = MIB.resolve("ifOutBroadcastPkts")
    end

    test "resolves ifX objects with instances" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 1]} = MIB.resolve("ifName.1")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 18, 2]} = MIB.resolve("ifAlias.2")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 6, 3]} = MIB.resolve("ifHCInOctets.3")
    end
  end

  describe "SNMP group object resolution" do
    test "resolves SNMP statistics objects" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 1]} = MIB.resolve("snmpInPkts")
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 2]} = MIB.resolve("snmpOutPkts")
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 3]} = MIB.resolve("snmpInBadVersions")
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 4]} = MIB.resolve("snmpInBadCommunityNames")
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 30]} = MIB.resolve("snmpEnableAuthenTraps")
    end

    test "resolves SNMP error counters" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 8]} = MIB.resolve("snmpInTooBigs")
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 9]} = MIB.resolve("snmpInNoSuchNames")
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 10]} = MIB.resolve("snmpInBadValues")
      assert {:ok, [1, 3, 6, 1, 2, 1, 11, 12]} = MIB.resolve("snmpInGenErrs")
    end
  end

  describe "IP group object resolution" do
    test "resolves basic IP objects" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 4, 1]} = MIB.resolve("ipForwarding")
      assert {:ok, [1, 3, 6, 1, 2, 1, 4, 2]} = MIB.resolve("ipDefaultTTL")
      assert {:ok, [1, 3, 6, 1, 2, 1, 4, 3]} = MIB.resolve("ipInReceives")
      assert {:ok, [1, 3, 6, 1, 2, 1, 4, 4]} = MIB.resolve("ipInHdrErrors")
      assert {:ok, [1, 3, 6, 1, 2, 1, 4, 5]} = MIB.resolve("ipInAddrErrors")
    end
  end

  describe "group prefix resolution" do
    test "resolves standard MIB-II groups" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1]} = MIB.resolve("system")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2]} = MIB.resolve("interfaces")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2]} = MIB.resolve("if")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31]} = MIB.resolve("ifX")
      assert {:ok, [1, 3, 6, 1, 2, 1, 4]} = MIB.resolve("ip")
      assert {:ok, [1, 3, 6, 1, 2, 1, 5]} = MIB.resolve("icmp")
      assert {:ok, [1, 3, 6, 1, 2, 1, 6]} = MIB.resolve("tcp")
      assert {:ok, [1, 3, 6, 1, 2, 1, 7]} = MIB.resolve("udp")
      assert {:ok, [1, 3, 6, 1, 2, 1, 11]} = MIB.resolve("snmp")
    end

    test "resolves root tree groups" do
      assert {:ok, [1, 3, 6, 1, 2, 1]} = MIB.resolve("mib-2")
      assert {:ok, [1, 3, 6, 1, 2]} = MIB.resolve("mgmt")
      assert {:ok, [1, 3, 6, 1]} = MIB.resolve("internet")
      assert {:ok, [1, 3, 6, 1, 4, 1]} = MIB.resolve("enterprises")
    end
  end

  describe "enterprise MIB resolution" do
    test "resolves major vendor enterprise OIDs" do
      assert {:ok, [1, 3, 6, 1, 4, 1, 9]} = MIB.resolve("cisco")
      assert {:ok, [1, 3, 6, 1, 4, 1, 11]} = MIB.resolve("hp")
      assert {:ok, [1, 3, 6, 1, 4, 1, 43]} = MIB.resolve("3com")
      assert {:ok, [1, 3, 6, 1, 4, 1, 42]} = MIB.resolve("sun")
      assert {:ok, [1, 3, 6, 1, 4, 1, 36]} = MIB.resolve("dec")
      assert {:ok, [1, 3, 6, 1, 4, 1, 2]} = MIB.resolve("ibm")
      assert {:ok, [1, 3, 6, 1, 4, 1, 311]} = MIB.resolve("microsoft")
    end

    test "resolves network equipment vendor OIDs" do
      assert {:ok, [1, 3, 6, 1, 4, 1, 789]} = MIB.resolve("netapp")
      assert {:ok, [1, 3, 6, 1, 4, 1, 2636]} = MIB.resolve("juniper")
      assert {:ok, [1, 3, 6, 1, 4, 1, 12356]} = MIB.resolve("fortinet")
      assert {:ok, [1, 3, 6, 1, 4, 1, 25461]} = MIB.resolve("paloalto")
      assert {:ok, [1, 3, 6, 1, 4, 1, 14988]} = MIB.resolve("mikrotik")
    end

    test "resolves cable/DOCSIS industry OIDs" do
      assert {:ok, [1, 3, 6, 1, 4, 1, 4491]} = MIB.resolve("cablelabs")
      assert {:ok, [1, 3, 6, 1, 2, 1, 127]} = MIB.resolve("docsis")
      assert {:ok, [1, 3, 6, 1, 4, 1, 4491, 2, 1]} = MIB.resolve("cableDataPrivateMib")
      assert {:ok, [1, 3, 6, 1, 4, 1, 4115]} = MIB.resolve("arris")
      assert {:ok, [1, 3, 6, 1, 4, 1, 1166]} = MIB.resolve("motorola")
      assert {:ok, [1, 3, 6, 1, 4, 1, 1429]} = MIB.resolve("scientificatlanta")
      assert {:ok, [1, 3, 6, 1, 4, 1, 4413]} = MIB.resolve("broadcom")
    end
  end

  describe "error handling" do
    test "returns error for unknown names" do
      assert {:error, :not_found} = MIB.resolve("unknownObject")
      assert {:error, :not_found} = MIB.resolve("nonexistentMib")
      assert {:error, :not_found} = MIB.resolve("invalidName123")
    end

    test "handles invalid input types gracefully" do
      assert {:error, :invalid_name} = MIB.resolve(nil)
      assert {:error, :invalid_name} = MIB.resolve(123)
      assert {:error, :invalid_name} = MIB.resolve([])
      assert {:error, :invalid_name} = MIB.resolve(%{})
    end

    test "handles empty and whitespace strings" do
      assert {:error, :not_found} = MIB.resolve("")
      assert {:error, :not_found} = MIB.resolve("   ")
      assert {:error, :not_found} = MIB.resolve("\t\n")
    end
  end

  describe "case sensitivity" do
    test "names are case sensitive" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1]} = MIB.resolve("sysDescr")
      assert {:error, :not_found} = MIB.resolve("sysdescr")
      assert {:error, :not_found} = MIB.resolve("SYSDESCR")
      assert {:error, :not_found} = MIB.resolve("SysDescr")
    end

    test "group names are case sensitive" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1]} = MIB.resolve("system")
      assert {:error, :not_found} = MIB.resolve("System")
      assert {:error, :not_found} = MIB.resolve("SYSTEM")
    end
  end

  describe "instance parsing" do
    test "parses single instance correctly" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = MIB.resolve("sysDescr.0")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 1]} = MIB.resolve("sysDescr.1")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 999]} = MIB.resolve("sysDescr.999")
    end

    test "parses multiple instances correctly" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1, 2]} = MIB.resolve("ifDescr.1.2")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 10, 20, 30]} = MIB.resolve("sysDescr.10.20.30")
    end

    test "rejects invalid instance formats" do
      assert {:error, :invalid_instance} = MIB.resolve("sysDescr.abc")
      assert {:error, :invalid_instance} = MIB.resolve("sysDescr.1.abc")
      assert {:error, :invalid_instance} = MIB.resolve("sysDescr.1.2.xyz")
    end

    test "handles large instance numbers" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 4294967295]} = MIB.resolve("sysDescr.4294967295")
    end
  end

  describe "comprehensive object coverage" do
    test "all system group objects are available" do
      system_objects = [
        "sysDescr", "sysObjectID", "sysUpTime", "sysContact",
        "sysName", "sysLocation", "sysServices"
      ]

      for object <- system_objects do
        assert {:ok, oid} = MIB.resolve(object)
        assert is_list(oid)
        assert length(oid) >= 8  # At least 1.3.6.1.2.1.1.X
        assert Enum.take(oid, 7) == [1, 3, 6, 1, 2, 1, 1]
      end
    end

    test "essential interface objects are available" do
      interface_objects = [
        "ifNumber", "ifTable", "ifEntry", "ifIndex", "ifDescr", "ifType",
        "ifMtu", "ifSpeed", "ifPhysAddress", "ifAdminStatus", "ifOperStatus",
        "ifInOctets", "ifOutOctets"
      ]

      for object <- interface_objects do
        assert {:ok, oid} = MIB.resolve(object)
        assert is_list(oid)
        assert Enum.take(oid, 7) == [1, 3, 6, 1, 2, 1, 2]
      end
    end

    test "essential ifX objects are available" do
      ifx_objects = [
        "ifXTable", "ifXEntry", "ifName", "ifHCInOctets", "ifHCOutOctets",
        "ifHighSpeed", "ifAlias"
      ]

      for object <- ifx_objects do
        assert {:ok, oid} = MIB.resolve(object)
        assert is_list(oid)
        assert Enum.take(oid, 7) == [1, 3, 6, 1, 2, 1, 31]
      end
    end
  end

  describe "compatibility with bulk operations" do
    test "group names work for bulk walk operations" do
      # These should resolve to valid OID prefixes suitable for bulk walking
      bulk_groups = ["system", "if", "ifX", "ip", "snmp"]

      for group <- bulk_groups do
        assert {:ok, oid} = MIB.resolve(group)
        assert is_list(oid)
        assert length(oid) >= 7  # At least 1.3.6.1.2.1.X
        assert Enum.take(oid, 6) == [1, 3, 6, 1, 2, 1]
      end
    end

    test "enterprise roots work for bulk walk operations" do
      enterprise_roots = ["cisco", "hp", "microsoft", "mikrotik", "cablelabs"]

      for root <- enterprise_roots do
        assert {:ok, oid} = MIB.resolve(root)
        assert is_list(oid)
        assert Enum.take(oid, 6) == [1, 3, 6, 1, 4, 1]
      end
    end
  end

  describe "performance characteristics" do
    test "resolution is fast for all stub objects" do
      # Test a sample of objects to ensure reasonable performance
      test_objects = [
        "sysDescr", "ifDescr", "ifName", "snmpInPkts", "ipForwarding",
        "system", "if", "ifX", "cisco", "mikrotik"
      ]

      # Measure time for multiple resolutions
      start_time = System.monotonic_time(:microsecond)

      for _i <- 1..100 do
        for object <- test_objects do
          assert {:ok, _oid} = MIB.resolve(object)
        end
      end

      end_time = System.monotonic_time(:microsecond)
      total_time = end_time - start_time

      # Should be fast - less than 10ms for 1000 resolutions
      assert total_time < 10_000
    end
  end

  describe "integration with existing MIB system" do
    test "stub resolution works when MIB system is active" do
      # Verify stubs work even when the MIB compilation system is available
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1]} = MIB.resolve("sysDescr")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 2]} = MIB.resolve("ifDescr")
      assert {:ok, [1, 3, 6, 1, 2, 1, 31, 1, 1, 1]} = MIB.resolve("ifName")
    end

    test "unknown objects still return not_found" do
      # Objects not in stubs should still return not_found
      # (would need compiled MIBs for these)
      assert {:error, :not_found} = MIB.resolve("docsIfCmStatusValue")
      assert {:error, :not_found} = MIB.resolve("ciscoVlanPortVlan")
      assert {:error, :not_found} = MIB.resolve("customObject")
    end
  end

  describe "edge cases and robustness" do
    test "handles objects with numeric-like names" do
      # These should fail since they're not in our stubs
      assert {:error, :not_found} = MIB.resolve("1234")
      assert {:error, :not_found} = MIB.resolve("obj123")
      assert {:error, :not_found} = MIB.resolve("123obj")
    end

    test "handles special characters in names" do
      assert {:error, :not_found} = MIB.resolve("sys-descr")
      assert {:error, :not_found} = MIB.resolve("sys_descr")
      assert {:error, :not_found} = MIB.resolve("sys@descr")
    end

    test "handles very long names" do
      long_name = String.duplicate("a", 1000)
      assert {:error, :not_found} = MIB.resolve(long_name)
    end

    test "enterprise OID with special names like '3com'" do
      # Special case: vendor name starts with number
      assert {:ok, [1, 3, 6, 1, 4, 1, 43]} = MIB.resolve("3com")
    end
  end
end
