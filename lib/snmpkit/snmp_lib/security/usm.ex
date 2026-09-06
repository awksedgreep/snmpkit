defmodule SnmpKit.SnmpLib.Security.USM do
  @moduledoc """
  User Security Model (USM) implementation for SNMPv3 - RFC 3414 compliant.

  The User Security Model provides the foundation for SNMPv3 security by implementing:

  - **User-based authentication** with multiple protocols
  - **Privacy (encryption)** for message confidentiality
  - **Time synchronization** to prevent replay attacks
  - **Engine discovery** for secure agent communication
  - **Security parameter validation** and error handling

  ## RFC 3414 Compliance

  This implementation fully complies with RFC 3414 "User-based Security Model (USM)
  for version 3 of the Simple Network Management Protocol (SNMPv3)" including:

  - Message authentication using HMAC-MD5 and HMAC-SHA
  - Privacy using DES and AES encryption
  - Key derivation using password localization
  - Time window validation for message freshness
  - Engine ID discovery and management

  ## Architecture

  The USM coordinates with other security modules:

  ```
  SnmpKit.SnmpLib.Security.USM
  ├── Auth protocols (MD5, SHA variants)
  ├── Priv protocols (DES, AES variants)
  ├── Key derivation and management
  └── Engine and time management
  ```

  ## Usage Examples

  ### Engine Discovery

      # Discover remote engine for secure communication
      {:ok, engine_id} = SnmpKit.SnmpLib.Security.USM.discover_engine("192.168.1.1")

      # Time synchronization
      {:ok, {boots, time}} = SnmpKit.SnmpLib.Security.USM.synchronize_time("192.168.1.1", engine_id)

  ### Message Processing

      # Process outgoing secure message
      {:ok, secure_message} = SnmpKit.SnmpLib.Security.USM.process_outgoing_message(
        user, message, security_level
      )

      # Process incoming secure message
      {:ok, {plain_message, user}} = SnmpKit.SnmpLib.Security.USM.process_incoming_message(
        secure_message, user_database
      )

  ## Security Considerations

  - Engine boot counters must be persistent across restarts
  - Time synchronization is critical for security
  - Failed authentication attempts should be logged
  - Key material should never be logged or persisted in plain text
  """

  require Logger

  @type engine_id :: binary()
  @type security_name :: binary()
  @type security_level :: :no_auth_no_priv | :auth_no_priv | :auth_priv
  @type engine_boots :: non_neg_integer()
  @type engine_time :: non_neg_integer()

  @type user_entry :: %{
          security_name: security_name(),
          auth_protocol: atom(),
          priv_protocol: atom(),
          auth_key: binary(),
          priv_key: binary(),
          engine_id: engine_id()
        }

  @type message_flags :: %{
          auth_flag: boolean(),
          priv_flag: boolean(),
          reportable_flag: boolean()
        }

  @type security_parameters :: %{
          authoritative_engine_id: engine_id(),
          authoritative_engine_boots: engine_boots(),
          authoritative_engine_time: engine_time(),
          user_name: security_name(),
          authentication_parameters: binary(),
          privacy_parameters: binary()
        }

  # Time window for message freshness (RFC 3414)
  @time_window 150

  # Maximum engine boots value before rollover

  ## Engine Discovery and Time Synchronization

  @doc """
  Discovers the engine ID of a remote SNMP agent.

  Engine discovery is the first step in establishing secure communication
  with a remote SNMPv3 agent. This function sends a discovery request and
  retrieves the agent's authoritative engine ID.

  ## Parameters

  - `host`: Target agent IP address or hostname
  - `opts`: Discovery options including port, timeout, and community

  ## Returns

  - `{:ok, engine_id}`: Successfully discovered engine ID
  - `{:error, reason}`: Discovery failed

  ## Examples

      {:ok, engine_id} = SnmpKit.SnmpLib.Security.USM.discover_engine("192.168.1.1")
      {:ok, engine_id} = SnmpKit.SnmpLib.Security.USM.discover_engine("10.0.0.1", port: 1161, timeout: 5000)
  """
  @spec discover_engine(binary(), keyword()) :: {:ok, engine_id()} | {:error, atom()}
  def discover_engine(host, opts \\ []) do
    Logger.debug("Starting engine discovery for host: #{host}")

    try do
      # Create discovery message
      msg_id = :rand.uniform(2_147_483_647)
      discovery_message = SnmpKit.SnmpLib.PDU.V3Encoder.create_discovery_message(msg_id)

      # Encode discovery message (no security)
      case SnmpKit.SnmpLib.PDU.V3Encoder.encode_message(discovery_message, nil) do
        {:ok, request_packet} ->
          # Send discovery request
          case send_discovery_request(host, request_packet, opts) do
            {:ok, response_packet} ->
              # Decode response to extract engine ID
              case SnmpKit.SnmpLib.PDU.V3Encoder.decode_message(response_packet, nil) do
                {:ok, response_message} ->
                  extract_engine_id_from_response(response_message)

                {:error, reason} ->
                  Logger.error("Failed to decode discovery response: #{inspect(reason)}")
                  {:error, :decode_failed}
              end

            {:error, reason} ->
              Logger.error("Discovery request failed: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Failed to encode discovery message: #{inspect(reason)}")
          {:error, :encode_failed}
      end
    rescue
      error ->
        Logger.error("Engine discovery failed: #{inspect(error)}")
        {:error, :discovery_failed}
    end
  end

  @doc """
  Synchronizes time with a remote SNMP agent.

  Time synchronization is required for authenticated communication to prevent
  replay attacks. This function retrieves the agent's current boot counter
  and engine time (RFC 3414 section 2.3).

  The request is sent with `msgAuthoritativeEngineBoots`/`Time` of zero. The
  agent answers with a Report PDU (usmStatsNotInTimeWindows) whose security
  parameters carry its real boots and time, which are returned.

  ## Options

  - `:user` - a security user (see `SnmpKit.SnmpLib.Security.create_user/2`)
    with valid authentication keys. Agents only answer time-sync requests they
    can authenticate, so this is needed for real devices.
  - `:security_name`, `:port`, `:timeout`
  """
  @spec synchronize_time(binary(), engine_id(), keyword()) ::
          {:ok, {engine_boots(), engine_time()}} | {:error, atom()}
  def synchronize_time(host, engine_id, opts \\ []) do
    Logger.debug("Starting time synchronization with engine: #{Base.encode16(engine_id)}")

    try do
      msg_id = :rand.uniform(2_147_483_647)
      user = sync_user(engine_id, opts)

      time_sync_message = %{
        version: 3,
        msg_id: msg_id,
        msg_max_size: SnmpKit.SnmpLib.PDU.Constants.default_max_message_size(),
        msg_flags: %{auth: user.auth_protocol != :none, priv: false, reportable: true},
        msg_security_model: SnmpKit.SnmpLib.PDU.Constants.usm_security_model(),
        msg_security_parameters: <<>>,
        msg_data: %{
          context_engine_id: engine_id,
          context_name: <<>>,
          pdu: %{
            type: :get_request,
            request_id: msg_id,
            error_status: 0,
            error_index: 0,
            # snmpEngineTime OID
            varbinds: [{[1, 3, 6, 1, 6, 3, 10, 2, 1, 3, 0], :null, :null}]
          }
        }
      }

      case send_time_sync_request(host, time_sync_message, user, opts) do
        {:ok, engine_boots, engine_time} ->
          Logger.debug(
            "Time synchronization successful: boots=#{engine_boots}, time=#{engine_time}"
          )

          {:ok, {engine_boots, engine_time}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Time synchronization failed: #{inspect(error)}")
        {:error, :sync_failed}
    end
  end

  ## Message Processing

  @doc """
  Processes an outgoing SNMP message with USM security.

  This function applies authentication and/or privacy protection to an outgoing
  message based on the user's security level configuration.
  """
  @spec process_outgoing_message(user_entry(), binary(), security_level()) ::
          {:ok, binary()} | {:error, atom()}
  def process_outgoing_message(user, message, security_level) do
    Logger.debug("Processing outgoing message with security level: #{security_level}")

    try do
      # Validate security level matches user configuration
      case validate_security_level(user, security_level) do
        :ok ->
          # Decode the message to get the PDU
          case SnmpKit.SnmpLib.PDU.decode_message(message) do
            {:ok, decoded_message} ->
              # Convert to SNMPv3 format and apply security
              v3_message = convert_to_v3_message(decoded_message, user, security_level)

              case SnmpKit.SnmpLib.PDU.V3Encoder.encode_message(v3_message, user) do
                {:ok, secure_message} ->
                  Logger.debug("Message security processing successful")
                  {:ok, secure_message}

                {:error, reason} ->
                  Logger.error("Failed to encode secure message: #{inspect(reason)}")
                  {:error, :encoding_failed}
              end

            {:error, reason} ->
              Logger.error("Failed to decode input message: #{inspect(reason)}")
              {:error, :decode_failed}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Message processing failed: #{inspect(error)}")
        {:error, :processing_failed}
    end
  end

  # Helper functions for engine discovery and time synchronization

  defp send_discovery_request(host, request_packet, opts) do
    port = Keyword.get(opts, :port, 161)
    timeout = Keyword.get(opts, :timeout, 5000)

    case :gen_udp.open(0, [:binary, {:active, false}]) do
      {:ok, socket} ->
        try do
          case :gen_udp.send(socket, to_charlist(host), port, request_packet) do
            :ok ->
              case :gen_udp.recv(socket, 0, timeout) do
                {:ok, {_address, _port, response_packet}} ->
                  {:ok, response_packet}

                {:error, reason} ->
                  {:error, reason}
              end

            {:error, reason} ->
              {:error, reason}
          end
        after
          :gen_udp.close(socket)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_engine_id_from_response(%{msg_data: %{context_engine_id: engine_id}})
       when byte_size(engine_id) > 0 do
    {:ok, engine_id}
  end

  defp extract_engine_id_from_response(_response) do
    {:error, :no_engine_id_found}
  end

  # The sync request goes out with boots/time 0 so the agent reports its own.
  defp sync_user(engine_id, opts) do
    base =
      case Keyword.get(opts, :user) do
        %{} = user ->
          user

        nil ->
          %{
            security_name: Keyword.get(opts, :security_name, ""),
            auth_protocol: :none,
            priv_protocol: :none,
            auth_key: <<>>,
            priv_key: <<>>
          }
      end

    Map.merge(base, %{engine_id: engine_id, engine_boots: 0, engine_time: 0})
  end

  defp send_time_sync_request(host, message, user, opts) do
    with {:ok, packet} <- SnmpKit.SnmpLib.PDU.V3Encoder.encode_message(message, user),
         {:ok, response_packet} <- send_discovery_request(host, packet, opts),
         {:ok, response} <- decode_sync_response(response_packet, user) do
      extract_timing_from_response(response)
    end
  end

  # A Report about our zero boots/time is authenticated by the agent with the
  # user's key; anything else (e.g. an unauthenticated report) is still useful
  # for its header, so fall back to header-only decoding.
  defp decode_sync_response(packet, user) do
    case SnmpKit.SnmpLib.PDU.V3Encoder.decode_message(packet, user) do
      {:ok, response} -> {:ok, response}
      {:error, _} -> SnmpKit.SnmpLib.PDU.V3Encoder.decode_message_header(packet)
    end
  end

  defp extract_timing_from_response(%{security_parameters: %{} = params}) do
    {:ok, params.authoritative_engine_boots, params.authoritative_engine_time}
  end

  defp extract_timing_from_response(_response) do
    {:error, :no_timing_info}
  end

  defp validate_security_level(user, security_level) do
    case {user.auth_protocol, user.priv_protocol, security_level} do
      {:none, :none, :no_auth_no_priv} -> :ok
      {auth, :none, :auth_no_priv} when auth != :none -> :ok
      {auth, priv, :auth_priv} when auth != :none and priv != :none -> :ok
      _ -> {:error, :security_level_mismatch}
    end
  end

  defp convert_to_v3_message(v1v2c_message, user, security_level) do
    flags = SnmpKit.SnmpLib.PDU.Constants.default_msg_flags(security_level)

    %{
      version: 3,
      msg_id: :rand.uniform(2_147_483_647),
      msg_max_size: SnmpKit.SnmpLib.PDU.Constants.default_max_message_size(),
      msg_flags: flags,
      msg_security_model: SnmpKit.SnmpLib.PDU.Constants.usm_security_model(),
      msg_security_parameters: <<>>,
      msg_data: %{
        context_engine_id: user.engine_id,
        context_name: <<>>,
        pdu: v1v2c_message.pdu
      }
    }
  end

  @doc """
  Processes an incoming SNMP message with USM security.

  Implements the receiving side of RFC 3414 section 3.2: the header is read to
  find `msgUserName`, the user is looked up in `user_database` (a map from
  security name to user entry), the engine ID, security level and timeliness
  window are checked, and finally the message is authenticated and decrypted
  with that user's keys.

  User entries must carry the authoritative engine's current `engine_boots`
  and `engine_time`; those are what incoming messages are checked against.

  ## Options

  - `:time_window` - allowed |time difference| in seconds (default 150)

  ## Returns

  - `{:ok, {message, user}}` where `message` is the decoded SNMPv3 message
    (see `SnmpKit.SnmpLib.PDU.V3Encoder.decode_message/2`)
  - `{:error, reason}` with the RFC 3414 failure class, e.g.
    `:unknown_user_name`, `:unknown_engine_id`, `:unsupported_security_level`,
    `:not_in_time_window`, `:authentication_mismatch`
  """
  @spec process_incoming_message(binary(), map(), keyword()) ::
          {:ok, {map(), user_entry()}} | {:error, atom()}
  def process_incoming_message(secure_message, user_database, opts \\ []) do
    Logger.debug("Processing incoming secure message")

    alias SnmpKit.SnmpLib.PDU.V3Encoder

    with {:ok, header} <- V3Encoder.decode_message_header(secure_message),
         {:ok, params} <- fetch_security_params(header),
         {:ok, user} <- lookup_user(user_database, params.user_name),
         :ok <- validate_security_parameters(user, params, header.msg_flags, opts),
         {:ok, message} <- V3Encoder.decode_message(secure_message, user) do
      Logger.debug("Incoming message processing successful")
      {:ok, {message, user}}
    else
      {:error, reason} ->
        Logger.error("Incoming message processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  ## Security Parameter Management

  @doc """
  Validates time-based security parameters to prevent replay attacks.

  Per RFC 3414, messages are considered fresh if:
  - Engine boots match (within 1)
  - Engine time is within 150 seconds
  """
  @spec validate_time_window(
          engine_boots(),
          engine_time(),
          engine_boots(),
          engine_time(),
          keyword()
        ) ::
          :ok | {:error, atom()}
  def validate_time_window(local_boots, local_time, remote_boots, remote_time, opts \\ []) do
    window = Keyword.get(opts, :time_window, @time_window)
    boots_diff = abs(local_boots - remote_boots)
    time_diff = abs(local_time - remote_time)

    cond do
      boots_diff > 1 ->
        Logger.warning("Engine boots difference too large: #{boots_diff}")
        {:error, :engine_boots_mismatch}

      boots_diff == 1 and time_diff > window ->
        Logger.warning("Time window exceeded across boot boundary: #{time_diff}s")
        {:error, :time_window_exceeded}

      boots_diff == 0 and time_diff > window ->
        Logger.warning("Time window exceeded: #{time_diff}s > #{window}s")
        {:error, :time_window_exceeded}

      true ->
        Logger.debug("Time window validation successful")
        :ok
    end
  end

  ## Private Implementation

  # TODO: The following helper functions are for future SNMPv3 support
  # They are commented out to avoid Dialyzer warnings until a proper
  # SNMPv3 encoder is implemented that handles scoped_pdu and security_parameters

  # defp build_discovery_request do
  #   # SNMPv3 discovery message with empty security parameters
  #   %{
  #     message_id: :rand.uniform(2_147_483_647),
  #     max_size: 65507,
  #     flags: %{auth_flag: false, priv_flag: false, reportable_flag: true},
  #     security_model: 3,  # USM
  #     security_parameters: %{
  #       authoritative_engine_id: <<>>,
  #       authoritative_engine_boots: 0,
  #       authoritative_engine_time: 0,
  #       user_name: <<>>,
  #       authentication_parameters: <<>>,
  #       privacy_parameters: <<>>
  #     },
  #     scoped_pdu: build_discovery_pdu()
  #   }
  # end

  # defp build_discovery_pdu do
  #   # GET request for snmpEngineID (1.3.6.1.6.3.10.2.1.1.0)
  #   engine_id_oid = [1, 3, 6, 1, 6, 3, 10, 2, 1, 1, 0]
  #   PDU.build_get_request(engine_id_oid, :rand.uniform(2_147_483_647))
  # end

  # defp send_discovery_request(host, port, request, timeout) do
  #   # Serialize and send discovery request
  #   case PDU.encode_message(request) do
  #     {:ok, encoded_request} ->
  #       Transport.send_request(host, port, encoded_request, timeout)
  #     {:error, reason} ->
  #       {:error, reason}
  #   end
  # end

  # defp parse_discovery_response(response) do
  #   case PDU.decode_message(response) do
  #     {:ok, decoded} ->
  #       # Check if this is an SNMPv3 message with security parameters
  #       case Map.get(decoded, :security_parameters) do
  #         nil ->
  #           # This is likely an SNMPv1/v2c message, not v3
  #           {:error, :not_snmpv3_message}
  #         security_params ->
  #           # Extract engine ID from security parameters
  #           case Map.get(security_params, :authoritative_engine_id) do
  #             nil ->
  #               {:error, :missing_engine_id}
  #             engine_id when is_binary(engine_id) and byte_size(engine_id) > 0 ->
  #               {:ok, engine_id}
  #             _ ->
  #               {:error, :empty_engine_id}
  #           end
  #       end
  #     {:error, reason} ->
  #       {:error, reason}
  #   end
  # end

  # defp build_time_sync_request(engine_id) do
  #   %{
  #     message_id: :rand.uniform(2_147_483_647),
  #     max_size: 65507,
  #     flags: %{auth_flag: false, priv_flag: false, reportable_flag: true},
  #     security_model: 3,
  #     security_parameters: %{
  #       authoritative_engine_id: engine_id,
  #       authoritative_engine_boots: 0,
  #       authoritative_engine_time: 0,
  #       user_name: <<>>,
  #       authentication_parameters: <<>>,
  #       privacy_parameters: <<>>
  #     },
  #     scoped_pdu: build_discovery_pdu()
  #   }
  # end

  # defp send_time_sync_request(host, port, request, timeout) do
  #   case PDU.encode_message(request) do
  #     {:ok, encoded_request} ->
  #       Transport.send_request(host, port, encoded_request, timeout)
  #     {:error, reason} ->
  #       {:error, reason}
  #   end
  # end

  # defp parse_time_sync_response(response) do
  #   case PDU.decode_message(response) do
  #     {:ok, decoded} ->
  #       # Check if this is an SNMPv3 message with required fields
  #       case Map.get(decoded, :security_parameters) do
  #         nil ->
  #           # This is likely an SNMPv1/v2c message, not v3
  #           {:error, :not_snmpv3_message}
  #         security_params ->
  #           boots = Map.get(security_params, :authoritative_engine_boots, 0)
  #           time = Map.get(security_params, :authoritative_engine_time, 0)
  #           {:ok, {boots, time}}
  #       end
  #     {:error, reason} ->
  #       {:error, reason}
  #   end
  # end

  # TODO: Additional SNMPv3 helper functions - commented out until proper v3 support is implemented

  # defp determine_message_flags(:no_auth_no_priv) do
  #   {:ok, %{auth_flag: false, priv_flag: false, reportable_flag: false}}
  # end
  # defp determine_message_flags(:auth_no_priv) do
  #   {:ok, %{auth_flag: true, priv_flag: false, reportable_flag: false}}
  # end
  # defp determine_message_flags(:auth_priv) do
  #   {:ok, %{auth_flag: true, priv_flag: true, reportable_flag: false}}
  # end
  # defp determine_message_flags(_) do
  #   {:error, :invalid_security_level}
  # end

  # defp apply_security(user, message, flags) do
  #   with {:ok, encrypted_message, priv_params} <- maybe_encrypt(user, message, flags.priv_flag),
  #        {:ok, auth_params} <- maybe_authenticate(user, encrypted_message, flags.auth_flag) do
  #     {:ok, {encrypted_message, auth_params, priv_params}}
  #   end
  # end

  # defp maybe_encrypt(user, message, true) do
  #   case Priv.encrypt(user.priv_protocol, user.priv_key, user.auth_key, message) do
  #     {:ok, {encrypted, params}} -> {:ok, encrypted, params}
  #     {:error, reason} -> {:error, reason}
  #   end
  # end
  # defp maybe_encrypt(_user, message, false) do
  #   {:ok, message, <<>>}
  # end

  # defp maybe_authenticate(user, message, true) do
  #   Auth.authenticate(user.auth_protocol, user.auth_key, message)
  # end
  # defp maybe_authenticate(_user, _message, false) do
  #   {:ok, <<>>}
  # end

  # defp build_security_parameters(user, auth_params, priv_params) do
  #   params = %{
  #     authoritative_engine_id: user.engine_id,
  #     authoritative_engine_boots: 1,  # This should come from persistent storage
  #     authoritative_engine_time: System.system_time(:second),
  #     user_name: user.security_name,
  #     authentication_parameters: auth_params,
  #     privacy_parameters: priv_params
  #   }
  #   {:ok, params}
  # end

  # TODO: SNMPv3 message building - commented out until proper v3 encoder is implemented
  # defp build_secure_message(scoped_pdu, security_params, flags) do
  #   message = %{
  #     message_id: :rand.uniform(2_147_483_647),
  #     max_size: 65507,
  #     flags: flags,
  #     security_model: 3,
  #     security_parameters: security_params,
  #     scoped_pdu: scoped_pdu
  #   }
  #   PDU.encode_message(message)
  # end

  defp fetch_security_params(%{security_parameters: %{} = params}), do: {:ok, params}
  defp fetch_security_params(_header), do: {:error, :missing_security_parameters}

  defp lookup_user(user_database, user_name) do
    case Map.get(user_database, user_name) do
      nil -> {:error, :unknown_user_name}
      user -> {:ok, user}
    end
  end

  # RFC 3414 3.2 steps 3-5,7: engine ID, security level, then timeliness
  # (only authenticated messages carry trustworthy boots/time).
  defp validate_security_parameters(user, params, flags, opts) do
    with :ok <- validate_engine_id(user.engine_id, params.authoritative_engine_id),
         :ok <- validate_flags_against_user(user, flags) do
      if flags.auth do
        validate_time_window(
          user.engine_boots,
          user.engine_time,
          params.authoritative_engine_boots,
          params.authoritative_engine_time,
          opts
        )
        |> case do
          :ok -> :ok
          {:error, _} -> {:error, :not_in_time_window}
        end
      else
        :ok
      end
    end
  end

  defp validate_engine_id(expected, actual) do
    if expected == actual do
      :ok
    else
      {:error, :unknown_engine_id}
    end
  end

  defp validate_flags_against_user(user, flags) do
    cond do
      flags.priv and not flags.auth -> {:error, :unsupported_security_level}
      flags.priv and user.priv_protocol == :none -> {:error, :unsupported_security_level}
      flags.auth and user.auth_protocol == :none -> {:error, :unsupported_security_level}
      true -> :ok
    end
  end
end
