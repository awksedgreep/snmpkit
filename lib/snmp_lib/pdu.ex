defmodule SnmpKit.SnmpLib.PDU do
  @moduledoc """
  SNMP PDU (Protocol Data Unit) encoding and decoding with RFC compliance.

  Provides comprehensive SNMP PDU functionality combining the best features from
  multiple SNMP implementations. Supports SNMPv1 and SNMPv2c protocols with
  high-performance encoding/decoding, robust error handling, and full RFC compliance.

  ## API Documentation

  ### PDU Structure

  All PDU functions in this library use a **consistent map structure** with these fields:

  ```elixir
  %{
    type: :get_request | :get_next_request | :get_response | :set_request | :get_bulk_request,
    request_id: non_neg_integer(),
    error_status: 0..5,
    error_index: non_neg_integer(),
    varbinds: [varbind()],
    # GETBULK only:
    non_repeaters: non_neg_integer(),      # Optional, GETBULK requests only
    max_repetitions: non_neg_integer()     # Optional, GETBULK requests only
  }
  ```

  **IMPORTANT**: Always use the `:type` field (not `:pdu_type`) with atom values.

  ### Variable Bindings Format

  Variable bindings (`varbinds`) support two formats:

  - **2-tuple format**: `{oid, value}` - Used for responses and simple cases
  - **3-tuple format**: `{oid, type, value}` - Used for requests with explicit type info

  ```elixir
  # Request varbinds (3-tuple with type information)
  [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null}]

  # Response varbinds (2-tuple format)
  [{[1, 3, 6, 1, 2, 1, 1, 1, 0], "Linux server"}]

  # Response varbinds (3-tuple format also supported)
  [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Linux server"}]
  ```

  ### Message Structure

  SNMP messages have this structure:

  ```elixir
  %{
    version: 0 | 1,           # 0 = SNMPv1, 1 = SNMPv2c
    community: binary(),      # Community string
    pdu: pdu()               # PDU map as described above
  }
  ```

  ## Examples

  ### Building PDUs

  ```elixir
  # GET request for system description
  {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 123)

  # GETBULK request for interface table
  {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_get_bulk_request([1, 3, 6, 1, 2, 1, 2, 2, 1], 124, 0, 10)

  # SET request
  {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_set_request([1, 3, 6, 1, 2, 1, 1, 5, 0], {:octet_string, "New Name"}, 125)
  ```

  ### Building Messages

  ```elixir
  # Complete SNMP message
  {:ok, message} = SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v2c)

  # Encode to binary
  {:ok, packet} = SnmpKit.SnmpLib.PDU.encode_message(message)

  # Decode from binary
  {:ok, decoded_message} = SnmpKit.SnmpLib.PDU.decode_message(packet)
  ```

  ### Error Responses

  ```elixir
  # Create error response
  error_pdu = SnmpKit.SnmpLib.PDU.create_error_response(original_pdu, :no_such_name, 1)
  ```
  """

  alias SnmpKit.SnmpLib.PDU.{Constants, Builder, Encoder, Decoder}

  # Re-export types from Constants
  @type message :: Constants.message()
  @type pdu :: Constants.pdu()
  @type varbind :: Constants.varbind()
  @type oid :: Constants.oid()
  @type snmp_value :: Constants.snmp_value()
  @type snmp_type :: Constants.snmp_type()
  @type error_status :: Constants.error_status()

  ## Public API - Encoding/Decoding

  @doc """
  Encodes an SNMP message to binary format.

  ## Examples

      iex> message = %{version: 1, community: "public", pdu: %{type: :get_request, request_id: 123, error_status: 0, error_index: 0, varbinds: []}}
      iex> {:ok, _binary} = SnmpKit.SnmpLib.PDU.encode_message(message)
  """
  @spec encode_message(message()) :: {:ok, binary()} | {:error, atom()}
  def encode_message(message), do: Encoder.encode_message(message)

  @doc """
  Decodes an SNMP message from binary format.

  ## Examples

      iex> {:ok, binary} = SnmpKit.SnmpLib.PDU.encode_message(%{version: 1, community: "public", pdu: %{type: :get_request, request_id: 123, error_status: 0, error_index: 0, varbinds: []}})
      iex> {:ok, _message} = SnmpKit.SnmpLib.PDU.decode_message(binary)
  """
  @spec decode_message(binary()) :: {:ok, message()} | {:error, atom()}
  def decode_message(data), do: Decoder.decode_message(data)

  @doc """
  Alias for encode_message/1.
  """
  @spec encode(message()) :: {:ok, binary()} | {:error, atom()}
  def encode(message), do: Encoder.encode(message)

  @doc """
  Alias for decode_message/1.
  """
  @spec decode(binary()) :: {:ok, message()} | {:error, atom()}
  def decode(data), do: Decoder.decode(data)

  @doc """
  Legacy alias for encode/1.
  """
  @spec encode_snmp_packet(message()) :: {:ok, binary()} | {:error, atom()}
  def encode_snmp_packet(message), do: Encoder.encode_snmp_packet(message)

  @doc """
  Legacy alias for decode/1.
  """
  @spec decode_snmp_packet(binary()) :: {:ok, message()} | {:error, atom()}
  def decode_snmp_packet(data), do: Decoder.decode_snmp_packet(data)

  ## Public API - Building PDUs and Messages

  @doc """
  Builds a GET request PDU.

  ## Parameters

  - `oid`: Single OID as list of integers
  - `request_id`: Unique request identifier

  ## Examples

      iex> {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 123)
      iex> pdu.type
      :get_request
  """
  @spec build_get_request(oid(), non_neg_integer()) :: pdu()
  def build_get_request(oid, request_id), do: Builder.build_get_request(oid, request_id)

  @doc """
  Builds a GET request PDU with multiple varbinds.

  ## Parameters

  - `varbinds`: List of variable bindings in format `{oid, type, value}`
  - `request_id`: Unique request identifier

  ## Examples

      iex> varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null}]
      iex> {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_get_request_multi(varbinds, 123)
      iex> pdu.type
      :get_request
  """
  @spec build_get_request_multi([varbind()], non_neg_integer()) :: pdu()
  def build_get_request_multi(varbinds, request_id) do
    Builder.build_get_request_multi(varbinds, request_id)
  end

  @doc """
  Builds a GETNEXT request PDU.

  ## Parameters

  - `oid_or_oids`: Single OID list or list of OID lists to request
  - `request_id`: Unique request identifier

  ## Examples

      iex> {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_get_next_request([1, 3, 6, 1, 2, 1, 1], 124)
      iex> pdu.type
      :get_next_request
  """
  @spec build_get_next_request(oid() | [oid()], non_neg_integer()) :: pdu()
  def build_get_next_request(oid_or_oids, request_id),
    do: Builder.build_get_next_request(oid_or_oids, request_id)

  @doc """
  Builds a GETBULK request PDU (SNMPv2c only).

  ## Parameters

  - `oid_list`: Single OID list or list of OID lists to request
  - `request_id`: Unique request identifier
  - `non_repeaters`: Number of non-repeating variables (default: 0)
  - `max_repetitions`: Maximum repetitions for repeating variables (default: 10)

  ## Examples

      iex> {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_get_bulk_request([1, 3, 6, 1, 2, 1, 2, 2, 1], 125, 0, 10)
      iex> pdu.type
      :get_bulk_request
  """
  @spec build_get_bulk_request(
          oid() | [oid()],
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: pdu()
  def build_get_bulk_request(oid_list, request_id, non_repeaters \\ 0, max_repetitions \\ 10) do
    Builder.build_get_bulk_request(oid_list, request_id, non_repeaters, max_repetitions)
  end

  @doc """
  Builds a SET request PDU.

  ## Parameters

  - `oid_list`: Single OID as list of integers
  - `type_value`: Tuple of `{type, value}` for the SET operation
  - `request_id`: Unique request identifier

  ## Examples

      iex> {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_set_request([1, 3, 6, 1, 2, 1, 1, 5, 0], {:octet_string, "New Name"}, 126)
      iex> pdu.type
      :set_request
  """
  @spec build_set_request(oid(), {atom(), any()}, non_neg_integer()) :: pdu()
  def build_set_request(oid_list, type_value, request_id),
    do: Builder.build_set_request(oid_list, type_value, request_id)

  @doc """
  Builds a response PDU.

  ## Parameters

  - `request_pdu`: Original request PDU to respond to
  - `varbinds`: List of variable bindings for the response
  - `error_status`: Error status code (default: 0 for no error)
  - `error_index`: Error index (default: 0)

  ## Examples

      iex> varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "Linux server"}]
      iex> pdu = SnmpKit.SnmpLib.PDU.build_response(123, 0, 0, varbinds)
      iex> pdu.type
      :get_response
  """
  @spec build_response(non_neg_integer(), error_status(), non_neg_integer(), [varbind()]) :: pdu()
  def build_response(request_id, error_status, error_index, varbinds \\ []) do
    Builder.build_response(request_id, error_status, error_index, varbinds)
  end

  @doc """
  Builds an SNMP message with version, community, and PDU.

  ## Parameters

  - `pdu`: PDU structure to include in the message
  - `community`: Community string for authentication
  - `version`: SNMP version

  ## Examples

      iex> {:ok, pdu} = SnmpKit.SnmpLib.PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 123)
      iex> message = SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v2c)
      iex> message.version
      1
  """
  @spec build_message(pdu(), binary(), Constants.snmp_version()) :: message()
  def build_message(pdu, community, version \\ :v1),
    do: Builder.build_message(pdu, community, version)

  @doc """
  Validates a community string.

  ## Parameters

  - `encoded_message`: Encoded SNMP message
  - `expected_community`: Expected community string

  ## Examples

      iex> :ok = SnmpKit.SnmpLib.PDU.validate_community(encoded_msg, "public")
  """
  @spec validate_community(binary(), binary()) :: :ok | {:error, atom()}
  def validate_community(encoded_message, expected_community),
    do: Builder.validate_community(encoded_message, expected_community)

  @doc """
  Creates an error response PDU.

  ## Parameters

  - `request_pdu`: Original request PDU
  - `error_status`: Error status atom or code
  - `error_index`: Index of the variable that caused the error

  ## Examples

      iex> request_pdu = %{type: :get_request, request_id: 123, error_status: 0, error_index: 0, varbinds: []}
      iex> error_pdu = SnmpKit.SnmpLib.PDU.create_error_response(request_pdu, :no_such_name, 1)
      iex> error_pdu.error_status
      2
  """
  @spec create_error_response(pdu(), error_status() | atom(), non_neg_integer()) :: pdu()
  def create_error_response(request_pdu, error_status, error_index) do
    Builder.create_error_response(request_pdu, error_status, error_index)
  end

  @doc """
  Creates an error response PDU.

  ## Parameters

  - `request_pdu`: Original request PDU
  - `error_status`: Error status atom or code

  ## Examples

      iex> request_pdu = %{type: :get_request, request_id: 123, error_status: 0, error_index: 0, varbinds: []}
      iex> error_pdu = SnmpKit.SnmpLib.PDU.create_error_response(request_pdu, :no_such_name)
      iex> error_pdu.error_status
      2
  """
  @spec create_error_response(pdu(), error_status() | atom()) :: pdu()
  def create_error_response(request_pdu, error_status) do
    Builder.create_error_response(request_pdu, error_status, 0)
  end

  ## Public API - Validation

  @doc """
  Validates a PDU structure.

  ## Examples

      iex> pdu = %{type: :get_request, request_id: 123, error_status: 0, error_index: 0, varbinds: []}
      iex> {:ok, ^pdu} = SnmpKit.SnmpLib.PDU.validate(pdu)
  """
  @spec validate(pdu()) :: {:ok, pdu()} | {:error, atom()}
  def validate(pdu), do: Builder.validate(pdu)

  ## Public API - Utility Functions

  @doc """
  Normalizes an OID to a list of integers.

  ## Examples

      iex> SnmpKit.SnmpLib.PDU.normalize_oid([1, 3, 6, 1, 2, 1, 1, 1, 0])
      [1, 3, 6, 1, 2, 1, 1, 1, 0]
  """
  @spec normalize_oid(oid() | binary()) :: oid()
  def normalize_oid(oid), do: Constants.normalize_oid(oid)

  @doc """
  Normalizes an SNMP type atom.

  ## Examples

      iex> SnmpKit.SnmpLib.PDU.normalize_type(:string)
      :octet_string
  """
  @spec normalize_type(atom()) :: snmp_type()
  def normalize_type(type), do: Constants.normalize_type(type)

  @doc """
  Converts an error status atom to its numeric code.

  ## Examples

      iex> SnmpKit.SnmpLib.PDU.error_status_to_code(:no_such_name)
      2
  """
  @spec error_status_to_code(atom()) :: non_neg_integer()
  def error_status_to_code(status), do: Constants.error_status_to_code(status)

  @doc """
  Converts an error status code to its atom representation.

  ## Examples

      iex> SnmpKit.SnmpLib.PDU.error_status_to_atom(2)
      :no_such_name
  """
  @spec error_status_to_atom(non_neg_integer()) :: atom()
  def error_status_to_atom(code), do: Constants.error_status_to_atom(code)
end
