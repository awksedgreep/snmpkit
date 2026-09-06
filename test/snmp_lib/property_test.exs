defmodule SnmpKit.SnmpLib.PropertyTest do
  @moduledoc "Round-trip properties for BER, OID and whole-message encoding."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SnmpKit.SnmpLib.{ASN1, OID, PDU}

  @max_sub_id 4_294_967_295

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

  defp varbind do
    gen all(
          oid <- oid_list(),
          {type, value} <-
            one_of([
              map(integer(-2_147_483_648..2_147_483_647), &{:integer, &1}),
              map(binary(max_length: 300), &{:octet_string, &1}),
              map(integer(0..4_294_967_295), &{:counter32, &1}),
              map(integer(0..4_294_967_295), &{:gauge32, &1}),
              map(integer(0..4_294_967_295), &{:timeticks, &1}),
              map(integer(0..18_446_744_073_709_551_615), &{:counter64, &1}),
              map(ip_bytes(), &{:ip_address, &1}),
              map(oid_list(), &{:object_identifier, &1}),
              constant({:null, :null})
            ])
        ) do
      {oid, type, value}
    end
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
                binary(min_length: 128, max_length: 300),
                binary(min_length: 256, max_length: 70_000)
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
      assert decoded.varbinds == normalize_varbinds(varbinds)
    end
  end

  property "GETBULK, responses, traps and informs keep their fields" do
    check all(
            varbinds <- list_of(varbind(), max_length: 6),
            request_id <- integer(0..2_147_483_647),
            max_rep <- integer(0..200),
            uptime <- integer(0..4_294_967_295),
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
      assert decoded == normalize_varbinds(varbinds)

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

  property "SNMPv1 traps round-trip every header field" do
    check all(
            enterprise <- oid_list(),
            {a, b, c, d} <- {byte(), byte(), byte(), byte()},
            generic <- integer(0..6),
            specific <- integer(0..2_147_483_647),
            stamp <- integer(0..4_294_967_295),
            varbinds <- list_of(varbind(), max_length: 4),
            max_runs: 100
          ) do
      trap = PDU.build_trap_v1(enterprise, {a, b, c, d}, generic, specific, stamp, varbinds)
      {:ok, bin} = PDU.encode_message(PDU.build_message(trap, "public", :v1))

      assert {:ok, %{version: 0, pdu: decoded}} = PDU.decode_message(bin)
      assert decoded.enterprise == enterprise
      assert decoded.agent_addr == <<a, b, c, d>>
      assert decoded.generic_trap == generic
      assert decoded.specific_trap == specific
      assert decoded.time_stamp == stamp
      assert decoded.varbinds == normalize_varbinds(varbinds)
    end
  end

  property "truncating a message never yields a successful decode with fewer varbinds" do
    check all(
            varbinds <- list_of(varbind(), min_length: 1, max_length: 5),
            cut <- integer(1..8),
            max_runs: 100
          ) do
      pdu = PDU.build_get_request_multi(varbinds, 1)
      {:ok, bin} = PDU.encode_message(PDU.build_message(pdu, "c", :v2c))
      truncated = binary_part(bin, 0, max(byte_size(bin) - cut, 0))

      case PDU.decode_message(truncated) do
        {:ok, %{pdu: %{varbinds: decoded}}} -> assert length(decoded) == length(varbinds)
        {:error, _} -> :ok
      end
    end
  end

  # what the decoder is specified to return for each generated varbind
  defp normalize_varbinds(varbinds) do
    Enum.map(varbinds, fn
      {oid, :null, :null} -> {oid, :null, :null}
      {oid, type, value} -> {oid, type, value}
    end)
  end
end
