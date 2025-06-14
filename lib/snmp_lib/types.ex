defmodule SnmpLib.Types do
  @moduledoc """
  SNMP data type validation, formatting, and coercion utilities.
  
  Provides comprehensive support for all SNMP data types including validation,
  formatting for display, and type coercion between different representations.
  Includes full support for SNMPv2c exception values.
  
  ## Supported SNMP Types
  
  - **Basic Types**: INTEGER, OCTET STRING, NULL, OBJECT IDENTIFIER
  - **Application Types**: Counter32, Gauge32, TimeTicks, Counter64, IpAddress, Opaque
  - **SNMPv2c Exception Types**: NoSuchObject, NoSuchInstance, EndOfMibView
  - **Constructed Types**: SEQUENCE (for complex structures)
  
  ## SNMPv2c Exception Values
  
  These special values are used in SNMPv2c responses to indicate specific conditions:
  
  - **`:no_such_object`** (0x80): The requested object does not exist in the MIB
  - **`:no_such_instance`** (0x81): The object exists but the specific instance does not
  - **`:end_of_mib_view`** (0x82): End of MIB tree reached during GETBULK/walk operations
  
  ## Features
  
  - Type validation with detailed error reporting
  - Human-readable formatting for logging and display
  - Type coercion and normalization
  - Range checking and constraint validation
  - Performance-optimized operations
  - RFC-compliant exception value handling
  
  ## Examples
  
      # Basic type validation
      iex> SnmpLib.Types.validate_counter32(42)
      :ok
      iex> SnmpLib.Types.validate_counter32(-1)
      {:error, :out_of_range}
      
      # Formatting for display
      iex> SnmpLib.Types.format_timeticks_uptime(4200)
      "42 seconds"
      iex> SnmpLib.Types.format_ip_address(<<192, 168, 1, 1>>)
      "192.168.1.1"
      
      # Type coercion
      iex> SnmpLib.Types.coerce_value(:counter32, 42)
      {:ok, {:counter32, 42}}
      iex> SnmpLib.Types.coerce_value(:string, "test")
      {:ok, {:string, "test"}}
      
      # SNMPv2c exception values
      iex> SnmpLib.Types.coerce_value(:no_such_object, nil)
      {:ok, {:no_such_object, nil}}
      iex> SnmpLib.Types.coerce_value(:end_of_mib_view, nil)
      {:ok, {:end_of_mib_view, nil}}
  """


  @type snmp_type :: :integer | :string | :null | :oid | :counter32 | :gauge32 | 
                    :timeticks | :counter64 | :ip_address | :opaque | :no_such_object |
                    :no_such_instance | :end_of_mib_view | :unsigned32 | :octet_string |
                    :object_identifier | :boolean

  @type snmp_value :: integer() | binary() | :null | [non_neg_integer()] | 
                     {:counter32, non_neg_integer()} | {:gauge32, non_neg_integer()} |
                     {:timeticks, non_neg_integer()} | {:counter64, non_neg_integer()} |
                     {:ip_address, binary()} | {:opaque, binary()} | {:unsigned32, non_neg_integer()} |
                     {:no_such_object, nil} | {:no_such_instance, nil} | {:end_of_mib_view, nil} |
                     {:string, binary()} | {:octet_string, binary()} | {:object_identifier, [non_neg_integer()]} |
                     {:boolean, boolean()}

  # SNMP type ranges and constraints
  @max_integer 2_147_483_647
  @min_integer -2_147_483_648
  @max_counter32 4_294_967_295
  @max_gauge32 4_294_967_295
  @max_timeticks 4_294_967_295
  @max_counter64 18_446_744_073_709_551_615
  @max_unsigned32 4_294_967_295

  ## Enhanced Type System

  @doc """
  Encodes a value with automatic type inference or explicit type specification.
  
  This is the main entry point for encoding values into SNMP types. It supports
  both automatic type inference based on the value and explicit type specification.
  
  ## Parameters
  
  - `value`: The value to encode
  - `opts`: Options including:
    - `:type` - Explicit type specification (overrides inference)
    - `:validate` - Whether to validate the encoded value (default: true)
  
  ## Returns
  
  - `{:ok, {type, encoded_value}}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      # Automatic type inference
      {:ok, {:string, "hello"}} = SnmpLib.Types.encode_value("hello")
      {:ok, {:integer, 42}} = SnmpLib.Types.encode_value(42)
      
      # Explicit type specification
      {:ok, {:ip_address, {192, 168, 1, 1}}} = SnmpLib.Types.encode_value("192.168.1.1", type: :ip_address)
      {:ok, {:counter32, 100}} = SnmpLib.Types.encode_value(100, type: :counter32)
  """
  @spec encode_value(term(), keyword()) :: {:ok, {snmp_type(), term()}} | {:error, atom()}
  def encode_value(value, opts \\ []) do
    type = case Keyword.get(opts, :type) do
      nil -> infer_type(value)
      explicit_type -> normalize_type(explicit_type)
    end
    
    case type do
      :unknown -> {:error, :cannot_infer_type}
      _ -> encode_value_with_type(value, type, opts)
    end
  end
  
  @doc """
  Automatically infers the SNMP type from an Elixir value.
  
  Uses intelligent heuristics to determine the most appropriate SNMP type
  for a given Elixir value.
  
  ## Examples
  
      :string = SnmpLib.Types.infer_type("hello")
      :integer = SnmpLib.Types.infer_type(42)
      :ip_address = SnmpLib.Types.infer_type("192.168.1.1")
      :object_identifier = SnmpLib.Types.infer_type([1, 3, 6, 1, 2, 1])
      :boolean = SnmpLib.Types.infer_type(true)
  """
  @spec infer_type(term()) :: snmp_type()
  def infer_type(value) when is_integer(value) do
    cond do
      value >= 0 and value <= @max_unsigned32 -> :unsigned32
      value >= @min_integer and value <= @max_integer -> :integer
      value >= 0 and value <= @max_counter64 -> :counter64
      true -> :integer  # Let validation catch out-of-range values
    end
  end
  
  def infer_type(value) when is_binary(value) do
    cond do
      String.printable?(value) and ip_address_string?(value) -> :ip_address
      String.printable?(value) -> :string
      true -> :octet_string
    end
  end
  
  def infer_type(value) when is_list(value) do
    cond do
      :io_lib.printable_list(value) -> :string  # It's a charlist, treat as string
      oid_list?(value) -> :object_identifier
      true -> :unknown
    end
  end
  
  def infer_type(value) when is_boolean(value), do: :boolean
  def infer_type(:null), do: :null
  def infer_type(nil), do: :null
  def infer_type({a, b, c, d}) when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    if a >= 0 and a <= 255 and b >= 0 and b <= 255 and c >= 0 and c <= 255 and d >= 0 and d <= 255 do
      :ip_address
    else
      :unknown
    end
  end
  def infer_type(_), do: :unknown
  
  @doc """
  Decodes an SNMP typed value back to a native Elixir value.
  
  Converts SNMP-encoded values back to their most natural Elixir representation,
  with consistent handling of strings (always returns binaries, not charlists).
  
  ## Parameters
  
  - `typed_value`: A tuple of `{type, value}` or just a value
  
  ## Returns
  
  The decoded Elixir value in its most natural form
  
  ## Examples
  
      "hello" = SnmpLib.Types.decode_value({:string, "hello"})
      "192.168.1.1" = SnmpLib.Types.decode_value({:ip_address, {192, 168, 1, 1}})
      42 = SnmpLib.Types.decode_value({:counter32, 42})
      [1, 3, 6, 1] = SnmpLib.Types.decode_value({:object_identifier, [1, 3, 6, 1]})
  """
  @spec decode_value({snmp_type(), term()} | term()) :: term()
  def decode_value({:string, value}) when is_binary(value), do: value
  def decode_value({:string, value}) when is_list(value), do: List.to_string(value)  # Handle charlists
  def decode_value({:octet_string, value}) when is_binary(value), do: value
  def decode_value({:octet_string, value}) when is_list(value), do: List.to_string(value)
  def decode_value({:integer, value}), do: value
  def decode_value({:unsigned32, value}), do: value
  def decode_value({:counter32, value}), do: value
  def decode_value({:gauge32, value}), do: value
  def decode_value({:timeticks, value}), do: value
  def decode_value({:counter64, value}), do: value
  def decode_value({:boolean, value}), do: value
  def decode_value({:null, _}), do: nil
  def decode_value({:ip_address, {a, b, c, d}}), do: "#{a}.#{b}.#{c}.#{d}"
  def decode_value({:ip_address, <<a, b, c, d>>}), do: "#{a}.#{b}.#{c}.#{d}"
  def decode_value({:object_identifier, value}) when is_list(value), do: value
  def decode_value({:oid, value}) when is_list(value), do: value
  def decode_value({:opaque, value}), do: value
  def decode_value({:no_such_object, _}), do: :no_such_object
  def decode_value({:no_such_instance, _}), do: :no_such_instance
  def decode_value({:end_of_mib_view, _}), do: :end_of_mib_view
  def decode_value(value), do: value  # Pass through untyped values
  
  @doc """
  Parses an IP address string into a 4-tuple of integers.
  
  ## Parameters
  
  - `ip_string`: IP address as a string like "192.168.1.1"
  
  ## Returns
  
  - `{:ok, {a, b, c, d}}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      {:ok, {192, 168, 1, 1}} = SnmpLib.Types.parse_ip_address("192.168.1.1")
      {:ok, {127, 0, 0, 1}} = SnmpLib.Types.parse_ip_address("127.0.0.1")
      {:error, :invalid_format} = SnmpLib.Types.parse_ip_address("invalid")
  """
  @spec parse_ip_address(binary()) :: {:ok, {0..255, 0..255, 0..255, 0..255}} | {:error, atom()}
  def parse_ip_address(ip_string) when is_binary(ip_string) do
    try do
      case :inet.parse_address(String.to_charlist(ip_string)) do
        {:ok, {a, b, c, d}} when a >= 0 and a <= 255 and b >= 0 and b <= 255 and
                                 c >= 0 and c <= 255 and d >= 0 and d <= 255 ->
          {:ok, {a, b, c, d}}
        {:ok, _} ->
          {:error, :not_ipv4}
        {:error, _} ->
          {:error, :invalid_format}
      end
    rescue
      _ -> {:error, :invalid_format}
    end
  end
  def parse_ip_address(_), do: {:error, :invalid_input}

  ## Type Validation

  @doc """
  Validates a Counter32 value.
  
  Counter32 is a 32-bit unsigned integer that wraps around when it reaches its maximum value.
  
  ## Parameters
  
  - `value`: Value to validate
  
  ## Returns
  
  - `:ok` if valid
  - `{:error, reason}` if invalid
  
  ## Examples
  
      :ok = SnmpLib.Types.validate_counter32(42)
      :ok = SnmpLib.Types.validate_counter32(4294967295)
      {:error, :out_of_range} = SnmpLib.Types.validate_counter32(-1)
      {:error, :not_integer} = SnmpLib.Types.validate_counter32("42")
  """
  @spec validate_counter32(term()) :: :ok | {:error, atom()}
  def validate_counter32(value) when is_integer(value) and value >= 0 and value <= @max_counter32 do
    :ok
  end
  def validate_counter32(value) when is_integer(value) do
    {:error, :out_of_range}
  end
  def validate_counter32(_), do: {:error, :not_integer}

  @doc """
  Validates a Gauge32 value.
  
  Gauge32 is a 32-bit unsigned integer that represents a non-negative integer value.
  Unlike Counter32, it does not wrap around.
  """
  @spec validate_gauge32(term()) :: :ok | {:error, atom()}
  def validate_gauge32(value) when is_integer(value) and value >= 0 and value <= @max_gauge32 do
    :ok
  end
  def validate_gauge32(value) when is_integer(value) do
    {:error, :out_of_range}
  end
  def validate_gauge32(_), do: {:error, :not_integer}

  @doc """
  Validates a TimeTicks value.
  
  TimeTicks represents time in hundredths of a second (centiseconds).
  """
  @spec validate_timeticks(term()) :: :ok | {:error, atom()}
  def validate_timeticks(value) when is_integer(value) and value >= 0 and value <= @max_timeticks do
    :ok
  end
  def validate_timeticks(value) when is_integer(value) do
    {:error, :out_of_range}
  end
  def validate_timeticks(_), do: {:error, :not_integer}

  @doc """
  Validates a Counter64 value.
  
  Counter64 is a 64-bit unsigned integer for high-speed interfaces.
  """
  @spec validate_counter64(term()) :: :ok | {:error, atom()}
  def validate_counter64(value) when is_integer(value) and value >= 0 and value <= @max_counter64 do
    :ok
  end
  def validate_counter64(value) when is_integer(value) do
    {:error, :out_of_range}
  end
  def validate_counter64(_), do: {:error, :not_integer}

  @doc """
  Validates an IP address value.
  
  IP address should be a 4-byte binary or a tuple of 4 integers.
  
  ## Examples
  
      :ok = SnmpLib.Types.validate_ip_address(<<192, 168, 1, 1>>)
      :ok = SnmpLib.Types.validate_ip_address({192, 168, 1, 1})
      {:error, :invalid_length} = SnmpLib.Types.validate_ip_address(<<192, 168, 1>>)
  """
  @spec validate_ip_address(term()) :: :ok | {:error, atom()}
  def validate_ip_address(<<a, b, c, d>>) when a <= 255 and b <= 255 and c <= 255 and d <= 255 do
    :ok
  end
  def validate_ip_address({a, b, c, d}) when is_integer(a) and is_integer(b) and 
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
        4 -> {:error, :invalid_format}  # Valid length but invalid values  
        _ -> {:error, :invalid_length}  # Wrong length
      end
    end
  end
  def validate_ip_address(_), do: {:error, :invalid_format}

  @doc """
  Validates an SNMP integer value.
  
  SNMP INTEGER is a signed 32-bit integer.
  """
  @spec validate_integer(term()) :: :ok | {:error, atom()}
  def validate_integer(value) when is_integer(value) and value >= @min_integer and value <= @max_integer do
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
    case SnmpLib.OID.valid_oid?(oid) do
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

  ## Formatting Utilities

  @doc """
  Formats TimeTicks as human-readable uptime string.
  
  ## Parameters
  
  - `centiseconds`: Time in centiseconds (hundredths of a second)
  
  ## Returns
  
  - Human-readable uptime string
  
  ## Examples
  
      "42 centiseconds" = SnmpLib.Types.format_timeticks_uptime(42)
      "1 second 50 centiseconds" = SnmpLib.Types.format_timeticks_uptime(150)
      "1 minute 30 seconds" = SnmpLib.Types.format_timeticks_uptime(9000)
      "2 hours 15 minutes 30 seconds" = SnmpLib.Types.format_timeticks_uptime(81300)
  """
  @spec format_timeticks_uptime(non_neg_integer()) :: binary()
  def format_timeticks_uptime(centiseconds) when is_integer(centiseconds) and centiseconds >= 0 do
    total_seconds = div(centiseconds, 100)
    remaining_centiseconds = rem(centiseconds, 100)
    
    format_time_components(total_seconds, remaining_centiseconds)
  end

  @doc """
  Formats Counter64 value with appropriate units.
  
  ## Examples
  
      "42" = SnmpLib.Types.format_counter64(42)
      "18,446,744,073,709,551,615" = SnmpLib.Types.format_counter64(18446744073709551615)
  """
  @spec format_counter64(non_neg_integer()) :: binary()
  def format_counter64(value) when is_integer(value) and value >= 0 do
    format_large_number(value)
  end

  @doc """
  Formats an IP address from binary format.
  
  ## Examples
  
      "192.168.1.1" = SnmpLib.Types.format_ip_address(<<192, 168, 1, 1>>)
      "0.0.0.0" = SnmpLib.Types.format_ip_address(<<0, 0, 0, 0>>)
  """
  @spec format_ip_address(binary()) :: binary()
  def format_ip_address(<<a, b, c, d>>) do
    "#{a}.#{b}.#{c}.#{d}"
  end
  def format_ip_address(_), do: "invalid"

  @doc """
  Formats bytes as human-readable size.
  
  ## Examples
  
      "1.5 KB" = SnmpLib.Types.format_bytes(1536)
      "2.3 MB" = SnmpLib.Types.format_bytes(2400000)
  """
  @spec format_bytes(non_neg_integer()) :: binary()
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes < 1024 ->
        "#{bytes} B"
      bytes < 1024 * 1024 ->
        kb = Float.round(bytes / 1024, 1)
        "#{kb} KB"
      bytes < 1024 * 1024 * 1024 ->
        mb = Float.round(bytes / (1024 * 1024), 1)
        "#{mb} MB"
      true ->
        gb = Float.round(bytes / (1024 * 1024 * 1024), 1)
        "#{gb} GB"
    end
  end

  @doc """
  Formats a rate value with units.
  
  ## Examples
  
      "100 bps" = SnmpLib.Types.format_rate(100, "bps")
      "1.5 Mbps" = SnmpLib.Types.format_rate(1500000, "bps")
  """
  @spec format_rate(number(), binary()) :: binary()
  def format_rate(value, unit) when is_number(value) and is_binary(unit) do
    cond do
      value < 1_000 ->
        "#{value} #{unit}"
      value < 1_000_000 ->
        k_value = Float.round(value / 1_000, 1)
        "#{k_value} K#{unit}"
      value < 1_000_000_000 ->
        m_value = Float.round(value / 1_000_000, 1)
        "#{m_value} M#{unit}"
      true ->
        g_value = Float.round(value / 1_000_000_000, 1)
        "#{g_value} G#{unit}"
    end
  end

  @doc """
  Truncates a string to a maximum length with ellipsis.
  
  ## Examples
  
      "hello" = SnmpLib.Types.truncate_string("hello", 10)
      "hello..." = SnmpLib.Types.truncate_string("hello world", 8)
  """
  @spec truncate_string(binary(), pos_integer()) :: binary()
  def truncate_string(string, max_length) when is_binary(string) and is_integer(max_length) and max_length > 3 do
    if String.length(string) <= max_length do
      string
    else
      truncated = String.slice(string, 0, max_length - 3)
      "#{truncated}..."
    end
  end
  def truncate_string(string, max_length) when is_binary(string) and is_integer(max_length) do
    String.slice(string, 0, max(max_length, 0))
  end

  @doc """
  Formats binary data as hexadecimal string.
  
  ## Examples
  
      "48656C6C6F" = SnmpLib.Types.format_hex(<<"Hello">>)
      "DEADBEEF" = SnmpLib.Types.format_hex(<<0xDE, 0xAD, 0xBE, 0xEF>>)
  """
  @spec format_hex(binary()) :: binary()
  def format_hex(binary) when is_binary(binary) do
    Base.encode16(binary)
  end

  @doc """
  Parses a hexadecimal string to binary.
  
  ## Examples
  
      {:ok, <<"Hello">>} = SnmpLib.Types.parse_hex_string("48656C6C6F")
      {:error, :invalid_hex} = SnmpLib.Types.parse_hex_string("XYZ")
  """
  @spec parse_hex_string(binary()) :: {:ok, binary()} | {:error, atom()}
  def parse_hex_string(hex_string) when is_binary(hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_hex}
    end
  end

  ## Type Coercion

  @doc """
  Coerces a value to the specified SNMP type.
  
  ## Parameters
  
  - `type`: Target SNMP type
  - `raw_value`: Value to coerce
  
  ## Returns
  
  - `{:ok, typed_value}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      {:ok, {:counter32, 42}} = SnmpLib.Types.coerce_value(:counter32, 42)
      {:ok, {:string, "test"}} = SnmpLib.Types.coerce_value(:string, "test")
      {:ok, {:ip_address, <<192, 168, 1, 1>>}} = SnmpLib.Types.coerce_value(:ip_address, {192, 168, 1, 1})
  """
  @spec coerce_value(snmp_type(), term()) :: {:ok, snmp_value()} | {:error, atom()}
  def coerce_value(:integer, value) when is_integer(value) do
    case validate_integer(value) do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:string, value) when is_binary(value) do
    case validate_octet_string(value) do
      :ok -> {:ok, {:string, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:null, _) do
    {:ok, :null}
  end

  def coerce_value(:oid, value) when is_list(value) do
    case validate_oid(value) do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:oid, value) when is_binary(value) do
    case SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:counter32, value) when is_integer(value) do
    case validate_counter32(value) do
      :ok -> {:ok, {:counter32, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:gauge32, value) when is_integer(value) do
    case validate_gauge32(value) do
      :ok -> {:ok, {:gauge32, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:timeticks, value) when is_integer(value) do
    case validate_timeticks(value) do
      :ok -> {:ok, {:timeticks, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:counter64, value) when is_integer(value) do
    case validate_counter64(value) do
      :ok -> {:ok, {:counter64, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:ip_address, <<_::32>> = value) do
    case validate_ip_address(value) do
      :ok -> {:ok, {:ip_address, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:ip_address, {a, b, c, d} = value) do
    case validate_ip_address(value) do
      :ok -> {:ok, {:ip_address, <<a, b, c, d>>}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:opaque, value) when is_binary(value) do
    case validate_opaque(value) do
      :ok -> {:ok, {:opaque, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:no_such_object, _) do
    {:ok, {:no_such_object, nil}}
  end

  def coerce_value(:no_such_instance, _) do
    {:ok, {:no_such_instance, nil}}
  end

  def coerce_value(:end_of_mib_view, _) do
    {:ok, {:end_of_mib_view, nil}}
  end

  def coerce_value(:unsigned32, value) when is_integer(value) do
    case validate_unsigned32(value) do
      :ok -> {:ok, {:unsigned32, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:octet_string, value) when is_binary(value) do
    case validate_octet_string(value) do
      :ok -> {:ok, {:octet_string, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:object_identifier, value) when is_list(value) do
    case validate_oid(value) do
      :ok -> {:ok, {:object_identifier, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:boolean, value) when is_boolean(value) do
    {:ok, {:boolean, value}}
  end

  def coerce_value(:ip_address, value) when is_binary(value) do
    case parse_ip_address(value) do
      {:ok, ip_tuple} -> {:ok, {:ip_address, ip_tuple}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(_, _), do: {:error, :unsupported_type}

  @doc """
  Normalizes a type identifier to a consistent format.
  
  ## Examples
  
      :counter32 = SnmpLib.Types.normalize_type("counter32")
      :integer = SnmpLib.Types.normalize_type(:integer)
      :string = SnmpLib.Types.normalize_type("octet_string")
  """
  @spec normalize_type(term()) :: snmp_type() | :unknown
  def normalize_type(type) when is_atom(type), do: type
  def normalize_type("integer"), do: :integer
  def normalize_type("string"), do: :string
  def normalize_type("octet_string"), do: :string
  def normalize_type("null"), do: :null
  def normalize_type("oid"), do: :oid
  def normalize_type("object_identifier"), do: :object_identifier
  def normalize_type("counter32"), do: :counter32
  def normalize_type("gauge32"), do: :gauge32
  def normalize_type("timeticks"), do: :timeticks
  def normalize_type("counter64"), do: :counter64
  def normalize_type("ip_address"), do: :ip_address
  def normalize_type("ipaddress"), do: :ip_address
  def normalize_type("opaque"), do: :opaque
  def normalize_type("no_such_object"), do: :no_such_object
  def normalize_type("no_such_instance"), do: :no_such_instance
  def normalize_type("end_of_mib_view"), do: :end_of_mib_view
  def normalize_type("unsigned32"), do: :unsigned32
  def normalize_type("boolean"), do: :boolean
  def normalize_type(_), do: :unknown

  ## Utility Functions

  @doc """
  Validates an Unsigned32 value.
  
  Unsigned32 is a 32-bit unsigned integer.
  """
  @spec validate_unsigned32(term()) :: :ok | {:error, atom()}
  def validate_unsigned32(value) when is_integer(value) and value >= 0 and value <= @max_unsigned32 do
    :ok
  end
  def validate_unsigned32(value) when is_integer(value) do
    {:error, :out_of_range}
  end
  def validate_unsigned32(_), do: {:error, :not_integer}

  @doc """
  Checks if a type is a numeric SNMP type.
  
  ## Examples
  
      true = SnmpLib.Types.is_numeric_type?(:counter32)
      true = SnmpLib.Types.is_numeric_type?(:integer)
      false = SnmpLib.Types.is_numeric_type?(:string)
  """
  @spec is_numeric_type?(snmp_type()) :: boolean()
  def is_numeric_type?(type) when type in [:integer, :counter32, :gauge32, :timeticks, :counter64, :unsigned32] do
    true
  end
  def is_numeric_type?(_), do: false

  @doc """
  Checks if a type is a binary SNMP type.
  
  ## Examples
  
      true = SnmpLib.Types.is_binary_type?(:string)
      true = SnmpLib.Types.is_binary_type?(:opaque)
      false = SnmpLib.Types.is_binary_type?(:integer)
  """
  @spec is_binary_type?(snmp_type()) :: boolean()
  def is_binary_type?(type) when type in [:string, :octet_string, :opaque, :ip_address] do
    true
  end
  def is_binary_type?(_), do: false

  @doc """
  Checks if a type is an exception SNMP type.
  
  ## Examples
  
      true = SnmpLib.Types.is_exception_type?(:no_such_object)
      false = SnmpLib.Types.is_exception_type?(:integer)
  """
  @spec is_exception_type?(snmp_type()) :: boolean()
  def is_exception_type?(type) when type in [:no_such_object, :no_such_instance, :end_of_mib_view] do
    true
  end
  def is_exception_type?(_), do: false

  @doc """
  Returns the maximum value for a numeric SNMP type.
  
  ## Examples
  
      4294967295 = SnmpLib.Types.max_value(:counter32)
      2147483647 = SnmpLib.Types.max_value(:integer)
  """
  @spec max_value(snmp_type()) :: non_neg_integer() | nil
  def max_value(:integer), do: @max_integer
  def max_value(:counter32), do: @max_counter32
  def max_value(:gauge32), do: @max_gauge32
  def max_value(:timeticks), do: @max_timeticks
  def max_value(:counter64), do: @max_counter64
  def max_value(:unsigned32), do: @max_unsigned32
  def max_value(_), do: nil

  @doc """
  Returns the minimum value for a numeric SNMP type.
  
  ## Examples
  
      -2147483648 = SnmpLib.Types.min_value(:integer)
      0 = SnmpLib.Types.min_value(:counter32)
  """
  @spec min_value(snmp_type()) :: integer() | nil
  def min_value(:integer), do: @min_integer
  def min_value(type) when type in [:counter32, :gauge32, :timeticks, :counter64, :unsigned32], do: 0
  def min_value(_), do: nil

  ## Private Implementation for Enhanced Type System
  
  # Encode value with a specific type
  defp encode_value_with_type(value, type, opts) do
    validate = Keyword.get(opts, :validate, true)
    
    case perform_encoding(value, type) do
      {:ok, encoded_value} ->
        if validate do
          case validate_encoded_value(type, encoded_value) do
            :ok -> {:ok, {type, encoded_value}}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, {type, encoded_value}}
        end
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Perform the actual encoding based on type
  defp perform_encoding(value, :string) when is_binary(value), do: {:ok, value}
  defp perform_encoding(value, :string) when is_list(value), do: {:ok, List.to_string(value)}
  defp perform_encoding(value, :octet_string) when is_binary(value), do: {:ok, value}
  defp perform_encoding(value, :octet_string) when is_list(value), do: {:ok, List.to_string(value)}
  defp perform_encoding(value, :integer) when is_integer(value), do: {:ok, value}
  defp perform_encoding(value, :unsigned32) when is_integer(value), do: {:ok, value}
  defp perform_encoding(value, :counter32) when is_integer(value), do: {:ok, value}
  defp perform_encoding(value, :gauge32) when is_integer(value), do: {:ok, value}
  defp perform_encoding(value, :timeticks) when is_integer(value), do: {:ok, value}
  defp perform_encoding(value, :counter64) when is_integer(value), do: {:ok, value}
  defp perform_encoding(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp perform_encoding(value, :object_identifier) when is_list(value), do: {:ok, value}
  defp perform_encoding(value, :oid) when is_list(value), do: {:ok, value}
  defp perform_encoding(_value, :null), do: {:ok, nil}
  defp perform_encoding(nil, :null), do: {:ok, nil}
  defp perform_encoding(:null, :null), do: {:ok, nil}
  defp perform_encoding(value, :opaque) when is_binary(value), do: {:ok, value}
  
  # Handle IP address encoding
  defp perform_encoding(value, :ip_address) when is_binary(value) do
    case parse_ip_address(value) do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, reason} -> {:error, reason}
    end
  end
  defp perform_encoding({a, b, c, d} = value, :ip_address) when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    {:ok, value}
  end
  defp perform_encoding(<<a, b, c, d>>, :ip_address), do: {:ok, {a, b, c, d}}
  
  # Handle OID string encoding
  defp perform_encoding(value, :object_identifier) when is_binary(value) do
    case SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, reason} -> {:error, reason}
    end
  end
  defp perform_encoding(value, :oid) when is_binary(value) do
    case SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp perform_encoding(_, _), do: {:error, :encoding_failed}
  
  # Validate encoded values
  defp validate_encoded_value(:string, value), do: validate_octet_string(value)
  defp validate_encoded_value(:octet_string, value), do: validate_octet_string(value)
  defp validate_encoded_value(:integer, value), do: validate_integer(value)
  defp validate_encoded_value(:unsigned32, value), do: validate_unsigned32(value)
  defp validate_encoded_value(:counter32, value), do: validate_counter32(value)
  defp validate_encoded_value(:gauge32, value), do: validate_gauge32(value)
  defp validate_encoded_value(:timeticks, value), do: validate_timeticks(value)
  defp validate_encoded_value(:counter64, value), do: validate_counter64(value)
  defp validate_encoded_value(:ip_address, value), do: validate_ip_address(value)
  defp validate_encoded_value(:object_identifier, value), do: validate_oid(value)
  defp validate_encoded_value(:oid, value), do: validate_oid(value)
  defp validate_encoded_value(:opaque, value), do: validate_opaque(value)
  defp validate_encoded_value(:boolean, value) when is_boolean(value), do: :ok
  defp validate_encoded_value(:boolean, _), do: {:error, :not_boolean}
  defp validate_encoded_value(:null, _), do: :ok
  defp validate_encoded_value(_, _), do: :ok
  
  # Check if a string looks like an IP address
  defp ip_address_string?(value) when is_binary(value) do
    # Simple regex check before expensive parsing
    if Regex.match?(~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, value) do
      case parse_ip_address(value) do
        {:ok, _} -> true
        _ -> false
      end
    else
      false
    end
  end
  
  # Check if a list looks like an OID (not a charlist)
  defp oid_list?(list) when is_list(list) do
    # Check if it's a valid charlist first (printable ASCII range)
    if :io_lib.printable_list(list) do
      false  # It's a charlist, not an OID
    else
      # Check if it looks like an OID: non-negative integers, length >= 2
      Enum.all?(list, fn
        x when is_integer(x) and x >= 0 -> true
        _ -> false
      end) and length(list) >= 2
    end
  end
  defp oid_list?(_), do: false

  ## Private Helper Functions

  defp format_time_components(0, 0), do: "0 centiseconds"
  defp format_time_components(0, centiseconds), do: "#{centiseconds} centiseconds"
  defp format_time_components(total_seconds, centiseconds) do
    days = div(total_seconds, 86400)
    remaining_seconds = rem(total_seconds, 86400)
    hours = div(remaining_seconds, 3600)
    remaining_seconds = rem(remaining_seconds, 3600)
    minutes = div(remaining_seconds, 60)
    seconds = rem(remaining_seconds, 60)
    
    parts = []
    parts = if days > 0, do: ["#{days} day#{plural(days)}" | parts], else: parts
    parts = if hours > 0, do: ["#{hours} hour#{plural(hours)}" | parts], else: parts
    parts = if minutes > 0, do: ["#{minutes} minute#{plural(minutes)}" | parts], else: parts
    parts = if seconds > 0, do: ["#{seconds} second#{plural(seconds)}" | parts], else: parts
    parts = if centiseconds > 0, do: ["#{centiseconds} centisecond#{plural(centiseconds)}" | parts], else: parts
    
    case Enum.reverse(parts) do
      [] -> "0 centiseconds"
      [single] -> single
      parts -> Enum.join(parts, " ")
    end
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"

  defp format_large_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join(&1, ""))
    |> Enum.join(",")
    |> String.reverse()
  end
end