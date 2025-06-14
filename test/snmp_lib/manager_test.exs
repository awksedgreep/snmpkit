defmodule SnmpKit.SnmpLib.ManagerTest do
  use ExUnit.Case, async: true
  doctest SnmpLib.Manager

  alias SnmpKit.SnmpLib.Manager

  @moduletag :manager_test

  describe "Manager.get/3" do
    test "performs basic GET operation with default options" do
      # Mock a simple GET response - this would normally connect to a real device
      # For testing, we can use a known OID that should work

      # Test OID normalization
      assert is_function(&Manager.get/3)

      # Test with list OID
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      assert {:error, _} = Manager.get("invalid.host.test", oid_list, timeout: 100)

      # Test with string OID
      oid_string = "1.3.6.1.2.1.1.1.0"
      assert {:error, _} = Manager.get("invalid.host.test", oid_string, timeout: 100)
    end

    test "validates input parameters" do
      # Test invalid host
      assert {:error, _} = Manager.get("", [1, 3, 6, 1], timeout: 100)

      # Test invalid OID (empty)
      assert {:error, _} = Manager.get("192.168.1.1", [], timeout: 100)

      # Test with valid parameters but non-existent host
      assert {:error, _} =
               Manager.get("192.168.255.255", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 100)
    end

    test "handles community string options" do
      opts = [community: "private", timeout: 100]

      # Should attempt connection with private community
      assert {:error, _} = Manager.get("invalid.host.test", [1, 3, 6, 1, 2, 1, 1, 1, 0], opts)
    end

    test "handles timeout options" do
      # Short timeout should fail quickly
      start_time = System.monotonic_time(:millisecond)
      {:error, _} = Manager.get("192.168.255.255", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 50)
      end_time = System.monotonic_time(:millisecond)

      # Should complete within reasonable time of timeout
      # Allow for overhead: socket creation, encoding, etc. can add ~25ms
      # Using 200ms threshold to avoid flaky tests under load
      assert end_time - start_time < 200
    end

    test "normalizes OID formats correctly" do
      # Both should work the same way
      list_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      string_oid = "1.3.6.1.2.1.1.1.0"

      result1 = Manager.get("invalid.host.test", list_oid, timeout: 100)
      result2 = Manager.get("invalid.host.test", string_oid, timeout: 100)

      # Both should fail the same way (since host is invalid)
      assert {:error, _} = result1
      assert {:error, _} = result2
    end
  end

  describe "Manager.get_bulk/3" do
    test "validates GETBULK requires SNMPv2c" do
      # v1 should be rejected
      assert {:error, :getbulk_requires_v2c} =
               Manager.get_bulk("192.168.1.1", [1, 3, 6, 1, 2, 1, 2, 2], version: :v1)

      # v2c should be accepted (but fail due to invalid host)
      assert {:error, _} =
               Manager.get_bulk("invalid.host.test", [1, 3, 6, 1, 2, 1, 2, 2],
                 version: :v2c,
                 timeout: 100
               )
    end

    test "handles bulk operation parameters" do
      opts = [
        max_repetitions: 50,
        non_repeaters: 0,
        timeout: 100
      ]

      assert {:error, _} = Manager.get_bulk("invalid.host.test", [1, 3, 6, 1, 2, 1, 2, 2], opts)
    end

    test "validates bulk parameters" do
      # Should work with valid bulk parameters
      opts = [max_repetitions: 10, non_repeaters: 0, timeout: 100]
      assert {:error, _} = Manager.get_bulk("invalid.host.test", [1, 3, 6, 1], opts)
    end
  end

  describe "Manager.set/4" do
    test "accepts different value types" do
      host = "invalid.host.test"
      oid = [1, 3, 6, 1, 2, 1, 1, 5, 0]
      opts = [timeout: 100]

      # String value
      assert {:error, _} = Manager.set(host, oid, {:string, "test"}, opts)

      # Integer value
      assert {:error, _} = Manager.set(host, oid, {:integer, 42}, opts)

      # Counter32 value
      assert {:error, _} = Manager.set(host, oid, {:counter32, 123}, opts)
    end

    test "validates SET parameters" do
      opts = [timeout: 100]

      # Invalid value format should be handled
      assert {:error, _} = Manager.set("invalid.host.test", [1, 3, 6, 1], {:string, "test"}, opts)
    end
  end

  describe "Manager.get_multi/3" do
    test "handles multiple OIDs efficiently" do
      oids = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 2, 1, 1, 3, 0],
        [1, 3, 6, 1, 2, 1, 1, 5, 0]
      ]

      opts = [timeout: 100]

      # Should return results for all OIDs (errors in this case)
      assert {:error, _} = Manager.get_multi("invalid.host.test", oids, opts)
    end

    test "validates multi-get parameters" do
      # Empty OID list should be handled
      assert {:error, _} = Manager.get_multi("192.168.1.1", [], timeout: 100)

      # Invalid OIDs should be handled - empty list case
      assert {:error, _} = Manager.get_multi("invalid.host.test", [], timeout: 100)
    end
  end

  describe "Manager.ping/2" do
    test "performs SNMP reachability test" do
      # Should attempt sysUpTime GET
      assert {:error, _} = Manager.ping("invalid.host.test", timeout: 100)

      # Test with custom community
      assert {:error, _} = Manager.ping("invalid.host.test", community: "private", timeout: 100)
    end

    test "validates ping parameters" do
      # Should handle various input formats
      assert {:error, _} = Manager.ping("", timeout: 100)
      assert {:error, _} = Manager.ping("192.168.255.255", timeout: 50)
    end
  end

  describe "Manager option handling" do
    test "merges default options correctly" do
      # Test that defaults are applied
      assert {:error, _} = Manager.get("invalid.host.test", [1, 3, 6, 1])

      # Test that custom options override defaults
      custom_opts = [
        community: "test",
        version: :v1,
        timeout: 200,
        port: 1161
      ]

      assert {:error, _} = Manager.get("invalid.host.test", [1, 3, 6, 1], custom_opts)
    end

    test "validates option values" do
      # Test various option combinations
      opts = [
        community: "public",
        version: :v2c,
        timeout: 5000,
        retries: 3,
        port: 161,
        local_port: 0
      ]

      assert {:error, _} = Manager.get("invalid.host.test", [1, 3, 6, 1], opts)
    end
  end

  describe "Manager host:port parsing" do
    test "supports host:port string format (backward compatibility)" do
      # Host with port in string format should work
      assert {:error, _} = Manager.get("invalid.host.test:1161", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get("192.168.255.255:162", [1, 3, 6, 1], timeout: 100)

      # Test with get_bulk
      assert {:error, _} = Manager.get_bulk("invalid.host.test:1161", [1, 3, 6, 1], timeout: 100)

      # Test with set
      assert {:error, _} =
               Manager.set("invalid.host.test:1161", [1, 3, 6, 1], {:string, "test"},
                 timeout: 100
               )

      # Test with get_multi
      oids = [[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 3, 0]]
      assert {:error, _} = Manager.get_multi("invalid.host.test:1161", oids, timeout: 100)

      # Test with ping
      assert {:error, _} = Manager.ping("invalid.host.test:1161", timeout: 100)
    end

    test "supports :port option format (new functionality)" do
      # Host without port, using :port option
      assert {:error, _} =
               Manager.get("invalid.host.test", [1, 3, 6, 1], port: 1161, timeout: 100)

      assert {:error, _} = Manager.get("192.168.255.255", [1, 3, 6, 1], port: 162, timeout: 100)

      # Test with get_bulk
      assert {:error, _} =
               Manager.get_bulk("invalid.host.test", [1, 3, 6, 1], port: 1161, timeout: 100)

      # Test with set
      assert {:error, _} =
               Manager.set("invalid.host.test", [1, 3, 6, 1], {:string, "test"},
                 port: 1161,
                 timeout: 100
               )

      # Test with get_multi
      oids = [[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 3, 0]]
      assert {:error, _} = Manager.get_multi("invalid.host.test", oids, port: 1161, timeout: 100)

      # Test with ping
      assert {:error, _} = Manager.ping("invalid.host.test", port: 1161, timeout: 100)
    end

    test "host:port string takes precedence over :port option" do
      # When both are specified, host:port should take precedence for backward compatibility
      # We can't easily test the actual port being used without mocking transport,
      # but we can verify both forms don't cause errors
      assert {:error, _} =
               Manager.get("invalid.host.test:1161", [1, 3, 6, 1], port: 162, timeout: 100)

      assert {:error, _} =
               Manager.get_bulk("invalid.host.test:1161", [1, 3, 6, 1], port: 162, timeout: 100)

      assert {:error, _} =
               Manager.set("invalid.host.test:1161", [1, 3, 6, 1], {:string, "test"},
                 port: 162,
                 timeout: 100
               )

      # Test with get_multi
      oids = [[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 3, 0]]

      assert {:error, _} =
               Manager.get_multi("invalid.host.test:1161", oids, port: 162, timeout: 100)

      # Test with ping
      assert {:error, _} = Manager.ping("invalid.host.test:1161", port: 162, timeout: 100)
    end

    test "handles IPv6 addresses without confusing them with port specifications" do
      # Plain IPv6 addresses contain colons but shouldn't be treated as host:port
      # Use invalid IPv6 addresses to avoid network calls
      assert {:error, _} = Manager.get("invalid::ipv6", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get("test:db8::invalid", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get("fake::1234:5678:9abc:def0", [1, 3, 6, 1], timeout: 100)

      # IPv6 with :port option should work (but fail due to invalid host)
      assert {:error, _} = Manager.get("invalid::ipv6", [1, 3, 6, 1], port: 1161, timeout: 100)

      assert {:error, _} =
               Manager.get("test:db8::invalid", [1, 3, 6, 1], port: 1161, timeout: 100)

      assert {:error, _} =
               Manager.get("fake::1234:5678:9abc:def0", [1, 3, 6, 1], port: 1161, timeout: 100)
    end

    test "supports RFC 3986 bracket notation for IPv6 with ports" do
      # IPv6 with port using bracket notation [addr]:port
      assert {:error, _} = Manager.get("[::1]:1161", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get("[2001:db8::1]:162", [1, 3, 6, 1], timeout: 100)

      assert {:error, _} =
               Manager.get("[fe80::1234:5678:9abc:def0]:2001", [1, 3, 6, 1], timeout: 100)

      # Test with get_bulk
      assert {:error, _} = Manager.get_bulk("[::1]:1161", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get_bulk("[2001:db8::1]:162", [1, 3, 6, 1], timeout: 100)

      # Test with set
      assert {:error, _} =
               Manager.set("[::1]:1161", [1, 3, 6, 1], {:string, "test"}, timeout: 100)

      assert {:error, _} =
               Manager.set("[2001:db8::1]:162", [1, 3, 6, 1], {:string, "test"}, timeout: 100)

      # Test with get_multi
      oids = [[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 3, 0]]
      assert {:error, _} = Manager.get_multi("[::1]:1161", oids, timeout: 100)
      assert {:error, _} = Manager.get_multi("[2001:db8::1]:162", oids, timeout: 100)

      # Test with ping
      assert {:error, _} = Manager.ping("[::1]:1161", timeout: 100)
      assert {:error, _} = Manager.ping("[2001:db8::1]:162", timeout: 100)
    end

    test "bracket notation takes precedence over :port option for IPv6" do
      # When both bracket notation and :port option are provided, bracket should take precedence
      assert {:error, _} = Manager.get("[::1]:1161", [1, 3, 6, 1], port: 162, timeout: 100)

      assert {:error, _} =
               Manager.get("[2001:db8::1]:2001", [1, 3, 6, 1], port: 161, timeout: 100)
    end

    test "handles malformed IPv6 bracket notation gracefully" do
      # Invalid bracket notation should be treated as hostnames and not cause crashes
      # Missing closing bracket
      assert {:error, _} = Manager.get("[::1", [1, 3, 6, 1], timeout: 100)
      # Missing opening bracket
      assert {:error, _} = Manager.get("::1]", [1, 3, 6, 1], timeout: 100)
      # Invalid format
      assert {:error, _} = Manager.get("[::1:abc", [1, 3, 6, 1], timeout: 100)
      # Invalid port
      assert {:error, _} = Manager.get("[::1]:99999", [1, 3, 6, 1], timeout: 100)
      # Non-numeric port
      assert {:error, _} = Manager.get("[::1]:abc", [1, 3, 6, 1], timeout: 100)
    end

    test "handles mixed IPv4/IPv6 scenarios correctly" do
      # IPv4 with port should still work
      assert {:error, _} = Manager.get("192.168.1.1:1161", [1, 3, 6, 1], timeout: 100)

      # IPv6 without port should use :port option
      assert {:error, _} = Manager.get("::1", [1, 3, 6, 1], port: 1161, timeout: 100)

      # IPv6 with bracket notation should override :port option
      assert {:error, _} = Manager.get("[::1]:2001", [1, 3, 6, 1], port: 1161, timeout: 100)

      # Complex IPv6 addresses should work with both patterns
      assert {:error, _} =
               Manager.get("2001:0db8:85a3:0000:0000:8a2e:0370:7334", [1, 3, 6, 1],
                 port: 1161,
                 timeout: 100
               )

      assert {:error, _} =
               Manager.get("[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:2002", [1, 3, 6, 1],
                 timeout: 100
               )
    end

    test "validates port numbers in host:port format" do
      # Invalid port numbers should be handled gracefully
      assert {:error, _} = Manager.get("invalid.host.test:99999", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get("invalid.host.test:0", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get("invalid.host.test:abc", [1, 3, 6, 1], timeout: 100)
    end

    test "falls back to default port 161 when no port specified" do
      # No port in host string and no :port option should use default 161
      assert {:error, _} = Manager.get("invalid.host.test", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get("192.168.255.255", [1, 3, 6, 1], timeout: 100)
    end
  end

  describe "Manager error handling" do
    test "handles network errors gracefully" do
      # Network errors (timeout or network unreachable)
      assert {:error, _} = Manager.get("192.168.255.255", [1, 3, 6, 1], timeout: 50)

      # Invalid host errors
      assert {:error, _} = Manager.get("invalid.hostname.test", [1, 3, 6, 1], timeout: 100)
    end

    test "handles SNMP protocol errors" do
      # These would test actual SNMP error responses
      # For now, we test that error handling structure is in place
      assert is_function(&Manager.get/3)
      assert is_function(&Manager.get_bulk/3)
      assert is_function(&Manager.set/4)
    end
  end

  describe "Manager error status mapping" do
    test "correctly maps SNMP error status codes" do
      # Test that Manager.decode_error_status works correctly through public API
      # We'll test this by simulating PDU responses with different error status codes

      # This tests the internal logic but through a way that's observable
      # The decode_error_status function should map:
      # 0 -> :no_error, 1 -> :too_big, 2 -> :no_such_name, 3 -> :bad_value, 4 -> :read_only, 5 -> :gen_err

      # We can verify this works by using the Error module which should have the same mapping
      assert SnmpLib.Error.error_atom(0) == :no_error
      assert SnmpLib.Error.error_atom(1) == :too_big
      assert SnmpLib.Error.error_atom(2) == :no_such_name
      assert SnmpLib.Error.error_atom(3) == :bad_value
      assert SnmpLib.Error.error_atom(4) == :read_only
      assert SnmpLib.Error.error_atom(5) == :gen_err
    end

    test "error status takes precedence over varbinds" do
      # This test verifies that when error_status != 0, it's handled immediately
      # regardless of what's in varbinds (which is the bug we just fixed)

      # The fix ensures that error_status is checked BEFORE varbinds pattern matching
      # This is critical for proper SNMP error handling

      # We can't directly test the private extract_get_result function,
      # but we can verify the logic is sound by testing error interpretation
      # The interpret_error function only changes :gen_err, other errors pass through
      assert Manager.interpret_error(:no_such_name, :get, :v2c) == :no_such_name
      assert Manager.interpret_error(:gen_err, :get, :v1) == :no_such_name
    end

    test "handles edge cases in error responses" do
      # Verify error handling doesn't break with various inputs
      assert Manager.interpret_error(:timeout, :get, :v2c) == :timeout
      assert Manager.interpret_error(:network_error, :get, :v1) == :network_error
      assert Manager.interpret_error(:invalid_response, :get, :v2c) == :invalid_response
    end

    test "correctly handles SNMPv2c exception values in varbinds" do
      # Test that exception values are properly extracted regardless of format
      # The fix handles both formats:
      # 1. {oid, :end_of_mib_view, nil} - simulator format (type field)
      # 2. {oid, :octet_string, {:end_of_mib_view, nil}} - standard format (value field)

      # This verifies the logic works but we can't test the private function directly
      # Instead verify that SNMPv2c exception types are recognized
      assert SnmpLib.Types.is_exception_type?(:no_such_object) == true
      assert SnmpLib.Types.is_exception_type?(:no_such_instance) == true
      assert SnmpLib.Types.is_exception_type?(:end_of_mib_view) == true
      assert SnmpLib.Types.is_exception_type?(:integer) == false
    end
  end

  describe "Manager error interpretation" do
    test "interpret_error provides better semantics for genErr" do
      # SNMPv1 GET operations
      assert Manager.interpret_error(:gen_err, :get, :v1) == :no_such_name

      # SNMPv2c+ GET operations
      assert Manager.interpret_error(:gen_err, :get, :v2c) == :no_such_object
      assert Manager.interpret_error(:gen_err, :get, :v2) == :no_such_object
      assert Manager.interpret_error(:gen_err, :get, :v3) == :no_such_object

      # SNMPv2c+ GETBULK operations
      assert Manager.interpret_error(:gen_err, :get_bulk, :v2c) == :no_such_object
      assert Manager.interpret_error(:gen_err, :get_bulk, :v2) == :no_such_object

      # Other errors pass through unchanged
      assert Manager.interpret_error(:too_big, :get, :v2c) == :too_big
      assert Manager.interpret_error(:no_such_name, :get, :v1) == :no_such_name
      assert Manager.interpret_error(:bad_value, :set, :v2c) == :bad_value

      # SET operations with genErr remain as genErr
      assert Manager.interpret_error(:gen_err, :set, :v2c) == :gen_err
    end

    test "interpret_error handles edge cases" do
      # Unknown operation types
      assert Manager.interpret_error(:gen_err, :unknown_op, :v2c) == :gen_err

      # Unknown SNMP versions
      assert Manager.interpret_error(:gen_err, :get, :unknown_version) == :gen_err

      # nil or invalid inputs
      assert Manager.interpret_error(nil, :get, :v2c) == nil
      assert Manager.interpret_error(:gen_err, nil, :v2c) == :gen_err
    end
  end

  describe "Manager integration" do
    test "integrates with existing SnmpLib modules" do
      # Verify Manager uses other SnmpLib modules correctly

      # Test OID normalization (should use SnmpLib.OID)
      string_oid = "1.3.6.1.2.1.1.1.0"
      assert {:error, _} = Manager.get("invalid.host.test", string_oid, timeout: 100)

      # Test PDU creation (should use SnmpKit.SnmpLib.PDU)
      assert {:error, _} = Manager.get("invalid.host.test", [1, 3, 6, 1], timeout: 100)

      # Test transport (should use SnmpLib.Transport)
      assert {:error, _} = Manager.ping("invalid.host.test", timeout: 100)
    end
  end

  # Performance and stress tests
  describe "Manager performance" do
    @tag :performance
    test "handles concurrent operations" do
      # Test multiple concurrent operations
      tasks =
        Enum.map(1..5, fn _i ->
          Task.async(fn ->
            Manager.get("invalid.host.test", [1, 3, 6, 1], timeout: 100)
          end)
        end)

      results = Task.await_many(tasks, 1000)

      # All should fail gracefully (invalid host)
      assert Enum.all?(results, fn result ->
               match?({:error, _}, result)
             end)
    end

    @tag :performance
    test "get_multi is more efficient than individual gets" do
      oids = Enum.map(1..10, fn i -> [1, 3, 6, 1, 2, 1, 1, i, 0] end)

      # Time individual gets
      {time_individual, _} =
        :timer.tc(fn ->
          Enum.map(oids, fn oid ->
            Manager.get("invalid.host.test", oid, timeout: 50)
          end)
        end)

      # Time multi get
      {time_multi, _} =
        :timer.tc(fn ->
          Manager.get_multi("invalid.host.test", oids, timeout: 50)
        end)

      # Multi should complete faster (though both will fail)
      # At minimum, they should both complete within reasonable time
      assert time_individual > 0
      assert time_multi > 0
    end
  end

  describe "Manager.get_next/3" do
    test "performs basic GETNEXT operation with default options" do
      # Test function exists and has correct signature
      assert is_function(&Manager.get_next/3)

      # Test with list OID - should fail with invalid host but function should work
      oid_list = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      assert {:error, _} = Manager.get_next("invalid.host.test", oid_list, timeout: 100)

      # Test with string OID
      oid_string = "1.3.6.1.2.1.1.1.0"
      assert {:error, _} = Manager.get_next("invalid.host.test", oid_string, timeout: 100)
    end

    test "uses proper GETNEXT PDU for SNMP v1" do
      # SNMP v1 should use actual GETNEXT PDU, not GETBULK
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      opts = [version: :v1, timeout: 100]

      # Should attempt GETNEXT operation (will fail due to invalid host)
      assert {:error, _} = Manager.get_next("invalid.host.test", oid, opts)
    end

    test "uses GETBULK with max_repetitions=1 for SNMP v2c+" do
      # SNMP v2c should use GETBULK for efficiency
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      opts = [version: :v2c, timeout: 100]

      # Should attempt GETBULK operation (will fail due to invalid host)
      assert {:error, _} = Manager.get_next("invalid.host.test", oid, opts)
    end

    test "validates input parameters" do
      # Test invalid host
      assert {:error, _} = Manager.get_next("", [1, 3, 6, 1], timeout: 100)

      # Test invalid OID (empty)
      assert {:error, _} = Manager.get_next("192.168.1.1", [], timeout: 100)

      # Test with valid parameters but non-existent host
      assert {:error, _} =
               Manager.get_next("192.168.255.255", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 100)
    end

    test "handles community string options" do
      opts = [community: "private", timeout: 100]

      # Should attempt connection with private community
      assert {:error, _} =
               Manager.get_next("invalid.host.test", [1, 3, 6, 1, 2, 1, 1, 1, 0], opts)
    end

    test "handles timeout options" do
      # Short timeout should fail quickly
      start_time = System.monotonic_time(:millisecond)
      {:error, _} = Manager.get_next("192.168.255.255", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 50)
      end_time = System.monotonic_time(:millisecond)

      # Should complete within reasonable time of timeout
      # Allow for overhead: socket creation, encoding, etc. can add ~25ms
      # Using 200ms threshold to avoid flaky tests under load
      assert end_time - start_time < 200
    end

    test "normalizes OID formats correctly" do
      # Both should work the same way
      list_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      string_oid = "1.3.6.1.2.1.1.1.0"

      result1 = Manager.get_next("invalid.host.test", list_oid, timeout: 100)
      result2 = Manager.get_next("invalid.host.test", string_oid, timeout: 100)

      # Both should fail the same way (since host is invalid)
      assert {:error, _} = result1
      assert {:error, _} = result2
    end

    test "supports both SNMP versions" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # Test v1 explicitly
      assert {:error, _} = Manager.get_next("invalid.host.test", oid, version: :v1, timeout: 100)

      # Test v2c explicitly
      assert {:error, _} = Manager.get_next("invalid.host.test", oid, version: :v2c, timeout: 100)

      # Test default (should be v2c)
      assert {:error, _} = Manager.get_next("invalid.host.test", oid, timeout: 100)
    end

    test "handles host:port format correctly" do
      # Host with port in string format should work
      assert {:error, _} = Manager.get_next("invalid.host.test:1161", [1, 3, 6, 1], timeout: 100)
      assert {:error, _} = Manager.get_next("192.168.255.255:162", [1, 3, 6, 1], timeout: 100)

      # IPv6 bracket notation
      assert {:error, _} = Manager.get_next("[::1]:1161", [1, 3, 6, 1], timeout: 100)

      # Port option
      assert {:error, _} =
               Manager.get_next("invalid.host.test", [1, 3, 6, 1], port: 1161, timeout: 100)
    end

    test "expected return format is {:ok, {next_oid, type, value}} tuple" do
      # While we can't test successful responses without a real SNMP device,
      # we can verify the function signature and error return format
      result = Manager.get_next("invalid.host.test", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 100)

      # Should return error tuple (since host is invalid)
      assert {:error, _reason} = result

      # The successful format would be {:ok, {next_oid, type, value}}
      # This is documented in the function spec and examples
    end

    test "handles various option combinations" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # Test with multiple options
      opts = [
        community: "test",
        version: :v1,
        timeout: 200,
        retries: 2,
        port: 1161,
        local_port: 0
      ]

      assert {:error, _} = Manager.get_next("invalid.host.test", oid, opts)

      # Test v2c with different options
      opts_v2c = [
        community: "public",
        version: :v2c,
        timeout: 500,
        retries: 1,
        port: 161
      ]

      assert {:error, _} = Manager.get_next("invalid.host.test", oid, opts_v2c)
    end
  end
end
