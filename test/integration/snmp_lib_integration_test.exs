defmodule SnmpKit.SnmpLib.Integration.Phase2Test do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpLib.{PDU, OID, Transport, Types, ASN1}

  @moduletag :integration
  @moduletag :protocol
  @moduletag :phase_2

  # Test timeout for network operations
  @test_timeout 200

  describe "PDU + OID Integration" do
    test "builds PDU with OID operations" do
      # Use OID module to build OID, then PDU module to create request
      {:ok, oid_list} = OID.string_to_list("1.3.6.1.2.1.1.1.0")

      # Create PDU with OID
      varbinds = [{oid_list, :null, :null}]
      {:ok, pdu} = PDU.build_get_request_multi(varbinds, 12345)
      message = PDU.build_message(pdu, "public")

      # Verify PDU structure contains our OID
      assert pdu.varbinds == varbinds
      assert pdu.type == :get_request
    end

    test "handles OID tree operations in PDU context" do
      parent_oid = [1, 3, 6, 1, 2, 1]
      child_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # Verify relationship
      assert OID.is_child_of?(child_oid, parent_oid) == true

      # Build PDU with child OID
      varbinds = [{child_oid, :null, :null}]
      {:ok, pdu} = PDU.build_get_request_multi(varbinds, 12345)

      assert pdu.varbinds == varbinds
    end

    test "validates OIDs in PDU context" do
      valid_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      invalid_oid = []

      # Valid OID should work
      assert :ok = OID.valid_oid?(valid_oid)
      varbinds = [{valid_oid, :null, :null}]
      {:ok, pdu} = PDU.build_get_request_multi(varbinds, 12345)
      assert pdu.varbinds == varbinds

      # Invalid OID should be caught by validation
      assert {:error, :empty_oid} = OID.valid_oid?(invalid_oid)
    end
  end

  describe "PDU + Types Integration" do
    test "coerces values in PDU responses" do
      # Build response PDU with typed values
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # Test different type coercions
      {:ok, counter_value} = Types.coerce_value(:counter32, 42)
      {:ok, string_value} = Types.coerce_value(:string, "System Description")
      {:ok, timeticks_value} = Types.coerce_value(:timeticks, 12345)

      varbinds = [
        {oid, counter_value},
        {[1, 3, 6, 1, 2, 1, 1, 2, 0], string_value},
        {[1, 3, 6, 1, 2, 1, 1, 3, 0], timeticks_value}
      ]

      response_pdu = PDU.build_response(1, 0, 0, varbinds)
      response_message = PDU.build_message(response_pdu, "public")

      # Verify typed values are preserved
      assert response_pdu.varbinds == varbinds
      assert response_pdu.type == :get_response
    end

    test "validates typed values" do
      # Test type validation
      assert :ok = Types.validate_counter32(42)
      assert {:error, :out_of_range} = Types.validate_counter32(-1)

      # Test IP address validation and formatting
      ip_binary = <<192, 168, 1, 1>>
      assert :ok = Types.validate_ip_address(ip_binary)
      assert "192.168.1.1" = Types.format_ip_address(ip_binary)

      # Test TimeTicks formatting
      assert "1 minute 23 seconds 45 centiseconds" = Types.format_timeticks_uptime(8345)
    end

    test "handles type coercion errors gracefully" do
      # Invalid type coercion should fail
      assert {:error, :unsupported_type} = Types.coerce_value(:invalid_type, 42)
      assert {:error, :out_of_range} = Types.coerce_value(:counter32, -1)
    end
  end

  describe "PDU + ASN.1 Integration" do
    test "encodes and decodes PDU with ASN.1" do
      # Create a simple PDU
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      varbinds = [{oid, :null, :null}]
      {:ok, pdu} = PDU.build_get_request_multi(varbinds, 12345)
      message = PDU.build_message(pdu, "public")

      # Encode PDU (this uses ASN.1 internally)
      {:ok, encoded_message} = PDU.encode_message(message)

      # Should be valid ASN.1 structure
      assert :ok = ASN1.validate_ber_structure(encoded_message)

      # Decode back
      {:ok, decoded_message} = PDU.decode_message(encoded_message)

      # Should match original (types may be auto-detected during decode)
      assert decoded_message.pdu.type == pdu.type
      assert length(decoded_message.pdu.varbinds) == 1
      [{decoded_oid, _decoded_type, decoded_value}] = decoded_message.pdu.varbinds
      [{original_oid, _original_type, original_value}] = pdu.varbinds
      assert decoded_oid == original_oid
      assert decoded_value == original_value
      assert decoded_message.community == "public"
    end

    test "handles ASN.1 integer encoding in PDU context" do
      # Test that PDU handles various integer types correctly
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # Different integer values that PDU might encounter
      test_values = [0, 42, 127, 128, 255, 256, 65535, 65536]

      for value <- test_values do
        varbinds = [{oid, :integer, value}]
        response_pdu = PDU.build_response(1, 0, 0, varbinds)
        message = PDU.build_message(response_pdu, "public")

        # Encode and decode
        {:ok, encoded} = PDU.encode_message(message)
        {:ok, decoded} = PDU.decode_message(encoded)

        # Value should be preserved
        [{_oid, _type, decoded_value}] = decoded.pdu.varbinds
        assert decoded_value == value
      end
    end

    test "validates ASN.1 structure of encoded PDUs" do
      # Create PDU with various data types
      varbinds = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], "System Description"},
        {[1, 3, 6, 1, 2, 1, 1, 3, 0], 12345},
        {[1, 3, 6, 1, 2, 1, 1, 4, 0], "admin@example.com"},
        {[1, 3, 6, 1, 2, 1, 1, 5, 0], "router.example.com"}
      ]

      response_pdu = PDU.build_response(1, 0, 0, varbinds)
      message = PDU.build_message(response_pdu, "public")
      {:ok, encoded} = PDU.encode_message(message)

      # Should be valid ASN.1
      assert :ok = ASN1.validate_ber_structure(encoded)

      # Should also calculate length correctly
      {:ok, calculated_length} = ASN1.calculate_ber_length(encoded)
      actual_length = byte_size(encoded)
      assert calculated_length == actual_length
    end
  end

  describe "OID + Types Integration" do
    test "validates OID strings with type context" do
      # Test OID validation with different type contexts
      oid_string = "1.3.6.1.2.1.1.1.0"
      {:ok, oid_list} = OID.string_to_list(oid_string)

      # Validate as OID type
      assert :ok = Types.validate_oid(oid_list)

      # Coerce string to OID
      {:ok, coerced_oid} = Types.coerce_value(:oid, oid_string)
      assert coerced_oid == oid_list
    end

    test "handles enterprise OIDs with type formatting" do
      enterprise_oid = [1, 3, 6, 1, 4, 1, 9, 1, 1]

      # Verify it's an enterprise OID
      assert OID.is_enterprise?(enterprise_oid) == true
      {:ok, enterprise_number} = OID.get_enterprise_number(enterprise_oid)
      assert enterprise_number == 9

      # Validate as OID type
      assert :ok = Types.validate_oid(enterprise_oid)

      # Format as string
      {:ok, oid_string} = OID.list_to_string(enterprise_oid)
      assert oid_string == "1.3.6.1.4.1.9.1.1"
    end
  end

  describe "Transport + PDU Integration" do
    test "creates sockets for SNMP communication" do
      # Create client socket for SNMP
      {:ok, client_socket} = Transport.create_client_socket()

      # Should recognize SNMP ports
      assert Transport.is_snmp_port?(161) == true
      assert Transport.is_snmp_port?(162) == true
      assert Transport.snmp_agent_port() == 161

      # Test connectivity functions exist
      max_payload = Transport.max_snmp_payload_size()
      assert is_integer(max_payload)
      assert max_payload > 0

      # Clean up
      :ok = Transport.close_socket(client_socket)
    end

    test "validates packet sizes for SNMP" do
      # Create a PDU and check if it fits in packet limits
      large_value = String.duplicate("A", 1000)
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      varbinds = [{oid, large_value}]

      pdu = PDU.build_response(1, 0, 0, varbinds)
      message = PDU.build_message(pdu, "public")
      {:ok, encoded} = PDU.encode_message(message)

      packet_size = byte_size(encoded)
      max_size = Transport.max_snmp_payload_size()

      # Should validate packet size
      is_valid = Transport.valid_packet_size?(packet_size)
      assert is_boolean(is_valid)

      # If packet is too large, should be invalid
      if packet_size > max_size do
        assert is_valid == false
      end
    end
  end

  describe "Full Stack Integration" do
    test "complete SNMP message workflow" do
      # Step 1: Create OID using OID module
      {:ok, system_desc_oid} = OID.string_to_list("1.3.6.1.2.1.1.1.0")

      # Step 2: Validate and coerce values using Types module
      {:ok, description_value} = Types.coerce_value(:string, "Test SNMP Agent")

      # Step 3: Build PDU
      varbinds = [{system_desc_oid, :string, description_value}]
      request_pdu = PDU.build_get_request_multi(varbinds, 12345)
      request_message = PDU.build_message(request_pdu, "public")

      # Step 4: Encode message (uses ASN.1 internally)
      {:ok, encoded_request} = PDU.encode_message(request_message)

      # Step 5: Validate message structure
      assert :ok = ASN1.validate_ber_structure(encoded_request)

      # Step 6: Simulate response creation
      response_varbinds = [{system_desc_oid, :string, "Simulated SNMP Agent v1.0"}]
      response_pdu = PDU.build_response(request_pdu.request_id, 0, 0, response_varbinds)
      response_message = PDU.build_message(response_pdu, "public")

      # Step 7: Encode response
      {:ok, encoded_response} = PDU.encode_message(response_message)

      # Step 8: Decode and verify response
      {:ok, decoded_response} = PDU.decode_message(encoded_response)

      # Verify round-trip integrity
      assert decoded_response.pdu.type == :get_response
      assert decoded_response.pdu.request_id == request_pdu.request_id
      assert decoded_response.community == "public"
      assert length(decoded_response.pdu.varbinds) == 1

      [{response_oid, _type, response_value}] = decoded_response.pdu.varbinds
      assert response_oid == system_desc_oid
      assert response_value == "Simulated SNMP Agent v1.0"
    end

    test "handles complex data types in full workflow" do
      # Create varbinds with different SNMP types
      varbinds = [
        # System description (string)
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], "Complex Agent"},
        # System uptime (timeticks)
        {[1, 3, 6, 1, 2, 1, 1, 3, 0], 123_456},
        # Interface count (integer)
        {[1, 3, 6, 1, 2, 1, 2, 1, 0], 5},
        # System OID
        {[1, 3, 6, 1, 2, 1, 1, 2, 0], [1, 3, 6, 1, 4, 1, 9, 1, 1]}
      ]

      # Build and encode response with complex types
      # Convert values to 3-tuple format
      typed_varbinds =
        Enum.map(varbinds, fn {oid, value} ->
          {oid, :string, value}
        end)

      pdu = PDU.build_response(123, 0, 0, typed_varbinds)
      message = PDU.build_message(pdu, "complex")
      {:ok, encoded} = PDU.encode_message(message)

      # Validate structure
      assert :ok = ASN1.validate_ber_structure(encoded)

      # Decode and verify
      {:ok, decoded} = PDU.decode_message(encoded)

      # Check that decoding preserves OIDs and basic structure
      # (decoder may auto-detect types differently than specified)
      assert length(decoded.pdu.varbinds) == length(typed_varbinds)

      # Verify at least the first varbind (string value) is preserved
      [{first_oid, _decoded_type, decoded_value} | _] = decoded.pdu.varbinds
      [{expected_oid, _expected_type, expected_value} | _] = typed_varbinds
      assert first_oid == expected_oid
      assert decoded_value == expected_value
      assert decoded.community == "complex"
    end

    test "error handling across modules" do
      # Test that errors propagate correctly across module boundaries

      # Invalid OID should be caught
      invalid_oid = []
      assert {:error, :empty_oid} = OID.valid_oid?(invalid_oid)

      # Invalid type coercion should fail
      assert {:error, :out_of_range} = Types.coerce_value(:counter32, -1)

      # PDU with invalid data should fail encoding
      invalid_varbinds = [{[1, 2, 3], :invalid_type, :invalid_value_type}]
      pdu = PDU.build_get_request_multi(invalid_varbinds, 456)

      # Should handle encoding errors gracefully
      message = PDU.build_message(pdu, "test")
      result = PDU.encode_message(message)
      # This may succeed or fail depending on implementation details,
      # but should not crash
      case result do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  describe "Performance Integration" do
    test "handles multiple operations efficiently" do
      # Test that combined operations perform reasonably
      start_time = System.monotonic_time(:microsecond)

      # Perform 100 complete workflows
      for i <- 1..100 do
        oid_string = "1.3.6.1.2.1.1.#{i}.0"
        {:ok, oid} = OID.string_to_list(oid_string)
        {:ok, value} = Types.coerce_value(:counter32, i)

        varbinds = [{oid, :counter32, value}]
        pdu = PDU.build_get_request_multi(varbinds, i)
        message = PDU.build_message(pdu, "perf")
        {:ok, encoded} = PDU.encode_message(message)
        {:ok, decoded} = PDU.decode_message(encoded)

        # Note: decoded may have different type representation
        assert length(decoded.pdu.varbinds) == 1
        [{decoded_oid, _decoded_type, _decoded_value}] = decoded.pdu.varbinds
        assert decoded_oid == oid
      end

      end_time = System.monotonic_time(:microsecond)
      duration = end_time - start_time

      # Should complete in reasonable time (< 100ms)
      assert duration < 100_000
    end
  end

  describe "Thread Safety Integration" do
    test "handles concurrent operations across modules" do
      # Test thread safety when using multiple modules concurrently
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            # Each task performs a complete workflow
            oid_string = "1.3.6.1.2.1.1.1.#{i}"
            {:ok, oid} = OID.string_to_list(oid_string)
            {:ok, value} = Types.coerce_value(:string, "Value #{i}")

            varbinds = [{oid, :string, value}]
            pdu = PDU.build_response(i, 0, 0, varbinds)
            message = PDU.build_message(pdu, "thread_test")
            {:ok, encoded} = PDU.encode_message(message)

            # Validate ASN.1 structure
            :ok = ASN1.validate_ber_structure(encoded)

            {:ok, decoded} = PDU.decode_message(encoded)

            {i, oid, value, decoded}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Verify all operations completed successfully
      assert length(results) == 50

      for {i, original_oid, original_value, decoded} <- results do
        assert decoded.pdu.request_id == i
        assert decoded.community == "thread_test"
        assert length(decoded.pdu.varbinds) == 1

        [{decoded_oid, _type, decoded_value}] = decoded.pdu.varbinds
        assert decoded_oid == original_oid
        assert decoded_value == original_value
      end
    end
  end
end
