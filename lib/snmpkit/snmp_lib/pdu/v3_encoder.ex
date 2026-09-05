defmodule SnmpKit.SnmpLib.PDU.V3Encoder do
  @moduledoc """
  SNMPv3 message encoding and decoding with User Security Model (USM) support.

  This module implements the SNMPv3 message format as specified in RFC 3412 and RFC 3414,
  providing authentication and privacy protection for SNMP communications.

  ## SNMPv3 Message Structure

  SNMPv3 messages have a complex hierarchical structure:

  ```
  SNMPv3Message ::= SEQUENCE {
      msgVersion INTEGER (0..2147483647),
      msgGlobalData HeaderData,
      msgSecurityParameters OCTET STRING,
      msgData ScopedPduData
  }

  HeaderData ::= SEQUENCE {
      msgID INTEGER (0..2147483647),
      msgMaxSize INTEGER (484..2147483647),
      msgFlags OCTET STRING (SIZE(1)),
      msgSecurityModel INTEGER (1..2147483647)
  }

  ScopedPduData ::= CHOICE {
      plaintext ScopedPDU,
      encryptedPDU OCTET STRING
  }

  ScopedPDU ::= SEQUENCE {
      contextEngineID OCTET STRING,
      contextName OCTET STRING,
      data ANY
  }
  ```

  ## Security Processing

  The module integrates with the security subsystem to provide:
  - Message authentication using HMAC algorithms
  - Message encryption using AES/DES algorithms
  - Time synchronization and engine discovery
  - Replay attack protection

  ## Usage Examples

  ### Encoding a SNMPv3 Message

      # Create security user
      user = %{
        security_name: "testuser",
        auth_protocol: :sha256,
        priv_protocol: :aes128,
        auth_key: derived_auth_key,
        priv_key: derived_priv_key,
        engine_id: "local_engine"
      }

      # Create SNMPv3 message
      message = %{
        version: 3,
        msg_id: 12345,
        msg_max_size: 65507,
        msg_flags: %{auth: true, priv: true, reportable: true},
        msg_security_model: 3,
        msg_security_parameters: "",  # Will be generated
        msg_data: %{
          context_engine_id: "target_engine",
          context_name: "",
          pdu: pdu
        }
      }

      # Encode with security
      {:ok, encoded} = SnmpKit.SnmpLib.PDU.V3Encoder.encode_message(message, user)

  ### Decoding a SNMPv3 Message

      {:ok, decoded} = SnmpKit.SnmpLib.PDU.V3Encoder.decode_message(binary_data, user)

  ## Security Notes

  - Authentication is required for privacy (encryption)
  - Engine discovery must be performed before authenticated communication
  - Time synchronization is required to prevent replay attacks
  - Message IDs should be unique to prevent duplicate processing

  ## Wire-format details

  - `msgAuthenticationParameters` is the HMAC computed over the *entire*
    serialized message with the parameter field itself zeroed (RFC 3414 6.3.1 /
    7.3.1). On decode the MAC is recomputed over the bytes actually received,
    never over a re-encoding, so any peer's BER choices are accepted.
  - Encrypted messages carry the ciphertext in an OCTET STRING `msgData`; the
    MAC covers that OCTET STRING, exactly as transmitted.
  - AES/DES IVs are derived from `msgAuthoritativeEngineBoots`/`Time` and the
    8-octet salt in `msgPrivacyParameters` (RFC 3414 8.1.1.1, RFC 3826 3.1.2.1).
  - Decoded messages expose the received USM parameters under
    `:security_parameters` (see `t:SnmpKit.SnmpLib.Security.security_params/0`)
    and the raw octets under `:msg_security_parameters`.
  """

  import Bitwise
  require Logger

  alias SnmpKit.SnmpLib.ASN1
  alias SnmpKit.SnmpLib.PDU.{Constants, Encoder, Decoder}
  alias SnmpKit.SnmpLib.Security
  alias SnmpKit.SnmpLib.Security.{Auth, Priv}

  @type v3_message :: Constants.v3_message()
  @type scoped_pdu :: Constants.scoped_pdu()
  @type security_user :: Security.security_user()
  @type security_params :: Security.security_params()

  # ASN.1 tags
  @sequence 0x30

  # Decoded msgSecurityParameters, USM flavour (RFC 3414 2.4)
  @typep usm_params :: %{
           engine_id: binary(),
           engine_boots: non_neg_integer(),
           engine_time: non_neg_integer(),
           security_name: binary(),
           auth_params: binary(),
           priv_params: binary(),
           auth_params_offset: non_neg_integer()
         }

  @doc """
  Encodes a SNMPv3 message with security processing.

  ## Parameters

  - `message` - SNMPv3 message structure
  - `user` - Security user configuration (optional for discovery messages)

  ## Returns

  - `{:ok, binary()}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, encoded} = encode_message(snmpv3_message, security_user)
      {:ok, discovery_msg} = encode_message(discovery_message, nil)
  """
  @spec encode_message(v3_message(), security_user() | nil) ::
          {:ok, binary()} | {:error, atom()}
  def encode_message(message, user \\ nil)

  def encode_message(%{version: 3} = message, user) do
    try do
      with {:ok, scoped_pdu_data} <- encode_scoped_pdu(message.msg_data) do
        apply_security_processing(message, scoped_pdu_data, user)
      end
    rescue
      error ->
        Logger.error("SNMPv3 encoding failed: #{inspect(error)}")
        {:error, :encoding_failed}
    end
  end

  def encode_message(%{version: version}, _user) when version != 3 do
    {:error, :invalid_version}
  end

  def encode_message(_, _) do
    {:error, :invalid_message_format}
  end

  @doc """
  Decodes a SNMPv3 message with security processing.

  ## Parameters

  - `data` - Binary SNMPv3 message data
  - `user` - Security user configuration (optional for discovery messages)

  ## Returns

  - `{:ok, message}` on success. Besides the header fields and `:msg_data`
    (the decoded ScopedPDU) the map carries `:msg_security_parameters` (raw
    octets) and `:security_parameters` (decoded USM parameters, or `nil` when
    they are not USM-shaped).
  - `{:error, reason}` on failure. An encrypted message decoded without a user
    yields `{:error, :user_required_for_privacy}`; use `decode_message_header/1`
    to read the security parameters first and look the user up.
  """
  @spec decode_message(binary(), security_user() | nil) ::
          {:ok, v3_message()} | {:error, atom()}
  def decode_message(data, user \\ nil) when is_binary(data) do
    try do
      with {:ok, message, security_params, msg_data, sec_offset} <- decode_v3_message(data),
           {:ok, plain_scoped_pdu} <-
             process_security_parameters(
               data,
               message,
               security_params,
               sec_offset,
               msg_data,
               user
             ),
           {:ok, scoped_pdu} <- decode_scoped_pdu(plain_scoped_pdu) do
        {:ok,
         message
         |> Map.put(:msg_security_parameters, security_params)
         |> Map.put(:security_parameters, public_security_params(security_params))
         |> Map.put(:msg_data, scoped_pdu)}
      end
    rescue
      error ->
        Logger.error("SNMPv3 decoding failed: #{inspect(error)}")
        {:error, :decoding_failed}
    end
  end

  @doc """
  Decodes only the header and security parameters of a SNMPv3 message.

  No authentication or decryption is performed. This is what an authoritative
  engine uses to find `msgUserName` before it can select the user whose keys
  verify the message.

  Returns the same map as `decode_message/2` minus `:msg_data`.
  """
  @spec decode_message_header(binary()) :: {:ok, map()} | {:error, atom()}
  def decode_message_header(data) when is_binary(data) do
    try do
      with {:ok, message, security_params, _msg_data, _sec_offset} <- decode_v3_message(data) do
        {:ok,
         message
         |> Map.put(:msg_security_parameters, security_params)
         |> Map.put(:security_parameters, public_security_params(security_params))}
      end
    rescue
      error ->
        Logger.error("SNMPv3 header decoding failed: #{inspect(error)}")
        {:error, :decoding_failed}
    end
  end

  @doc """
  Decodes a raw `msgSecurityParameters` OCTET STRING as USM parameters.

  Returns a map in the `t:SnmpKit.SnmpLib.Security.security_params/0` shape.
  """
  @spec decode_security_parameters(binary()) :: {:ok, security_params()} | {:error, atom()}
  def decode_security_parameters(security_params) when is_binary(security_params) do
    with {:ok, usm} <- decode_usm_security_params(security_params) do
      {:ok, to_public_security_params(usm)}
    end
  end

  # Private encoding functions ------------------------------------------------

  # Discovery / unauthenticated messages still carry USM parameters, just with
  # empty engine ID, user name and zero boots/time (RFC 3414 4).
  @discovery_params %{
    engine_id: <<>>,
    engine_boots: 0,
    engine_time: 0,
    security_name: <<>>
  }

  defp apply_security_processing(message, scoped_pdu_data, nil) do
    with {:ok, security_params, _} <- encode_usm_security_params(@discovery_params, <<>>, <<>>),
         {:ok, packet, _} <- assemble_message(message, security_params, scoped_pdu_data) do
      {:ok, packet}
    end
  end

  defp apply_security_processing(message, scoped_pdu_data, user) do
    flags = message.msg_flags

    cond do
      flags.priv -> apply_auth_priv_processing(message, scoped_pdu_data, user)
      flags.auth -> apply_auth_processing(message, scoped_pdu_data, user, <<>>)
      true -> apply_no_auth_processing(message, scoped_pdu_data, user)
    end
  end

  defp apply_no_auth_processing(message, scoped_pdu_data, user) do
    with {:ok, security_params, _} <- encode_usm_security_params(user, <<>>, <<>>),
         {:ok, packet, _} <- assemble_message(message, security_params, scoped_pdu_data) do
      {:ok, packet}
    end
  end

  defp apply_auth_priv_processing(message, scoped_pdu_data, user) do
    priv_opts = [engine_boots: user.engine_boots, engine_time: user.engine_time]

    with {:ok, {ciphertext, priv_params}} <-
           Priv.encrypt(
             user.priv_protocol,
             user.priv_key,
             user.auth_key,
             scoped_pdu_data,
             priv_opts
           ),
         {:ok, encrypted_msg_data} <- ASN1.encode_octet_string(ciphertext) do
      apply_auth_processing(message, encrypted_msg_data, user, priv_params)
    end
  end

  # RFC 3414 6.3.1 / 7.3.1: serialize the whole message with a zero-filled
  # msgAuthenticationParameters of the protocol's MAC length, MAC those exact
  # bytes, then write the MAC into the placeholder.
  defp apply_auth_processing(message, msg_data, user, priv_params) do
    mac_len = Auth.auth_params_size(user.auth_protocol)
    placeholder = :binary.copy(<<0>>, mac_len)

    with {:ok, security_params, auth_offset} <-
           encode_usm_security_params(user, placeholder, priv_params),
         {:ok, packet, sec_offset} <- assemble_message(message, security_params, msg_data),
         {:ok, mac} <- Auth.authenticate(user.auth_protocol, user.auth_key, packet) do
      if byte_size(mac) == mac_len do
        {:ok, splice(packet, sec_offset + auth_offset, mac)}
      else
        {:error, :authentication_failed}
      end
    end
  end

  # Serializes the SNMPv3Message. Returns the packet and the byte offset of the
  # msgSecurityParameters *content* within it.
  defp assemble_message(message, security_params, msg_data) do
    with {:ok, version_data} <- ASN1.encode_integer(message.version),
         {:ok, header_data} <-
           encode_header_data(
             message.msg_id,
             message.msg_max_size,
             message.msg_flags,
             message.msg_security_model
           ),
         {:ok, security_data} <- ASN1.encode_octet_string(security_params) do
      content =
        <<version_data::binary, header_data::binary, security_data::binary, msg_data::binary>>

      {:ok, packet} = encode_sequence(content)

      sec_offset =
        byte_size(packet) - byte_size(content) + byte_size(version_data) +
          byte_size(header_data) + (byte_size(security_data) - byte_size(security_params))

      {:ok, packet, sec_offset}
    end
  end

  defp encode_header_data(msg_id, msg_max_size, msg_flags, security_model) do
    flags_binary = Constants.encode_msg_flags(msg_flags)

    with {:ok, msg_id_data} <- ASN1.encode_integer(msg_id),
         {:ok, size_data} <- ASN1.encode_integer(msg_max_size),
         {:ok, flags_data} <- ASN1.encode_octet_string(flags_binary),
         {:ok, model_data} <- ASN1.encode_integer(security_model) do
      encode_sequence(
        <<msg_id_data::binary, size_data::binary, flags_data::binary, model_data::binary>>
      )
    end
  end

  defp encode_scoped_pdu(%{context_engine_id: engine_id, context_name: name, pdu: pdu}) do
    with {:ok, pdu_data} <- Encoder.encode_pdu(pdu),
         {:ok, engine_data} <- ASN1.encode_octet_string(engine_id),
         {:ok, name_data} <- ASN1.encode_octet_string(name) do
      encode_sequence(<<engine_data::binary, name_data::binary, pdu_data::binary>>)
    end
  end

  defp encode_scoped_pdu(_), do: {:error, :invalid_scoped_pdu}

  # UsmSecurityParameters (RFC 3414 2.4). Returns the encoded SEQUENCE and the
  # offset of the msgAuthenticationParameters value within it.
  defp encode_usm_security_params(params, auth_params, priv_params) do
    with {:ok, engine_data} <- ASN1.encode_octet_string(params.engine_id),
         {:ok, boots_data} <- ASN1.encode_integer(params.engine_boots),
         {:ok, time_data} <- ASN1.encode_integer(params.engine_time),
         {:ok, name_data} <- ASN1.encode_octet_string(params.security_name),
         {:ok, auth_data} <- ASN1.encode_octet_string(auth_params),
         {:ok, priv_data} <- ASN1.encode_octet_string(priv_params) do
      content =
        <<engine_data::binary, boots_data::binary, time_data::binary, name_data::binary,
          auth_data::binary, priv_data::binary>>

      {:ok, encoded} = encode_sequence(content)
      auth_offset = byte_size(encoded) - byte_size(priv_data) - byte_size(auth_params)
      {:ok, encoded, auth_offset}
    end
  end

  defp splice(binary, offset, replacement) do
    len = byte_size(replacement)
    <<before::binary-size(^offset), _::binary-size(^len), rest::binary>> = binary
    <<before::binary, replacement::binary, rest::binary>>
  end

  # Private decoding functions ------------------------------------------------

  # Returns the header map, the raw msgSecurityParameters, the raw msgData and
  # the byte offset of the security parameters content within `data`.
  defp decode_v3_message(data) do
    with {:ok, {content, remaining}} <- ASN1.decode_sequence(data),
         {:ok, version, header_data, security_params, msg_data, sec_offset_in_content} <-
           decode_message_components(content),
         :ok <- check_version(version),
         {:ok, msg_id, msg_max_size, msg_flags, security_model} <- decode_header_data(header_data) do
      message = %{
        version: version,
        msg_id: msg_id,
        msg_max_size: msg_max_size,
        msg_flags: msg_flags,
        msg_security_model: security_model
      }

      content_offset = byte_size(data) - byte_size(remaining) - byte_size(content)
      {:ok, message, security_params, msg_data, content_offset + sec_offset_in_content}
    end
  end

  defp check_version(3), do: :ok
  defp check_version(version), do: {:error, {:invalid_version, version}}

  defp decode_message_components(content) do
    with {:ok, {version, rest1}} <- ASN1.decode_integer(content),
         {:ok, {header_data, rest2}} <- ASN1.decode_sequence(rest1),
         {:ok, {security_params, rest3}} <- ASN1.decode_octet_string(rest2) do
      sec_offset = byte_size(content) - byte_size(rest3) - byte_size(security_params)
      {:ok, version, header_data, security_params, rest3, sec_offset}
    end
  end

  defp decode_header_data(data) do
    with {:ok, {msg_id, rest1}} <- ASN1.decode_integer(data),
         {:ok, {msg_max_size, rest2}} <- ASN1.decode_integer(rest1),
         {:ok, {msg_flags_binary, rest3}} <- ASN1.decode_octet_string(rest2),
         {:ok, {security_model, _rest4}} <- ASN1.decode_integer(rest3) do
      {:ok, msg_id, msg_max_size, Constants.decode_msg_flags(msg_flags_binary), security_model}
    end
  end

  # msgData is either a plaintext ScopedPDU (SEQUENCE) or an OCTET STRING of ciphertext.
  defp unwrap_encrypted_msg_data(msg_data) do
    case ASN1.decode_octet_string(msg_data) do
      {:ok, {ciphertext, _remaining}} -> {:ok, ciphertext}
      {:error, _} -> {:error, :invalid_encrypted_msg_data}
    end
  end

  # Trailing octets after the SEQUENCE are ignored on purpose: DES-CBC plaintext
  # keeps its RFC 3414 block padding, and the BER length tells us where the
  # ScopedPDU ends.
  defp decode_scoped_pdu(data) do
    with {:ok, {content, _remaining}} <- ASN1.decode_sequence(data),
         {:ok, {context_engine_id, rest1}} <- ASN1.decode_octet_string(content),
         {:ok, {context_name, rest2}} <- ASN1.decode_octet_string(rest1),
         {:ok, pdu} <- Decoder.decode_pdu(rest2) do
      {:ok, %{context_engine_id: context_engine_id, context_name: context_name, pdu: pdu}}
    end
  end

  # No user: only unencrypted messages can be read; nothing is verified.
  defp process_security_parameters(_data, message, _security_params, _sec_offset, msg_data, nil) do
    if message.msg_flags.priv do
      {:error, :user_required_for_privacy}
    else
      {:ok, msg_data}
    end
  end

  defp process_security_parameters(data, message, security_params, sec_offset, msg_data, user) do
    flags = message.msg_flags

    with {:ok, usm} <- decode_usm_security_params(security_params),
         :ok <- verify_authentication(data, sec_offset, usm, flags, user) do
      if flags.priv do
        decrypt_msg_data(msg_data, usm, user)
      else
        {:ok, msg_data}
      end
    end
  end

  defp verify_authentication(_data, _sec_offset, _usm, %{auth: false}, _user), do: :ok

  # Recompute the MAC over the received datagram with msgAuthenticationParameters
  # zeroed in place. No re-encoding is involved, so peers that pick different
  # (but valid) BER encodings still verify.
  defp verify_authentication(data, sec_offset, usm, %{auth: true}, user) do
    expected_len = Auth.auth_params_size(user.auth_protocol)
    received = usm.auth_params

    if byte_size(received) != expected_len do
      Logger.warning(
        "Authentication parameter length #{byte_size(received)} does not match #{user.auth_protocol}"
      )

      {:error, :authentication_mismatch}
    else
      zeroed =
        splice(data, sec_offset + usm.auth_params_offset, :binary.copy(<<0>>, expected_len))

      Auth.verify(user.auth_protocol, user.auth_key, zeroed, received)
    end
  end

  defp decrypt_msg_data(msg_data, usm, user) do
    with {:ok, ciphertext} <- unwrap_encrypted_msg_data(msg_data) do
      Priv.decrypt(
        user.priv_protocol,
        user.priv_key,
        user.auth_key,
        ciphertext,
        usm.priv_params,
        engine_boots: usm.engine_boots,
        engine_time: usm.engine_time
      )
    end
  end

  @spec decode_usm_security_params(binary()) :: {:ok, usm_params()} | {:error, atom()}
  defp decode_usm_security_params(data) do
    with {:ok, {content, remaining}} <- ASN1.decode_sequence(data),
         {:ok, {engine_id, rest1}} <- ASN1.decode_octet_string(content),
         {:ok, {engine_boots, rest2}} <- ASN1.decode_integer(rest1),
         {:ok, {engine_time, rest3}} <- ASN1.decode_integer(rest2),
         {:ok, {security_name, rest4}} <- ASN1.decode_octet_string(rest3),
         {:ok, {auth_params, rest5}} <- ASN1.decode_octet_string(rest4),
         {:ok, {priv_params, _rest6}} <- ASN1.decode_octet_string(rest5) do
      content_offset = byte_size(data) - byte_size(remaining) - byte_size(content)

      auth_offset =
        content_offset + byte_size(content) - byte_size(rest5) - byte_size(auth_params)

      {:ok,
       %{
         engine_id: engine_id,
         engine_boots: engine_boots,
         engine_time: engine_time,
         security_name: security_name,
         auth_params: auth_params,
         priv_params: priv_params,
         auth_params_offset: auth_offset
       }}
    end
  end

  defp public_security_params(security_params) do
    case decode_usm_security_params(security_params) do
      {:ok, usm} -> to_public_security_params(usm)
      {:error, _} -> nil
    end
  end

  defp to_public_security_params(usm) do
    %{
      authoritative_engine_id: usm.engine_id,
      authoritative_engine_boots: usm.engine_boots,
      authoritative_engine_time: usm.engine_time,
      user_name: usm.security_name,
      authentication_parameters: usm.auth_params,
      privacy_parameters: usm.priv_params
    }
  end

  # Utility functions

  defp encode_sequence(content) do
    length = byte_size(content)
    {:ok, <<@sequence, encode_length(length)::binary, content::binary>>}
  end

  defp encode_length(length) when length < 128 do
    <<length>>
  end

  defp encode_length(length) do
    bytes = encode_length_bytes(length, [])
    byte_count = byte_size(bytes)
    <<0x80 ||| byte_count, bytes::binary>>
  end

  defp encode_length_bytes(0, acc), do: :erlang.list_to_binary(acc)

  defp encode_length_bytes(length, acc) do
    encode_length_bytes(length >>> 8, [length &&& 0xFF | acc])
  end

  @doc """
  Creates a discovery message for engine ID discovery.
  """
  @spec create_discovery_message(non_neg_integer()) :: v3_message()
  def create_discovery_message(msg_id \\ :rand.uniform(2_147_483_647)) do
    %{
      version: 3,
      msg_id: msg_id,
      msg_max_size: Constants.default_max_message_size(),
      msg_flags: %{auth: false, priv: false, reportable: true},
      msg_security_model: Constants.usm_security_model(),
      msg_security_parameters: <<>>,
      msg_data: %{
        context_engine_id: <<>>,
        context_name: <<>>,
        pdu: %{
          type: :get_request,
          request_id: msg_id,
          error_status: 0,
          error_index: 0,
          # snmpEngineID
          varbinds: [{[1, 3, 6, 1, 6, 3, 10, 2, 1, 1, 0], :null, :null}]
        }
      }
    }
  end
end
