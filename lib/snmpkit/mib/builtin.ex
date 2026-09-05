defmodule SnmpKit.MIB.Builtin do
  @moduledoc """
  Name/OID table and curated syntax metadata for the standard objects SnmpKit
  knows without loading any MIB file (SNMPv2-MIB, IF-MIB, IP-MIB, BRIDGE-MIB,
  Q-BRIDGE-MIB and friends).

  `SnmpKit.SnmpMgr.MIB` seeds its registry from `name_to_oid/0`; the curated
  `syntax/1` metadata is a stopgap for objects whose MIB has not been compiled.
  """

  @standard_mibs %{
    # System group (1.3.6.1.2.1.1)
    "sysDescr" => [1, 3, 6, 1, 2, 1, 1, 1],
    "sysObjectID" => [1, 3, 6, 1, 2, 1, 1, 2],
    "sysUpTime" => [1, 3, 6, 1, 2, 1, 1, 3],
    "sysContact" => [1, 3, 6, 1, 2, 1, 1, 4],
    "sysName" => [1, 3, 6, 1, 2, 1, 1, 5],
    "sysLocation" => [1, 3, 6, 1, 2, 1, 1, 6],
    "sysServices" => [1, 3, 6, 1, 2, 1, 1, 7],

    # Interface group (1.3.6.1.2.1.2)
    "ifNumber" => [1, 3, 6, 1, 2, 1, 2, 1],
    "ifTable" => [1, 3, 6, 1, 2, 1, 2, 2],
    "ifEntry" => [1, 3, 6, 1, 2, 1, 2, 2, 1],
    "ifIndex" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 1],
    "ifDescr" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 2],
    "ifType" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 3],
    "ifMtu" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 4],
    "ifSpeed" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 5],
    "ifPhysAddress" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 6],
    "ifAdminStatus" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 7],
    "ifOperStatus" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 8],
    "ifLastChange" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 9],
    "ifInOctets" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 10],
    "ifInUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 11],
    "ifInNUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 12],
    "ifInDiscards" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 13],
    "ifInErrors" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 14],
    "ifInUnknownProtos" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 15],
    "ifOutOctets" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 16],
    "ifOutUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 17],
    "ifOutNUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 18],
    "ifOutDiscards" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 19],
    "ifOutErrors" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 20],
    "ifOutQLen" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 21],
    "ifSpecific" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 22],

    # Interface Extensions (ifX) group (1.3.6.1.2.1.31)
    "ifXTable" => [1, 3, 6, 1, 2, 1, 31, 1],
    "ifXEntry" => [1, 3, 6, 1, 2, 1, 31, 1, 1],
    "ifName" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 1],
    "ifInMulticastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 2],
    "ifInBroadcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 3],
    "ifOutMulticastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 4],
    "ifOutBroadcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 5],
    "ifHCInOctets" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 6],
    "ifHCInUcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 7],
    "ifHCInMulticastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 8],
    "ifHCInBroadcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 9],
    "ifHCOutOctets" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 10],
    "ifHCOutUcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 11],
    "ifHCOutMulticastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 12],
    "ifHCOutBroadcastPkts" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 13],
    "ifLinkUpDownTrapEnable" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 14],
    "ifHighSpeed" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 15],
    "ifPromiscuousMode" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 16],
    "ifConnectorPresent" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 17],
    "ifAlias" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 18],
    "ifCounterDiscontinuityTime" => [1, 3, 6, 1, 2, 1, 31, 1, 1, 19],

    # IP group (1.3.6.1.2.1.4)
    "ipForwarding" => [1, 3, 6, 1, 2, 1, 4, 1],
    "ipDefaultTTL" => [1, 3, 6, 1, 2, 1, 4, 2],
    "ipInReceives" => [1, 3, 6, 1, 2, 1, 4, 3],
    "ipInHdrErrors" => [1, 3, 6, 1, 2, 1, 4, 4],
    "ipInAddrErrors" => [1, 3, 6, 1, 2, 1, 4, 5],

    # SNMP group (1.3.6.1.2.1.11)
    "snmpInPkts" => [1, 3, 6, 1, 2, 1, 11, 1],
    "snmpOutPkts" => [1, 3, 6, 1, 2, 1, 11, 2],
    "snmpInBadVersions" => [1, 3, 6, 1, 2, 1, 11, 3],
    "snmpInBadCommunityNames" => [1, 3, 6, 1, 2, 1, 11, 4],
    "snmpInBadCommunityUses" => [1, 3, 6, 1, 2, 1, 11, 5],
    "snmpInASNParseErrs" => [1, 3, 6, 1, 2, 1, 11, 6],
    "snmpInTooBigs" => [1, 3, 6, 1, 2, 1, 11, 8],
    "snmpInNoSuchNames" => [1, 3, 6, 1, 2, 1, 11, 9],
    "snmpInBadValues" => [1, 3, 6, 1, 2, 1, 11, 10],
    "snmpInReadOnlys" => [1, 3, 6, 1, 2, 1, 11, 11],
    "snmpInGenErrs" => [1, 3, 6, 1, 2, 1, 11, 12],
    "snmpInTotalReqVars" => [1, 3, 6, 1, 2, 1, 11, 13],
    "snmpInTotalSetVars" => [1, 3, 6, 1, 2, 1, 11, 14],
    "snmpInGetRequests" => [1, 3, 6, 1, 2, 1, 11, 15],
    "snmpInGetNexts" => [1, 3, 6, 1, 2, 1, 11, 16],
    "snmpInSetRequests" => [1, 3, 6, 1, 2, 1, 11, 17],
    "snmpInGetResponses" => [1, 3, 6, 1, 2, 1, 11, 18],
    "snmpInTraps" => [1, 3, 6, 1, 2, 1, 11, 19],
    "snmpOutTooBigs" => [1, 3, 6, 1, 2, 1, 11, 20],
    "snmpOutNoSuchNames" => [1, 3, 6, 1, 2, 1, 11, 21],
    "snmpOutBadValues" => [1, 3, 6, 1, 2, 1, 11, 22],
    "snmpOutGenErrs" => [1, 3, 6, 1, 2, 1, 11, 24],
    "snmpOutGetRequests" => [1, 3, 6, 1, 2, 1, 11, 25],
    "snmpOutGetNexts" => [1, 3, 6, 1, 2, 1, 11, 26],
    "snmpOutSetRequests" => [1, 3, 6, 1, 2, 1, 11, 27],
    "snmpOutGetResponses" => [1, 3, 6, 1, 2, 1, 11, 28],
    "snmpOutTraps" => [1, 3, 6, 1, 2, 1, 11, 29],
    "snmpEnableAuthenTraps" => [1, 3, 6, 1, 2, 1, 11, 30],

    # Common group prefixes for bulk walking
    "system" => [1, 3, 6, 1, 2, 1, 1],
    "interfaces" => [1, 3, 6, 1, 2, 1, 2],
    "if" => [1, 3, 6, 1, 2, 1, 2],
    "ifX" => [1, 3, 6, 1, 2, 1, 31],
    "ip" => [1, 3, 6, 1, 2, 1, 4],
    "icmp" => [1, 3, 6, 1, 2, 1, 5],
    "tcp" => [1, 3, 6, 1, 2, 1, 6],
    "udp" => [1, 3, 6, 1, 2, 1, 7],
    "snmp" => [1, 3, 6, 1, 2, 1, 11],
    "mib-2" => [1, 3, 6, 1, 2, 1],
    "mgmt" => [1, 3, 6, 1, 2],
    "internet" => [1, 3, 6, 1],

    # Common enterprise OIDs
    "enterprises" => [1, 3, 6, 1, 4, 1],
    "cisco" => [1, 3, 6, 1, 4, 1, 9],
    "hp" => [1, 3, 6, 1, 4, 1, 11],
    "3com" => [1, 3, 6, 1, 4, 1, 43],
    "sun" => [1, 3, 6, 1, 4, 1, 42],
    "dec" => [1, 3, 6, 1, 4, 1, 36],
    "ibm" => [1, 3, 6, 1, 4, 1, 2],
    "microsoft" => [1, 3, 6, 1, 4, 1, 311],
    "netapp" => [1, 3, 6, 1, 4, 1, 789],
    "juniper" => [1, 3, 6, 1, 4, 1, 2636],
    "fortinet" => [1, 3, 6, 1, 4, 1, 12356],
    "paloalto" => [1, 3, 6, 1, 4, 1, 25461],
    "mikrotik" => [1, 3, 6, 1, 4, 1, 14988],

    # Cable/DOCSIS industry OIDs
    "cablelabs" => [1, 3, 6, 1, 4, 1, 4491],
    "docsis" => [1, 3, 6, 1, 2, 1, 127],
    "cableDataPrivateMib" => [1, 3, 6, 1, 4, 1, 4491, 2, 1],
    "arris" => [1, 3, 6, 1, 4, 1, 4115],
    "motorola" => [1, 3, 6, 1, 4, 1, 1166],
    "scientificatlanta" => [1, 3, 6, 1, 4, 1, 1429],
    "broadcom" => [1, 3, 6, 1, 4, 1, 4413]
  }

  # Curated minimal metadata for high-value IF-MIB objects (stopgap until full compiler integration)
  @curated_syntax %{
    # SNMPv2-MIB system group
    "sysDescr" => %{
      base: :octet_string,
      textual_convention: "DisplayString",
      display_hint: "255a"
    },
    "sysObjectID" => %{base: :object_identifier, textual_convention: nil, display_hint: nil},
    "sysUpTime" => %{base: :timeticks, textual_convention: nil, display_hint: nil},
    "sysContact" => %{
      base: :octet_string,
      textual_convention: "DisplayString",
      display_hint: "255a"
    },
    "sysName" => %{base: :octet_string, textual_convention: "DisplayString", display_hint: "255a"},
    "sysLocation" => %{
      base: :octet_string,
      textual_convention: "DisplayString",
      display_hint: "255a"
    },
    "sysServices" => %{base: :integer, textual_convention: nil, display_hint: nil},

    # IF-MIB ifTable (1.3.6.1.2.1.2.2.1)
    "ifIndex" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "ifDescr" => %{base: :octet_string, textual_convention: "DisplayString", display_hint: "255a"},
    "ifType" => %{base: :integer, textual_convention: "IANAifType", display_hint: nil},
    "ifMtu" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "ifSpeed" => %{base: :gauge32, textual_convention: nil, display_hint: nil},
    "ifPhysAddress" => %{
      base: :octet_string,
      textual_convention: "PhysAddress",
      display_hint: nil
    },
    "ifAdminStatus" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "ifOperStatus" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "ifLastChange" => %{base: :timeticks, textual_convention: nil, display_hint: nil},
    "ifInOctets" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifInUcastPkts" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifInNUcastPkts" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifInDiscards" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifInErrors" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifInUnknownProtos" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifOutOctets" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifOutUcastPkts" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifOutNUcastPkts" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifOutDiscards" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifOutErrors" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifOutQLen" => %{base: :gauge32, textual_convention: nil, display_hint: nil},
    "ifSpecific" => %{base: :object_identifier, textual_convention: nil, display_hint: nil},

    # IF-MIB ifXTable (1.3.6.1.2.1.31.1.1.1)
    "ifName" => %{base: :octet_string, textual_convention: "DisplayString", display_hint: "255a"},
    "ifInMulticastPkts" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifInBroadcastPkts" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifOutMulticastPkts" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifOutBroadcastPkts" => %{base: :counter32, textual_convention: nil, display_hint: nil},
    "ifHCInOctets" => %{base: :counter64, textual_convention: nil, display_hint: nil},
    "ifHCInUcastPkts" => %{base: :counter64, textual_convention: nil, display_hint: nil},
    "ifHCInMulticastPkts" => %{base: :counter64, textual_convention: nil, display_hint: nil},
    "ifHCInBroadcastPkts" => %{base: :counter64, textual_convention: nil, display_hint: nil},
    "ifHCOutOctets" => %{base: :counter64, textual_convention: nil, display_hint: nil},
    "ifHCOutUcastPkts" => %{base: :counter64, textual_convention: nil, display_hint: nil},
    "ifHCOutMulticastPkts" => %{base: :counter64, textual_convention: nil, display_hint: nil},
    "ifHCOutBroadcastPkts" => %{base: :counter64, textual_convention: nil, display_hint: nil},
    "ifLinkUpDownTrapEnable" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "ifHighSpeed" => %{base: :gauge32, textual_convention: nil, display_hint: nil},
    "ifPromiscuousMode" => %{base: :boolean, textual_convention: "TruthValue", display_hint: nil},
    "ifConnectorPresent" => %{base: :boolean, textual_convention: "TruthValue", display_hint: nil},
    "ifAlias" => %{base: :octet_string, textual_convention: "DisplayString", display_hint: "255a"},
    "ifCounterDiscontinuityTime" => %{
      base: :timeticks,
      textual_convention: "TimeStamp",
      display_hint: nil
    },

    # IP-MIB (ARP table: ipNetToMediaTable 1.3.6.1.2.1.4.22)
    "ipNetToMediaIfIndex" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "ipNetToMediaPhysAddress" => %{
      base: :octet_string,
      textual_convention: "PhysAddress",
      display_hint: nil
    },
    "ipNetToMediaNetAddress" => %{
      base: :ip_address,
      textual_convention: "IpAddress",
      display_hint: nil
    },
    "ipNetToMediaType" => %{base: :integer, textual_convention: nil, display_hint: nil},

    # BRIDGE-MIB (dot1dTpFdbTable and base)
    "dot1dBaseBridgeAddress" => %{
      base: :octet_string,
      textual_convention: "MacAddress",
      display_hint: nil
    },
    "dot1dBaseNumPorts" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "dot1dBasePortIfIndex" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "dot1dTpFdbAddress" => %{
      base: :octet_string,
      textual_convention: "MacAddress",
      display_hint: nil
    },
    "dot1dTpFdbPort" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "dot1dTpFdbStatus" => %{base: :integer, textual_convention: nil, display_hint: nil},

    # IP-MIB (RFC 4293) modern ARP replacement: ipNetToPhysicalTable
    # Prefer these over ipNetToMedia*
    "ipNetToPhysicalIfIndex" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "ipNetToPhysicalPhysAddress" => %{
      base: :octet_string,
      textual_convention: "PhysAddress",
      display_hint: nil
    },
    "ipNetToPhysicalNetAddress" => %{
      base: :octet_string,
      textual_convention: "InetAddress",
      display_hint: nil
    },
    "ipNetToPhysicalType" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "ipNetToPhysicalLastUpdated" => %{
      base: :timeticks,
      textual_convention: "TimeStamp",
      display_hint: nil
    },

    # Q-BRIDGE-MIB (VLAN-aware FDB)
    "dot1qTpFdbAddress" => %{
      base: :octet_string,
      textual_convention: "MacAddress",
      display_hint: nil
    },
    "dot1qTpFdbPort" => %{base: :integer, textual_convention: nil, display_hint: nil},
    "dot1qTpFdbStatus" => %{base: :integer, textual_convention: nil, display_hint: nil}
  }

  @doc "Name to OID map for the built-in objects."
  @spec name_to_oid() :: %{String.t() => [non_neg_integer()]}
  def name_to_oid, do: @standard_mibs

  @doc "Curated syntax metadata (`%{base, textual_convention, display_hint}`) for a base name."
  @spec syntax(String.t()) :: map()
  def syntax(base_name) do
    Map.get(@curated_syntax, base_name, %{base: nil, textual_convention: nil, display_hint: nil})
  end

  def module_for(base_name) do
    cond do
      String.starts_with?(base_name, "sys") -> "SNMPv2-MIB"
      String.starts_with?(base_name, "ifHC") -> "IF-MIB"
      String.starts_with?(base_name, "ifIn") -> "IF-MIB"
      String.starts_with?(base_name, "ifOut") -> "IF-MIB"
      String.starts_with?(base_name, "if") -> "IF-MIB"
      String.starts_with?(base_name, "ipNetToMedia") -> "IP-MIB"
      String.starts_with?(base_name, "ipNetToPhysical") -> "IP-MIB"
      String.starts_with?(base_name, "dot1d") -> "BRIDGE-MIB"
      String.starts_with?(base_name, "dot1q") -> "Q-BRIDGE-MIB"
      true -> nil
    end
  end
end
