defmodule SnmpMgr.Types do
  @moduledoc """
  SNMP data type handling and conversion.
  
  Handles encoding and decoding of SNMP values, including automatic type inference
  and explicit type specification.
  """

  @doc """
  Encodes a value for SNMP with optional type specification.

  ## Parameters
  - `value` - The value to encode
  - `opts` - Options including :type for explicit type specification

  ## Examples

      iex> SnmpMgr.Types.encode_value("Hello World")
      {:ok, {:string, "Hello World"}}

      iex> SnmpMgr.Types.encode_value(42)
      {:ok, {:integer, 42}}

      iex> SnmpMgr.Types.encode_value("192.168.1.1", type: :ipAddress)
      {:ok, {:ipAddress, {192, 168, 1, 1}}}
  """
  def encode_value(value, opts \\ []) do
    case Keyword.get(opts, :type) do
      nil -> infer_and_encode_type(value)
      type -> encode_with_explicit_type(value, type)
    end
  end

  @doc """
  Decodes an SNMP value to an Elixir term.

  ## Examples

      iex> SnmpMgr.Types.decode_value({:string, "Hello"})
      "Hello"

      iex> SnmpMgr.Types.decode_value({:integer, 42})
      42
  """
  def decode_value({:string, value}), do: to_string(value)
  def decode_value({:integer, value}), do: value
  def decode_value({:gauge32, value}), do: value
  def decode_value({:counter32, value}), do: value
  def decode_value({:counter64, value}), do: value
  def decode_value({:unsigned32, value}), do: value
  def decode_value({:timeticks, value}), do: value
  def decode_value({:ipAddress, {a, b, c, d}}) when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 do
    "#{a}.#{b}.#{c}.#{d}"
  end
  def decode_value({:ipAddress, invalid_tuple}) do
    {:error, {:invalid_ip_address, invalid_tuple}}
  end
  def decode_value({:objectId, oid}), do: oid
  def decode_value({:objectIdentifier, oid}), do: oid
  def decode_value({:octetString, value}), do: value
  def decode_value({:boolean, value}), do: value
  def decode_value({:opaque, value}), do: value
  def decode_value({:null, _}), do: nil
  
  # SNMPv2c specific exception values
  def decode_value(:noSuchObject), do: :no_such_object
  def decode_value(:noSuchInstance), do: :no_such_instance
  def decode_value(:endOfMibView), do: :end_of_mib_view
  
  def decode_value({type, _value}) when type not in [:string, :integer, :gauge32, :counter32, :counter64, :unsigned32, :timeticks, :ipAddress, :objectId, :objectIdentifier, :octetString, :boolean, :opaque, :null] do
    {:error, {:unknown_snmp_type, type}}
  end
  
  def decode_value(value), do: value

  @doc """
  Automatically infers the SNMP type from an Elixir value.

  ## Examples

      iex> SnmpMgr.Types.infer_type("hello")
      :string

      iex> SnmpMgr.Types.infer_type(42)
      :integer

      iex> SnmpMgr.Types.infer_type("192.168.1.1")
      :string  # Would need explicit :ipAddress type
  """
  def infer_type(value) when is_binary(value) do
    cond do
      # Empty string is still a string
      byte_size(value) == 0 -> :string
      # Check if it's pure ASCII printable text vs binary data
      String.printable?(value) and String.valid?(value) -> :string
      # Binary data is octet string
      true -> :octetString
    end
  end
  def infer_type(value) when is_integer(value) and value >= 0 and value < 4294967296, do: :unsigned32
  def infer_type(value) when is_integer(value) and value >= 4294967296, do: :counter64
  def infer_type(value) when is_integer(value), do: :integer
  def infer_type(value) when is_list(value) do
    # Could be an OID list
    if Enum.all?(value, &is_integer/1) do
      :objectIdentifier
    else
      :string
    end
  end
  def infer_type(value) when is_boolean(value), do: :boolean  
  def infer_type(value) when is_tuple(value) and tuple_size(value) == 4 do
    # Could be IP address tuple
    case value do
      {a, b, c, d} when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 ->
        :ipAddress
      _ ->
        :opaque
    end
  end
  def infer_type(nil), do: :null
  def infer_type(:null), do: :null
  def infer_type(:undefined), do: :null
  def infer_type(:noSuchObject), do: :null
  def infer_type(:noSuchInstance), do: :null
  def infer_type(:endOfMibView), do: :null
  def infer_type(_), do: :opaque

  # Private functions

  defp infer_and_encode_type(value) do
    type = infer_type(value)
    encode_with_inferred_type(value, type)
  end

  defp encode_with_inferred_type(value, :string) when is_binary(value) do
    # Keep strings as strings for consistency
    {:ok, {:string, value}}
  end

  defp encode_with_inferred_type(value, :integer) when is_integer(value) do
    {:ok, {:integer, value}}
  end

  defp encode_with_inferred_type(value, :unsigned32) when is_integer(value) and value >= 0 do
    {:ok, {:unsigned32, value}}
  end

  defp encode_with_inferred_type(value, :counter64) when is_integer(value) and value >= 0 do
    {:ok, {:counter64, value}}
  end

  defp encode_with_inferred_type(value, :objectIdentifier) when is_list(value) do
    if Enum.all?(value, &is_integer/1) do
      {:ok, {:objectIdentifier, value}}
    else
      {:ok, {:string, to_string(value)}}
    end
  end

  defp encode_with_inferred_type(value, :octetString) when is_binary(value) do
    {:ok, {:octetString, value}}
  end

  defp encode_with_inferred_type(value, :boolean) when is_boolean(value) do
    {:ok, {:boolean, value}}
  end

  defp encode_with_inferred_type(value, :ipAddress) when is_tuple(value) and tuple_size(value) == 4 do
    {:ok, {:ipAddress, value}}
  end

  defp encode_with_inferred_type(nil, :null) do
    {:ok, {:null, :null}}
  end

  defp encode_with_inferred_type(value, :opaque) do
    {:ok, {:opaque, value}}
  end

  defp encode_with_explicit_type(value, :string) when is_binary(value) do
    # Keep strings as strings for consistency
    {:ok, {:string, value}}
  end

  defp encode_with_explicit_type(value, :integer) when is_integer(value) do
    {:ok, {:integer, value}}
  end

  defp encode_with_explicit_type(value, :gauge32) when is_integer(value) and value >= 0 do
    {:ok, {:gauge32, value}}
  end

  defp encode_with_explicit_type(value, :counter32) when is_integer(value) and value >= 0 do
    {:ok, {:counter32, value}}
  end

  defp encode_with_explicit_type(value, :counter64) when is_integer(value) and value >= 0 do
    {:ok, {:counter64, value}}
  end

  defp encode_with_explicit_type(value, :unsigned32) when is_integer(value) and value >= 0 do
    {:ok, {:unsigned32, value}}
  end

  defp encode_with_explicit_type(value, :timeticks) when is_integer(value) and value >= 0 do
    {:ok, {:timeticks, value}}
  end

  defp encode_with_explicit_type(value, :ipAddress) when is_binary(value) do
    case parse_ip_address(value) do
      {:ok, ip_tuple} -> {:ok, {:ipAddress, ip_tuple}}
      :error -> {:error, {:invalid_ip_address, value}}
    end
  end

  defp encode_with_explicit_type(value, :ipAddress) when is_tuple(value) and tuple_size(value) == 4 do
    {:ok, {:ipAddress, value}}
  end

  defp encode_with_explicit_type(value, :objectIdentifier) when is_binary(value) do
    case SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} -> {:ok, {:objectIdentifier, oid_list}}
      {:error, _reason} -> {:error, {:unsupported_type_conversion, value, :objectIdentifier}}
    end
  end

  defp encode_with_explicit_type(value, :objectIdentifier) when is_list(value) do
    if Enum.all?(value, &is_integer/1) do
      {:ok, {:objectIdentifier, value}}
    else
      {:error, "OID values must be numeric integers, found non-integer elements in #{inspect(value)}"}
    end
  end

  defp encode_with_explicit_type(value, :octetString) when is_binary(value) do
    {:ok, {:octetString, value}}
  end

  defp encode_with_explicit_type(value, :boolean) when is_boolean(value) do
    {:ok, {:boolean, value}}
  end

  defp encode_with_explicit_type(value, :opaque) do
    {:ok, {:opaque, value}}
  end

  defp encode_with_explicit_type(nil, :null) do
    {:ok, {:null, :null}}
  end

  defp encode_with_explicit_type(_value, :null) do
    {:ok, {:null, :null}}
  end

  defp encode_with_explicit_type(value, type) do
    {:error, {:unsupported_type_conversion, value, type}}
  end

  defp parse_ip_address(ip_string) do
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, _} -> :error
    end
  end

end