defmodule SnmpKit.SnmpLib.PropertyTest do
  @moduledoc """
  Round-trip and negative properties for BER, OID, whole-message and SNMPv3
  USM encoding.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SnmpKit.SnmpLib.{ASN1, OID, PDU, Security}
  alias SnmpKit.SnmpLib.PDU.V3Encoder

  @max_sub_id 4_294_967_295
  @max_unsigned32 4_294_967_295
  @max_counter64 18_446_744_073_709_551_615

  ## Generators

  defp oid_list do
    gen all(
          first <- integer(0..2),
          second <- if(first == 2, do: integer(0..@max_sub_id), else: integer(0..39)),
          rest <- list_of(integer(0..@max_sub_id), max_length: 24)
        ) do
      [first, second | rest]
    end
  end

  defp ip_bytes, do: map({byte(), byte(), byte(), byte()}, fn {a, b, c, d} -> <<a, b, c, d>> end)

  # An IpAddress in either form the library accepts; the decoder always
  # returns the 4-byte binary.
  defp ip_either_form, do: one_of([ip_bytes(), {byte(), byte(), byte(), byte()}])

  # The encoder takes an IpAddress varbind value only as a 4-byte binary (a
  # tuple is accepted for the v1 trap agent address alone).
  defp varbind do
    gen all(
          oid <- oid_list(),
          {type, value} <-
            one_of([
              map(integer(-2_147_483_648..2_147_483_647), &{:integer, &1}),
              map(binary(max_length: 300), &{:octet_string, &1}),
              map(integer(0..@max_unsigned32), &{:counter32, &1}),
              map(integer(0..@max_unsigned32), &{:gauge32, &1}),
              map(integer(0..@max_unsigned32), &{:timeticks, &1}),
              map(integer(0..@max_counter64), &{:counter64, &1}),
              map(ip_bytes(), &{:ip_address, &1}),
              map(oid_list(), &{:object_identifier, &1}),
              constant({:null, :null})
            ])
        ) do
      {oid, type, value}
    end
  end

  ## Oracle

  # What the decoder is specified to return for a generated varbind
  # (Decoder.parse_value_with_type/1): OIDs as integer lists, INTEGER and the
  # unsigned application types as integers, OCTET STRING and IpAddress as raw
  # binaries (an IpAddress given as a tuple comes back as its 4 bytes), and
  # NULL as `:null`.
  defp expected_varbinds(varbinds), do: Enum.map(varbinds, &expected_varbind/1)

  defp expected_varbind({oid, :ip_address, ip}), do: {oid, :ip_address, canonical_ip(ip)}
  defp expected_varbind({oid, type, value}), do: {oid, type, value}

  defp canonical_ip({a, b, c, d}), do: <<a, b, c, d>>
  defp canonical_ip(<<_::binary-size(4)>> = bytes), do: bytes

  # Every decoded value must have the documented shape, so a decoder that
  # handed back an IpAddress as a tuple or NULL as nil fails here even when
  # the input happened to match.
  defp assert_decoded_shape({oid, type, value}) do
    assert is_list(oid) and Enum.all?(oid, &is_integer/1)

    case type do
      :integer -> assert is_integer(value)
      t when t in [:counter32, :gauge32, :timeticks] -> assert value in 0..@max_unsigned32
      :counter64 -> assert is_integer(value) and value >= 0 and value <= @max_counter64
      :octet_string -> assert is_binary(value)
      :ip_address -> assert is_binary(value) and byte_size(value) == 4
      :object_identifier -> assert is_list(value)
      :null -> assert value == :null
    end
  end

  defp encode_get_request(varbinds, request_id \\ 1) do
    pdu = PDU.build_get_request_multi(varbinds, request_id)
    {:ok, bin} = PDU.encode_message(PDU.build_message(pdu, "c", :v2c))
    bin
  end

  ## ASN.1 primitives

  property "INTEGER round-trips across the 64-bit range and trailing data is preserved" do
    check all(
            value <-
              one_of([integer(), integer(-9_223_372_036_854_775_808..9_223_372_036_854_775_807)]),
            tail <- binary(max_length: 8)
          ) do
      {:ok, encoded} = ASN1.encode_integer(value)
      assert {:ok, {^value, ^tail}} = ASN1.decode_integer(encoded <> tail)
    end
  end

  property "OCTET STRING round-trips through the 1, 2 and 3 byte length forms" do
    check all(
            bytes <-
              one_of([
                binary(max_length: 127),
                binary(min_length: 128, max_length: 255),
                binary(min_length: 256, max_length: 4_000)
              ]),
            max_runs: 60
          ) do
      {:ok, encoded} = ASN1.encode_octet_string(bytes)
      assert {:ok, {^bytes, ""}} = ASN1.decode_octet_string(encoded)

      assert {:ok, {byte_size(bytes), bytes}} ==
               ASN1.decode_length(encoded |> binary_part(1, byte_size(encoded) - 1))
               |> normalize_length(bytes)
    end
  end

  test "a 70_000-byte OCTET STRING takes the 3-byte length form and round-trips" do
    bytes = :crypto.strong_rand_bytes(70_000)
    {:ok, encoded} = ASN1.encode_octet_string(bytes)
    # 70_000 = 0x011170
    assert <<0x04, 0x83, 0x01, 0x11, 0x70, ^bytes::binary>> = encoded
    assert {:ok, {^bytes, ""}} = ASN1.decode_octet_string(encoded)
  end

  defp normalize_length({:ok, {len, content_and_rest}}, bytes),
    do: {:ok, {len, binary_part(content_and_rest, 0, byte_size(bytes))}}

  defp normalize_length(other, _), do: other

  property "OBJECT IDENTIFIER round-trips, including sub-identifiers above 127 and 2^32-1" do
    check all(oid <- oid_list()) do
      {:ok, encoded} = ASN1.encode_oid(oid)
      assert {:ok, {^oid, ""}} = ASN1.decode_oid(encoded)
    end
  end

  property "OID list and string forms convert both ways" do
    check all(oid <- oid_list()) do
      {:ok, string} = OID.list_to_string(oid)
      assert {:ok, ^oid} = OID.string_to_list(string)
      assert string == Enum.join(oid, ".")
    end
  end

  ## Whole messages

  property "v1 and v2c messages with any varbinds round-trip" do
    check all(
            varbinds <- list_of(varbind(), min_length: 1, max_length: 12),
            community <- binary(max_length: 32),
            version <- member_of([:v1, :v2c]),
            request_id <- integer(0..2_147_483_647),
            max_runs: 150
          ) do
      pdu = PDU.build_get_request_multi(varbinds, request_id)
      message = PDU.build_message(pdu, community, version)
      {:ok, bin} = PDU.encode_message(message)

      assert {:ok, %{community: ^community, pdu: decoded}} = PDU.decode_message(bin)
      assert decoded.request_id == request_id
      assert decoded.varbinds == expected_varbinds(varbinds)
      Enum.each(decoded.varbinds, &assert_decoded_shape/1)
    end
  end

  property "GETBULK, responses, traps and informs keep their fields" do
    check all(
            varbinds <- list_of(varbind(), max_length: 6),
            request_id <- integer(0..2_147_483_647),
            max_rep <- integer(0..200),
            uptime <- integer(0..@max_unsigned32),
            trap_oid <- oid_list(),
            max_runs: 100
          ) do
      bulk = PDU.build_get_bulk_request([1, 3, 6, 1], request_id, 0, max_rep)
      {:ok, bin} = PDU.encode_message(PDU.build_message(bulk, "c", :v2c))

      assert {:ok,
              %{
                pdu: %{
                  type: :get_bulk_request,
                  max_repetitions: ^max_rep,
                  request_id: ^request_id
                }
              }} = PDU.decode_message(bin)

      response = PDU.build_response(request_id, 0, 0, varbinds)
      {:ok, bin} = PDU.encode_message(PDU.build_message(response, "c", :v2c))
      assert {:ok, %{pdu: %{type: :get_response, varbinds: decoded}}} = PDU.decode_message(bin)
      assert decoded == expected_varbinds(varbinds)
      Enum.each(decoded, &assert_decoded_shape/1)

      trap = PDU.build_trap_v2(uptime, trap_oid, varbinds, request_id)
      {:ok, bin} = PDU.encode_message(PDU.build_message(trap, "c", :v2c))

      assert {:ok,
              %{
                pdu: %{
                  type: :snmpv2_trap,
                  varbinds: [{_, :timeticks, ^uptime}, {_, :object_identifier, ^trap_oid} | _]
                }
              }} = PDU.decode_message(bin)

      inform = PDU.build_inform(uptime, trap_oid, varbinds, request_id)
      {:ok, bin} = PDU.encode_message(PDU.build_message(inform, "c", :v2c))

      assert {:ok, %{pdu: %{type: :inform_request, request_id: ^request_id}}} =
               PDU.decode_message(bin)
    end
  end

  property "SNMPv1 traps round-trip every header field, agent address in either form" do
    check all(
            enterprise <- oid_list(),
            agent_addr <- ip_either_form(),
            generic <- integer(0..6),
            specific <- integer(0..2_147_483_647),
            stamp <- integer(0..@max_unsigned32),
            varbinds <- list_of(varbind(), max_length: 4),
            max_runs: 100
          ) do
      trap = PDU.build_trap_v1(enterprise, agent_addr, generic, specific, stamp, varbinds)
      {:ok, bin} = PDU.encode_message(PDU.build_message(trap, "public", :v1))

      assert {:ok, %{version: 0, pdu: decoded}} = PDU.decode_message(bin)
      assert decoded.enterprise == enterprise
      assert decoded.agent_addr == canonical_ip(agent_addr)
      assert decoded.generic_trap == generic
      assert decoded.specific_trap == specific
      assert decoded.time_stamp == stamp
      assert decoded.varbinds == expected_varbinds(varbinds)
      Enum.each(decoded.varbinds, &assert_decoded_shape/1)
    end
  end

  ## Negative properties

  # BER lengths are explicit, so a message is exactly as long as its outer
  # SEQUENCE says: every proper prefix is malformed and must be rejected.
  property "every proper prefix of a message fails to decode" do
    check all(
            varbinds <- list_of(varbind(), min_length: 1, max_length: 5),
            bin = encode_get_request(varbinds),
            cut <- integer(1..(byte_size(bin) - 1)),
            max_runs: 150
          ) do
      truncated = binary_part(bin, 0, byte_size(bin) - cut)
      assert {:error, _} = PDU.decode_message(truncated)
    end
  end

  property "corrupting a varbind tag or length octet never decodes to the original varbinds" do
    check all(
            varbinds <- list_of(varbind(), min_length: 1, max_length: 5),
            bin = encode_get_request(varbinds),
            offset <- member_of(varbind_header_offsets(bin)),
            flip <- integer(1..255),
            max_runs: 150
          ) do
      <<prefix::binary-size(offset), byte, suffix::binary>> = bin
      corrupted = prefix <> <<Bitwise.bxor(byte, flip)>> <> suffix

      case PDU.decode_message(corrupted) do
        {:error, _} -> :ok
        {:ok, %{pdu: %{varbinds: decoded}}} -> assert decoded != expected_varbinds(varbinds)
      end
    end
  end

  property "garbage never crashes the decoder" do
    check all(
            garbage <- binary(max_length: 200),
            varbinds <- list_of(varbind(), min_length: 1, max_length: 3),
            bin = encode_get_request(varbinds),
            start <- integer(0..(byte_size(bin) - 1)),
            splice <- binary(min_length: 1, max_length: 16),
            max_runs: 150
          ) do
      assert {:error, _} = PDU.decode_message(garbage)

      # a valid message with a random slice overwritten must yield a tuple, not raise
      tail_at = min(start + byte_size(splice), byte_size(bin))

      spliced =
        binary_part(bin, 0, start) <>
          splice <> binary_part(bin, tail_at, byte_size(bin) - tail_at)

      assert match?({:ok, _}, PDU.decode_message(spliced)) or
               match?({:error, _}, PDU.decode_message(spliced))
    end
  end

  # Byte offsets of every tag and length octet of the varbind TLVs (each
  # varbind SEQUENCE, its OID and its value) inside an encoded v1/v2c message.
  defp varbind_header_offsets(bin) do
    {:ok, {content, <<>>}} = ASN1.decode_sequence(bin)
    {:ok, {_version, rest}} = ASN1.decode_integer(content)
    {:ok, {_community, pdu}} = ASN1.decode_octet_string(rest)
    {pdu_header, _pdu_len, <<>>} = split_tlv(pdu)
    pdu_body = binary_part(pdu, pdu_header, byte_size(pdu) - pdu_header)
    {:ok, {_request_id, r1}} = ASN1.decode_integer(pdu_body)
    {:ok, {_error_status, r2}} = ASN1.decode_integer(r1)
    {:ok, {_error_index, list_tlv}} = ASN1.decode_integer(r2)
    {:ok, {list_content, <<>>}} = ASN1.decode_sequence(list_tlv)
    walk_varbinds(list_content, byte_size(bin) - byte_size(list_content), [])
  end

  defp walk_varbinds(<<>>, _offset, acc), do: acc

  defp walk_varbinds(data, offset, acc) do
    {vb_header, vb_len, rest} = split_tlv(data)
    vb_content = binary_part(data, vb_header, vb_len)
    {oid_header, oid_len, after_oid} = split_tlv(vb_content)
    {value_header, _value_len, <<>>} = split_tlv(after_oid)
    oid_at = offset + vb_header
    value_at = oid_at + oid_header + oid_len

    offsets =
      Enum.to_list(offset..(offset + vb_header - 1)) ++
        Enum.to_list(oid_at..(oid_at + oid_header - 1)) ++
        Enum.to_list(value_at..(value_at + value_header - 1))

    walk_varbinds(rest, offset + vb_header + vb_len, acc ++ offsets)
  end

  # {header size (tag + length octets), content length, bytes after the TLV}
  defp split_tlv(<<_tag, len_and_rest::binary>> = tlv) do
    {:ok, {len, content_and_rest}} = ASN1.decode_length(len_and_rest)
    header = byte_size(tlv) - byte_size(content_and_rest)
    <<_content::binary-size(len), rest::binary>> = content_and_rest
    {header, len, rest}
  end

  ## SNMPv3 / USM

  property "SNMPv3 USM messages round-trip through every auth and priv pair, and only for the right key" do
    check all(
            auth <- member_of([:md5, :sha1, :sha256]),
            priv <- member_of([:none, :des, :aes128]),
            auth_password <- string(:alphanumeric, min_length: 8, max_length: 24),
            priv_password <- string(:alphanumeric, min_length: 8, max_length: 24),
            engine_id <- binary(min_length: 5, max_length: 32),
            varbinds <- list_of(varbind(), min_length: 1, max_length: 6),
            msg_id <- integer(0..2_147_483_647),
            request_id <- integer(0..2_147_483_647),
            max_runs: 25
          ) do
      config =
        [auth_protocol: auth, auth_password: auth_password, engine_id: engine_id] ++
          if(priv == :none, do: [], else: [priv_protocol: priv, priv_password: priv_password])

      {:ok, user} = Security.create_user("prop_user", config)

      message = %{
        version: 3,
        msg_id: msg_id,
        msg_max_size: 65507,
        msg_flags: %{auth: true, priv: priv != :none, reportable: true},
        msg_security_model: 3,
        msg_security_parameters: <<>>,
        msg_data: %{
          context_engine_id: engine_id,
          context_name: "",
          pdu: %{
            type: :get_request,
            request_id: request_id,
            error_status: 0,
            error_index: 0,
            varbinds: varbinds
          }
        }
      }

      {:ok, bin} = V3Encoder.encode_message(message, user)

      assert {:ok, decoded} = V3Encoder.decode_message(bin, user)
      assert decoded.msg_id == msg_id
      assert decoded.msg_flags.auth == true
      assert decoded.msg_flags.priv == (priv != :none)
      assert decoded.msg_data.pdu.request_id == request_id
      assert decoded.msg_data.pdu.varbinds == expected_varbinds(varbinds)
      Enum.each(decoded.msg_data.pdu.varbinds, &assert_decoded_shape/1)

      # the same message under another password must fail verification
      {:ok, other} =
        Security.create_user(
          "prop_user",
          Keyword.put(config, :auth_password, auth_password <> "x")
        )

      assert {:error, _} = V3Encoder.decode_message(bin, other)
    end
  end
end
