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
  """

  import Bitwise
  require Logger

  alias SnmpKit.SnmpLib.ASN1
  alias SnmpKit.SnmpLib.PDU.{Constants, Encoder, Decoder}
  alias SnmpKit.SnmpLib.Security

  @type v3_message :: Constants.v3_message()
  @type scoped_pdu :: Constants.scoped_pdu()
  @type security_user :: Security.security_user()
  @type security_params :: Security.security_params()

  # ASN.1 tags
  @sequence 0x30
  @octet_string 0x04
  @integer 0x02

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
      # Encode scoped PDU
      case encode_scoped_pdu(message.msg_data) do
        {:ok, scoped_pdu_data} ->
          # Apply security processing
          case apply_security_processing(message, scoped_pdu_data, user) do
            {:ok, final_msg_data, security_params} ->
              # Encode complete message
              encode_v3_message(message, security_params, final_msg_data)

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
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

  - `{:ok, message}` on success
  - `{:error, reason}` on failure
  """
  @spec decode_message(binary(), security_user() | nil) ::
          {:ok, v3_message()} | {:error, atom()}
  def decode_message(data, user \\ nil) when is_binary(data) do
    try do
      case decode_v3_message(data) do
        {:ok, message, security_params, msg_data} ->
          # Apply security processing
          case process_security_parameters(message, security_params, msg_data, user) do
            {:ok, result} when user == nil ->
              # For discovery messages, process_security_parameters already returns the scoped_pdu
              final_message = Map.put(message, :msg_data, result)
              {:ok, final_message}

            {:ok, decrypted_data} ->
              # Decode scoped PDU
              case decode_scoped_pdu(decrypted_data) do
                {:ok, scoped_pdu} ->
                  final_message = Map.put(message, :msg_data, scoped_pdu)
                  {:ok, final_message}

                {:error, reason} ->
                  {:error, reason}
              end

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("SNMPv3 decoding failed: #{inspect(error)}")
        {:error, :decoding_failed}
    end
  end

  # Private encoding functions

  defp encode_v3_message(message, security_params, msg_data) do
    # Build complete message
    with {:ok, version_data} <- ASN1.encode_integer(message.version),
         {:ok, header_data} <-
           encode_header_data(
             message.msg_id,
             message.msg_max_size,
             message.msg_flags,
             message.msg_security_model
           ),
         {:ok, security_data} <- ASN1.encode_octet_string(security_params),
         {:ok, msg_data_encoded} <- encode_msg_data_for_transport(msg_data, message.msg_flags) do
      iodata = [
        version_data,
        header_data,
        security_data,
        msg_data_encoded
      ]

      content = :erlang.iolist_to_binary(iodata)
      encode_sequence(content)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_msg_data_for_transport(msg_data, msg_flags) do
    # For encrypted messages (priv=true), msg_data is encrypted binary that needs OCTET STRING wrapper
    # For plaintext messages, msg_data is scoped PDU binary that should remain as sequence data
    if msg_flags.priv do
      ASN1.encode_octet_string(msg_data)
    else
      # Plaintext scoped PDU data is already properly encoded as sequence
      {:ok, msg_data}
    end
  end

  defp encode_header_data(msg_id, msg_max_size, msg_flags, security_model) do
    flags_binary = Constants.encode_msg_flags(msg_flags)

    with {:ok, msg_id_data} <- ASN1.encode_integer(msg_id),
         {:ok, size_data} <- ASN1.encode_integer(msg_max_size),
         {:ok, flags_data} <- ASN1.encode_octet_string(flags_binary),
         {:ok, model_data} <- ASN1.encode_integer(security_model) do
      iodata = [
        msg_id_data,
        size_data,
        flags_data,
        model_data
      ]

      content = :erlang.iolist_to_binary(iodata)
      encode_sequence(content)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_scoped_pdu(%{context_engine_id: engine_id, context_name: name, pdu: pdu}) do
    case Encoder.encode_pdu(pdu) do
      {:ok, pdu_data} ->
        # Instead of trying to construct iodata directly, let's validate each component
        with {:ok, engine_data} <- ASN1.encode_octet_string(engine_id),
             {:ok, name_data} <- ASN1.encode_octet_string(name) do
          try do
            # Build the sequence content directly without intermediate iodata
            content = <<engine_data::binary, name_data::binary, pdu_data::binary>>
            {:ok, encoded_seq} = encode_sequence(content)
            {:ok, encoded_seq}
          rescue
            error ->
              Logger.error(
                "Scoped PDU encoding failed: #{inspect(error)} - engine_id: #{inspect(engine_id)}, name: #{inspect(name)}, pdu_data size: #{byte_size(pdu_data)}"
              )

              {:error, :scoped_pdu_encoding_failed}
          end
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_security_processing(_message, scoped_pdu_data, nil) do
    # No security processing for discovery messages
    {:ok, scoped_pdu_data, <<>>}
  end

  defp apply_security_processing(message, scoped_pdu_data, user) do
    flags = message.msg_flags

    cond do
      flags.priv ->
        # Authentication and Privacy
        apply_auth_priv_processing(message, scoped_pdu_data, user)

      flags.auth ->
        # Authentication only
        apply_auth_processing(message, scoped_pdu_data, user)

      true ->
        # No security
        {:ok, scoped_pdu_data, encode_usm_security_params(user, <<>>, <<>>)}
    end
  end

  defp apply_auth_processing(message, scoped_pdu_data, user) do
    # Create security parameters with placeholder for authentication
    # 12-byte placeholder
    auth_placeholder = :binary.copy(<<0>>, 12)
    security_params = encode_usm_security_params(user, auth_placeholder, <<>>)

    # Build message for authentication
    temp_msg_data = scoped_pdu_data
    auth_message = build_auth_message(message, security_params, temp_msg_data)

    # Calculate authentication parameters
    case Security.authenticate_message(user, auth_message) do
      {:ok, auth_params} ->
        # Replace placeholder with actual authentication
        final_security_params = encode_usm_security_params(user, auth_params, <<>>)
        {:ok, scoped_pdu_data, final_security_params}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_auth_priv_processing(message, scoped_pdu_data, user) do
    # Encrypt the scoped PDU
    case Security.Priv.encrypt(user.priv_protocol, user.priv_key, user.auth_key, scoped_pdu_data) do
      {:ok, {encrypted_data, priv_params}} ->
        # Apply authentication to encrypted data
        auth_placeholder = :binary.copy(<<0>>, 12)
        security_params = encode_usm_security_params(user, auth_placeholder, priv_params)

        # Build message for authentication
        auth_message = build_auth_message(message, security_params, encrypted_data)

        case Security.authenticate_message(user, auth_message) do
          {:ok, auth_params} ->
            final_security_params = encode_usm_security_params(user, auth_params, priv_params)
            {:ok, encrypted_data, final_security_params}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_usm_security_params(user, auth_params, priv_params) do
    # USM Security Parameters format
    with {:ok, engine_data} <- ASN1.encode_octet_string(user.engine_id),
         {:ok, boots_data} <- ASN1.encode_integer(user.engine_boots),
         {:ok, time_data} <- ASN1.encode_integer(user.engine_time),
         {:ok, name_data} <- ASN1.encode_octet_string(user.security_name),
         {:ok, auth_data} <- ASN1.encode_octet_string(auth_params),
         {:ok, priv_data} <- ASN1.encode_octet_string(priv_params) do
      iodata = [
        engine_data,
        boots_data,
        time_data,
        name_data,
        auth_data,
        priv_data
      ]

      content = :erlang.iolist_to_binary(iodata)
      {:ok, result} = encode_sequence(content)
      result
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_auth_message(message, security_params, msg_data) do
    # Build complete message for authentication calculation

    with {:ok, version_data} <- ASN1.encode_integer(message.version),
         {:ok, header_data} <-
           encode_header_data(
             message.msg_id,
             message.msg_max_size,
             message.msg_flags,
             message.msg_security_model
           ),
         {:ok, security_params_data} <- ASN1.encode_octet_string(security_params) do
      iodata = [
        version_data,
        header_data,
        security_params_data,
        msg_data
      ]

      content = :erlang.iolist_to_binary(iodata)
      {:ok, auth_message} = encode_sequence(content)
      auth_message
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private decoding functions

  defp decode_v3_message(data) do
    case ASN1.decode_sequence(data) do
      {:ok, {content, _remaining}} ->
        case decode_message_components(content) do
          {:ok, version, header_data, security_params, msg_data} when version == 3 ->
            case decode_header_data(header_data) do
              {:ok, msg_id, msg_max_size, msg_flags, security_model} ->
                message = %{
                  version: version,
                  msg_id: msg_id,
                  msg_max_size: msg_max_size,
                  msg_flags: msg_flags,
                  msg_security_model: security_model
                }

                {:ok, message, security_params, msg_data}

              {:error, reason} ->
                {:error, reason}
            end

          {:ok, version, _, _, _} ->
            {:error, {:invalid_version, version}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_message_components(data) do
    with {:ok, {version, rest1}} <- ASN1.decode_integer(data),
         {:ok, {header_data, rest2}} <- ASN1.decode_sequence(rest1),
         {:ok, {security_params, rest3}} <- ASN1.decode_octet_string(rest2),
         {:ok, msg_data, _rest4} <- decode_msg_data(rest3) do
      {:ok, version, header_data, security_params, msg_data}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_header_data(data) do
    with {:ok, {msg_id, rest1}} <- ASN1.decode_integer(data),
         {:ok, {msg_max_size, rest2}} <- ASN1.decode_integer(rest1),
         {:ok, {msg_flags_binary, rest3}} <- ASN1.decode_octet_string(rest2),
         {:ok, {security_model, _rest4}} <- ASN1.decode_integer(rest3) do
      msg_flags = Constants.decode_msg_flags(msg_flags_binary)
      {:ok, msg_id, msg_max_size, msg_flags, security_model}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_msg_data(data) do
    # msg_data can be either plaintext ScopedPDU or encrypted OCTET STRING
    # Try OCTET STRING first (encrypted data), then return raw data for plaintext
    case ASN1.decode_octet_string(data) do
      {:ok, {encrypted_data, remaining}} ->
        {:ok, encrypted_data, remaining}

      {:error, _} ->
        # For plaintext, return the raw data (which should be a complete SEQUENCE)
        {:ok, data, <<>>}
    end
  end

  defp decode_scoped_pdu(data) do
    case ASN1.decode_sequence(data) do
      {:ok, {content, _remaining}} ->
        with {:ok, {context_engine_id, rest1}} <- ASN1.decode_octet_string(content),
             {:ok, {context_name, rest2}} <- ASN1.decode_octet_string(rest1),
             {:ok, pdu} <- Decoder.decode_pdu(rest2) do
          scoped_pdu = %{
            context_engine_id: context_engine_id,
            context_name: context_name,
            pdu: pdu
          }

          {:ok, scoped_pdu}
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_security_parameters(_message, _security_params, msg_data, nil) do
    # No security processing for discovery messages
    # For discovery messages, msg_data might be raw SEQUENCE data
    # First try to decode as SEQUENCE to get content, then process content
    case ASN1.decode_sequence(msg_data) do
      {:ok, {sequence_content, _}} ->
        # Now process the sequence content
        with {:ok, {context_engine_id, rest1}} <- ASN1.decode_octet_string(sequence_content),
             {:ok, {context_name, rest2}} <- ASN1.decode_octet_string(rest1),
             {:ok, pdu} <- Decoder.decode_pdu(rest2) do
          scoped_pdu = %{
            context_engine_id: context_engine_id,
            context_name: context_name,
            pdu: pdu
          }

          {:ok, scoped_pdu}
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, _} ->
        # msg_data is already sequence content, try direct processing
        with {:ok, {context_engine_id, rest1}} <- ASN1.decode_octet_string(msg_data),
             {:ok, {context_name, rest2}} <- ASN1.decode_octet_string(rest1),
             {:ok, pdu} <- Decoder.decode_pdu(rest2) do
          scoped_pdu = %{
            context_engine_id: context_engine_id,
            context_name: context_name,
            pdu: pdu
          }

          {:ok, scoped_pdu}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp process_security_parameters(message, security_params, msg_data, user) do
    case decode_usm_security_params(security_params) do
      {:ok, usm_params} ->
        flags = message.msg_flags

        cond do
          flags.priv ->
            # Decrypt and verify authentication
            process_auth_priv_message(message, usm_params, msg_data, user)

          flags.auth ->
            # Verify authentication only
            process_auth_message(message, usm_params, msg_data, user)

          true ->
            # No authentication or privacy
            {:ok, msg_data}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_auth_message(message, usm_params, msg_data, user) do
    # Build message for authentication verification
    auth_placeholder = :binary.copy(<<0>>, 12)

    temp_security_params =
      encode_usm_security_params(
        user,
        auth_placeholder,
        usm_params.priv_params
      )

    # For auth-only messages, msg_data should remain as sequence (not OCTET STRING wrapped)
    auth_message = build_auth_message(message, temp_security_params, msg_data)

    case Security.Auth.verify(
           user.auth_protocol,
           user.auth_key,
           auth_message,
           usm_params.auth_params
         ) do
      :ok ->
        {:ok, msg_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_auth_priv_message(message, usm_params, encrypted_data, user) do
    # First verify authentication
    auth_placeholder = :binary.copy(<<0>>, 12)

    temp_security_params =
      encode_usm_security_params(
        user,
        auth_placeholder,
        usm_params.priv_params
      )

    # Use raw encrypted data for authentication, same as during encoding
    # OCTET STRING wrapping happens later for transport, not for authentication
    auth_message = build_auth_message(message, temp_security_params, encrypted_data)

    case Security.Auth.verify(
           user.auth_protocol,
           user.auth_key,
           auth_message,
           usm_params.auth_params
         ) do
      :ok ->
        # Decrypt the message
        Security.Priv.decrypt(
          user.priv_protocol,
          user.priv_key,
          user.auth_key,
          encrypted_data,
          usm_params.priv_params
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_usm_security_params(data) do
    case ASN1.decode_sequence(data) do
      {:ok, {content, _remaining}} ->
        with {:ok, {engine_id, rest1}} <- ASN1.decode_octet_string(content),
             {:ok, {engine_boots, rest2}} <- ASN1.decode_integer(rest1),
             {:ok, {engine_time, rest3}} <- ASN1.decode_integer(rest2),
             {:ok, {security_name, rest4}} <- ASN1.decode_octet_string(rest3),
             {:ok, {auth_params, rest5}} <- ASN1.decode_octet_string(rest4),
             {:ok, {priv_params, _rest6}} <- ASN1.decode_octet_string(rest5) do
          usm_params = %{
            engine_id: engine_id,
            engine_boots: engine_boots,
            engine_time: engine_time,
            security_name: security_name,
            auth_params: auth_params,
            priv_params: priv_params
          }

          {:ok, usm_params}
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
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
