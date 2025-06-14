defmodule SnmpKit.SnmpLib.PDU.Decoder do
  @moduledoc """
  ASN.1 BER decoding functions for SNMP PDUs and messages.

  This module handles the conversion of binary ASN.1 BER format to Elixir data structures
  for SNMP protocol communication.
  """

  import Bitwise
  alias SnmpKit.SnmpLib.PDU.Constants

  @type message :: Constants.message()
  @type pdu :: Constants.pdu()

  # Import constants for decoding
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
  Decodes an SNMP message from binary format.
  """
  @spec decode_message(binary()) :: {:ok, message()} | {:error, atom()}
  def decode_message(data) when is_binary(data) do
    try do
      decode_snmp_message_comprehensive(data)
    rescue
      error -> {:error, {:decoding_error, error}}
    catch
      error -> {:error, {:decoding_error, error}}
    end
  end

  def decode_message(_), do: {:error, :invalid_input}

  @doc """
  Decodes an SNMP message from binary format (alias for decode_message/1).
  """
  @spec decode(binary()) :: {:ok, message()} | {:error, atom()}
  def decode(data) when is_binary(data) do
    decode_message(data)
  end

  @doc """
  Alias for decode/1.
  """
  @spec decode_snmp_packet(binary()) :: {:ok, message()} | {:error, atom()}
  def decode_snmp_packet(data), do: decode(data)

  ## Private Implementation

  # Comprehensive decoding implementation (from SnmpSim)
  defp decode_snmp_message_comprehensive(<<0x30, rest::binary>>) do
    case parse_ber_length(rest) do
      {:ok, {_content_length, content}} ->
        case parse_snmp_message_fields(content) do
          {:ok, {version, community, pdu_data}} ->
            case parse_pdu_comprehensive(pdu_data) do
              {:ok, pdu} ->
                {:ok,
                 %{
                   version: version,
                   community: community,
                   pdu: pdu
                 }}

              {:error, reason} ->
                {:error, {:pdu_parse_error, reason}}
            end

          {:error, reason} ->
            {:error, {:message_parse_error, reason}}
        end

      {:error, reason} ->
        {:error, {:message_parse_error, reason}}
    end
  end

  defp decode_snmp_message_comprehensive(_), do: {:error, :invalid_message_format}

  defp parse_ber_length(<<length, rest::binary>>) when length < 128 do
    if byte_size(rest) >= length do
      content = binary_part(rest, 0, length)
      {:ok, {length, content}}
    else
      {:error, :insufficient_data}
    end
  end

  defp parse_ber_length(<<length_of_length, rest::binary>>) when length_of_length >= 128 do
    num_length_bytes = length_of_length - 128

    if num_length_bytes > 0 and num_length_bytes <= 4 and byte_size(rest) >= num_length_bytes do
      <<length_bytes::binary-size(num_length_bytes), remaining::binary>> = rest
      actual_length = :binary.decode_unsigned(length_bytes, :big)

      if byte_size(remaining) >= actual_length do
        content = binary_part(remaining, 0, actual_length)
        {:ok, {actual_length, content}}
      else
        {:error, :insufficient_data}
      end
    else
      {:error, :invalid_length_encoding}
    end
  end

  defp parse_ber_length(_), do: {:error, :invalid_length_format}

  defp parse_snmp_message_fields(data) do
    with {:ok, {version, rest1}} <- parse_integer(data),
         {:ok, {community, rest2}} <- parse_octet_string(rest1),
         {:ok, pdu_data} <- {:ok, rest2} do
      {:ok, {version, community, pdu_data}}
    end
  end

  defp parse_integer(<<@integer, rest::binary>>) do
    case parse_ber_length_and_remaining(rest) do
      {:ok, {_length, value_bytes, remaining}} ->
        if byte_size(value_bytes) > 0 do
          value = decode_integer_value(value_bytes)
          {:ok, {value, remaining}}
        else
          {:error, :invalid_integer_length}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_integer(_), do: {:error, :invalid_integer}

  defp parse_octet_string(<<@octet_string, rest::binary>>) do
    case parse_ber_length_and_remaining(rest) do
      {:ok, {_length, value_bytes, remaining}} ->
        {:ok, {value_bytes, remaining}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_octet_string(_), do: {:error, :invalid_octet_string}

  defp parse_ber_length_and_remaining(<<length, rest::binary>>) when length < 128 do
    if byte_size(rest) >= length do
      content = binary_part(rest, 0, length)
      remaining = binary_part(rest, length, byte_size(rest) - length)
      {:ok, {length, content, remaining}}
    else
      {:error, :insufficient_data}
    end
  end

  defp parse_ber_length_and_remaining(<<length_of_length, rest::binary>>)
       when length_of_length >= 128 do
    num_length_bytes = length_of_length - 128

    if num_length_bytes > 0 and num_length_bytes <= 4 and byte_size(rest) >= num_length_bytes do
      <<length_bytes::binary-size(num_length_bytes), remaining_with_content::binary>> = rest
      actual_length = :binary.decode_unsigned(length_bytes, :big)

      if byte_size(remaining_with_content) >= actual_length do
        content = binary_part(remaining_with_content, 0, actual_length)

        remaining =
          binary_part(
            remaining_with_content,
            actual_length,
            byte_size(remaining_with_content) - actual_length
          )

        {:ok, {actual_length, content, remaining}}
      else
        {:error, :insufficient_data}
      end
    else
      {:error, :invalid_length_encoding}
    end
  end

  defp parse_ber_length_and_remaining(_), do: {:error, :invalid_length_format}

  defp parse_pdu_comprehensive(<<tag, rest::binary>>)
       when tag in [0xA0, 0xA1, 0xA2, 0xA3, 0xA5] do
    pdu_type =
      case tag do
        0xA0 -> :get_request
        0xA1 -> :get_next_request
        0xA2 -> :get_response
        0xA3 -> :set_request
        0xA5 -> :get_bulk_request
      end

    case parse_ber_length_and_remaining(rest) do
      {:ok, {_length, pdu_content, _remaining}} ->
        case pdu_type do
          :get_bulk_request ->
            case parse_bulk_pdu_fields(pdu_content) do
              {:ok, {request_id, non_repeaters, max_repetitions, varbinds}} ->
                {:ok,
                 %{
                   type: pdu_type,
                   request_id: request_id,
                   non_repeaters: non_repeaters,
                   max_repetitions: max_repetitions,
                   varbinds: varbinds
                 }}

              {:error, _reason} ->
                {:ok, %{type: pdu_type, varbinds: [], non_repeaters: 0, max_repetitions: 0}}
            end

          _ ->
            case parse_standard_pdu_fields(pdu_content) do
              {:ok, {request_id, error_status, error_index, varbinds}} ->
                {:ok,
                 %{
                   type: pdu_type,
                   request_id: request_id,
                   error_status: error_status,
                   error_index: error_index,
                   varbinds: varbinds
                 }}

              {:error, _reason} ->
                {:ok, %{type: pdu_type, varbinds: [], error_status: 0, error_index: 0}}
            end
        end

      {:error, _reason} ->
        case pdu_type do
          :get_bulk_request ->
            {:ok, %{type: pdu_type, varbinds: [], non_repeaters: 0, max_repetitions: 0}}

          _ ->
            {:ok, %{type: pdu_type, varbinds: [], error_status: 0, error_index: 0}}
        end
    end
  end

  defp parse_pdu_comprehensive(_), do: {:error, :invalid_pdu}

  defp parse_standard_pdu_fields(data) do
    with {:ok, {request_id, rest1}} <- parse_integer(data),
         {:ok, {error_status, rest2}} <- parse_integer(rest1),
         {:ok, {error_index, rest3}} <- parse_integer(rest2),
         {:ok, varbinds} <- parse_varbinds(rest3) do
      {:ok, {request_id, error_status, error_index, varbinds}}
    end
  end

  defp parse_bulk_pdu_fields(data) do
    with {:ok, {request_id, rest1}} <- parse_integer(data),
         {:ok, {non_repeaters, rest2}} <- parse_integer(rest1),
         {:ok, {max_repetitions, rest3}} <- parse_integer(rest2),
         {:ok, varbinds} <- parse_varbinds(rest3) do
      {:ok, {request_id, non_repeaters, max_repetitions, varbinds}}
    end
  end

  defp parse_varbinds(data) do
    case parse_sequence(data) do
      {:ok, {varbind_data, _rest}} -> parse_varbind_list(varbind_data, [])
      {:error, _} -> {:ok, []}
    end
  end

  defp parse_sequence(<<0x30, rest::binary>>) do
    case parse_ber_length_and_remaining(rest) do
      {:ok, {_length, data, remaining}} ->
        {:ok, {data, remaining}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_sequence(_), do: {:error, :not_sequence}

  defp parse_varbind_list(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_varbind_list(data, acc) do
    case parse_sequence(data) do
      {:ok, {varbind_data, rest}} ->
        case parse_single_varbind(varbind_data) do
          {:ok, varbind} -> parse_varbind_list(rest, [varbind | acc])
          {:error, _} -> parse_varbind_list(rest, acc)
        end

      {:error, _} ->
        {:ok, Enum.reverse(acc)}
    end
  end

  defp parse_single_varbind(data) do
    with {:ok, {oid, rest1}} <- parse_oid(data),
         {:ok, {type, value, _rest2}} <- parse_value_with_type(rest1) do
      {:ok, {oid, type, value}}
    else
      _ -> {:error, :invalid_varbind}
    end
  end

  defp parse_oid(<<@object_identifier, length, oid_data::binary-size(length), rest::binary>>) do
    case decode_oid_data(oid_data) do
      {:ok, oid} -> {:ok, {oid, rest}}
      error -> error
    end
  end

  defp parse_oid(_), do: {:error, :invalid_oid}

  defp decode_oid_data(<<first, rest::binary>>) do
    first_subid = div(first, 40)
    second_subid = rem(first, 40)

    case decode_oid_subids(rest, [second_subid, first_subid]) do
      {:ok, subids} -> {:ok, Enum.reverse(subids)}
      error -> error
    end
  end

  defp decode_oid_data(_), do: {:error, :invalid_oid_data}

  defp decode_oid_subids(<<>>, acc), do: {:ok, acc}

  defp decode_oid_subids(data, acc) do
    case decode_oid_subid(data, 0) do
      {:ok, {subid, rest}} -> decode_oid_subids(rest, [subid | acc])
      error -> error
    end
  end

  defp decode_oid_subid(<<byte, rest::binary>>, acc) do
    new_acc = (acc <<< 7) + (byte &&& 0x7F)

    if (byte &&& 0x80) == 0 do
      {:ok, {new_acc, rest}}
    else
      decode_oid_subid(rest, new_acc)
    end
  end

  defp decode_oid_subid(<<>>, _), do: {:error, :incomplete_oid}

  defp parse_value_with_type(<<@octet_string, length, value::binary-size(length), rest::binary>>) do
    {:ok, {:octet_string, value, rest}}
  end

  defp parse_value_with_type(<<@integer, length, value_data::binary-size(length), rest::binary>>) do
    int_value = decode_integer_value(value_data)
    {:ok, {:integer, int_value, rest}}
  end

  defp parse_value_with_type(<<@null, 0, rest::binary>>) do
    {:ok, {:null, :null, rest}}
  end

  defp parse_value_with_type(
         <<@object_identifier, length, oid_data::binary-size(length), rest::binary>>
       ) do
    case decode_oid_data(oid_data) do
      {:ok, oid_list} ->
        {:ok, {:object_identifier, oid_list, rest}}

      {:error, _} ->
        {:error, :invalid_oid}
    end
  end

  defp parse_value_with_type(<<@counter32, length, value::binary-size(length), rest::binary>>) do
    {:ok, {:counter32, decode_unsigned_integer(value), rest}}
  end

  defp parse_value_with_type(<<@gauge32, length, value::binary-size(length), rest::binary>>) do
    {:ok, {:gauge32, decode_unsigned_integer(value), rest}}
  end

  defp parse_value_with_type(<<@timeticks, length, value::binary-size(length), rest::binary>>) do
    {:ok, {:timeticks, decode_unsigned_integer(value), rest}}
  end

  defp parse_value_with_type(<<@counter64, length, value::binary-size(length), rest::binary>>) do
    {:ok, {:counter64, decode_counter64(value), rest}}
  end

  defp parse_value_with_type(<<@ip_address, length, value::binary-size(length), rest::binary>>) do
    {:ok, {:ip_address, value, rest}}
  end

  defp parse_value_with_type(<<@opaque_type, length, value::binary-size(length), rest::binary>>) do
    {:ok, {:opaque, value, rest}}
  end

  defp parse_value_with_type(<<@no_such_object, 0, rest::binary>>) do
    {:ok, {:no_such_object, nil, rest}}
  end

  defp parse_value_with_type(<<@no_such_instance, 0, rest::binary>>) do
    {:ok, {:no_such_instance, nil, rest}}
  end

  defp parse_value_with_type(<<@end_of_mib_view, 0, rest::binary>>) do
    {:ok, {:end_of_mib_view, nil, rest}}
  end

  defp parse_value_with_type(_), do: {:error, :invalid_value}

  defp decode_integer_value(<<byte>>) when byte < 128, do: byte
  defp decode_integer_value(<<byte>>) when byte >= 128, do: byte - 256

  defp decode_integer_value(data) do
    case :binary.decode_unsigned(data, :big) do
      value ->
        bit_size = byte_size(data) * 8

        if value >= 1 <<< (bit_size - 1) do
          value - (1 <<< bit_size)
        else
          value
        end
    end
  end

  defp decode_unsigned_integer(data) when byte_size(data) <= 4 do
    :binary.decode_unsigned(data, :big)
  end

  defp decode_unsigned_integer(data) when byte_size(data) == 5 do
    # Handle 5-byte case for large 32-bit unsigned values that require leading zero padding
    case data do
      <<0, rest::binary-size(4)>> ->
        # Leading zero byte for unsigned representation, decode the remaining 4 bytes
        :binary.decode_unsigned(rest, :big)

      _ ->
        # If first byte is not zero, this exceeds 32-bit range
        0
    end
  end

  defp decode_unsigned_integer(_), do: 0

  defp decode_counter64(data) when byte_size(data) == 8 do
    :binary.decode_unsigned(data, :big)
  end

  defp decode_counter64(_), do: 0
end
