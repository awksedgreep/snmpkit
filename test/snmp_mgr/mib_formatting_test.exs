defmodule SnmpKit.SnmpMgr.MibFormattingTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.Format

  doctest SnmpKit.MIB.DisplayHint
  doctest SnmpKit.SnmpMgr.Format, only: [format_value: 3]

  defp enrich(oid, type, value), do: Format.enrich_varbind({oid, type, value}, [])

  test "built-in enumerations label INTEGER objects" do
    assert %{name: "ifOperStatus.1", formatted: "up"} =
             enrich("1.3.6.1.2.1.2.2.1.8.1", :integer, 1)

    assert %{formatted: "lowerLayerDown"} = enrich("1.3.6.1.2.1.2.2.1.8.1", :integer, 7)
    assert %{formatted: "ethernetCsmacd"} = enrich("1.3.6.1.2.1.2.2.1.3.1", :integer, 6)
    assert %{formatted: "gigabitEthernet"} = enrich("1.3.6.1.2.1.2.2.1.3.1", :integer, 117)

    assert %{name: "ifAdminStatus.1", formatted: "testing"} =
             enrich("1.3.6.1.2.1.2.2.1.7.1", :integer, 3)
  end

  test "objects without enumerations format plainly (no guessing from the value)" do
    assert %{name: "ifIndex.3", formatted: "3"} = enrich("1.3.6.1.2.1.2.2.1.1.3", :integer, 3)
    assert %{name: "ifMtu.1", formatted: "1500"} = enrich("1.3.6.1.2.1.2.2.1.4.1", :integer, 1500)
    assert %{formatted: "1000000000"} = enrich("1.3.6.1.2.1.2.2.1.5.1", :gauge32, 1_000_000_000)
    assert %{formatted: "42000000"} = enrich("1.3.6.1.2.1.2.2.1.10.1", :counter32, 42_000_000)
    assert %{formatted: "1"} = enrich("1.3.6.1.4.1.9999.1.0", :integer, 1)
  end

  test "PhysAddress objects render as MAC addresses through their DISPLAY-HINT" do
    assert %{name: "ifPhysAddress.2", formatted: "00:1a:2b:3c:4d:5e"} =
             enrich("1.3.6.1.2.1.2.2.1.6.2", :octet_string, <<0, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E>>)
  end

  test "unknown values of an enumerated object fall back to the number" do
    assert %{formatted: "42"} = enrich("1.3.6.1.2.1.2.2.1.8.1", :integer, 42)
  end

  test "enumerations, textual conventions and display hints come from loaded MIBs" do
    mib = """
    FMT-TEST-MIB DEFINITIONS ::= BEGIN
    IMPORTS OBJECT-TYPE, Integer32, enterprises FROM SNMPv2-SMI
            TEXTUAL-CONVENTION, TruthValue, DateAndTime FROM SNMPv2-TC;

    fmtTest OBJECT IDENTIFIER ::= { enterprises 99996 }

    Celsius ::= TEXTUAL-CONVENTION
      DISPLAY-HINT "d-1"
      STATUS current
      DESCRIPTION "tenths of a degree"
      SYNTAX Integer32

    fmtMode OBJECT-TYPE
      SYNTAX INTEGER { off(0), eco(1), turbo(2) }
      MAX-ACCESS read-write
      STATUS current
      DESCRIPTION "mode"
      ::= { fmtTest 1 }

    fmtTemp OBJECT-TYPE
      SYNTAX Celsius
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "temperature"
      ::= { fmtTest 2 }

    fmtEnabled OBJECT-TYPE
      SYNTAX TruthValue
      MAX-ACCESS read-write
      STATUS current
      DESCRIPTION "flag"
      ::= { fmtTest 3 }

    fmtWhen OBJECT-TYPE
      SYNTAX DateAndTime
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "stamp"
      ::= { fmtTest 4 }
    END
    """

    {:ok, compiled} = SnmpKit.MIB.compile_string(mib)
    :ok = SnmpKit.MIB.load(compiled)

    assert %{name: "fmtMode.0", formatted: "turbo"} = enrich("1.3.6.1.4.1.99996.1.0", :integer, 2)

    assert %{name: "fmtTemp.0", formatted: "21.5"} =
             enrich("1.3.6.1.4.1.99996.2.0", :integer, 215)

    assert %{name: "fmtEnabled.0", formatted: "false"} =
             enrich("1.3.6.1.4.1.99996.3.0", :integer, 2)

    assert %{name: "fmtWhen.0", formatted: "2024-3-5,10:3:7.0,+0:0"} =
             enrich(
               "1.3.6.1.4.1.99996.4.0",
               :octet_string,
               <<7, 232, 3, 5, 10, 3, 7, 0, ?+, 0, 0>>
             )

    assert {:ok, %{syntax: %{textual_convention: "Celsius", display_hint: "d-1"}}} =
             SnmpKit.SnmpMgr.MIB.object_info("fmtTemp")
  end

  test "formatting stays off when names are off" do
    assert %{formatted: "1"} =
             Format.enrich_varbind({"1.3.6.1.2.1.2.2.1.8.1", :integer, 1}, include_names: false)

    refute Map.has_key?(
             Format.enrich_varbind({"1.3.6.1.2.1.2.2.1.8.1", :integer, 1},
               include_formatted: false
             ),
             :formatted
           )
  end
end
