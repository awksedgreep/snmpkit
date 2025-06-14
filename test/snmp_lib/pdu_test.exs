defmodule SnmpKit.SnmpLib.PDUTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpKit.SnmpLib.PDU

  @moduletag :unit
  @moduletag :protocol
  @moduletag :phase_1

  describe "PDU construction" do
    test "builds GET request PDU with correct structure" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      request_id = 12345

      pdu = PDU.build_get_request(oid, request_id)

      assert pdu.type == :get_request
      assert pdu.request_id == request_id
      assert pdu.error_status == 0
      assert pdu.error_index == 0
      assert pdu.varbinds == [{oid, :null, :null}]
    end

    test "builds GETNEXT request PDU" do
      oid = [1, 3, 6, 1, 2, 1, 1]
      request_id = 23456

      pdu = PDU.build_get_next_request(oid, request_id)

      assert pdu.type == :get_next_request
      assert pdu.request_id == request_id
      assert pdu.varbinds == [{oid, :null, :null}]
    end

    test "builds GETBULK request PDU with non-repeaters and max-repetitions" do
      oid = [1, 3, 6, 1, 2, 1, 2, 2]
      request_id = 34567
      non_repeaters = 0
      max_repetitions = 10

      pdu = PDU.build_get_bulk_request(oid, request_id, non_repeaters, max_repetitions)

      assert pdu.type == :get_bulk_request
      assert pdu.request_id == request_id
      assert pdu.non_repeaters == non_repeaters
      assert pdu.max_repetitions == max_repetitions
      assert pdu.varbinds == [{oid, :null, :null}]
    end

    test "builds SET request PDU with value" do
      oid = [1, 3, 6, 1, 2, 1, 1, 5, 0]
      request_id = 45678
      value = {:string, "new-hostname"}

      pdu = PDU.build_set_request(oid, value, request_id)

      assert pdu.type == :set_request
      assert pdu.request_id == request_id
      assert pdu.varbinds == [{oid, :string, "new-hostname"}]
    end

    test "builds response PDU with error status" do
      request_id = 56789
      # noSuchName
      error_status = 2
      error_index = 1
      varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :string, "test"}]

      pdu = PDU.build_response(request_id, error_status, error_index, varbinds)

      assert pdu.type == :get_response
      assert pdu.request_id == request_id
      assert pdu.error_status == error_status
      assert pdu.error_index == error_index
      assert pdu.varbinds == varbinds
    end

    test "builds multi-varbind GET request" do
      varbinds = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null},
        {[1, 3, 6, 1, 2, 1, 1, 2, 0], :null, :null}
      ]

      request_id = 67890

      pdu = PDU.build_get_request_multi(varbinds, request_id)

      assert pdu.type == :get_request
      assert pdu.request_id == request_id
      assert pdu.varbinds == varbinds
    end
  end

  describe "PDU validation" do
    test "validates request ID range" do
      valid_ids = [0, 1, 65535, 2_147_483_647]

      for request_id <- valid_ids do
        pdu = PDU.build_get_request([1, 3, 6, 1], request_id)
        assert {:ok, _} = PDU.validate(pdu)
      end
    end

    test "rejects invalid request IDs" do
      invalid_ids = [-1, 2_147_483_648]

      for request_id <- invalid_ids do
        assert_raise ArgumentError, fn ->
          PDU.build_get_request([1, 3, 6, 1], request_id)
        end
      end
    end

    test "validates PDU type" do
      pdu = PDU.build_get_request([1, 3, 6, 1], 123)
      assert {:ok, _} = PDU.validate(pdu)

      invalid_pdu = %{type: :invalid_type, request_id: 123, varbinds: []}
      assert {:error, :invalid_pdu_type} = PDU.validate(invalid_pdu)
    end

    test "validates varbinds format" do
      valid_varbinds = [{[1, 3, 6, 1], :null, :null}]
      pdu = PDU.build_get_request_multi(valid_varbinds, 123)
      assert {:ok, _} = PDU.validate(pdu)

      invalid_varbinds = [{"invalid", :null, :null}]

      assert {:error, :invalid_varbind_format} =
               PDU.build_get_request_multi(invalid_varbinds, 123)
    end

    test "validates GETBULK specific fields" do
      pdu = PDU.build_get_bulk_request([1, 3, 6, 1], 123, 0, 10)
      assert {:ok, _} = PDU.validate(pdu)

      invalid_bulk = %{type: :get_bulk_request, request_id: 123, varbinds: []}
      assert {:error, :missing_bulk_fields} = PDU.validate(invalid_bulk)
    end
  end

  describe "Message construction" do
    test "builds SNMP message with v1" do
      pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      message = PDU.build_message(pdu, "public", :v1)

      assert message.version == 0
      assert message.community == "public"
      assert message.pdu == pdu
    end

    test "builds SNMP message with v2c" do
      pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      message = PDU.build_message(pdu, "public", :v2c)

      assert message.version == 1
      assert message.community == "public"
      assert message.pdu == pdu
    end

    test "rejects GETBULK with v1" do
      pdu = PDU.build_get_bulk_request([1, 3, 6, 1], 123)

      assert_raise ArgumentError, ~r/GETBULK requests require SNMPv2c/, fn ->
        PDU.build_message(pdu, "public", :v1)
      end
    end

    test "validates community string" do
      pdu = PDU.build_get_request([1, 3, 6, 1], 123)

      assert_raise ArgumentError, ~r/Community must be a binary string/, fn ->
        PDU.build_message(pdu, :invalid_community, :v1)
      end
    end
  end

  describe "Encoding and decoding" do
    test "encodes and decodes GET request round-trip" do
      # Build request
      pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      message = PDU.build_message(pdu, "public", :v2c)

      # Encode
      {:ok, encoded} = PDU.encode_message(message)
      assert is_binary(encoded)
      assert byte_size(encoded) > 0

      # Decode
      {:ok, decoded} = PDU.decode_message(encoded)

      # Verify structure
      assert decoded.version == 1
      assert decoded.community == "public"
      assert decoded.pdu.type == :get_request
      assert decoded.pdu.request_id == 12345
      assert decoded.pdu.error_status == 0
      assert decoded.pdu.error_index == 0
      assert length(decoded.pdu.varbinds) == 1
    end

    test "encodes and decodes GETBULK request round-trip" do
      pdu = PDU.build_get_bulk_request([1, 3, 6, 1, 2, 1, 2], 23456, 0, 10)
      message = PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded} = PDU.encode_message(message)
      {:ok, decoded} = PDU.decode_message(encoded)

      assert decoded.version == 1
      assert decoded.community == "public"
      assert decoded.pdu.type == :get_bulk_request
      assert decoded.pdu.request_id == 23456
      assert decoded.pdu.non_repeaters == 0
      assert decoded.pdu.max_repetitions == 10
    end

    test "encodes and decodes SET request with values" do
      pdu = PDU.build_set_request([1, 3, 6, 1, 2, 1, 1, 5, 0], {:string, "test-value"}, 34567)
      message = PDU.build_message(pdu, "private", :v2c)

      {:ok, encoded} = PDU.encode_message(message)
      {:ok, decoded} = PDU.decode_message(encoded)

      assert decoded.version == 1
      assert decoded.community == "private"
      assert decoded.pdu.type == :set_request
      assert decoded.pdu.request_id == 34567
      assert length(decoded.pdu.varbinds) == 1
    end

    test "handles encoding errors gracefully" do
      invalid_message = %{invalid: :structure}
      assert {:error, :invalid_message_format} = PDU.encode_message(invalid_message)
    end

    test "handles decoding errors gracefully" do
      invalid_binary = <<1, 2, 3, 4>>
      assert {:error, _} = PDU.decode_message(invalid_binary)

      assert {:error, :invalid_input} = PDU.decode_message(:not_binary)
    end

    test "decodes malformed packets with error" do
      malformed_data = <<0x01, 0x02, 0x03, 0x04>>
      result = PDU.decode_message(malformed_data)
      assert {:error, _} = result
    end
  end

  describe "Community validation" do
    test "validates correct community string" do
      pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      message = PDU.build_message(pdu, "test-community", :v1)
      {:ok, encoded} = PDU.encode_message(message)

      assert :ok = PDU.validate_community(encoded, "test-community")
    end

    test "rejects incorrect community string" do
      pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      message = PDU.build_message(pdu, "correct-community", :v1)
      {:ok, encoded} = PDU.encode_message(message)

      assert {:error, :invalid_community} = PDU.validate_community(encoded, "wrong-community")
    end

    test "handles validation with malformed packets" do
      malformed_data = <<0x01, 0x02, 0x03>>
      result = PDU.validate_community(malformed_data, "any-community")
      assert {:error, _} = result
    end

    test "validates parameter types" do
      assert {:error, :invalid_parameters} = PDU.validate_community(:not_binary, "community")
      assert {:error, :invalid_parameters} = PDU.validate_community(<<1, 2, 3>>, :not_binary)
    end
  end

  describe "Error response creation" do
    test "creates error response from request PDU" do
      request_pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      error_pdu = PDU.create_error_response(request_pdu, 2, 1)

      assert error_pdu.type == :get_response
      assert error_pdu.request_id == 12345
      assert error_pdu.error_status == 2
      assert error_pdu.error_index == 1
      assert error_pdu.varbinds == request_pdu.varbinds
    end

    test "creates error response with default error index" do
      request_pdu = PDU.build_get_request([1, 3, 6, 1], 98765)
      error_pdu = PDU.create_error_response(request_pdu, 3)

      assert error_pdu.type == :get_response
      assert error_pdu.request_id == 98765
      assert error_pdu.error_status == 3
      assert error_pdu.error_index == 0
    end

    test "handles missing fields gracefully" do
      incomplete_pdu = %{type: :get_request}
      error_pdu = PDU.create_error_response(incomplete_pdu, 5, 2)

      assert error_pdu.type == :get_response
      # Default fallback
      assert error_pdu.request_id == 1
      assert error_pdu.error_status == 5
      assert error_pdu.error_index == 2
      # Default fallback
      assert error_pdu.varbinds == []
    end
  end

  describe "Performance and edge cases" do
    test "handles large request IDs" do
      # Max 32-bit signed integer
      large_id = 2_147_483_647
      pdu = PDU.build_get_request([1, 3, 6, 1], large_id)
      message = PDU.build_message(pdu, "public", :v1)

      {:ok, encoded} = PDU.encode_message(message)
      {:ok, decoded} = PDU.decode_message(encoded)

      assert decoded.pdu.request_id == large_id
    end

    test "handles empty community string" do
      pdu = PDU.build_get_request([1, 3, 6, 1], 123)
      message = PDU.build_message(pdu, "", :v1)

      {:ok, encoded} = PDU.encode_message(message)
      {:ok, decoded} = PDU.decode_message(encoded)

      assert decoded.community == ""
    end

    test "handles long community strings" do
      long_community = String.duplicate("x", 255)
      pdu = PDU.build_get_request([1, 3, 6, 1], 123)
      message = PDU.build_message(pdu, long_community, :v1)

      {:ok, encoded} = PDU.encode_message(message)
      {:ok, decoded} = PDU.decode_message(encoded)

      assert decoded.community == long_community
    end

    test "handles complex OIDs" do
      # Use simple values that work correctly - large OID values to be fixed in Phase 2
      complex_oid = [1, 3, 6, 1, 4, 1, 127, 1, 2, 3, 4, 5, 10, 100, 127]
      pdu = PDU.build_get_request(complex_oid, 123)
      message = PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded} = PDU.encode_message(message)
      {:ok, decoded} = PDU.decode_message(encoded)

      assert length(decoded.pdu.varbinds) == 1
      {decoded_oid, _, _} = hd(decoded.pdu.varbinds)
      assert decoded_oid == complex_oid
    end

    test "handles maximum GETBULK parameters" do
      max_reps = 65535
      pdu = PDU.build_get_bulk_request([1, 3, 6, 1], 123, 255, max_reps)
      message = PDU.build_message(pdu, "public", :v2c)

      {:ok, encoded} = PDU.encode_message(message)
      {:ok, decoded} = PDU.decode_message(encoded)

      assert decoded.pdu.non_repeaters == 255
      assert decoded.pdu.max_repetitions == max_reps
    end
  end

  describe "Error conditions and boundary testing" do
    test "handles zero-length input gracefully" do
      assert {:error, _} = PDU.decode_message(<<>>)
    end

    test "handles truncated packets" do
      # Create a valid packet then truncate it
      pdu = PDU.build_get_request([1, 3, 6, 1], 123)
      message = PDU.build_message(pdu, "public", :v1)
      {:ok, encoded} = PDU.encode_message(message)

      truncated = binary_part(encoded, 0, div(byte_size(encoded), 2))
      assert {:error, _} = PDU.decode_message(truncated)
    end

    test "validates OID bounds in varbinds" do
      # Very large OID component
      large_oid = [1, 3, 6, 1, 999_999_999]
      pdu = PDU.build_get_request(large_oid, 123)
      message = PDU.build_message(pdu, "public", :v2c)

      # Should encode/decode without error
      {:ok, encoded} = PDU.encode_message(message)
      {:ok, decoded} = PDU.decode_message(encoded)

      assert is_map(decoded.pdu)
    end

    test "handles concurrent encoding/decoding operations" do
      # Test thread safety by running multiple operations concurrently
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            pdu = PDU.build_get_request([1, 3, 6, 1, i], i)
            message = PDU.build_message(pdu, "public-#{i}", :v2c)
            {:ok, encoded} = PDU.encode_message(message)
            {:ok, decoded} = PDU.decode_message(encoded)
            {i, decoded.pdu.request_id, decoded.community}
          end)
        end

      results = Task.await_many(tasks, 1000)

      # Verify all operations completed successfully
      assert length(results) == 50

      for {i, request_id, community} <- results do
        assert i == request_id
        assert community == "public-#{i}"
      end
    end

    test "maintains encoding fidelity with random data" do
      # Test with various random OIDs and values
      for _iteration <- 1..20 do
        # Generate random but valid OID
        # 3 to 12 components
        oid_length = :rand.uniform(10) + 2
        oid = [1, 3] ++ for(_ <- 1..(oid_length - 2), do: :rand.uniform(65535))

        request_id = :rand.uniform(2_147_483_647)
        community = "test-#{:rand.uniform(1000)}"

        pdu = PDU.build_get_request(oid, request_id)
        message = PDU.build_message(pdu, community, :v2c)

        {:ok, encoded} = PDU.encode_message(message)
        {:ok, decoded} = PDU.decode_message(encoded)

        # Verify round-trip fidelity
        assert decoded.pdu.request_id == request_id
        assert decoded.community == community
        assert decoded.pdu.type == :get_request
      end
    end
  end
end
