defmodule SnmpKit.SnmpLib.DecoderLongLengthTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpLib.PDU.Decoder

  # BER length encoder supporting short form and 1–2 byte long form
  defp len_bytes(n) when n < 128, do: <<n>>
  defp len_bytes(n) when n < 256, do: <<0x81, n>>

  defp len_bytes(n) do
    <<hi, lo>> = <<n::16>>
    <<0x82, hi, lo>>
  end

  defp seq(tag, content) do
    tag_bin = <<tag>>
    tag_bin <> len_bytes(byte_size(content)) <> content
  end

  test "decodes OCTET STRING with long-form length in varbind" do
    # sysDescr.0 OID = 1.3.6.1.2.1.1.1.0 => 2B 06 01 02 01 01 01 00
    oid_bytes = <<0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x01, 0x00>>
    oid_tlv = <<0x06, 0x08>> <> oid_bytes

    # Build a long-form length OCTET STRING value (130 bytes)
    s = String.duplicate("A", 130)
    value_tlv = <<0x04>> <> <<0x81, byte_size(s)>> <> s

    varbind = seq(0x30, oid_tlv <> value_tlv)
    varbind_list = seq(0x30, varbind)

    # Minimal GetResponse PDU (v2c)
    req_id = <<0x02, 0x01, 0x01>>
    err_stat = <<0x02, 0x01, 0x00>>
    err_idx = <<0x02, 0x01, 0x00>>

    pdu_content = req_id <> err_stat <> err_idx <> varbind_list
    pdu = <<0xA2>> <> len_bytes(byte_size(pdu_content)) <> pdu_content

    # Message: version=1 (v2c), community="public"
    version = <<0x02, 0x01, 0x01>>
    community = <<0x04, 0x06, ?p, ?u, ?b, ?l, ?i, ?c>>

    message_content = version <> community <> pdu
    message = <<0x30>> <> len_bytes(byte_size(message_content)) <> message_content

    assert {:ok, %{pdu: %{varbinds: [{oid, :octet_string, value}]}}} =
             Decoder.decode_message(message)

    assert oid == [1, 3, 6, 1, 2, 1, 1, 1, 0]
    assert value == s

    # And the formatter should render it as plain text, not hex
    formatted = SnmpKit.SnmpMgr.Format.format_by_type(:octet_string, value)
    assert formatted == s
  end

  test "decodes Counter64 values with fewer than 8 bytes correctly" do
    # sysUpTime.0 OID = 1.3.6.1.2.1.1.3.0 => 2B 06 01 02 01 01 03 00
    oid_bytes = <<0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x03, 0x00>>
    oid_tlv = <<0x06, 0x08>> <> oid_bytes

    # Test case 1: 4-byte Counter64 value (898308721 = 0x358B1A71)
    counter64_value = 898_308_721
    counter64_bytes = <<0x35, 0x8B, 0x1A, 0x71>>
    # 0x46 = Counter64 tag
    value_tlv = <<0x46, 0x04>> <> counter64_bytes

    varbind = seq(0x30, oid_tlv <> value_tlv)
    varbind_list = seq(0x30, varbind)

    # Minimal GetResponse PDU (v2c)
    req_id = <<0x02, 0x01, 0x01>>
    err_stat = <<0x02, 0x01, 0x00>>
    err_idx = <<0x02, 0x01, 0x00>>

    pdu_content = req_id <> err_stat <> err_idx <> varbind_list
    pdu = <<0xA2>> <> len_bytes(byte_size(pdu_content)) <> pdu_content

    # Message: version=1 (v2c), community="public"
    version = <<0x02, 0x01, 0x01>>
    community = <<0x04, 0x06, ?p, ?u, ?b, ?l, ?i, ?c>>

    message_content = version <> community <> pdu
    message = <<0x30>> <> len_bytes(byte_size(message_content)) <> message_content

    assert {:ok, %{pdu: %{varbinds: [{oid, :counter64, value}]}}} =
             Decoder.decode_message(message)

    assert oid == [1, 3, 6, 1, 2, 1, 1, 3, 0]
    assert value == counter64_value
  end

  test "decodes Counter64 values with various byte lengths" do
    oid_bytes = <<0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x03, 0x00>>
    oid_tlv = <<0x06, 0x08>> <> oid_bytes

    # Test different byte lengths for Counter64
    test_cases = [
      # 1 byte: 1
      {1, <<0x01>>},
      # 1 byte: 255
      {255, <<0xFF>>},
      # 2 bytes: 256
      {256, <<0x01, 0x00>>},
      # 2 bytes: 65535
      {65535, <<0xFF, 0xFF>>},
      # 3 bytes: 65536
      {65536, <<0x01, 0x00, 0x00>>},
      # 3 bytes: 16777215
      {16_777_215, <<0xFF, 0xFF, 0xFF>>},
      # 4 bytes: 16777216
      {16_777_216, <<0x01, 0x00, 0x00, 0x00>>},
      # 4 bytes: 4294967295
      {4_294_967_295, <<0xFF, 0xFF, 0xFF, 0xFF>>},
      # 5 bytes: 4294967296
      {4_294_967_296, <<0x01, 0x00, 0x00, 0x00, 0x00>>},
      # 5 bytes: max 40-bit
      {1_099_511_627_775, <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>},
      # 6 bytes: max 48-bit
      {281_474_976_710_655, <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>},
      # 7 bytes: max 56-bit
      {72_057_594_037_927_935, <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>},
      # 8 bytes: max 64-bit
      {18_446_744_073_709_551_615, <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>}
    ]

    for {expected_value, counter64_bytes} <- test_cases do
      value_tlv = <<0x46, byte_size(counter64_bytes)>> <> counter64_bytes

      varbind = seq(0x30, oid_tlv <> value_tlv)
      varbind_list = seq(0x30, varbind)

      # Minimal GetResponse PDU
      req_id = <<0x02, 0x01, 0x01>>
      err_stat = <<0x02, 0x01, 0x00>>
      err_idx = <<0x02, 0x01, 0x00>>

      pdu_content = req_id <> err_stat <> err_idx <> varbind_list
      pdu = <<0xA2>> <> len_bytes(byte_size(pdu_content)) <> pdu_content

      # Message: version=1 (v2c), community="public"
      version = <<0x02, 0x01, 0x01>>
      community = <<0x04, 0x06, ?p, ?u, ?b, ?l, ?i, ?c>>

      message_content = version <> community <> pdu
      message = <<0x30>> <> len_bytes(byte_size(message_content)) <> message_content

      assert {:ok, %{pdu: %{varbinds: [{_oid, :counter64, value}]}}} =
               Decoder.decode_message(message)

      assert value == expected_value,
             "Failed for #{byte_size(counter64_bytes)}-byte Counter64 value #{expected_value}"
    end
  end

  test "handles Counter64 edge cases" do
    oid_bytes = <<0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x03, 0x00>>
    oid_tlv = <<0x06, 0x08>> <> oid_bytes

    # Test empty Counter64 (should return 0)
    value_tlv = <<0x46, 0x00>>

    varbind = seq(0x30, oid_tlv <> value_tlv)
    varbind_list = seq(0x30, varbind)

    req_id = <<0x02, 0x01, 0x01>>
    err_stat = <<0x02, 0x01, 0x00>>
    err_idx = <<0x02, 0x01, 0x00>>

    pdu_content = req_id <> err_stat <> err_idx <> varbind_list
    pdu = <<0xA2>> <> len_bytes(byte_size(pdu_content)) <> pdu_content

    version = <<0x02, 0x01, 0x01>>
    community = <<0x04, 0x06, ?p, ?u, ?b, ?l, ?i, ?c>>

    message_content = version <> community <> pdu
    message = <<0x30>> <> len_bytes(byte_size(message_content)) <> message_content

    assert {:ok, %{pdu: %{varbinds: [{_oid, :counter64, value}]}}} =
             Decoder.decode_message(message)

    assert value == 0
  end
end
