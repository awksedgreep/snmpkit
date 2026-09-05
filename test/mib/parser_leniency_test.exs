defmodule SnmpKit.MIB.ParserLeniencyTest do
  @moduledoc "Vendor-MIB constructs accepted with a warning, matching net-snmp."
  use ExUnit.Case, async: true

  alias SnmpKit.MIB.Parser

  defp parse!(body) do
    {:ok, mib} =
      Parser.parse("""
      LENIENT-MIB DEFINITIONS ::= BEGIN
      IMPORTS OBJECT-TYPE, Integer32, Unsigned32 FROM SNMPv2-SMI;
      lenient OBJECT IDENTIFIER ::= { enterprises 99998 }
      #{body}
      END
      """)

    mib
  end

  defp object(mib, name), do: Enum.find(mib.definitions, &(&1.name == name))

  test "a clean module has no warnings" do
    mib =
      parse!("""
      okObj OBJECT-TYPE
        SYNTAX INTEGER { on(1), off(2) }
        MAX-ACCESS read-only
        STATUS current
        DESCRIPTION "fine"
        ::= { lenient 1 }
      """)

    assert mib.warnings == []
  end

  test "enumerations on Integer32 and Unsigned32 are treated as INTEGER" do
    mib =
      parse!("""
      stat OBJECT-TYPE
        SYNTAX Integer32 { active(1), non-active(2) }
        MAX-ACCESS read-only
        STATUS current
        DESCRIPTION "x"
        ::= { lenient 2 }
      iuc OBJECT-TYPE
        SYNTAX Unsigned32 { iuc5(5), iuc6(6) }
        MAX-ACCESS read-only
        STATUS current
        DESCRIPTION "x"
        ::= { lenient 3 }
      """)

    # the grammar builds enumeration lists last-first

    assert {{:type_with_enum, :INTEGER, [{"non-active", 2}, {"active", 1}]}, _} =
             object(mib, "stat").syntax

    assert {{:type_with_enum, :INTEGER, [{"iuc6", 6}, {"iuc5", 5}]}, _} =
             object(mib, "iuc").syntax

    assert [
             {5, "enumeration on Integer32 is not allowed in SMIv2; treated as INTEGER"},
             {11, "enumeration on Unsigned32 is not allowed in SMIv2; treated as INTEGER"}
           ] = mib.warnings
  end

  test "uppercase enumeration labels are kept with a warning" do
    mib =
      parse!("""
      policy OBJECT-TYPE
        SYNTAX INTEGER { freqOnly(8), FreqWidthOnly(24) }
        MAX-ACCESS read-write
        STATUS current
        DESCRIPTION "x"
        ::= { lenient 4 }
      """)

    assert {{:type_with_enum, :INTEGER, [{"FreqWidthOnly", 24}, {"freqOnly", 8}]}, _} =
             object(mib, "policy").syntax

    assert [{5, "enumeration label 'FreqWidthOnly' must start with a lowercase letter"}] =
             mib.warnings
  end

  test "MAX-ACCESS write-only is accepted with a warning" do
    mib =
      parse!("""
      opcode OBJECT-TYPE
        SYNTAX INTEGER
        MAX-ACCESS write-only
        STATUS deprecated
        DESCRIPTION "x"
        ::= { lenient 5 }
      """)

    assert object(mib, "opcode").max_access == :"write-only"
    assert [{6, "MAX-ACCESS write-only is not allowed in SMIv2"}] = mib.warnings
  end

  test "UNITS on an SMIv1 OBJECT-TYPE is kept with a warning" do
    mib =
      parse!("""
      power OBJECT-TYPE
        SYNTAX INTEGER
        UNITS "Tenth-dBm"
        ACCESS read-only
        STATUS mandatory
        DESCRIPTION "x"
        ::= { lenient 6 }
      """)

    assert %{units: "Tenth-dBm", max_access: :"read-only", status: :mandatory} =
             object(mib, "power")

    assert [{4, "UNITS is not allowed in an SMIv1 OBJECT-TYPE"}] = mib.warnings
  end

  test "malformed LAST-UPDATED and REVISION stamps are reported" do
    {:ok, mib} =
      Parser.parse("""
      STAMP-MIB DEFINITIONS ::= BEGIN
      IMPORTS MODULE-IDENTITY FROM SNMPv2-SMI;
      stampMib MODULE-IDENTITY
        LAST-UPDATED "200001010000Z"
        ORGANIZATION "x"
        CONTACT-INFO "x"
        DESCRIPTION "x"
        REVISION "000926000000Z"
        DESCRIPTION "bad: month 26"
        ::= { enterprises 99997 }
      END
      """)

    assert [{3, "invalid timestamp '000926000000Z' (expected YYYYMMDDHHMMZ)"}] = mib.warnings
  end
end
