defmodule SnmpKit.SnmpLib.ASN1Test do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpLib.ASN1

  @moduletag :unit
  @moduletag :protocol
  @moduletag :phase_2

  describe "Integer encoding and decoding" do
    test "encodes and decodes positive integers" do
      {:ok, encoded} = ASN1.encode_integer(42)
      {:ok, {decoded, <<>>}} = ASN1.decode_integer(encoded)
      assert decoded == 42
    end

    test "encodes and decodes zero" do
      {:ok, encoded} = ASN1.encode_integer(0)
      {:ok, {decoded, <<>>}} = ASN1.decode_integer(encoded)
      assert decoded == 0
    end

    test "encodes and decodes negative integers" do
      {:ok, encoded} = ASN1.encode_integer(-1)
      {:ok, {decoded, <<>>}} = ASN1.decode_integer(encoded)
      assert decoded == -1

      {:ok, encoded} = ASN1.encode_integer(-128)
      {:ok, {decoded, <<>>}} = ASN1.decode_integer(encoded)
      assert decoded == -128
    end

    test "encodes and decodes large integers" do
      large_value = 123_456_789
      {:ok, encoded} = ASN1.encode_integer(large_value)
      {:ok, {decoded, <<>>}} = ASN1.decode_integer(encoded)
      assert decoded == large_value
    end

    test "decodes integer with remaining data" do
      {:ok, encoded} = ASN1.encode_integer(42)
      test_data = encoded <> <<99, 100, 101>>
      {:ok, {decoded, remaining}} = ASN1.decode_integer(test_data)
      assert decoded == 42
      assert remaining == <<99, 100, 101>>
    end

    test "rejects invalid integer tags" do
      assert {:error, :invalid_tag} = ASN1.decode_integer(<<0x04, 0x01, 0x42>>)
      assert {:error, :invalid_tag} = ASN1.decode_integer(<<0x05, 0x00>>)
    end
  end

  describe "OCTET STRING encoding and decoding" do
    test "encodes and decodes octet strings" do
      test_string = "Hello, World!"
      {:ok, encoded} = ASN1.encode_octet_string(test_string)
      {:ok, {decoded, <<>>}} = ASN1.decode_octet_string(encoded)
      assert decoded == test_string
    end

    test "encodes and decodes empty octet strings" do
      {:ok, encoded} = ASN1.encode_octet_string("")
      {:ok, {decoded, <<>>}} = ASN1.decode_octet_string(encoded)
      assert decoded == ""
    end

    test "encodes and decodes binary data" do
      binary_data = <<1, 2, 3, 255, 0, 42>>
      {:ok, encoded} = ASN1.encode_octet_string(binary_data)
      {:ok, {decoded, <<>>}} = ASN1.decode_octet_string(encoded)
      assert decoded == binary_data
    end

    test "decodes octet string with remaining data" do
      {:ok, encoded} = ASN1.encode_octet_string("test")
      test_data = encoded <> <<99, 100>>
      {:ok, {decoded, remaining}} = ASN1.decode_octet_string(test_data)
      assert decoded == "test"
      assert remaining == <<99, 100>>
    end

    test "rejects invalid octet string tags" do
      assert {:error, :invalid_tag} = ASN1.decode_octet_string(<<0x02, 0x01, 0x42>>)
    end
  end

  describe "NULL encoding and decoding" do
    test "encodes and decodes null values" do
      {:ok, encoded} = ASN1.encode_null()
      assert encoded == <<0x05, 0x00>>
      {:ok, {decoded, <<>>}} = ASN1.decode_null(encoded)
      assert decoded == :null
    end

    test "decodes null with remaining data" do
      test_data = <<0x05, 0x00, 42, 43>>
      {:ok, {decoded, remaining}} = ASN1.decode_null(test_data)
      assert decoded == :null
      assert remaining == <<42, 43>>
    end

    test "rejects null with invalid length" do
      assert {:error, :invalid_null_length} = ASN1.decode_null(<<0x05, 0x01, 0x00>>)
    end

    test "rejects invalid null tags" do
      assert {:error, :invalid_tag} = ASN1.decode_null(<<0x02, 0x00>>)
    end
  end

  describe "OBJECT IDENTIFIER encoding and decoding" do
    test "encodes and decodes simple OIDs" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      {:ok, encoded} = ASN1.encode_oid(oid)
      {:ok, {decoded, <<>>}} = ASN1.decode_oid(encoded)
      assert decoded == oid
    end

    test "encodes and decodes short OIDs" do
      oid = [1, 3]
      {:ok, encoded} = ASN1.encode_oid(oid)
      {:ok, {decoded, <<>>}} = ASN1.decode_oid(encoded)
      assert decoded == oid
    end

    test "encodes and decodes OIDs with large components" do
      oid = [1, 3, 6, 1, 4, 1, 200, 1]
      {:ok, encoded} = ASN1.encode_oid(oid)
      {:ok, {decoded, <<>>}} = ASN1.decode_oid(encoded)
      assert decoded == oid
    end

    test "decodes OID with remaining data" do
      oid = [1, 3, 6, 1]
      {:ok, encoded} = ASN1.encode_oid(oid)
      test_data = encoded <> <<99, 100>>
      {:ok, {decoded, remaining}} = ASN1.decode_oid(test_data)
      assert decoded == oid
      assert remaining == <<99, 100>>
    end

    test "rejects invalid OIDs" do
      assert {:error, :invalid_oid} = ASN1.encode_oid([])
      assert {:error, :invalid_oid} = ASN1.encode_oid([1])
      assert {:error, :invalid_oid} = ASN1.encode_oid(:not_a_list)
    end

    test "rejects invalid OID tags" do
      assert {:error, :invalid_tag} = ASN1.decode_oid(<<0x02, 0x01, 0x42>>)
    end
  end

  describe "SEQUENCE encoding and decoding" do
    test "encodes and decodes sequences" do
      # Create sequence content: INTEGER 42 + OCTET STRING "test"
      {:ok, int_encoded} = ASN1.encode_integer(42)
      {:ok, str_encoded} = ASN1.encode_octet_string("test")
      content = int_encoded <> str_encoded

      {:ok, sequence_encoded} = ASN1.encode_sequence(content)
      {:ok, {decoded_content, <<>>}} = ASN1.decode_sequence(sequence_encoded)
      assert decoded_content == content
    end

    test "encodes and decodes empty sequences" do
      {:ok, encoded} = ASN1.encode_sequence(<<>>)
      {:ok, {decoded, <<>>}} = ASN1.decode_sequence(encoded)
      assert decoded == <<>>
    end

    test "decodes sequence with remaining data" do
      {:ok, encoded} = ASN1.encode_sequence(<<1, 2, 3>>)
      test_data = encoded <> <<99, 100>>
      {:ok, {decoded, remaining}} = ASN1.decode_sequence(test_data)
      assert decoded == <<1, 2, 3>>
      assert remaining == <<99, 100>>
    end

    test "rejects invalid sequence tags" do
      assert {:error, :invalid_tag} = ASN1.decode_sequence(<<0x02, 0x01, 0x42>>)
    end
  end

  describe "Custom TLV encoding" do
    test "encodes custom TLV structures" do
      custom_tag = 0xA0
      content = "custom_content"
      {:ok, encoded} = ASN1.encode_custom_tlv(custom_tag, content)

      # Should start with our custom tag
      assert <<^custom_tag, _rest::binary>> = encoded
    end

    test "encodes TLV with different tags" do
      {:ok, encoded1} = ASN1.encode_custom_tlv(0x80, "content1")
      {:ok, encoded2} = ASN1.encode_custom_tlv(0x81, "content2")

      assert <<0x80, _::binary>> = encoded1
      assert <<0x81, _::binary>> = encoded2
    end
  end

  describe "Generic TLV decoding" do
    test "decodes any TLV structure" do
      {:ok, encoded} = ASN1.encode_integer(42)
      {:ok, {tag, content, <<>>}} = ASN1.decode_tlv(encoded)

      # INTEGER tag
      assert tag == 0x02
      assert content == <<42>>
    end

    test "decodes TLV with remaining data" do
      {:ok, encoded} = ASN1.encode_octet_string("test")
      test_data = encoded <> <<99, 100>>
      {:ok, {tag, content, remaining}} = ASN1.decode_tlv(test_data)

      # OCTET STRING tag
      assert tag == 0x04
      assert content == "test"
      assert remaining == <<99, 100>>
    end

    test "rejects insufficient data" do
      assert {:error, :insufficient_data} = ASN1.decode_tlv(<<>>)
    end
  end

  describe "Length encoding and decoding" do
    test "encodes and decodes short form lengths" do
      for length <- [0, 1, 42, 127] do
        encoded = ASN1.encode_length(length)
        {:ok, {decoded, <<>>}} = ASN1.decode_length(encoded)
        assert decoded == length
      end
    end

    test "encodes and decodes long form lengths" do
      test_cases = [128, 200, 300, 1000, 65535, 100_000]

      for length <- test_cases do
        encoded = ASN1.encode_length(length)
        {:ok, {decoded, <<>>}} = ASN1.decode_length(encoded)
        assert decoded == length
      end
    end

    test "decodes length with remaining data" do
      encoded = ASN1.encode_length(42)
      test_data = encoded <> <<99, 100>>
      {:ok, {decoded, remaining}} = ASN1.decode_length(test_data)
      assert decoded == 42
      assert remaining == <<99, 100>>
    end

    test "rejects indefinite length" do
      assert {:error, :indefinite_length_not_supported} = ASN1.decode_length(<<0x80>>)
    end

    test "rejects overly long length encoding" do
      # 5 octets for length is too much
      assert {:error, :length_too_large} = ASN1.decode_length(<<0x85, 1, 2, 3, 4, 5>>)
    end

    test "rejects insufficient length bytes" do
      assert {:error, :insufficient_length_bytes} = ASN1.decode_length(<<0x82, 0x01>>)
    end
  end

  describe "Tag parsing" do
    test "parses universal class tags" do
      # INTEGER
      info = ASN1.parse_tag(0x02)
      assert info.class == :universal
      assert info.constructed == false
      assert info.tag_number == 2
      assert info.original_byte == 0x02
    end

    test "parses constructed tags" do
      # SEQUENCE
      info = ASN1.parse_tag(0x30)
      assert info.class == :universal
      assert info.constructed == true
      assert info.tag_number == 16
    end

    test "parses application class tags" do
      # Application, primitive, tag 1
      info = ASN1.parse_tag(0x41)
      assert info.class == :application
      assert info.constructed == false
      assert info.tag_number == 1
    end

    test "parses context class tags" do
      # Context, primitive, tag 0
      info = ASN1.parse_tag(0x80)
      assert info.class == :context
      assert info.constructed == false
      assert info.tag_number == 0
    end

    test "parses private class tags" do
      # Private, primitive, tag 0
      info = ASN1.parse_tag(0xC0)
      assert info.class == :private
      assert info.constructed == false
      assert info.tag_number == 0
    end
  end

  describe "BER structure validation" do
    test "validates simple valid structures" do
      {:ok, encoded} = ASN1.encode_integer(42)
      assert :ok = ASN1.validate_ber_structure(encoded)
    end

    test "validates sequences of structures" do
      {:ok, int_encoded} = ASN1.encode_integer(42)
      {:ok, str_encoded} = ASN1.encode_octet_string("test")
      combined = int_encoded <> str_encoded

      assert :ok = ASN1.validate_ber_structure(combined)
    end

    test "validates nested sequences" do
      # Sequence with INTEGER 42
      {:ok, inner_seq} = ASN1.encode_sequence(<<0x02, 0x01, 0x42>>)
      {:ok, outer_seq} = ASN1.encode_sequence(inner_seq)

      assert :ok = ASN1.validate_ber_structure(outer_seq)
    end

    test "rejects malformed structures" do
      # Invalid length - claims 10 bytes but only has 2
      malformed = <<0x02, 0x0A, 0x42, 0x43>>
      assert {:error, :insufficient_content} = ASN1.validate_ber_structure(malformed)
    end

    test "validates empty data" do
      assert :ok = ASN1.validate_ber_structure(<<>>)
    end
  end

  describe "BER length calculation" do
    test "calculates length for simple structures" do
      {:ok, encoded} = ASN1.encode_integer(42)
      {:ok, total_length} = ASN1.calculate_ber_length(encoded)
      assert total_length == byte_size(encoded)
    end

    test "calculates length for different structure sizes" do
      test_cases = [
        42,
        123_456,
        "Hello, World!",
        String.duplicate("A", 200)
      ]

      for test_value <- test_cases do
        {:ok, encoded} =
          case test_value do
            value when is_integer(value) -> ASN1.encode_integer(value)
            value when is_binary(value) -> ASN1.encode_octet_string(value)
          end

        {:ok, calculated_length} = ASN1.calculate_ber_length(encoded)
        actual_length = byte_size(encoded)
        assert calculated_length == actual_length
      end
    end

    test "rejects insufficient data for length calculation" do
      assert {:error, :insufficient_data} = ASN1.calculate_ber_length(<<>>)
      assert {:error, :insufficient_data} = ASN1.calculate_ber_length(<<0x02>>)
    end
  end

  describe "Round-trip encoding/decoding" do
    test "integer round-trips correctly" do
      test_values = [0, 1, -1, 42, -42, 127, -128, 255, -256, 32767, -32768]

      for value <- test_values do
        {:ok, encoded} = ASN1.encode_integer(value)
        {:ok, {decoded, <<>>}} = ASN1.decode_integer(encoded)
        assert decoded == value, "Failed round-trip for integer #{value}"
      end
    end

    test "octet string round-trips correctly" do
      test_values = [
        "",
        "Hello",
        "Hello, World!",
        <<0, 1, 2, 255>>,
        String.duplicate("A", 100)
      ]

      for value <- test_values do
        {:ok, encoded} = ASN1.encode_octet_string(value)
        {:ok, {decoded, <<>>}} = ASN1.decode_octet_string(encoded)
        assert decoded == value
      end
    end

    test "OID round-trips correctly" do
      test_oids = [
        [1, 3],
        [1, 3, 6, 1, 2, 1],
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 4, 1, 200, 1, 2, 3]
      ]

      for oid <- test_oids do
        {:ok, encoded} = ASN1.encode_oid(oid)
        {:ok, {decoded, <<>>}} = ASN1.decode_oid(encoded)
        assert decoded == oid
      end
    end
  end

  describe "Error handling and edge cases" do
    test "handles encoding failures gracefully" do
      # These should not crash, but return errors
      assert {:error, :invalid_oid} = ASN1.encode_oid([])
      assert {:error, :invalid_oid} = ASN1.encode_oid(:not_a_list)
    end

    test "handles decoding failures gracefully" do
      # Truncated data
      assert {:error, :insufficient_data} = ASN1.decode_integer(<<0x02>>)
      assert {:error, :insufficient_content} = ASN1.decode_integer(<<0x02, 0x05, 0x42>>)
    end

    test "handles empty input data" do
      assert {:error, :invalid_tag} = ASN1.decode_integer(<<>>)
      assert {:error, :invalid_tag} = ASN1.decode_octet_string(<<>>)
      assert {:error, :invalid_tag} = ASN1.decode_oid(<<>>)
      assert {:error, :invalid_tag} = ASN1.decode_sequence(<<>>)
    end

    test "handles concurrent operations" do
      # Test thread safety
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            value = rem(i, 1000)
            {:ok, encoded} = ASN1.encode_integer(value)
            {:ok, {decoded, <<>>}} = ASN1.decode_integer(encoded)
            {i, value, decoded}
          end)
        end

      results = Task.await_many(tasks, 1000)

      # Verify all operations completed successfully
      assert length(results) == 20

      for {i, original, decoded} <- results do
        expected = rem(i, 1000)
        assert original == expected
        assert decoded == expected
      end
    end
  end

  describe "Performance and large data handling" do
    test "handles large integers efficiently" do
      large_values = [
        123_456_789,
        -123_456_789,
        2_147_483_647,
        -2_147_483_648
      ]

      for value <- large_values do
        start_time = System.monotonic_time(:microsecond)
        {:ok, encoded} = ASN1.encode_integer(value)
        {:ok, {decoded, <<>>}} = ASN1.decode_integer(encoded)
        end_time = System.monotonic_time(:microsecond)

        assert decoded == value
        # Should complete in reasonable time (< 1ms)
        assert end_time - start_time < 1000
      end
    end

    test "handles large octet strings efficiently" do
      large_string = String.duplicate("Hello, World! ", 100)

      start_time = System.monotonic_time(:microsecond)
      {:ok, encoded} = ASN1.encode_octet_string(large_string)
      {:ok, {decoded, <<>>}} = ASN1.decode_octet_string(encoded)
      end_time = System.monotonic_time(:microsecond)

      assert decoded == large_string
      # Should complete in reasonable time (< 5ms)
      assert end_time - start_time < 5000
    end

    test "handles complex nested structures" do
      # Create a sequence containing multiple nested sequences
      # INTEGER 42
      {:ok, inner1} = ASN1.encode_sequence(<<0x02, 0x01, 0x42>>)
      # OCTET STRING "test"
      {:ok, inner2} = ASN1.encode_sequence(<<0x04, 0x04, "test"::binary>>)
      {:ok, outer} = ASN1.encode_sequence(inner1 <> inner2)

      # Should be able to decode the outer structure
      {:ok, {content, <<>>}} = ASN1.decode_sequence(outer)
      assert content == inner1 <> inner2

      # Should validate correctly
      assert :ok = ASN1.validate_ber_structure(outer)
    end
  end
end
