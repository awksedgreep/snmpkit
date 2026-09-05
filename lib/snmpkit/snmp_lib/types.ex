defmodule SnmpKit.SnmpLib.Types do
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
      iex> SnmpKit.SnmpLib.Types.validate_counter32(42)
      :ok
      iex> SnmpKit.SnmpLib.Types.validate_counter32(-1)
      {:error, :out_of_range}

      # Formatting for display
      iex> SnmpKit.SnmpLib.Types.format_timeticks_uptime(4200)
      "42 seconds"
      iex> SnmpKit.SnmpLib.Types.format_ip_address(<<192, 168, 1, 1>>)
      "192.168.1.1"

      # Type coercion
      iex> SnmpKit.SnmpLib.Types.coerce_value(:counter32, 42)
      {:ok, {:counter32, 42}}
      iex> SnmpKit.SnmpLib.Types.coerce_value(:string, "test")
      {:ok, {:string, "test"}}

      # SNMPv2c exception values
      iex> SnmpKit.SnmpLib.Types.coerce_value(:no_such_object, nil)
      {:ok, {:no_such_object, nil}}
      iex> SnmpKit.SnmpLib.Types.coerce_value(:end_of_mib_view, nil)
      {:ok, {:end_of_mib_view, nil}}
  """

  @type snmp_type ::
          :integer
          | :string
          | :null
          | :oid
          | :counter32
          | :gauge32
          | :timeticks
          | :counter64
          | :ip_address
          | :opaque
          | :no_such_object
          | :no_such_instance
          | :end_of_mib_view
          | :unsigned32
          | :octet_string
          | :object_identifier
          | :boolean

  @type snmp_value ::
          integer()
          | binary()
          | :null
          | [non_neg_integer()]
          | {:counter32, non_neg_integer()}
          | {:gauge32, non_neg_integer()}
          | {:timeticks, non_neg_integer()}
          | {:counter64, non_neg_integer()}
          | {:ip_address, binary()}
          | {:opaque, binary()}
          | {:unsigned32, non_neg_integer()}
          | {:no_such_object, nil}
          | {:no_such_instance, nil}
          | {:end_of_mib_view, nil}
          | {:string, binary()}
          | {:octet_string, binary()}
          | {:object_identifier, [non_neg_integer()]}
          | {:boolean, boolean()}

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
      {:ok, {:string, "hello"}} = SnmpKit.SnmpLib.Types.encode_value("hello")
      {:ok, {:integer, 42}} = SnmpKit.SnmpLib.Types.encode_value(42)

      # Explicit type specification
      {:ok, {:ip_address, {192, 168, 1, 1}}} = SnmpKit.SnmpLib.Types.encode_value("192.168.1.1", type: :ip_address)
      {:ok, {:counter32, 100}} = SnmpKit.SnmpLib.Types.encode_value(100, type: :counter32)
  """
  @spec encode_value(term(), keyword()) :: {:ok, {snmp_type(), term()}} | {:error, atom()}
  def encode_value(value, opts \\ []) do
    type =
      case Keyword.get(opts, :type) do
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

      :string = SnmpKit.SnmpLib.Types.infer_type("hello")
      :integer = SnmpKit.SnmpLib.Types.infer_type(42)
      :ip_address = SnmpKit.SnmpLib.Types.infer_type("192.168.1.1")
      :object_identifier = SnmpKit.SnmpLib.Types.infer_type([1, 3, 6, 1, 2, 1])
      :boolean = SnmpKit.SnmpLib.Types.infer_type(true)
  """
  @spec infer_type(term()) :: snmp_type()
  def infer_type(value) when is_integer(value) do
    cond do
      value >= 0 and value <= @max_unsigned32 -> :unsigned32
      value >= @min_integer and value <= @max_integer -> :integer
      value >= 0 and value <= @max_counter64 -> :counter64
      # Let validation catch out-of-range values
      true -> :integer
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
      # It's a charlist, treat as string
      :io_lib.printable_list(value) -> :string
      oid_list?(value) -> :object_identifier
      true -> :unknown
    end
  end

  def infer_type(value) when is_boolean(value), do: :boolean
  def infer_type(:null), do: :null
  def infer_type(nil), do: :null

  def infer_type({a, b, c, d})
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
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

      "hello" = SnmpKit.SnmpLib.Types.decode_value({:string, "hello"})
      "192.168.1.1" = SnmpKit.SnmpLib.Types.decode_value({:ip_address, {192, 168, 1, 1}})
      42 = SnmpKit.SnmpLib.Types.decode_value({:counter32, 42})
      [1, 3, 6, 1] = SnmpKit.SnmpLib.Types.decode_value({:object_identifier, [1, 3, 6, 1]})
  """
  @spec decode_value({snmp_type(), term()} | term()) :: term()
  def decode_value({:string, value}) when is_binary(value), do: value
  # Handle charlists
  def decode_value({:string, value}) when is_list(value), do: List.to_string(value)
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
  # Pass through untyped values
  def decode_value(value), do: value

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

      :ok = SnmpKit.SnmpLib.Types.validate_counter32(42)
      :ok = SnmpKit.SnmpLib.Types.validate_counter32(4294967295)
      {:error, :out_of_range} = SnmpKit.SnmpLib.Types.validate_counter32(-1)
      {:error, :not_integer} = SnmpKit.SnmpLib.Types.validate_counter32("42")
  """
  @spec validate_counter32(term()) :: :ok | {:error, atom()}
  def validate_counter32(value)
      when is_integer(value) and value >= 0 and value <= @max_counter32 do
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
  Validates a Counter64 value.

  Counter64 is a 64-bit unsigned integer for high-speed interfaces.
  """
  @spec validate_counter64(term()) :: :ok | {:error, atom()}
  def validate_counter64(value)
      when is_integer(value) and value >= 0 and value <= @max_counter64 do
    :ok
  end

  def validate_counter64(value) when is_integer(value) do
    {:error, :out_of_range}
  end

  def validate_counter64(_), do: {:error, :not_integer}

  ## Formatting Utilities

  @doc """
  Formats Counter64 value with appropriate units.

  ## Examples

      "42" = SnmpKit.SnmpLib.Types.format_counter64(42)
      "18,446,744,073,709,551,615" = SnmpKit.SnmpLib.Types.format_counter64(18446744073709551615)
  """
  @spec format_counter64(non_neg_integer()) :: binary()
  def format_counter64(value) when is_integer(value) and value >= 0 do
    format_large_number(value)
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

      {:ok, {:counter32, 42}} = SnmpKit.SnmpLib.Types.coerce_value(:counter32, 42)
      {:ok, {:string, "test"}} = SnmpKit.SnmpLib.Types.coerce_value(:string, "test")
      {:ok, {:ip_address, <<192, 168, 1, 1>>}} = SnmpKit.SnmpLib.Types.coerce_value(:ip_address, {192, 168, 1, 1})
  """
  @spec coerce_value(snmp_type(), term()) :: {:ok, snmp_value()} | {:error, atom()}
  def coerce_value(:integer, value) when is_integer(value) do
    case SnmpKit.SnmpLib.Types.Validation.validate_integer(value) do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:string, value) when is_binary(value) do
    case SnmpKit.SnmpLib.Types.Validation.validate_octet_string(value) do
      :ok -> {:ok, {:string, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:null, _) do
    {:ok, :null}
  end

  def coerce_value(:oid, value) when is_list(value) do
    case SnmpKit.SnmpLib.Types.Validation.validate_oid(value) do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:oid, value) when is_binary(value) do
    case SnmpKit.SnmpLib.OID.string_to_list(value) do
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
    case SnmpKit.SnmpLib.Types.Validation.validate_timeticks(value) do
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
    case SnmpKit.SnmpLib.Types.Validation.validate_ip_address(value) do
      :ok -> {:ok, {:ip_address, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:ip_address, {a, b, c, d} = value) do
    case SnmpKit.SnmpLib.Types.Validation.validate_ip_address(value) do
      :ok -> {:ok, {:ip_address, <<a, b, c, d>>}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:opaque, value) when is_binary(value) do
    case SnmpKit.SnmpLib.Types.Validation.validate_opaque(value) do
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
    case SnmpKit.SnmpLib.Types.Validation.validate_octet_string(value) do
      :ok -> {:ok, {:octet_string, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:object_identifier, value) when is_list(value) do
    case SnmpKit.SnmpLib.Types.Validation.validate_oid(value) do
      :ok -> {:ok, {:object_identifier, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(:boolean, value) when is_boolean(value) do
    {:ok, {:boolean, value}}
  end

  def coerce_value(:ip_address, value) when is_binary(value) do
    case SnmpKit.SnmpLib.Types.Format.parse_ip_address(value) do
      {:ok, ip_tuple} -> {:ok, {:ip_address, ip_tuple}}
      {:error, reason} -> {:error, reason}
    end
  end

  def coerce_value(_, _), do: {:error, :unsupported_type}

  @doc """
  Normalizes a type identifier to a consistent format.

  ## Examples

      :counter32 = SnmpKit.SnmpLib.Types.normalize_type("counter32")
      :integer = SnmpKit.SnmpLib.Types.normalize_type(:integer)
      :string = SnmpKit.SnmpLib.Types.normalize_type("octet_string")
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
  def validate_unsigned32(value)
      when is_integer(value) and value >= 0 and value <= @max_unsigned32 do
    :ok
  end

  def validate_unsigned32(value) when is_integer(value) do
    {:error, :out_of_range}
  end

  def validate_unsigned32(_), do: {:error, :not_integer}

  @doc """
  Checks if a type is a numeric SNMP type.

  ## Examples

      true = SnmpKit.SnmpLib.Types.is_numeric_type?(:counter32)
      true = SnmpKit.SnmpLib.Types.is_numeric_type?(:integer)
      false = SnmpKit.SnmpLib.Types.is_numeric_type?(:string)
  """
  @spec is_numeric_type?(snmp_type()) :: boolean()
  def is_numeric_type?(type)
      when type in [:integer, :counter32, :gauge32, :timeticks, :counter64, :unsigned32] do
    true
  end

  def is_numeric_type?(_), do: false

  @doc """
  Checks if a type is a binary SNMP type.

  ## Examples

      true = SnmpKit.SnmpLib.Types.is_binary_type?(:string)
      true = SnmpKit.SnmpLib.Types.is_binary_type?(:opaque)
      false = SnmpKit.SnmpLib.Types.is_binary_type?(:integer)
  """
  @spec is_binary_type?(snmp_type()) :: boolean()
  def is_binary_type?(type) when type in [:string, :octet_string, :opaque, :ip_address] do
    true
  end

  def is_binary_type?(_), do: false

  @doc """
  Checks if a type is an exception SNMP type.

  ## Examples

      true = SnmpKit.SnmpLib.Types.is_exception_type?(:no_such_object)
      false = SnmpKit.SnmpLib.Types.is_exception_type?(:integer)
  """
  @spec is_exception_type?(snmp_type()) :: boolean()
  def is_exception_type?(type)
      when type in [:no_such_object, :no_such_instance, :end_of_mib_view] do
    true
  end

  def is_exception_type?(_), do: false

  @doc """
  Returns the maximum value for a numeric SNMP type.

  ## Examples

      4294967295 = SnmpKit.SnmpLib.Types.max_value(:counter32)
      2147483647 = SnmpKit.SnmpLib.Types.max_value(:integer)
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

      -2147483648 = SnmpKit.SnmpLib.Types.min_value(:integer)
      0 = SnmpKit.SnmpLib.Types.min_value(:counter32)
  """
  @spec min_value(snmp_type()) :: integer() | nil
  def min_value(:integer), do: @min_integer

  def min_value(type) when type in [:counter32, :gauge32, :timeticks, :counter64, :unsigned32],
    do: 0

  def min_value(_), do: nil

  ## Validation and formatting (implemented in Types.Validation / Types.Format)

  defdelegate validate_timeticks(a1), to: SnmpKit.SnmpLib.Types.Validation
  defdelegate validate_ip_address(a1), to: SnmpKit.SnmpLib.Types.Validation
  defdelegate validate_integer(a1), to: SnmpKit.SnmpLib.Types.Validation
  defdelegate validate_octet_string(a1), to: SnmpKit.SnmpLib.Types.Validation
  defdelegate validate_oid(a1), to: SnmpKit.SnmpLib.Types.Validation
  defdelegate validate_opaque(a1), to: SnmpKit.SnmpLib.Types.Validation
  defdelegate format_timeticks_uptime(a1), to: SnmpKit.SnmpLib.Types.Format
  defdelegate format_ip_address(a1), to: SnmpKit.SnmpLib.Types.Format
  defdelegate format_bytes(a1), to: SnmpKit.SnmpLib.Types.Format
  defdelegate format_rate(a1, a2), to: SnmpKit.SnmpLib.Types.Format
  defdelegate truncate_string(a1, a2), to: SnmpKit.SnmpLib.Types.Format
  defdelegate format_hex(a1), to: SnmpKit.SnmpLib.Types.Format
  defdelegate parse_hex_string(a1), to: SnmpKit.SnmpLib.Types.Format
  defdelegate parse_ip_address(a1), to: SnmpKit.SnmpLib.Types.Format

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

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Perform the actual encoding based on type
  defp perform_encoding(value, :string) when is_binary(value), do: {:ok, value}
  defp perform_encoding(value, :string) when is_list(value), do: {:ok, List.to_string(value)}
  defp perform_encoding(value, :octet_string) when is_binary(value), do: {:ok, value}

  defp perform_encoding(value, :octet_string) when is_list(value),
    do: {:ok, List.to_string(value)}

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
  defp perform_encoding(value, :opaque) when is_binary(value), do: {:ok, value}

  # Handle IP address encoding
  defp perform_encoding(value, :ip_address) when is_binary(value) do
    case SnmpKit.SnmpLib.Types.Format.parse_ip_address(value) do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, reason} -> {:error, reason}
    end
  end

  defp perform_encoding({a, b, c, d} = value, :ip_address)
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    {:ok, value}
  end

  defp perform_encoding(<<a, b, c, d>>, :ip_address), do: {:ok, {a, b, c, d}}

  # Handle OID string encoding
  defp perform_encoding(value, :object_identifier) when is_binary(value) do
    case SnmpKit.SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, reason} -> {:error, reason}
    end
  end

  defp perform_encoding(value, :oid) when is_binary(value) do
    case SnmpKit.SnmpLib.OID.string_to_list(value) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, reason} -> {:error, reason}
    end
  end

  defp perform_encoding(_, _), do: {:error, :encoding_failed}

  # Validate encoded values
  defp validate_encoded_value(:string, value),
    do: SnmpKit.SnmpLib.Types.Validation.validate_octet_string(value)

  defp validate_encoded_value(:octet_string, value),
    do: SnmpKit.SnmpLib.Types.Validation.validate_octet_string(value)

  defp validate_encoded_value(:integer, value),
    do: SnmpKit.SnmpLib.Types.Validation.validate_integer(value)

  defp validate_encoded_value(:unsigned32, value), do: validate_unsigned32(value)
  defp validate_encoded_value(:counter32, value), do: validate_counter32(value)
  defp validate_encoded_value(:gauge32, value), do: validate_gauge32(value)

  defp validate_encoded_value(:timeticks, value),
    do: SnmpKit.SnmpLib.Types.Validation.validate_timeticks(value)

  defp validate_encoded_value(:counter64, value), do: validate_counter64(value)

  defp validate_encoded_value(:ip_address, value),
    do: SnmpKit.SnmpLib.Types.Validation.validate_ip_address(value)

  defp validate_encoded_value(:object_identifier, value),
    do: SnmpKit.SnmpLib.Types.Validation.validate_oid(value)

  defp validate_encoded_value(:oid, value),
    do: SnmpKit.SnmpLib.Types.Validation.validate_oid(value)

  defp validate_encoded_value(:opaque, value),
    do: SnmpKit.SnmpLib.Types.Validation.validate_opaque(value)

  defp validate_encoded_value(:boolean, value) when is_boolean(value), do: :ok
  defp validate_encoded_value(:boolean, _), do: {:error, :not_boolean}
  defp validate_encoded_value(:null, _), do: :ok

  # Check if a string looks like an IP address
  defp ip_address_string?(value) when is_binary(value) do
    # Simple regex check before expensive parsing
    if Regex.match?(~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, value) do
      case SnmpKit.SnmpLib.Types.Format.parse_ip_address(value) do
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
      # It's a charlist, not an OID
      false
    else
      # Check if it looks like an OID: non-negative integers, length >= 2
      Enum.all?(list, fn
        x when is_integer(x) and x >= 0 -> true
        _ -> false
      end) and length(list) >= 2
    end
  end

  ## Private Helper Functions

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
