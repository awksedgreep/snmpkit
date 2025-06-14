defmodule SnmpKit.SnmpSim.WalkParserTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.WalkParser

  describe "Walk File Parsing" do
    test "parses named MIB format walk files (IF-MIB::ifInOctets.2)" do
      line = "IF-MIB::ifInOctets.2 = Counter32: 1234567890"

      result = WalkParser.parse_walk_line(line)

      assert {"1.3.6.1.2.1.2.2.1.10.2",
              %{type: "Counter32", value: 1_234_567_890, mib_name: "IF-MIB::ifInOctets.2"}} =
               result
    end

    test "parses numeric OID format walk files (.1.3.6.1.2.1.2.2.1.10.2)" do
      line = ".1.3.6.1.2.1.2.2.1.10.2 = Counter32: 1234567890"

      result = WalkParser.parse_walk_line(line)

      assert {"1.3.6.1.2.1.2.2.1.10.2", %{type: "Counter32", value: 1_234_567_890}} = result
    end

    test "handles mixed walk file formats in same file" do
      temp_dir = System.tmp_dir!()
      temp_file = Path.join(temp_dir, "mixed_walk_#{:rand.uniform(1_000_000)}")

      content = """
      SNMPv2-MIB::sysDescr.0 = STRING: "Test Device"
      .1.3.6.1.2.1.1.2.0 = OID: .1.3.6.1.4.1.9.1.1
      IF-MIB::ifInOctets.1 = Counter32: 12345
      .1.3.6.1.2.1.2.2.1.16.1 = Counter32: 67890
      """

      File.write!(temp_file, content)

      {:ok, oid_map} = WalkParser.parse_walk_file(temp_file)

      assert map_size(oid_map) == 4
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.1.1.0")
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.1.2.0")
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.2.2.1.10.1")
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.2.2.1.16.1")

      File.rm(temp_file)
    end

    test "extracts data types correctly (Counter32, STRING, INTEGER)" do
      lines = [
        "SNMPv2-MIB::sysDescr.0 = STRING: \"Test Device\"",
        "SNMPv2-MIB::sysServices.0 = INTEGER: 72",
        "IF-MIB::ifInOctets.1 = Counter32: 1234567890",
        "IF-MIB::ifSpeed.1 = Gauge32: 1000000000"
      ]

      results = Enum.map(lines, &WalkParser.parse_walk_line/1)

      assert {_oid1, %{type: "STRING", value: "Test Device"}} = Enum.at(results, 0)
      assert {_oid2, %{type: "INTEGER", value: 72}} = Enum.at(results, 1)
      assert {_oid3, %{type: "Counter32", value: 1_234_567_890}} = Enum.at(results, 2)
      assert {_oid4, %{type: "Gauge32", value: 1_000_000_000}} = Enum.at(results, 3)
    end

    test "cleans quoted strings and hex values" do
      lines = [
        "SNMPv2-MIB::sysDescr.0 = STRING: \"Quoted String\"",
        "IF-MIB::ifPhysAddress.1 = HEX-STRING: 00 1A 2B 3C 4D 5E",
        "SNMPv2-MIB::sysContact.0 = STRING: admin@example.com"
      ]

      results = Enum.map(lines, &WalkParser.parse_walk_line/1)

      assert {_oid1, %{value: "Quoted String"}} = Enum.at(results, 0)
      assert {_oid2, %{value: "001A2B3C4D5E"}} = Enum.at(results, 1)
      assert {_oid3, %{value: "admin@example.com"}} = Enum.at(results, 2)
    end

    test "resolves basic MIB names to numeric OIDs" do
      mib_lines = [
        "SNMPv2-MIB::sysDescr.0 = STRING: \"Test\"",
        "IF-MIB::ifNumber.0 = INTEGER: 2",
        "IP-MIB::ipForwarding.0 = INTEGER: 1"
      ]

      results = Enum.map(mib_lines, &WalkParser.parse_walk_line/1)

      assert {"1.3.6.1.2.1.1.1.0", _} = Enum.at(results, 0)
      assert {"1.3.6.1.2.1.2.1.0", _} = Enum.at(results, 1)
      assert {"1.3.6.1.2.1.4.1.0", _} = Enum.at(results, 2)
    end

    test "skips comments and empty lines" do
      lines = [
        "# This is a comment",
        "",
        "SNMPv2-MIB::sysDescr.0 = STRING: \"Test Device\"",
        "   ",
        "# Another comment"
      ]

      results = Enum.map(lines, &WalkParser.parse_walk_line/1)

      assert [nil, nil, {_oid, _value}, nil, nil] = results
    end

    test "handles timeticks format correctly" do
      line = "SNMPv2-MIB::sysUpTime.0 = Timeticks: (12345600) 1 day, 10:17:36.00"

      result = WalkParser.parse_walk_line(line)

      assert {"1.3.6.1.2.1.1.3.0", %{type: "Timeticks", value: 12_345_600}} = result
    end
  end

  describe "File Reading" do
    test "reads actual walk file successfully" do
      {:ok, oid_map} = WalkParser.parse_walk_file("priv/walks/cable_modem.walk")

      assert is_map(oid_map)
      assert map_size(oid_map) > 0

      # Check for specific expected OIDs
      # sysDescr
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.1.1.0")
      # ifNumber
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.2.1.0")
    end

    test "reads numeric OID walk file successfully" do
      {:ok, oid_map} = WalkParser.parse_walk_file("priv/walks/cable_modem_oids.walk")

      assert is_map(oid_map)
      assert map_size(oid_map) > 0

      # Check for specific expected OIDs
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.1.1.0")
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.2.1.0")
    end

    test "handles non-existent file gracefully" do
      result = WalkParser.parse_walk_file("non_existent_file.walk")

      assert {:error, {:file_read_error, :enoent}} = result
    end
  end

  describe "Data Type Parsing" do
    test "parses integer values correctly" do
      lines = [
        "SNMPv2-MIB::sysServices.0 = INTEGER: 72",
        "IF-MIB::ifIndex.1 = INTEGER: 1",
        "IF-MIB::ifType.1 = INTEGER: ethernetCsmacd(6)"
      ]

      results = Enum.map(lines, &WalkParser.parse_walk_line/1)

      assert {_, %{value: 72}} = Enum.at(results, 0)
      assert {_, %{value: 1}} = Enum.at(results, 1)
      assert {_, %{value: 6}} = Enum.at(results, 2)
    end

    test "parses IP addresses correctly" do
      line = "IP-MIB::ipAdEntAddr.192.168.1.1 = IpAddress: 192.168.1.1"

      result = WalkParser.parse_walk_line(line)

      assert {_, %{value: "192.168.1.1"}} = result
    end

    test "handles OID values correctly" do
      line = "SNMPv2-MIB::sysObjectID.0 = OID: .1.3.6.1.4.1.4491.2.4.1"

      result = WalkParser.parse_walk_line(line)

      assert {_, %{value: "1.3.6.1.4.1.4491.2.4.1"}} = result
    end
  end
end
