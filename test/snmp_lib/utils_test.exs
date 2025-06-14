defmodule SnmpKit.SnmpLib.UtilsTest do
  use ExUnit.Case, async: true
  doctest SnmpLib.Utils
  
  alias SnmpKit.SnmpLib.Utils
  
  describe "Utils.pretty_print_pdu/1" do
    test "formats basic GET request PDU" do
      pdu = %{
        type: :get_request,
        request_id: 123,
        varbinds: [
          {[1, 3, 6, 1, 2, 1, 1, 1, 0], :null}
        ]
      }
      
      result = Utils.pretty_print_pdu(pdu)
      
      assert String.contains?(result, "GET Request")
      assert String.contains?(result, "ID: 123")
      assert String.contains?(result, "1.3.6.1.2.1.1.1.0")
    end
    
    test "formats error response PDU" do
      pdu = %{
        type: :get_response,
        request_id: 456,
        error_status: 2,
        error_index: 1,
        varbinds: []
      }
      
      result = Utils.pretty_print_pdu(pdu)
      
      assert String.contains?(result, "Response")
      assert String.contains?(result, "ID: 456")
      assert String.contains?(result, "Error:")
      assert String.contains?(result, "no varbinds")
    end
    
    test "formats GET-BULK request PDU" do
      pdu = %{
        type: :get_bulk_request,
        request_id: 789,
        non_repeaters: 1,
        max_repetitions: 10,
        varbinds: [
          {[1, 3, 6, 1, 2, 1, 2, 2, 1, 1], :null}
        ]
      }
      
      result = Utils.pretty_print_pdu(pdu)
      
      assert String.contains?(result, "GET-BULK Request")
      assert String.contains?(result, "Non-repeaters: 1")
      assert String.contains?(result, "Max-repetitions: 10")
    end
    
    test "handles invalid PDU gracefully" do
      result = Utils.pretty_print_pdu("not a map")
      assert result == "Invalid PDU"
    end
  end
  
  describe "Utils.pretty_print_varbinds/1" do
    test "formats varbinds list" do
      varbinds = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], "Linux server"},
        {[1, 3, 6, 1, 2, 1, 1, 3, 0], {:timeticks, 12345}}
      ]
      
      result = Utils.pretty_print_varbinds(varbinds)
      
      assert String.contains?(result, "1. 1.3.6.1.2.1.1.1.0")
      assert String.contains?(result, "2. 1.3.6.1.2.1.1.3.0")
      assert String.contains?(result, "Linux server")
      assert String.contains?(result, "TimeTicks")
    end
    
    test "handles empty varbinds list" do
      result = Utils.pretty_print_varbinds([])
      assert result == "  (no varbinds)"
    end
    
    test "handles invalid varbinds" do
      result = Utils.pretty_print_varbinds("not a list")
      assert result == "Invalid varbinds"
    end
  end
  
  describe "Utils.pretty_print_oid/1" do
    test "formats OID list" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      result = Utils.pretty_print_oid(oid)
      assert result == "1.3.6.1.2.1.1.1.0"
    end
    
    test "handles OID string" do
      oid = "1.3.6.1.2.1.1.1.0"
      result = Utils.pretty_print_oid(oid)
      assert result == "1.3.6.1.2.1.1.1.0"
    end
    
    test "handles invalid OID" do
      result = Utils.pretty_print_oid(123)
      assert result == "invalid-oid"
    end
  end
  
  describe "Utils.pretty_print_value/1" do
    test "formats null value" do
      result = Utils.pretty_print_value(:null)
      assert result == "NULL"
    end
    
    test "formats integer values" do
      result = Utils.pretty_print_value({:integer, 42})
      assert result == "INTEGER: 42"
      
      result = Utils.pretty_print_value(42)
      assert result == "INTEGER: 42"
    end
    
    test "formats string values" do
      result = Utils.pretty_print_value({:octet_string, "Hello"})
      assert result == ~s(OCTET STRING: "Hello")
      
      result = Utils.pretty_print_value("Hello")
      assert result == ~s("Hello")
    end
    
    test "formats binary data as hex" do
      binary_data = <<0x00, 0x1B, 0x21, 0x3C>>
      result = Utils.pretty_print_value({:octet_string, binary_data})
      assert String.contains?(result, "00 1B 21 3C")
      
      result = Utils.pretty_print_value(binary_data)
      assert String.contains?(result, "00 1B 21 3C")
    end
    
    test "formats SNMP-specific types" do
      result = Utils.pretty_print_value({:counter32, 12345})
      assert result == "Counter32: 12,345"
      
      result = Utils.pretty_print_value({:gauge32, 67890})
      assert result == "Gauge32: 67,890"
      
      result = Utils.pretty_print_value({:timeticks, 123456})
      assert String.contains?(result, "TimeTicks: 123,456")
      
      result = Utils.pretty_print_value({:counter64, 9876543210})
      assert result == "Counter64: 9,876,543,210"
    end
    
    test "formats IP address" do
      result = Utils.pretty_print_value({:ip_address, <<192, 168, 1, 1>>})
      assert result == "IpAddress: 192.168.1.1"
    end
    
    test "formats OID value" do
      result = Utils.pretty_print_value({:object_identifier, [1, 3, 6, 1, 2, 1, 1, 1, 0]})
      assert result == "OID: 1.3.6.1.2.1.1.1.0"
    end
    
    test "formats SNMPv2c exception values" do
      result = Utils.pretty_print_value({:no_such_object, nil})
      assert result == "noSuchObject"
      
      result = Utils.pretty_print_value({:no_such_instance, nil})
      assert result == "noSuchInstance"
      
      result = Utils.pretty_print_value({:end_of_mib_view, nil})
      assert result == "endOfMibView"
    end
    
    test "formats unknown values" do
      result = Utils.pretty_print_value({:unknown_type, "data"})
      assert String.contains?(result, "unknown_type")
    end
  end
  
  describe "Utils.format_bytes/1" do
    test "formats bytes" do
      assert Utils.format_bytes(512) == "512 B"
      assert Utils.format_bytes(0) == "0 B"
    end
    
    test "formats kilobytes" do
      assert Utils.format_bytes(1024) == "1.0 KB"
      assert Utils.format_bytes(1536) == "1.5 KB"
    end
    
    test "formats megabytes" do
      assert Utils.format_bytes(1_048_576) == "1.0 MB"
      assert Utils.format_bytes(2_621_440) == "2.5 MB"
    end
    
    test "formats gigabytes" do
      assert Utils.format_bytes(1_073_741_824) == "1.0 GB"
      assert Utils.format_bytes(2_147_483_648) == "2.0 GB"
    end
    
    test "handles invalid input" do
      assert Utils.format_bytes(-1) == "Invalid byte count"
      assert Utils.format_bytes("not a number") == "Invalid byte count"
    end
  end
  
  describe "Utils.format_rate/2" do
    test "formats basic rates" do
      assert Utils.format_rate(100, "bps") == "100 bps"
      assert Utils.format_rate(45, "pps") == "45 pps"
    end
    
    test "formats kilo rates" do
      assert Utils.format_rate(1500, "bps") == "1.5 Kbps"
      assert Utils.format_rate(2000, "pps") == "2.0 Kpps"
    end
    
    test "formats mega rates" do
      assert Utils.format_rate(1_500_000, "bps") == "1.5 Mbps"
      assert Utils.format_rate(10_000_000, "Hz") == "10.0 MHz"
    end
    
    test "formats giga rates" do
      assert Utils.format_rate(1_000_000_000, "bps") == "1.0 Gbps"
      assert Utils.format_rate(2_500_000_000, "Hz") == "2.5 GHz"
    end
    
    test "handles invalid input" do
      assert Utils.format_rate("not a number", "bps") == "Invalid rate"
      assert Utils.format_rate(100, 123) == "Invalid rate"
    end
  end
  
  describe "Utils.truncate_string/2" do
    test "truncates long strings" do
      result = Utils.truncate_string("Hello, World!", 10)
      assert result == "Hello, ..."
    end
    
    test "leaves short strings unchanged" do
      result = Utils.truncate_string("Short", 10)
      assert result == "Short"
    end
    
    test "handles exact length" do
      result = Utils.truncate_string("1234567890", 10)
      assert result == "1234567890"
    end
    
    test "handles edge cases" do
      result = Utils.truncate_string("Test", 3)
      assert result == "Test"  # max_length too small for ellipsis
      
      result = Utils.truncate_string("", 10)
      assert result == ""
      
      result = Utils.truncate_string(123, 10)
      assert result == ""
    end
  end
  
  describe "Utils.format_hex/2" do
    test "formats hex with default separator" do
      data = <<0x00, 0x1B, 0x21, 0x3C, 0x92, 0xEB>>
      result = Utils.format_hex(data)
      assert result == "00:1B:21:3C:92:EB"
    end
    
    test "formats hex with custom separator" do
      data = <<0xDE, 0xAD, 0xBE, 0xEF>>
      result = Utils.format_hex(data, " ")
      assert result == "DE AD BE EF"
      
      result = Utils.format_hex(data, "-")
      assert result == "DE-AD-BE-EF"
    end
    
    test "handles empty binary" do
      result = Utils.format_hex(<<>>)
      assert result == ""
    end
    
    test "handles single byte" do
      result = Utils.format_hex(<<0xFF>>)
      assert result == "FF"
    end
    
    test "handles invalid input" do
      result = Utils.format_hex(12345, ":")
      assert result == "Invalid binary data"
      
      result = Utils.format_hex(<<0x00>>, 123)
      assert result == "Invalid binary data"
    end
  end
  
  describe "Utils.format_number/1" do
    test "formats numbers with commas" do
      assert Utils.format_number(1234567) == "1,234,567"
      assert Utils.format_number(12345) == "12,345"
      assert Utils.format_number(1234) == "1,234"
    end
    
    test "handles small numbers" do
      assert Utils.format_number(123) == "123"
      assert Utils.format_number(42) == "42"
      assert Utils.format_number(0) == "0"
    end
    
    test "handles negative numbers" do
      assert Utils.format_number(-12345) == "-12,345"
      assert Utils.format_number(-123) == "-123"
    end
    
    test "handles invalid input" do
      assert Utils.format_number("not a number") == "Invalid number"
      assert Utils.format_number(12.34) == "Invalid number"
    end
  end
  
  describe "Utils.measure_request_time/1" do
    test "measures function execution time" do
      {result, time} = Utils.measure_request_time(fn ->
        :timer.sleep(10)
        :test_result
      end)
      
      assert result == :test_result
      assert time >= 10_000  # At least 10ms in microseconds
      assert is_integer(time)
    end
    
    test "handles functions that return various types" do
      {result, time} = Utils.measure_request_time(fn -> {:ok, "success"} end)
      assert result == {:ok, "success"}
      assert is_integer(time)
      
      assert_raise RuntimeError, fn ->
        Utils.measure_request_time(fn -> raise "error" end)
      end
    end
  end
  
  describe "Utils.format_response_time/1" do
    test "formats microseconds" do
      assert Utils.format_response_time(500) == "500μs"
      assert Utils.format_response_time(999) == "999μs"
    end
    
    test "formats milliseconds" do
      assert Utils.format_response_time(1500) == "1.50ms"
      assert Utils.format_response_time(10_000) == "10.00ms"
      assert Utils.format_response_time(999_999) == "1000.00ms"
    end
    
    test "formats seconds" do
      assert Utils.format_response_time(1_500_000) == "1.50s"
      assert Utils.format_response_time(2_500_000) == "2.50s"
    end
    
    test "handles edge cases" do
      assert Utils.format_response_time(0) == "0μs"
      assert Utils.format_response_time(1000) == "1.00ms"
      assert Utils.format_response_time(1_000_000) == "1.00s"
    end
    
    test "handles invalid input" do
      assert Utils.format_response_time(-1) == "Invalid time"
      assert Utils.format_response_time("not a number") == "Invalid time"
    end
  end
  
  describe "Utils.valid_snmp_version?/1" do
    test "validates numeric versions" do
      assert Utils.valid_snmp_version?(0) == true
      assert Utils.valid_snmp_version?(1) == true
      assert Utils.valid_snmp_version?(2) == true
      assert Utils.valid_snmp_version?(3) == true
    end
    
    test "validates atom versions" do
      assert Utils.valid_snmp_version?(:v1) == true
      assert Utils.valid_snmp_version?(:v2c) == true
      assert Utils.valid_snmp_version?(:v3) == true
    end
    
    test "rejects invalid versions" do
      assert Utils.valid_snmp_version?(4) == false
      assert Utils.valid_snmp_version?(-1) == false
      assert Utils.valid_snmp_version?(:v4) == false
      assert Utils.valid_snmp_version?("1") == false
    end
  end
  
  describe "Utils.valid_community_string?/1" do
    test "validates good community strings" do
      assert Utils.valid_community_string?("public") == true
      assert Utils.valid_community_string?("private") == true
      assert Utils.valid_community_string?("community123") == true
      assert Utils.valid_community_string?("My-Community_String") == true
    end
    
    test "rejects invalid community strings" do
      assert Utils.valid_community_string?("") == false
      assert Utils.valid_community_string?(123) == false
      assert Utils.valid_community_string?(nil) == false
    end
    
    test "rejects non-printable characters" do
      # This test assumes non-printable characters would be rejected
      # The exact behavior depends on String.printable?/1
      binary_with_null = "test\0string"
      assert Utils.valid_community_string?(binary_with_null) == false
    end
  end
  
  describe "Utils.sanitize_community/1" do
    test "sanitizes community strings" do
      assert Utils.sanitize_community("public") == "******"
      assert Utils.sanitize_community("private") == "*******"
      assert Utils.sanitize_community("a") == "*"
    end
    
    test "handles empty community" do
      assert Utils.sanitize_community("") == "<empty>"
    end
    
    test "handles invalid input" do
      assert Utils.sanitize_community(123) == "<invalid>"
      assert Utils.sanitize_community(nil) == "<invalid>"
    end
  end
  
  describe "integration tests" do
    test "pretty printing works with complex PDU" do
      pdu = %{
        type: :get_response,
        request_id: 42,
        error_status: 0,
        error_index: 0,
        varbinds: [
          {[1, 3, 6, 1, 2, 1, 1, 1, 0], "Linux server 4.19.0"},
          {[1, 3, 6, 1, 2, 1, 1, 3, 0], {:timeticks, 123456}},
          {[1, 3, 6, 1, 2, 1, 2, 1, 0], {:integer, 2}},
          {[1, 3, 6, 1, 2, 1, 1, 6, 0], {:object_identifier, [1, 3, 6, 1, 4, 1, 8072, 3, 2, 10]}}
        ]
      }
      
      result = Utils.pretty_print_pdu(pdu)
      
      # Should contain all the expected elements
      assert String.contains?(result, "Response")
      assert String.contains?(result, "Linux server")
      assert String.contains?(result, "TimeTicks")
      assert String.contains?(result, "INTEGER: 2")
      assert String.contains?(result, "OID:")
    end
    
    test "timing utilities work with SNMP operations" do
      # Simulate an SNMP operation
      mock_snmp_operation = fn ->
        :timer.sleep(5)  # Simulate 5ms operation
        {:ok, "SNMP response"}
      end
      
      {result, time_us} = Utils.measure_request_time(mock_snmp_operation)
      formatted_time = Utils.format_response_time(time_us)
      
      assert result == {:ok, "SNMP response"}
      assert time_us >= 5000  # At least 5ms in microseconds
      assert String.contains?(formatted_time, "ms") or String.contains?(formatted_time, "μs")
    end
    
    test "data formatting works with SNMP values" do
      # Test formatting of various SNMP counter values
      interface_octets = 1_234_567_890
      uptime_ticks = 12_345_600  # About 1.4 days
      
      formatted_bytes = Utils.format_bytes(interface_octets)
      formatted_number = Utils.format_number(interface_octets)
      formatted_timeticks = Utils.pretty_print_value({:timeticks, uptime_ticks})
      
      assert String.contains?(formatted_bytes, "GB") or String.contains?(formatted_bytes, "MB")
      assert String.contains?(formatted_number, ",")
      assert String.contains?(formatted_timeticks, "d") or String.contains?(formatted_timeticks, "h")
    end
  end
end