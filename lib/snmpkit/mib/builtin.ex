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
    # SNMPv2-MIB notification objects
    "snmpTrap" => [1, 3, 6, 1, 6, 3, 1, 1, 4],
    "snmpTrapOID" => [1, 3, 6, 1, 6, 3, 1, 1, 4, 1],
    "snmpTrapEnterprise" => [1, 3, 6, 1, 6, 3, 1, 1, 4, 3],
    "snmpTraps" => [1, 3, 6, 1, 6, 3, 1, 1, 5],
    "coldStart" => [1, 3, 6, 1, 6, 3, 1, 1, 5, 1],
    "warmStart" => [1, 3, 6, 1, 6, 3, 1, 1, 5, 2],
    "linkDown" => [1, 3, 6, 1, 6, 3, 1, 1, 5, 3],
    "linkUp" => [1, 3, 6, 1, 6, 3, 1, 1, 5, 4],
    "authenticationFailure" => [1, 3, 6, 1, 6, 3, 1, 1, 5, 5],
    "egpNeighborLoss" => [1, 3, 6, 1, 6, 3, 1, 1, 5, 6],
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

  # Enumeration labels for the built-in objects (IF-MIB, IP-MIB, TCP-MIB,
  # SNMPv2-MIB, HOST-RESOURCES-MIB, BRIDGE-MIB, DOCS-IF-MIB); ifType follows
  # IANAifType-MIB.
  @enumerations %{
    "ifAdminStatus" => %{1 => "up", 2 => "down", 3 => "testing"},
    "ifOperStatus" => %{
      1 => "up",
      2 => "down",
      3 => "testing",
      4 => "unknown",
      5 => "dormant",
      6 => "notPresent",
      7 => "lowerLayerDown"
    },
    "ifType" => %{
      1 => "other",
      2 => "regular1822",
      3 => "hdh1822",
      4 => "ddnX25",
      5 => "rfc877x25",
      6 => "ethernetCsmacd",
      7 => "iso88023Csmacd",
      8 => "iso88024TokenBus",
      9 => "iso88025TokenRing",
      10 => "iso88026Man",
      11 => "starLan",
      12 => "proteon10Mbit",
      13 => "proteon80Mbit",
      14 => "hyperchannel",
      15 => "fddi",
      16 => "lapb",
      17 => "sdlc",
      18 => "ds1",
      19 => "e1",
      20 => "basicISDN",
      21 => "primaryISDN",
      22 => "propPointToPointSerial",
      23 => "ppp",
      24 => "softwareLoopback",
      25 => "eon",
      26 => "ethernet3Mbit",
      27 => "nsip",
      28 => "slip",
      29 => "ultra",
      30 => "ds3",
      31 => "sip",
      32 => "frameRelay",
      33 => "rs232",
      34 => "para",
      35 => "arcnet",
      36 => "arcnetPlus",
      37 => "atm",
      38 => "miox25",
      39 => "sonet",
      40 => "x25ple",
      41 => "iso88022llc",
      42 => "localTalk",
      43 => "smdsDxi",
      44 => "frameRelayService",
      45 => "v35",
      46 => "hssi",
      47 => "hippi",
      48 => "modem",
      49 => "aal5",
      50 => "sonetPath",
      51 => "sonetVT",
      52 => "smdsIcip",
      53 => "propVirtual",
      54 => "propMultiplexor",
      55 => "ieee80212",
      56 => "fibreChannel",
      57 => "hippiInterface",
      58 => "frameRelayInterconnect",
      59 => "aflane8023",
      60 => "aflane8025",
      61 => "cctEmul",
      62 => "fastEther",
      63 => "isdn",
      64 => "v11",
      65 => "v36",
      66 => "g703at64k",
      67 => "g703at2mb",
      68 => "qllc",
      69 => "fastEtherFX",
      70 => "channel",
      71 => "ieee80211",
      72 => "ibm370parChan",
      73 => "escon",
      74 => "dlsw",
      75 => "isdns",
      76 => "isdnu",
      77 => "lapd",
      78 => "ipSwitch",
      79 => "rsrb",
      80 => "atmLogical",
      81 => "ds0",
      82 => "ds0Bundle",
      83 => "bsc",
      84 => "async",
      85 => "cnr",
      86 => "iso88025Dtr",
      87 => "eplrs",
      88 => "arap",
      89 => "propCnls",
      90 => "hostPad",
      91 => "termPad",
      92 => "frameRelayMPI",
      93 => "x213",
      94 => "adsl",
      95 => "radsl",
      96 => "sdsl",
      97 => "vdsl",
      98 => "iso88025CRFPInt",
      99 => "myrinet",
      100 => "voiceEM",
      101 => "voiceFXO",
      102 => "voiceFXS",
      103 => "voiceEncap",
      104 => "voiceOverIp",
      105 => "atmDxi",
      106 => "atmFuni",
      107 => "atmIma",
      108 => "pppMultilinkBundle",
      109 => "ipOverCdlc",
      110 => "ipOverClaw",
      111 => "stackToStack",
      112 => "virtualIpAddress",
      113 => "mpc",
      114 => "ipOverAtm",
      115 => "iso88025Fiber",
      116 => "tdlc",
      117 => "gigabitEthernet",
      118 => "hdlc",
      119 => "lapf",
      120 => "v37",
      121 => "x25mlp",
      122 => "x25huntGroup",
      123 => "transpHdlc",
      124 => "interleave",
      125 => "fast",
      126 => "ip",
      127 => "docsCableMaclayer",
      128 => "docsCableDownstream",
      129 => "docsCableUpstream",
      130 => "a12MppSwitch",
      131 => "tunnel",
      132 => "coffee",
      133 => "ces",
      134 => "atmSubInterface",
      135 => "l2vlan",
      136 => "l3ipvlan",
      137 => "l3ipxvlan",
      138 => "digitalPowerline",
      139 => "mediaMailOverIp",
      140 => "dtm",
      141 => "dcn",
      142 => "ipForward",
      143 => "msdsl",
      144 => "ieee1394",
      145 => "if-gsn",
      146 => "dvbRccMacLayer",
      147 => "dvbRccDownstream",
      148 => "dvbRccUpstream",
      149 => "atmVirtual",
      150 => "mplsTunnel",
      151 => "srp",
      152 => "voiceOverAtm",
      153 => "voiceOverFrameRelay",
      154 => "idsl",
      155 => "compositeLink",
      156 => "ss7SigLink",
      157 => "propWirelessP2P",
      158 => "frForward",
      159 => "rfc1483",
      160 => "usb",
      161 => "ieee8023adLag",
      162 => "bgppolicyaccounting",
      163 => "frf16MfrBundle",
      164 => "h323Gatekeeper",
      165 => "h323Proxy",
      166 => "mpls",
      167 => "mfSigLink",
      168 => "hdsl2",
      169 => "shdsl",
      170 => "ds1FDL",
      171 => "pos",
      172 => "dvbAsiIn",
      173 => "dvbAsiOut",
      174 => "plc",
      175 => "nfas",
      176 => "tr008",
      177 => "gr303RDT",
      178 => "gr303IDT",
      179 => "isup",
      180 => "propDocsWirelessMaclayer",
      181 => "propDocsWirelessDownstream",
      182 => "propDocsWirelessUpstream",
      183 => "hiperlan2",
      184 => "propBWAp2Mp",
      185 => "sonetOverheadChannel",
      186 => "digitalWrapperOverheadChannel",
      187 => "aal2",
      188 => "radioMAC",
      189 => "atmRadio",
      190 => "imt",
      191 => "mvl",
      192 => "reachDSL",
      193 => "frDlciEndPt",
      194 => "atmVciEndPt",
      195 => "opticalChannel",
      196 => "opticalTransport",
      197 => "propAtm",
      198 => "voiceOverCable",
      199 => "infiniband",
      200 => "teLink",
      201 => "q2931",
      202 => "virtualTg",
      203 => "sipTg",
      204 => "sipSig",
      205 => "docsCableUpstreamChannel",
      206 => "econet",
      207 => "pon155",
      208 => "pon622",
      209 => "bridge",
      210 => "linegroup",
      211 => "voiceEMFGD",
      212 => "voiceFGDEANA",
      213 => "voiceDID",
      214 => "mpegTransport",
      215 => "sixToFour",
      216 => "gtp",
      217 => "pdnEtherLoop1",
      218 => "pdnEtherLoop2",
      219 => "opticalChannelGroup",
      220 => "homepna",
      221 => "gfp",
      222 => "ciscoISLvlan",
      223 => "actelisMetaLOOP",
      224 => "fcipLink",
      225 => "rpr",
      226 => "qam",
      227 => "lmp",
      228 => "cblVectaStar",
      229 => "docsCableMCmtsDownstream",
      230 => "adsl2",
      231 => "macSecControlledIF",
      232 => "macSecUncontrolledIF",
      233 => "aviciOpticalEther",
      234 => "atmbond",
      235 => "voiceFGDOS",
      236 => "mocaVersion1",
      237 => "ieee80216WMAN",
      238 => "adsl2plus",
      239 => "dvbRcsMacLayer",
      240 => "dvbTdm",
      241 => "dvbRcsTdma",
      242 => "x86Laps",
      243 => "wwanPP",
      244 => "wwanPP2",
      245 => "voiceEBS",
      246 => "ifPwType",
      247 => "ilan",
      248 => "pip",
      249 => "aluELP",
      250 => "gpon",
      251 => "vdsl2",
      252 => "capwapDot11Profile",
      253 => "capwapDot11Bss",
      254 => "capwapWtpVirtualRadio",
      255 => "bits",
      256 => "docsCableUpstreamRfPort",
      257 => "cableDownstreamRfPort",
      258 => "vmwareVirtualNic",
      259 => "ieee802154",
      260 => "otnOdu",
      261 => "otnOch",
      262 => "ifVfiType",
      263 => "g9981",
      264 => "g9982",
      265 => "g9983",
      266 => "aluEpon",
      267 => "aluEponOnu",
      268 => "aluEponPhysicalUni",
      269 => "aluEponLogicalLink",
      270 => "aluGponOnu",
      271 => "aluGponPhysicalUni",
      272 => "vmwareNicTeam"
    },
    "ifLinkUpDownTrapEnable" => %{1 => "enabled", 2 => "disabled"},
    "ifPromiscuousMode" => %{1 => "true", 2 => "false"},
    "ifConnectorPresent" => %{1 => "true", 2 => "false"},
    "ipForwarding" => %{1 => "forwarding", 2 => "notForwarding"},
    "ipRouteType" => %{1 => "other", 2 => "invalid", 3 => "direct", 4 => "indirect"},
    "ipRouteProto" => %{
      1 => "other",
      2 => "local",
      3 => "netmgmt",
      4 => "icmp",
      5 => "egp",
      6 => "ggp",
      7 => "hello",
      8 => "rip",
      9 => "is-is",
      10 => "es-is",
      11 => "ciscoIgrp",
      12 => "bbnSpfIgp",
      13 => "ospf",
      14 => "bgp"
    },
    "ipNetToMediaType" => %{1 => "other", 2 => "invalid", 3 => "dynamic", 4 => "static"},
    "ipNetToPhysicalType" => %{
      1 => "other",
      2 => "invalid",
      3 => "dynamic",
      4 => "static",
      5 => "local"
    },
    "tcpConnState" => %{
      1 => "closed",
      2 => "listen",
      3 => "synSent",
      4 => "synReceived",
      5 => "established",
      6 => "finWait1",
      7 => "finWait2",
      8 => "closeWait",
      9 => "lastAck",
      10 => "closing",
      11 => "timeWait",
      12 => "deleteTCB"
    },
    "tcpRtoAlgorithm" => %{1 => "other", 2 => "constant", 3 => "rsre", 4 => "vanj"},
    "snmpEnableAuthenTraps" => %{1 => "enabled", 2 => "disabled"},
    "hrDeviceStatus" => %{
      1 => "unknown",
      2 => "running",
      3 => "warning",
      4 => "testing",
      5 => "down"
    },
    "hrDiskStorageAccess" => %{1 => "readWrite", 2 => "readOnly"},
    "hrDiskStorageMedia" => %{
      1 => "other",
      2 => "unknown",
      3 => "hardDisk",
      4 => "floppyDisk",
      5 => "opticalDiskROM",
      6 => "opticalDiskWORM",
      7 => "opticalDiskRW",
      8 => "ramDisk"
    },
    "hrSWRunType" => %{
      1 => "unknown",
      2 => "operatingSystem",
      3 => "deviceDriver",
      4 => "application"
    },
    "hrSWRunStatus" => %{1 => "running", 2 => "runnable", 3 => "notRunnable", 4 => "invalid"},
    "dot1dTpFdbStatus" => %{
      1 => "other",
      2 => "invalid",
      3 => "learned",
      4 => "self",
      5 => "mgmt"
    },
    "dot1qTpFdbStatus" => %{
      1 => "other",
      2 => "invalid",
      3 => "learned",
      4 => "self",
      5 => "mgmt"
    },
    "dot1dStpPortState" => %{
      1 => "disabled",
      2 => "blocking",
      3 => "listening",
      4 => "learning",
      5 => "forwarding",
      6 => "broken"
    },
    "docsIfCmStatusValue" => %{
      1 => "other",
      2 => "notReady",
      3 => "notSynchronized",
      4 => "phySynchronized",
      5 => "usParametersAcquired",
      6 => "rangingComplete",
      7 => "ipComplete",
      8 => "todEstablished",
      9 => "securityEstablished",
      10 => "paramTransferComplete",
      11 => "registrationComplete",
      12 => "operational",
      13 => "accessDenied"
    },
    "docsIfCmtsCmStatusValue" => %{
      1 => "other",
      2 => "ranging",
      3 => "rangingAborted",
      4 => "rangingComplete",
      5 => "ipComplete",
      6 => "registrationComplete",
      7 => "accessDenied",
      9 => "operational",
      10 => "registeredBPIInitializing"
    },
    "docsIfDownChannelModulation" => %{1 => "unknown", 2 => "other", 3 => "qam64", 4 => "qam256"},
    "docsIfDownChannelInterleave" => %{
      1 => "unknown",
      2 => "other",
      3 => "taps8Increment16",
      4 => "taps16Increment8",
      5 => "taps32Increment4",
      6 => "taps64Increment2",
      7 => "taps128Increment1",
      8 => "taps12increment17"
    },
    "docsIfUpChannelType" => %{
      0 => "unknown",
      1 => "tdma",
      2 => "atdma",
      3 => "scdma",
      4 => "tdmaAndAtdma"
    }
  }

  # INDEX objects of the built-in conceptual rows
  @table_indexes %{
    "ifEntry" => ["ifIndex"],
    "ifXEntry" => ["ifIndex"],
    "ipAddrEntry" => ["ipAdEntAddr"],
    "ipRouteEntry" => ["ipRouteDest"],
    "ipNetToMediaEntry" => ["ipNetToMediaIfIndex", "ipNetToMediaNetAddress"],
    "dot1dTpFdbEntry" => ["dot1dTpFdbAddress"],
    "docsIfDownstreamChannelEntry" => ["ifIndex"],
    "docsIfUpstreamChannelEntry" => ["ifIndex"],
    "docsIfSignalQualityEntry" => ["ifIndex"],
    "docsIfCmStatusEntry" => ["ifIndex"]
  }

  @doc "INDEX object names of a built-in conceptual row (ifEntry -> [\"ifIndex\"]), or `nil`."
  @spec table_indexes(String.t()) :: [String.t()] | nil
  def table_indexes(entry_name), do: Map.get(@table_indexes, entry_name)

  @doc "Enumeration labels (`%{value => label}`) for a built-in object, or `nil`."
  @spec enumerations(String.t()) :: %{integer() => String.t()} | nil
  def enumerations(base_name), do: Map.get(@enumerations, base_name)

  @doc """
  Everything the formatter needs for a built-in object: syntax base, textual
  convention, DISPLAY-HINT and enumerations, with the textual convention's
  hint and labels filled in from `SnmpKit.MIB.Syntax`.
  """
  @spec meta(String.t()) :: map()
  def meta(base_name) do
    syntax = syntax(base_name)
    tc = syntax.textual_convention
    tc_info = tc && Map.get(SnmpKit.MIB.Syntax.builtin_textual_conventions(), tc)

    %{
      syntax_base: syntax.base || (tc_info && tc_info.base),
      textual_convention: tc,
      display_hint: syntax.display_hint || (tc_info && tc_info.display_hint),
      enumerations: enumerations(base_name) || (tc_info && tc_info.enumerations),
      size: tc_info && Map.get(tc_info, :size),
      indexes: table_indexes(base_name) && Enum.map(table_indexes(base_name), &{&1, false}),
      augments: nil
    }
  end

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
