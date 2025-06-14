defmodule SnmpKit.SnmpLib.PDU.Encoder do
  @moduledoc """
  ASN.1 BER encoding functions for SNMP PDUs and messages.

  This module handles the conversion of Elixir data structures to binary ASN.1 BER format
  for SNMP protocol communication.
  """

  import Bitwise
  alias SnmpKit.SnmpLib.PDU.Constants

  @type message :: Constants.message()
  @type pdu :: Constants.pdu()

  # Import constants for encoding
  @get_request Constants.get_request()
  @getnext_request Constants.getnext_request()
  @get_response Constants.get_response()
  @set_request Constants.set_request()
  @getbulk_request Constants.getbulk_request()

  @integer Constants.integer()
  @octet_string Constants.octet_string()
  @null Constants.null()
  @object_identifier Constants.object_identifier()
  @counter32 Constants.counter32()
  @gauge32 Constants.gauge32()
  @timeticks Constants.timeticks()
  @counter64 Constants.counter64()
  @ip_address Constants.ip_address()
  @opaque_type Constants.opaque_type()
  @no_such_object Constants.no_such_object()
  @no_such_instance Constants.no_such_instance()
  @end_of_mib_view Constants.end_of_mib_view()

  @doc """
  Encodes an SNMP message to binary format.
  """
  @spec encode_message(message()) :: {:ok, binary()} | {:error, atom()}
  def encode_message(%{version: version, community: community, pdu: pdu}) do
    try do
      encode_snmp_message_fast(version, community, pdu)
    rescue
      error -> {:error, {:encoding_error, error}}
    catch
      error -> {:error, {:encoding_error, error}}
    end
  end

  def encode_message(_), do: {:error, :invalid_message_format}

  @doc """
  Encodes an SNMP message to binary format (alias for encode_message/1).
  """
  @spec encode(message()) :: {:ok, binary()} | {:error, atom()}
  def encode(message) when is_map(message) do
    encode_message(message)
  end

  @doc """
  Alias for encode/1.
  """
  @spec encode_snmp_packet(message()) :: {:ok, binary()} | {:error, atom()}
  def encode_snmp_packet(message), do: encode(message)

  ## Private Implementation

  defp encode_snmp_message_fast(version, community, pdu)
       when is_integer(version) and is_binary(community) and is_map(pdu) do
    case encode_pdu_fast(pdu) do
      {:ok, pdu_encoded} ->
        iodata = [
          encode_integer_fast(version),
          encode_octet_string_fast(community),
          pdu_encoded
        ]

        content = :erlang.iolist_to_binary(iodata)
        {:ok, encode_sequence_ber(content)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_snmp_message_fast(_, _, _), do: {:error, :invalid_message_format}

  defp encode_pdu_fast(%{type: :get_request} = pdu),
    do: encode_standard_pdu_fast(pdu, @get_request)

  defp encode_pdu_fast(%{type: :get_next_request} = pdu),
    do: encode_standard_pdu_fast(pdu, @getnext_request)

  defp encode_pdu_fast(%{type: :get_response} = pdu),
    do: encode_standard_pdu_fast(pdu, @get_response)

  defp encode_pdu_fast(%{type: :set_request} = pdu),
    do: encode_standard_pdu_fast(pdu, @set_request)

  defp encode_pdu_fast(%{type: :get_bulk_request} = pdu), do: encode_bulk_pdu_fast(pdu)
  defp encode_pdu_fast(_), do: {:error, :unsupported_pdu_type}

  defp encode_standard_pdu_fast(pdu, tag) do
    %{
      request_id: request_id,
      error_status: error_status,
      error_index: error_index,
      varbinds: varbinds
    } = pdu

    case encode_varbinds_fast(varbinds) do
      {:ok, varbinds_encoded} ->
        iodata = [
          encode_integer_fast(request_id),
          encode_integer_fast(error_status),
          encode_integer_fast(error_index),
          varbinds_encoded
        ]

        content = :erlang.iolist_to_binary(iodata)
        {:ok, encode_tag_length_value(tag, byte_size(content), content)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_bulk_pdu_fast(pdu) do
    %{
      request_id: request_id,
      non_repeaters: non_repeaters,
      max_repetitions: max_repetitions,
      varbinds: varbinds
    } = pdu

    case encode_varbinds_fast(varbinds) do
      {:ok, varbinds_encoded} ->
        iodata = [
          encode_integer_fast(request_id),
          encode_integer_fast(non_repeaters),
          encode_integer_fast(max_repetitions),
          varbinds_encoded
        ]

        content = :erlang.iolist_to_binary(iodata)
        {:ok, encode_tag_length_value(@getbulk_request, byte_size(content), content)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_varbinds_fast(varbinds) when is_list(varbinds) do
    case encode_varbinds_acc(varbinds, []) do
      {:ok, iodata} ->
        content = :erlang.iolist_to_binary(iodata)
        {:ok, encode_sequence_ber(content)}

      error ->
        error
    end
  end

  defp encode_varbinds_acc([], acc), do: {:ok, Enum.reverse(acc)}

  defp encode_varbinds_acc([varbind | rest], acc) do
    case encode_varbind_fast(varbind) do
      {:ok, encoded} -> encode_varbinds_acc(rest, [encoded | acc])
      error -> error
    end
  end

  defp encode_varbind_fast({oid, type, value}) when is_list(oid) do
    case encode_oid_fast(oid) do
      {:ok, oid_encoded} ->
        value_encoded = encode_snmp_value_fast(type, value)
        content = :erlang.iolist_to_binary([oid_encoded, value_encoded])
        {:ok, encode_sequence_ber(content)}

      error ->
        error
    end
  end

  defp encode_varbind_fast({oid, value}) when is_list(oid) do
    encode_varbind_fast({oid, :auto, value})
  end

  defp encode_varbind_fast(_), do: {:error, :invalid_varbind_format}

  # Fast integer encoder
  defp encode_integer_fast(0), do: <<@integer, 0x01, 0x00>>

  defp encode_integer_fast(value) when value > 0 and value < 128 do
    <<@integer, 0x01, value>>
  end

  defp encode_integer_fast(value) when is_integer(value) do
    encode_integer_ber(value)
  end

  defp encode_octet_string_fast(value) when is_binary(value) do
    length = byte_size(value)
    length_bytes = encode_length_ber(length)
    [<<@octet_string>>, length_bytes, value]
  end

  defp encode_snmp_value_fast(:null, _), do: <<@null, 0x00>>
  defp encode_snmp_value_fast(:auto, nil), do: <<@null, 0x00>>
  defp encode_snmp_value_fast(:auto, :null), do: <<@null, 0x00>>

  defp encode_snmp_value_fast(:integer, value) when is_integer(value),
    do: encode_integer_fast(value)

  defp encode_snmp_value_fast(:string, value) when is_binary(value),
    do: encode_octet_string_fast(value)

  defp encode_snmp_value_fast(:octet_string, value) when is_binary(value),
    do: encode_octet_string_fast(value)

  defp encode_snmp_value_fast(:counter32, value)
       when is_integer(value) and value >= 0 and value <= 4_294_967_295 do
    encode_unsigned_integer(@counter32, value)
  end

  defp encode_snmp_value_fast(:gauge32, value)
       when is_integer(value) and value >= 0 and value <= 4_294_967_295 do
    encode_unsigned_integer(@gauge32, value)
  end

  defp encode_snmp_value_fast(:timeticks, value)
       when is_integer(value) and value >= 0 and value <= 4_294_967_295 do
    encode_unsigned_integer(@timeticks, value)
  end

  defp encode_snmp_value_fast(:counter64, value)
       when is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615 do
    encode_counter64(@counter64, value)
  end

  defp encode_snmp_value_fast(:ip_address, value)
       when is_binary(value) and byte_size(value) == 4 do
    encode_tag_length_value(@ip_address, 4, value)
  end

  defp encode_snmp_value_fast(:opaque, value) when is_binary(value) do
    length = byte_size(value)
    encode_tag_length_value(@opaque_type, length, value)
  end

  defp encode_snmp_value_fast(:object_identifier, value) when is_list(value) do
    case encode_oid_fast(value) do
      {:ok, encoded} -> encoded
      {:error, _} -> raise ArgumentError, "Invalid OID list: #{inspect(value)}"
    end
  end

  defp encode_snmp_value_fast(:object_identifier, value) when is_binary(value) do
    case SnmpKit.SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} ->
        case encode_oid_fast(oid_list) do
          {:ok, encoded} -> encoded
          {:error, _} -> raise ArgumentError, "Invalid OID string: #{inspect(value)}"
        end

      {:error, _} ->
        raise ArgumentError, "Invalid OID string format: #{inspect(value)}"
    end
  end

  defp encode_snmp_value_fast(:auto, {:object_identifier, value}) when is_list(value) do
    case encode_oid_fast(value) do
      {:ok, encoded} -> encoded
      {:error, _} -> <<@null, 0x00>>
    end
  end

  defp encode_snmp_value_fast(:auto, {:object_identifier, value}) when is_binary(value) do
    case SnmpKit.SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} ->
        case encode_oid_fast(oid_list) do
          {:ok, encoded} -> encoded
          {:error, _} -> <<@null, 0x00>>
        end

      {:error, _} ->
        <<@null, 0x00>>
    end
  end

  defp encode_snmp_value_fast(:auto, {:no_such_object, _}), do: <<@no_such_object, 0x00>>
  defp encode_snmp_value_fast(:auto, {:no_such_instance, _}), do: <<@no_such_instance, 0x00>>
  defp encode_snmp_value_fast(:auto, {:end_of_mib_view, _}), do: <<@end_of_mib_view, 0x00>>

  defp encode_snmp_value_fast(:auto, {:opaque, value}) when is_binary(value) do
    length = byte_size(value)
    encode_tag_length_value(@opaque_type, length, value)
  end

  defp encode_snmp_value_fast(:auto, {:opaque, _value}), do: <<@null, 0x00>>

  defp encode_snmp_value_fast(:auto, {:counter32, value})
       when is_integer(value) and value >= 0 and value <= 4_294_967_295 do
    encode_unsigned_integer(@counter32, value)
  end

  defp encode_snmp_value_fast(:auto, {:counter32, _value}) do
    <<@null, 0x00>>
  end

  defp encode_snmp_value_fast(:auto, {:gauge32, value})
       when is_integer(value) and value >= 0 and value <= 4_294_967_295 do
    encode_unsigned_integer(@gauge32, value)
  end

  defp encode_snmp_value_fast(:auto, {:gauge32, _value}) do
    <<@null, 0x00>>
  end

  defp encode_snmp_value_fast(:auto, {:timeticks, value})
       when is_integer(value) and value >= 0 and value <= 4_294_967_295 do
    encode_unsigned_integer(@timeticks, value)
  end

  defp encode_snmp_value_fast(:auto, {:timeticks, _value}) do
    <<@null, 0x00>>
  end

  defp encode_snmp_value_fast(:auto, {:counter64, value})
       when is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615 do
    encode_counter64(@counter64, value)
  end

  defp encode_snmp_value_fast(:auto, {:counter64, _value}) do
    <<@null, 0x00>>
  end

  defp encode_snmp_value_fast(:auto, {:ip_address, value})
       when is_binary(value) and byte_size(value) == 4 do
    encode_tag_length_value(@ip_address, 4, value)
  end

  defp encode_snmp_value_fast(:auto, {:ip_address, _value}) do
    <<@null, 0x00>>
  end

  defp encode_snmp_value_fast(:auto, {_type, _value}) do
    <<@null, 0x00>>
  end

  defp encode_snmp_value_fast(:auto, value) when is_integer(value), do: encode_integer_fast(value)

  defp encode_snmp_value_fast(:auto, value) when is_binary(value) do
    # Try to parse as OID string first, fallback to octet string
    case SnmpKit.SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} ->
        case encode_oid_fast(oid_list) do
          {:ok, encoded} -> encoded
          {:error, _} -> encode_octet_string_fast(value)
        end

      {:error, _} ->
        encode_octet_string_fast(value)
    end
  end

  defp encode_snmp_value_fast(:auto, value) when is_list(value) do
    # Assume it's an OID if it's a list of non-negative integers
    if Enum.all?(value, &(is_integer(&1) and &1 >= 0)) do
      case encode_oid_fast(value) do
        {:ok, encoded} -> encoded
        {:error, _} -> raise ArgumentError, "Invalid OID list: #{inspect(value)}"
      end
    else
      raise ArgumentError, "Invalid value for :auto type: #{inspect(value)}"
    end
  end

  defp encode_snmp_value_fast(:end_of_mib_view, nil), do: <<@end_of_mib_view, 0x00>>
  defp encode_snmp_value_fast(:no_such_object, _), do: <<@no_such_object, 0x00>>
  defp encode_snmp_value_fast(:no_such_instance, _), do: <<@no_such_instance, 0x00>>

  defp encode_snmp_value_fast(type, value) do
    raise ArgumentError, """
    Invalid SNMP value encoding. Unsupported type/value combination:
    Type: #{inspect(type)}
    Value: #{inspect(value)}

    Supported types: :integer, :octet_string, :null, :object_identifier, :counter32, :gauge32, :timeticks, :counter64, :ip_address, :opaque, :no_such_object, :no_such_instance, :end_of_mib_view
    """
  end

  # ASN.1 BER encoding helpers
  defp encode_integer_ber(value) when is_integer(value) do
    bytes = integer_to_bytes(value)
    length = byte_size(bytes)
    encode_tag_length_value(@integer, length, bytes)
  end

  defp integer_to_bytes(0), do: <<0>>

  defp integer_to_bytes(value) when value > 0 do
    bytes = :binary.encode_unsigned(value, :big)

    case bytes do
      <<bit::1, _::bitstring>> when bit == 1 ->
        <<0>> <> bytes

      _ ->
        bytes
    end
  end

  defp integer_to_bytes(value) when value < 0 do
    positive = abs(value)
    bit_length = bit_length_for_integer(positive) + 1
    byte_length = div(bit_length + 7, 8)
    max_value = 1 <<< (byte_length * 8)
    twos_comp = max_value + value
    <<twos_comp::size(byte_length)-unit(8)-big>>
  end

  @spec bit_length_for_integer(pos_integer()) :: pos_integer()
  defp bit_length_for_integer(n) when n > 0 do
    :math.log2(n) |> :math.ceil() |> trunc()
  end

  defp encode_sequence_ber(content) when is_binary(content) do
    length = byte_size(content)
    encode_tag_length_value(0x30, length, content)
  end

  defp encode_tag_length_value(tag, length, content) do
    length_bytes = encode_length_ber(length)
    <<tag>> <> length_bytes <> content
  end

  defp encode_length_ber(length) when length < 128 do
    <<length>>
  end

  defp encode_length_ber(length) when length < 256 do
    <<0x81, length>>
  end

  defp encode_length_ber(length) when length < 65536 do
    <<0x82, length::16>>
  end

  defp encode_length_ber(length) when length < 16_777_216 do
    <<0x83, length::24>>
  end

  defp encode_length_ber(length) do
    <<0x84, length::32>>
  end

  # Helper functions for encoding unsigned integers and counter64
  defp encode_unsigned_integer(tag, value) when is_integer(value) and value >= 0 do
    bytes = encode_unsigned_bytes(value)
    length = byte_size(bytes)
    encode_tag_length_value(tag, length, bytes)
  end

  defp encode_counter64(tag, value) when is_integer(value) and value >= 0 do
    bytes = <<value::64>>
    length = byte_size(bytes)
    encode_tag_length_value(tag, length, bytes)
  end

  defp encode_unsigned_bytes(0), do: <<0>>

  defp encode_unsigned_bytes(value) when value > 0 do
    bytes = :binary.encode_unsigned(value, :big)
    # Ensure the most significant bit is 0 for unsigned integers
    case bytes do
      <<bit::1, _::bitstring>> when bit == 1 ->
        <<0>> <> bytes

      _ ->
        bytes
    end
  end

  defp encode_oid_fast(oid_list) when is_list(oid_list) and length(oid_list) >= 2 do
    [first, second | rest] = oid_list

    if first >= 0 and first < 3 and second >= 0 and second < 40 do
      first_encoded = first * 40 + second

      case encode_oid_subids_fast([first_encoded | rest], []) do
        {:ok, content} ->
          {:ok, encode_tag_length_value(@object_identifier, byte_size(content), content)}

        error ->
          error
      end
    else
      {:error, :invalid_oid_format}
    end
  end

  defp encode_oid_fast(_), do: {:error, :invalid_oid_format}

  defp encode_oid_subids_fast([], acc), do: {:ok, :erlang.iolist_to_binary(Enum.reverse(acc))}

  defp encode_oid_subids_fast([subid | rest], acc) when subid >= 0 and subid < 128 do
    encode_oid_subids_fast(rest, [<<subid>> | acc])
  end

  defp encode_oid_subids_fast([subid | rest], acc) when subid >= 128 do
    bytes = encode_subid_multibyte(subid, [])
    encode_oid_subids_fast(rest, [bytes | acc])
  end

  defp encode_oid_subids_fast(_, _), do: {:error, :invalid_subidentifier}

  # Encode a subidentifier using ASN.1 BER multibyte encoding
  defp encode_subid_multibyte(subid, _acc) do
    encode_subid_multibyte_correct(subid)
  end

  # Correct implementation: build bytes from most significant to least significant
  defp encode_subid_multibyte_correct(subid) when subid < 128 do
    <<subid>>
  end

  defp encode_subid_multibyte_correct(subid) do
    # Build list of 7-bit groups from least to most significant
    bytes = build_multibyte_list(subid, [])
    # Convert to binary with high bits set correctly
    bytes_with_high_bits = set_high_bits(bytes)
    :erlang.iolist_to_binary(bytes_with_high_bits)
  end

  # Build list of 7-bit values from least to most significant
  defp build_multibyte_list(subid, acc) when subid < 128 do
    # Most significant byte (no more bits)
    [subid | acc]
  end

  defp build_multibyte_list(subid, acc) do
    lower_7_bits = subid &&& 0x7F
    build_multibyte_list(subid >>> 7, [lower_7_bits | acc])
  end

  # Set high bits: all bytes except the last one get the high bit set
  # Last byte has no high bit
  defp set_high_bits([last]), do: [last]

  defp set_high_bits([first | rest]) do
    # Set high bit on all but last
    [first ||| 0x80 | set_high_bits(rest)]
  end
end
