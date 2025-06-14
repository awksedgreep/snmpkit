defmodule SnmpKit.SnmpMgr.FormatTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpKit.SnmpMgr.Format

  describe "pretty_print/1 - new functionality" do
    test "formats 3-tuple results with type-aware formatting" do
      # Test timeticks formatting (delegates to SnmpKit.SnmpLib.Types)
      result = {"1.3.6.1.2.1.1.3.0", :timeticks, 12_345_678}
      {oid, type, formatted} = Format.pretty_print(result)

      assert oid == "1.3.6.1.2.1.1.3.0"
      assert type == :timeticks
      assert is_binary(formatted)
      assert String.contains?(formatted, "day")
    end

    test "formats counter types with labels" do
      result = {"1.3.6.1.2.1.2.2.1.10.1", :counter32, 42_000_000}
      {_oid, _type, formatted} = Format.pretty_print(result)

      assert formatted == "42000000 (Counter32)"
    end

    test "formats gauge types with labels" do
      result = {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 100_000_000}
      {_oid, _type, formatted} = Format.pretty_print(result)

      assert formatted == "100000000 (Gauge32)"
    end

    test "formats object identifiers" do
      # Test with OID list
      result = {"1.3.6.1.2.1.1.2.0", :object_identifier, [1, 3, 6, 1, 4, 1, 9]}
      {_oid, _type, formatted} = Format.pretty_print(result)

      assert formatted == "1.3.6.1.4.1.9"

      # Test with OID string
      result2 = {"1.3.6.1.2.1.1.2.0", :object_identifier, "1.3.6.1.4.1.9"}
      {_oid, _type, formatted2} = Format.pretty_print(result2)

      assert formatted2 == "1.3.6.1.4.1.9"
    end

    test "handles unknown types gracefully" do
      result = {"1.3.6.1.2.1.1.1.0", :unknown_type, "test value"}
      {_oid, _type, formatted} = Format.pretty_print(result)

      assert formatted == "\"test value\""
    end
  end

  describe "pretty_print_all/1 - new functionality" do
    test "formats list of SNMP results" do
      results = [
        {"1.3.6.1.2.1.1.3.0", :timeticks, 12345},
        {"1.3.6.1.2.1.2.2.1.10.1", :counter32, 42_000_000}
      ]

      formatted = Format.pretty_print_all(results)

      assert length(formatted) == 2
      assert Enum.all?(formatted, fn {_oid, _type, value} -> is_binary(value) end)
    end
  end

  describe "bytes/1 - new functionality" do
    test "formats byte counts into human-readable sizes" do
      assert Format.bytes(512) == "512 bytes"
      assert Format.bytes(1024) == "1.0 KB"
      assert Format.bytes(1_048_576) == "1.0 MB"
      assert Format.bytes(1_073_741_824) == "1.0 GB"
      assert Format.bytes(1_099_511_627_776) == "1.0 TB"
    end

    test "handles edge cases" do
      assert Format.bytes(0) == "0 bytes"
      assert Format.bytes(1023) == "1023 bytes"
      assert Format.bytes(1536) == "1.5 KB"
    end

    test "handles non-integer input gracefully" do
      result = Format.bytes("not a number")
      assert String.contains?(result, "not a number")
    end
  end

  describe "speed/1 - new functionality" do
    test "formats network speeds into human-readable rates" do
      assert Format.speed(100) == "100 bps"
      assert Format.speed(1000) == "1.0 Kbps"
      assert Format.speed(1_000_000) == "1.0 Mbps"
      assert Format.speed(1_000_000_000) == "1.0 Gbps"
      assert Format.speed(1_000_000_000_000) == "1.0 Tbps"
    end

    test "handles common network speeds" do
      assert Format.speed(10_000_000) == "10.0 Mbps"
      assert Format.speed(100_000_000) == "100.0 Mbps"
      assert Format.speed(1_000_000_000) == "1.0 Gbps"
    end

    test "handles non-integer input gracefully" do
      result = Format.speed("fast")
      assert String.contains?(result, "fast")
    end
  end

  describe "interface_status/1 - new functionality" do
    test "formats standard interface status codes" do
      assert Format.interface_status(1) == "up"
      assert Format.interface_status(2) == "down"
      assert Format.interface_status(3) == "testing"
      assert Format.interface_status(4) == "unknown"
      assert Format.interface_status(5) == "dormant"
      assert Format.interface_status(6) == "notPresent"
      assert Format.interface_status(7) == "lowerLayerDown"
    end

    test "handles unknown status codes" do
      assert Format.interface_status(99) == "unknown(99)"
      assert Format.interface_status(0) == "unknown(0)"
    end
  end

  describe "interface_type/1 - new functionality" do
    test "formats common interface types" do
      assert Format.interface_type(1) == "other"
      assert Format.interface_type(6) == "ethernetCsmacd"
      assert Format.interface_type(24) == "softwareLoopback"
      assert Format.interface_type(131) == "tunnel"
      assert Format.interface_type(161) == "ieee80211"
    end

    test "handles unknown interface types" do
      assert Format.interface_type(999) == "type999"
      assert Format.interface_type(42) == "type42"
    end
  end

  describe "mac_address/1" do
    test "formats binary MAC address" do
      mac_binary = <<0x00, 0x1B, 0x21, 0x3C, 0x4D, 0x5E>>
      result = SnmpKit.SnmpMgr.Format.mac_address(mac_binary)
      assert result == "00:1b:21:3c:4d:5e"
    end

    test "formats list MAC address" do
      mac_list = [0, 27, 33, 60, 77, 94]
      result = SnmpKit.SnmpMgr.Format.mac_address(mac_list)
      assert result == "00:1b:21:3c:4d:5e"
    end

    test "handles uppercase hex values" do
      mac_list = [255, 255, 255, 255, 255, 255]
      result = SnmpKit.SnmpMgr.Format.mac_address(mac_list)
      assert result == "ff:ff:ff:ff:ff:ff"
    end

    test "handles all zeros" do
      mac_binary = <<0, 0, 0, 0, 0, 0>>
      result = SnmpKit.SnmpMgr.Format.mac_address(mac_binary)
      assert result == "00:00:00:00:00:00"
    end

    test "handles invalid input gracefully" do
      result = SnmpKit.SnmpMgr.Format.mac_address("invalid")
      assert is_binary(result)
    end
  end

  describe "format_by_type/2 with MAC addresses" do
    test "auto-detects MAC address in 6-byte octet string" do
      mac_binary = <<0x00, 0x1B, 0x21, 0x3C, 0x4D, 0x5E>>
      result = SnmpKit.SnmpMgr.Format.format_by_type(:octet_string, mac_binary)
      assert result == "00:1b:21:3c:4d:5e"
    end

    test "does not format non-6-byte octet strings as MAC" do
      short_binary = <<0x00, 0x1B>>
      result = SnmpKit.SnmpMgr.Format.format_by_type(:octet_string, short_binary)
      assert result == short_binary
    end

    test "formats explicit mac_address type" do
      mac_list = [0, 27, 33, 60, 77, 94]
      result = SnmpKit.SnmpMgr.Format.format_by_type(:mac_address, mac_list)
      assert result == "00:1b:21:3c:4d:5e"
    end
  end
end
