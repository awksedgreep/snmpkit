defmodule SnmpKit.SnmpLib do
  @moduledoc """
  Protocol layer of SnmpKit: RFC-compliant PDU encoding and decoding, ASN.1
  BER, OID utilities, SNMP data types, UDP transport, a low-level manager and
  the SNMPv3 User-based Security Model.

  Most applications use `SnmpKit.SNMP` instead; this layer is for code that
  needs to build or inspect SNMP messages directly.

  ## Modules

  - `SnmpKit.SnmpLib.PDU` - PDU and message encoding/decoding for SNMPv1,
    v2c and v3, including the v2c exception values `noSuchObject`,
    `noSuchInstance` and `endOfMibView`
  - `SnmpKit.SnmpLib.ASN1` - BER primitives, with correct multibyte OID
    sub-identifiers (X.690)
  - `SnmpKit.SnmpLib.OID` - string/list conversion, comparison, tree and
    table-index helpers
  - `SnmpKit.SnmpLib.Types` - validation and formatting of SNMP types
  - `SnmpKit.SnmpLib.Transport` - UDP sockets and address handling
  - `SnmpKit.SnmpLib.Manager` - GET, GETNEXT, GETBULK and SET against one
    host, returning `{type, value}` tuples
  - `SnmpKit.SnmpLib.Walker` - GETNEXT/GETBULK walks at this level
  - `SnmpKit.SnmpLib.ErrorHandler` - retry with exponential backoff, error
    classification, per-device circuit breakers
  - `SnmpKit.SnmpLib.Security` and `Security.{USM, Auth, Priv, Keys}` -
    SNMPv3 USM per RFC 3414 (MD5, SHA-1, SHA-2 family per RFC 7860; DES and
    AES-128/192/256)

  ## Examples

      # One GET against a host, raw {type, value} result
      {:ok, {:octet_string, description}} =
        SnmpKit.SnmpLib.Manager.get("192.168.1.1", [1, 3, 6, 1, 2, 1, 1, 1, 0])

      # Retry with exponential backoff
      SnmpKit.SnmpLib.ErrorHandler.with_retry(fn ->
        SnmpKit.SnmpLib.Manager.get("flaky.device", [1, 3, 6, 1, 2, 1, 1, 1, 0])
      end, max_attempts: 5, base_delay: 2000)

      # Encode a GET request PDU
      iex> pdu = SnmpKit.SnmpLib.PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      iex> message = SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v2c)
      iex> {:ok, encoded} = SnmpKit.SnmpLib.PDU.encode_message(message)
      iex> is_binary(encoded)
      true

      # Build a GETBULK request (SNMPv2c)
      iex> bulk_pdu = SnmpKit.SnmpLib.PDU.build_get_bulk_request([1, 3, 6, 1, 2, 1, 2, 2], 456, 0, 10)
      iex> bulk_pdu.type
      :get_bulk_request

      # OID manipulation with multibyte values
      iex> {:ok, oid_list} = SnmpKit.SnmpLib.OID.string_to_list("1.3.6.1.4.1.200.1")
      iex> oid_list
      [1, 3, 6, 1, 4, 1, 200, 1]
      iex> {:ok, oid_string} = SnmpKit.SnmpLib.OID.list_to_string([1, 3, 6, 1, 4, 1, 200, 1])
      iex> oid_string
      "1.3.6.1.4.1.200.1"

      # SNMPv2c exception values
      iex> {:ok, exception_val} = SnmpKit.SnmpLib.Types.coerce_value(:no_such_object, nil)
      iex> exception_val
      {:no_such_object, nil}

  ## Standards

  RFC 1157 (SNMPv1), RFC 3416 (SNMPv2c operations), RFC 3412/3414/3826/7860
  (SNMPv3 message processing, USM, AES, SHA-2 authentication) and ITU-T X.690
  (BER).
  """

  @doc """
  Returns the version of the SnmpLib library.

  ## Examples

      iex> is_binary(SnmpLib.version())
      true

      iex> SnmpLib.version() |> String.contains?(".")
      true
  """
  def version do
    Application.spec(:snmp_lib, :vsn) |> to_string()
  end

  @doc """
  Returns comprehensive information about the SnmpLib library capabilities.

  Useful for debugging, configuration validation, and feature discovery.

  ## Returns

  A map containing:
  - `:version`: Library version
  - `:features`: Available features and capabilities
  - `:modules`: Core modules and their descriptions
  - `:compliance`: RFC compliance information

  ## Examples

      info = SnmpLib.info()
      IO.puts("SNMP Library v" <> info.version)
      IO.puts("Features: " <> Enum.join(info.features, ", "))
  """
  @spec info() :: map()
  def info do
    %{
      version: version(),
      features: [
        "SNMPv1/v2c/v3 protocol support",
        "RFC-compliant PDU encoding/decoding",
        "SNMPv2c exception values",
        "Multibyte OID support",
        "Low-level manager API",
        "Retry, error classification and circuit breakers",
        "SNMPv3 USM: MD5/SHA/SHA-2 authentication, DES/AES privacy"
      ],
      modules: %{
        "SnmpKit.SnmpLib.Manager" => "Low-level SNMP operations (GET, GETNEXT, SET, GETBULK)",
        "SnmpKit.SnmpLib.Walker" => "GETNEXT/GETBULK walks",
        "SnmpKit.SnmpLib.ErrorHandler" => "Retry logic and circuit breakers",
        "SnmpKit.SnmpLib.PDU" => "SNMP PDU encoding/decoding",
        "SnmpKit.SnmpLib.ASN1" => "ASN.1 BER encoding/decoding",
        "SnmpKit.SnmpLib.OID" => "OID manipulation utilities",
        "SnmpKit.SnmpLib.Types" => "SNMP data type handling",
        "SnmpKit.SnmpLib.Transport" => "UDP transport layer",
        "SnmpKit.SnmpLib.Security" => "SNMPv3 User-based Security Model"
      },
      compliance: %{
        "RFC 1157" => "SNMPv1 Protocol",
        "RFC 1905" => "SNMPv2c Protocol Operations",
        "RFC 3416" => "SNMPv2c Enhanced Operations",
        "RFC 3414" => "SNMPv3 User-based Security Model",
        "RFC 3826" => "AES privacy for USM",
        "RFC 7860" => "HMAC-SHA-2 authentication for USM",
        "ITU-T X.690" => "ASN.1 BER Encoding Rules"
      }
    }
  end
end
