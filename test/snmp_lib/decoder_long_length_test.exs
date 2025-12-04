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

    assert {:ok, %{pdu: %{varbinds: [{oid, :octet_string, value}]}}} = Decoder.decode_message(message)

    assert oid == [1, 3, 6, 1, 2, 1, 1, 1, 0]
    assert value == s

    # And the formatter should render it as plain text, not hex
    formatted = SnmpKit.SnmpMgr.Format.format_by_type(:octet_string, value)
    assert formatted == s
  end
end
