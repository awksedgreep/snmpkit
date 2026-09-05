defmodule SnmpKit.SnmpLib.Types.Validation do
  @moduledoc """
  Range and shape validation for SNMP values (Counter32/64, Gauge32, TimeTicks, Unsigned32, INTEGER, OCTET STRING, OID, IpAddress, Opaque). `SnmpKit.SnmpLib.Types` delegates here.
  """

  @max_integer 2_147_483_647
  @min_integer -2_147_483_648
  @max_timeticks 4_294_967_295
  @doc """
  @spec encode_value(term(), keyword()) :: {:ok, {snmp_type(), term()}} | {:error, atom()}

  @doc \"""
  Validates a TimeTicks value.

  TimeTicks represents time in hundredths of a second (centiseconds).
  """
  @spec validate_timeticks(term()) :: :ok | {:error, atom()}
  def validate_timeticks(value)
      when is_integer(value) and value >= 0 and value <= @max_timeticks do
    :ok
  end

  def validate_timeticks(value) when is_integer(value) do
    {:error, :out_of_range}
  end

  def validate_timeticks(_), do: {:error, :not_integer}

  @doc """
  Validates an IP address value.

  IP address should be a 4-byte binary or a tuple of 4 integers.

  ## Examples

      :ok = SnmpKit.SnmpLib.Types.validate_ip_address(<<192, 168, 1, 1>>)
      :ok = SnmpKit.SnmpLib.Types.validate_ip_address({192, 168, 1, 1})
      {:error, :invalid_length} = SnmpKit.SnmpLib.Types.validate_ip_address(<<192, 168, 1>>)
  """
  @spec validate_ip_address(term()) :: :ok | {:error, atom()}
  def validate_ip_address(<<a, b, c, d>>) when a <= 255 and b <= 255 and c <= 255 and d <= 255 do
    :ok
  end

  def validate_ip_address({a, b, c, d})
      when is_integer(a) and is_integer(b) and
             is_integer(c) and is_integer(d) and
             a >= 0 and a <= 255 and b >= 0 and b <= 255 and
             c >= 0 and c <= 255 and d >= 0 and d <= 255 do
    :ok
  end

  def validate_ip_address(value) when is_binary(value) do
    # Check if it's a printable string (likely an IP address string)
    if String.printable?(value) do
      {:error, :invalid_format}
    else
      # It's binary data, check length
      case byte_size(value) do
        # Valid length but invalid values
        4 -> {:error, :invalid_format}
        # Wrong length
        _ -> {:error, :invalid_length}
      end
    end
  end

  def validate_ip_address(_), do: {:error, :invalid_format}

  @doc """
  Validates an SNMP integer value.

  SNMP INTEGER is a signed 32-bit integer.
  """
  @spec validate_integer(term()) :: :ok | {:error, atom()}
  def validate_integer(value)
      when is_integer(value) and value >= @min_integer and value <= @max_integer do
    :ok
  end

  def validate_integer(value) when is_integer(value) do
    {:error, :out_of_range}
  end

  def validate_integer(_), do: {:error, :not_integer}

  @doc """
  Validates an OCTET STRING value.

  OCTET STRING should be a binary with reasonable length limits.
  """
  @spec validate_octet_string(term()) :: :ok | {:error, atom()}
  def validate_octet_string(value) when is_binary(value) do
    case byte_size(value) do
      size when size <= 65535 -> :ok
      _ -> {:error, :too_long}
    end
  end

  def validate_octet_string(_), do: {:error, :not_binary}

  @doc """
  Validates an OBJECT IDENTIFIER value.

  OID should be a list of non-negative integers.
  """
  @spec validate_oid(term()) :: :ok | {:error, atom()}
  def validate_oid(oid) when is_list(oid) do
    case SnmpKit.SnmpLib.OID.valid_oid?(oid) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_oid(_), do: {:error, :not_list}

  @doc """
  Validates an Opaque value.

  Opaque is used for arbitrary binary data.
  """
  @spec validate_opaque(term()) :: :ok | {:error, atom()}
  def validate_opaque(value) when is_binary(value) do
    case byte_size(value) do
      size when size <= 65535 -> :ok
      _ -> {:error, :too_long}
    end
  end

  def validate_opaque(_), do: {:error, :not_binary}
end
