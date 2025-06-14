defmodule SnmpLib.ASN1 do
  @moduledoc """
  Comprehensive ASN.1 BER (Basic Encoding Rules) encoding and decoding utilities.

  Provides low-level ASN.1 operations that are used by the PDU module and can be
  used for other ASN.1 encoding/decoding needs. This module offers improved
  performance and better error handling compared to basic implementations.

  ## Features

  - Complete BER encoding/decoding support
  - Optimized length handling for large values
  - Comprehensive error reporting
  - Support for constructed and primitive types
  - Memory-efficient implementations
  - Validation and constraint checking
  - RFC-compliant OID multibyte encoding (values ≥ 128)

  ## ASN.1 Types Supported

  - **INTEGER**: Signed integers with arbitrary precision
  - **OCTET STRING**: Binary data of any length
  - **NULL**: Null value representation
  - **OBJECT IDENTIFIER**: Hierarchical object identifiers with multibyte subidentifiers
  - **SEQUENCE**: Constructed type for complex structures
  - **Custom Tags**: Application-specific and context-specific tags

  ## Important: OID Encoding

  OID subidentifiers use 7-bit encoding where values ≥ 128 require multibyte encoding:

  - Values 0-127: Single byte
  - Values 128+: Multibyte with continuation bits
  - Example: 200 → `[0x81, 0x48]` (not single byte `0xC8`)

  ## Examples

      # Integer encoding/decoding
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_integer(42)
      iex> {:ok, {value, <<>>}} = SnmpLib.ASN1.decode_integer(encoded)
      iex> value
      42

      # OCTET STRING encoding/decoding
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_octet_string("Hello")
      iex> {:ok, {value, <<>>}} = SnmpLib.ASN1.decode_octet_string(encoded)
      iex> value
      "Hello"

      # OID encoding/decoding with multibyte values
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_oid([1, 3, 6, 1, 4, 1, 200])
      iex> {:ok, {oid, <<>>}} = SnmpLib.ASN1.decode_oid(encoded)
      iex> oid
      [1, 3, 6, 1, 4, 1, 200]

      # Length encoding for large values
      iex> encoded_length = SnmpLib.ASN1.encode_length(1000)
      iex> {:ok, {length, <<>>}} = SnmpLib.ASN1.decode_length(encoded_length)
      iex> length
      1000

      # NULL encoding
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_null()
      iex> {:ok, {value, <<>>}} = SnmpLib.ASN1.decode_null(encoded)
      iex> value
      :null
  """

  import Bitwise

  @type tag :: non_neg_integer()
  @type length :: non_neg_integer()
  @type content :: binary()
  @type tlv :: {tag(), length(), content()}
  @type oid :: [non_neg_integer()]

  # Standard ASN.1 tags
  @tag_integer 0x02
  @tag_octet_string 0x04
  @tag_null 0x05
  @tag_oid 0x06
  @tag_sequence 0x30

  # Length encoding constants
  @short_form_max 127
  @indefinite_length 0x80

  ## Generic Encoding Functions

  @doc """
  Encodes an ASN.1 INTEGER value using BER (Basic Encoding Rules).

  Supports arbitrary precision integers using two's complement representation.
  The encoded result includes the ASN.1 tag (0x02), length, and content bytes.

  ## Parameters

  - `value`: Integer value to encode (any size)

  ## Returns

  - `{:ok, encoded_bytes}` on success
  - `{:error, reason}` on failure

  ## Examples

      # Positive integers
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_integer(42)
      iex> encoded
      <<2, 1, 42>>

      # Negative integers (two's complement)
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_integer(-1)
      iex> encoded
      <<2, 1, 255>>

      # Zero
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_integer(0)
      iex> encoded
      <<2, 1, 0>>

      # Large integers
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_integer(32767)
      iex> byte_size(encoded) > 3
      true
  """
  @spec encode_integer(integer()) :: {:ok, binary()} | {:error, atom()}
  def encode_integer(value) when is_integer(value) do
    content = encode_integer_content(value)
    tlv_bytes = encode_tlv(@tag_integer, content)
    {:ok, tlv_bytes}
  end

  @doc """
  Encodes an ASN.1 OCTET STRING value.

  ## Parameters

  - `value`: Binary data to encode

  ## Examples

      {:ok, encoded} = SnmpLib.ASN1.encode_octet_string("Hello")
      {:ok, encoded} = SnmpLib.ASN1.encode_octet_string(<<1, 2, 3, 4>>)
  """
  @spec encode_octet_string(binary()) :: {:ok, binary()} | {:error, atom()}
  def encode_octet_string(value) when is_binary(value) do
    tlv_bytes = encode_tlv(@tag_octet_string, value)
    {:ok, tlv_bytes}
  end

  @doc """
  Encodes an ASN.1 NULL value.

  ## Examples

      {:ok, <<5, 0>>} = SnmpLib.ASN1.encode_null()
  """
  @spec encode_null() :: {:ok, binary()}
  def encode_null do
    {:ok, encode_tlv(@tag_null, <<>>)}
  end

  @doc """
  Encodes an ASN.1 OBJECT IDENTIFIER (OID) value using BER encoding.

  OIDs are hierarchical identifiers where each component is encoded using
  7-bit subidentifiers. Values ≥ 128 require multibyte encoding with
  continuation bits, which is correctly handled by this implementation.

  ## Parameters

  - `oid_list`: List of non-negative integers representing the OID (minimum 2 components)

  ## Returns

  - `{:ok, encoded_bytes}` on success
  - `{:error, reason}` on failure (invalid OID format)

  ## Encoding Rules

  - First two components are combined: `first * 40 + second`
  - Remaining components use 7-bit encoding with continuation bits
  - Values 0-127: single byte
  - Values 128+: multibyte with high bit indicating continuation

  ## Examples

      # Standard SNMP OID (sysDescr.0)
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_oid([1, 3, 6, 1, 2, 1, 1, 1, 0])
      iex> {:ok, {decoded, <<>>}} = SnmpLib.ASN1.decode_oid(encoded)
      iex> decoded
      [1, 3, 6, 1, 2, 1, 1, 1, 0]

      # OID with multibyte values (≥ 128)
      iex> {:ok, encoded} = SnmpLib.ASN1.encode_oid([1, 3, 6, 1, 4, 1, 200])
      iex> {:ok, {decoded, <<>>}} = SnmpLib.ASN1.decode_oid(encoded)
      iex> decoded
      [1, 3, 6, 1, 4, 1, 200]

      # Invalid OIDs
      iex> SnmpLib.ASN1.encode_oid([])
      {:error, :invalid_oid}

      iex> SnmpLib.ASN1.encode_oid([1])
      {:error, :invalid_oid}
  """
  @spec encode_oid(oid()) :: {:ok, binary()} | {:error, atom()}
  def encode_oid(oid_list) when is_list(oid_list) and length(oid_list) >= 2 do
    case encode_oid_content(oid_list) do
      {:ok, content} ->
        tlv_bytes = encode_tlv(@tag_oid, content)
        {:ok, tlv_bytes}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def encode_oid(_), do: {:error, :invalid_oid}

  @doc """
  Encodes an ASN.1 SEQUENCE with the given content.

  ## Parameters

  - `content`: Pre-encoded content for the sequence

  ## Examples

      content = encode_integer_content(42) <> encode_octet_string_content("test")
      {:ok, sequence} = SnmpLib.ASN1.encode_sequence(content)
  """
  @spec encode_sequence(binary()) :: {:ok, binary()}
  def encode_sequence(content) when is_binary(content) do
    {:ok, encode_tlv(@tag_sequence, content)}
  end

  @doc """
  Encodes a custom TLV (Tag-Length-Value) structure.

  ## Parameters

  - `tag`: ASN.1 tag value
  - `content`: Binary content

  ## Examples

      {:ok, tlv} = SnmpLib.ASN1.encode_custom_tlv(0xA0, <<"custom_content">>)
  """
  @spec encode_custom_tlv(tag(), binary()) :: {:ok, binary()}
  def encode_custom_tlv(tag, content) when is_integer(tag) and is_binary(content) do
    {:ok, encode_tlv(tag, content)}
  end

  ## Generic Decoding Functions

  @doc """
  Decodes an ASN.1 INTEGER value.

  ## Parameters

  - `data`: Binary data starting with an INTEGER TLV

  ## Returns

  - `{:ok, {value, remaining_data}}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, {42, remaining}} = SnmpLib.ASN1.decode_integer(<<2, 1, 42, 99, 100>>)
      # Returns {42, <<99, 100>>}
  """
  @spec decode_integer(binary()) :: {:ok, {integer(), binary()}} | {:error, atom()}
  def decode_integer(<<@tag_integer, rest::binary>>) do
    case decode_length_and_content(rest) do
      {:ok, {content, remaining}} ->
        case decode_integer_content(content) do
          {:ok, value} -> {:ok, {value, remaining}}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end
  def decode_integer(_), do: {:error, :invalid_tag}

  @doc """
  Decodes an ASN.1 OCTET STRING value.

  ## Examples

      {:ok, {"Hello", remaining}} = SnmpLib.ASN1.decode_octet_string(encoded_data)
  """
  @spec decode_octet_string(binary()) :: {:ok, {binary(), binary()}} | {:error, atom()}
  def decode_octet_string(<<@tag_octet_string, rest::binary>>) do
    case decode_length_and_content(rest) do
      {:ok, {content, remaining}} -> {:ok, {content, remaining}}
      {:error, reason} -> {:error, reason}
    end
  end
  def decode_octet_string(_), do: {:error, :invalid_tag}

  @doc """
  Decodes an ASN.1 NULL value.

  ## Examples

      {:ok, {:null, remaining}} = SnmpLib.ASN1.decode_null(<<5, 0, 1, 2, 3>>)
      # Returns {:null, <<1, 2, 3>>}
  """
  @spec decode_null(binary()) :: {:ok, {:null, binary()}} | {:error, atom()}
  def decode_null(<<@tag_null, 0, rest::binary>>) do
    {:ok, {:null, rest}}
  end
  def decode_null(<<@tag_null, _::binary>>), do: {:error, :invalid_null_length}
  def decode_null(_), do: {:error, :invalid_tag}

  @doc """
  Decodes an ASN.1 OBJECT IDENTIFIER value.

  ## Examples

      {:ok, {[1, 3, 6, 1], remaining}} = SnmpLib.ASN1.decode_oid(encoded_data)
  """
  @spec decode_oid(binary()) :: {:ok, {oid(), binary()}} | {:error, atom()}
  def decode_oid(<<@tag_oid, rest::binary>>) do
    case decode_length_and_content(rest) do
      {:ok, {content, remaining}} ->
        case decode_oid_content(content) do
          {:ok, oid_list} -> {:ok, {oid_list, remaining}}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end
  def decode_oid(_), do: {:error, :invalid_tag}

  @doc """
  Decodes an ASN.1 SEQUENCE value.

  Returns the content of the sequence without further parsing.

  ## Examples

      {:ok, {sequence_content, remaining}} = SnmpLib.ASN1.decode_sequence(encoded_data)
  """
  @spec decode_sequence(binary()) :: {:ok, {binary(), binary()}} | {:error, atom()}
  def decode_sequence(<<@tag_sequence, rest::binary>>) do
    case decode_length_and_content(rest) do
      {:ok, {content, remaining}} -> {:ok, {content, remaining}}
      {:error, reason} -> {:error, reason}
    end
  end
  def decode_sequence(_), do: {:error, :invalid_tag}

  @doc """
  Decodes a generic TLV structure.

  ## Parameters

  - `data`: Binary data starting with a TLV

  ## Returns

  - `{:ok, {tag, content, remaining}}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, {tag, content, remaining}} = SnmpLib.ASN1.decode_tlv(binary_data)
  """
  @spec decode_tlv(binary()) :: {:ok, {tag(), binary(), binary()}} | {:error, atom()}
  def decode_tlv(<<tag, rest::binary>>) when is_integer(tag) do
    case decode_length_and_content(rest) do
      {:ok, {content, remaining}} -> {:ok, {tag, content, remaining}}
      {:error, reason} -> {:error, reason}
    end
  end
  def decode_tlv(_), do: {:error, :insufficient_data}

  ## Length Encoding/Decoding

  @doc """
  Encodes an ASN.1 length field.

  Supports both short form (< 128) and long form encoding.

  ## Parameters

  - `length`: Length value to encode

  ## Returns

  - Binary representation of the length

  ## Examples

      <<42>> = SnmpLib.ASN1.encode_length(42)
      <<0x81, 200>> = SnmpLib.ASN1.encode_length(200)
      <<0x82, 1, 44>> = SnmpLib.ASN1.encode_length(300)
  """
  @spec encode_length(length()) :: binary()
  def encode_length(length) when is_integer(length) and length >= 0 do
    cond do
      length <= @short_form_max ->
        # Short form: length fits in 7 bits
        <<length>>

      length < 256 ->
        # Long form: 1 byte for length
        <<0x81, length>>

      length < 65536 ->
        # Long form: 2 bytes for length
        <<0x82, length::16>>

      length < 16777216 ->
        # Long form: 3 bytes for length
        <<0x83, length::24>>

      true ->
        # Long form: 4 bytes for length (handles up to ~4GB)
        <<0x84, length::32>>
    end
  end

  @doc """
  Decodes an ASN.1 length field.

  ## Parameters

  - `data`: Binary data starting with a length field

  ## Returns

  - `{:ok, {length, remaining_data}}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, {42, remaining}} = SnmpLib.ASN1.decode_length(<<42, 1, 2, 3>>)
      {:ok, {300, remaining}} = SnmpLib.ASN1.decode_length(<<0x82, 1, 44, 1, 2, 3>>)
  """
  @spec decode_length(binary()) :: {:ok, {length(), binary()}} | {:error, atom()}
  def decode_length(<<length_byte, rest::binary>>) when length_byte <= @short_form_max do
    # Short form
    {:ok, {length_byte, rest}}
  end

  def decode_length(<<length_byte, rest::binary>>) when length_byte > @short_form_max do
    if length_byte == @indefinite_length do
      {:error, :indefinite_length_not_supported}
    else
      # Long form
      num_octets = length_byte - @indefinite_length

      if num_octets > 4 do
        {:error, :length_too_large}
      else
        case rest do
          <<length_bytes::binary-size(num_octets), remaining::binary>> ->
            length = :binary.decode_unsigned(length_bytes, :big)
            {:ok, {length, remaining}}
          _ ->
            {:error, :insufficient_length_bytes}
        end
      end
    end
  end

  def decode_length(_), do: {:error, :insufficient_data}

  ## Tag Parsing

  @doc """
  Parses an ASN.1 tag byte.

  Returns information about the tag including class, constructed bit, and tag number.

  ## Parameters

  - `tag_byte`: Single byte representing the tag

  ## Returns

  - Map with tag information

  ## Examples

      info = SnmpLib.ASN1.parse_tag(0x30)
      # Returns %{class: :universal, constructed: true, tag_number: 16}
  """
  @spec parse_tag(tag()) :: map()
  def parse_tag(tag_byte) when is_integer(tag_byte) and tag_byte >= 0 and tag_byte <= 255 do
    class = case (tag_byte &&& 0xC0) >>> 6 do
      0 -> :universal
      1 -> :application
      2 -> :context
      3 -> :private
    end

    constructed = (tag_byte &&& 0x20) != 0
    tag_number = tag_byte &&& 0x1F

    %{
      class: class,
      constructed: constructed,
      tag_number: tag_number,
      original_byte: tag_byte
    }
  end

  ## Validation and Utilities

  @doc """
  Validates the structure of BER-encoded data.

  Performs basic validation without full decoding.

  ## Parameters

  - `data`: BER-encoded binary data

  ## Returns

  - `:ok` if structure is valid
  - `{:error, reason}` if structure is invalid

  ## Examples

      :ok = SnmpLib.ASN1.validate_ber_structure(valid_ber_data)
      {:error, :invalid_length} = SnmpLib.ASN1.validate_ber_structure(malformed_data)
  """
  @spec validate_ber_structure(binary()) :: :ok | {:error, atom()}
  def validate_ber_structure(data) when is_binary(data) do
    validate_ber_recursive(data)
  end

  @doc """
  Calculates the total length of a BER-encoded structure.

  ## Parameters

  - `data`: BER-encoded binary data

  ## Returns

  - `{:ok, total_length}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, 10} = SnmpLib.ASN1.calculate_ber_length(ber_data)
  """
  @spec calculate_ber_length(binary()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def calculate_ber_length(<<tag, rest::binary>>) when is_integer(tag) do
    case decode_length(rest) do
      {:ok, {content_length, _}} ->
        tag_length = 1
        length_field_length = byte_size(rest) - byte_size(rest) +
                              (byte_size(encode_length(content_length)))
        total_length = tag_length + length_field_length + content_length
        {:ok, total_length}
      {:error, reason} ->
        {:error, reason}
    end
  end
  def calculate_ber_length(_), do: {:error, :insufficient_data}

  ## Private Helper Functions

  # TLV encoding
  defp encode_tlv(tag, content) when is_integer(tag) and is_binary(content) do
    length_bytes = encode_length(byte_size(content))
    <<tag, length_bytes::binary, content::binary>>
  end

  # Integer content encoding
  defp encode_integer_content(0), do: <<0>>

  defp encode_integer_content(value) when value > 0 do
    bytes = encode_positive_integer(value, [])
    # Check if MSB is set (would be interpreted as negative)
    case bytes do
      <<msb, _::binary>> when msb >= 128 -> <<0, bytes::binary>>
      _ -> bytes
    end
  end

  defp encode_integer_content(value) when value < 0 do
    # Two's complement encoding for negative numbers
    positive_value = abs(value)
    bit_length = calculate_bit_length(positive_value) + 1  # +1 for sign bit
    byte_length = div(bit_length + 7, 8)  # Round up to byte boundary

    max_positive = 1 <<< (byte_length * 8 - 1)

    byte_length = if positive_value > max_positive do
      # Need one more byte
      byte_length + 1
    else
      byte_length
    end

    # Calculate two's complement
    twos_complement = (1 <<< (byte_length * 8)) + value
    encode_unsigned_integer(twos_complement, byte_length)
  end

  defp encode_positive_integer(0, acc), do: :binary.list_to_bin(acc)
  defp encode_positive_integer(value, acc) do
    encode_positive_integer(value >>> 8, [value &&& 0xFF | acc])
  end

  defp encode_unsigned_integer(value, byte_length) do
    <<value::size(byte_length)-unit(8)-big>>
  end

  defp calculate_bit_length(value) when value == 0, do: 1
  defp calculate_bit_length(value) when value > 0 do
    :math.log2(value) |> :math.ceil() |> trunc()
  end

  # Integer content decoding
  defp decode_integer_content(<<>>), do: {:error, :empty_integer}
  defp decode_integer_content(<<byte>>) when byte < 128, do: {:ok, byte}
  defp decode_integer_content(<<byte>>) when byte >= 128, do: {:ok, byte - 256}

  defp decode_integer_content(data) when byte_size(data) > 1 do
    <<msb, _::binary>> = data

    if msb >= 128 do
      # Negative number (two's complement)
      bit_size = byte_size(data) * 8
      unsigned_value = :binary.decode_unsigned(data, :big)
      signed_value = unsigned_value - (1 <<< bit_size)
      {:ok, signed_value}
    else
      # Positive number
      value = :binary.decode_unsigned(data, :big)
      {:ok, value}
    end
  end

  # OID content encoding
  defp encode_oid_content([first, second | rest]) when first < 3 and second < 40 do
    first_byte = first * 40 + second
    first_encoded = encode_oid_subidentifier(first_byte)
    rest_encoded = Enum.map(rest, &encode_oid_subidentifier/1)
    content = :binary.list_to_bin([first_encoded | rest_encoded])
    {:ok, content}
  end
  defp encode_oid_content(_), do: {:error, :invalid_oid}

  defp encode_oid_subidentifier(value) when value < 128 do
    <<value>>
  end
  defp encode_oid_subidentifier(value) when value >= 128 do
    encode_oid_large_value(value)
  end

  defp encode_oid_large_value(value) when value >= 128 do
    encode_oid_multibyte(value)
  end

  defp encode_oid_multibyte(value) do
    # Build the multibyte encoding by collecting 7-bit chunks
    bytes = build_multibyte_chunks(value, [])
    # All bytes except the last need continuation bit set
    {leading_bytes, [last_byte]} = Enum.split(bytes, length(bytes) - 1)
    continuation_bytes = Enum.map(leading_bytes, fn byte -> byte ||| 0x80 end)
    :binary.list_to_bin(continuation_bytes ++ [last_byte])
  end

  defp build_multibyte_chunks(value, acc) when value < 128 do
    [value | acc]
  end
  defp build_multibyte_chunks(value, acc) do
    seven_bits = value &&& 0x7F
    remaining = value >>> 7
    build_multibyte_chunks(remaining, [seven_bits | acc])
  end

  # OID content decoding
  defp decode_oid_content(<<first_byte, rest::binary>>) do
    first_subid = div(first_byte, 40)
    second_subid = rem(first_byte, 40)

    case decode_oid_subidentifiers(rest, []) do
      {:ok, remaining_subids} ->
        {:ok, [first_subid, second_subid | remaining_subids]}
      {:error, reason} ->
        {:error, reason}
    end
  end
  defp decode_oid_content(_), do: {:error, :invalid_oid_content}

  defp decode_oid_subidentifiers(<<>>, acc) do
    {:ok, Enum.reverse(acc)}
  end
  defp decode_oid_subidentifiers(data, acc) do
    case decode_oid_subidentifier(data, 0) do
      {:ok, {subid, remaining}} ->
        decode_oid_subidentifiers(remaining, [subid | acc])
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_oid_subidentifier(<<byte, rest::binary>>, acc) do
    new_acc = (acc <<< 7) + (byte &&& 0x7F)

    if (byte &&& 0x80) == 0 do
      # Final byte
      {:ok, {new_acc, rest}}
    else
      # Continue reading
      decode_oid_subidentifier(rest, new_acc)
    end
  end
  defp decode_oid_subidentifier(<<>>, _), do: {:error, :incomplete_subidentifier}

  # Length and content decoding
  defp decode_length_and_content(data) do
    case decode_length(data) do
      {:ok, {length, rest}} ->
        if byte_size(rest) >= length do
          content = binary_part(rest, 0, length)
          remaining = binary_part(rest, length, byte_size(rest) - length)
          {:ok, {content, remaining}}
        else
          {:error, :insufficient_content}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  # BER structure validation
  defp validate_ber_recursive(<<>>), do: :ok
  defp validate_ber_recursive(data) do
    case decode_tlv(data) do
      {:ok, {_tag, _content, remaining}} ->
        validate_ber_recursive(remaining)
      {:error, reason} ->
        {:error, reason}
    end
  end
end
