defmodule SnmpKit.SnmpSim.Core.UsmAgent do
  @moduledoc """
  Agent-side SNMPv3 User-based Security Model for simulated devices
  (RFC 3414): engine identity, boots and time, per-user localized keys,
  authentication and privacy on both directions, and the `usmStats` reports
  that drive a manager's discovery and time synchronisation.

  A device gets one of these when started with `v3_users:`:

      SnmpKit.Sim.start_device(profile,
        port: 1161,
        v3_users: [
          %{name: "guest"},
          %{name: "ops", auth: :sha256, auth_password: "authpass"},
          %{name: "admin", auth: :sha256, auth_password: "authpass", priv: :aes128, priv_password: "privpass"}
        ]
      )

  Each user's `auth` may be `:md5`, `:sha1`, `:sha256`, `:sha384` or
  `:sha512` and `priv` may be `:des`, `:aes128`, `:aes192` or `:aes256`; a
  request must use at least the user's security level.
  """

  require Logger

  alias SnmpKit.SnmpLib.PDU.V3Encoder
  alias SnmpKit.SnmpLib.Security

  @time_window 150
  @usm_stats [1, 3, 6, 1, 6, 3, 15, 1, 1]

  @type t :: %__MODULE__{
          engine_id: binary(),
          engine_boots: non_neg_integer(),
          started_at: integer(),
          users: %{String.t() => map()},
          stats: map()
        }

  defstruct engine_id: <<>>, engine_boots: 1, started_at: 0, users: %{}, stats: %{}

  @doc """
  Builds the agent state. Options: `:v3_users` (list of maps or keyword
  lists with `name`, `auth`, `auth_password`, `priv`, `priv_password`),
  `:engine_id` (binary; derived from `:device_id` when absent),
  `:engine_boots` (default 1).
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) do
    engine_id =
      Keyword.get(opts, :engine_id) || derive_engine_id(Keyword.get(opts, :device_id, "snmpkit"))

    users =
      Enum.reduce_while(Keyword.get(opts, :v3_users, []), {:ok, %{}}, fn spec, {:ok, acc} ->
        case build_user(spec, engine_id) do
          {:ok, user} -> {:cont, {:ok, Map.put(acc, user.security_name, user)}}
          {:error, reason} -> {:halt, {:error, {:invalid_v3_user, spec, reason}}}
        end
      end)

    with {:ok, users} <- users do
      {:ok,
       %__MODULE__{
         engine_id: engine_id,
         engine_boots: Keyword.get(opts, :engine_boots, 1),
         started_at: System.monotonic_time(:second),
         users: users,
         stats: %{}
       }}
    end
  end

  @doc "RFC 3411 engine id (format 4, text) derived from a device id."
  @spec derive_engine_id(String.t()) :: binary()
  def derive_engine_id(device_id) do
    # enterprise 0 (reserved) with the text format so the id is stable and printable
    <<0x80, 0, 0, 0, 0, 4>> <> binary_part(:crypto.hash(:sha, to_string(device_id)), 0, 12)
  end

  @doc "The agent's engine time in seconds since its boot."
  @spec engine_time(t()) :: non_neg_integer()
  def engine_time(%__MODULE__{started_at: started_at}),
    do: System.monotonic_time(:second) - started_at

  @doc """
  Decodes an incoming SNMPv3 datagram. Returns `{:request, pdu, ctx}` for a
  request the device should answer (encode the reply with
  `encode_response/3`), `{:report, packet}` for a USM report to send back
  as-is, or `{:error, reason}` to drop it.
  """
  @spec decode_request(binary(), t()) ::
          {:request, map(), map()} | {:report, binary()} | {:error, term()}
  def decode_request(packet, %__MODULE__{} = agent) do
    with {:ok, header} <- V3Encoder.decode_message_header(packet),
         params = header.security_parameters || %{},
         request_id = request_id_from(packet, header) do
      user_name = Map.get(params, :user_name, "")
      remote_engine = Map.get(params, :authoritative_engine_id, <<>>)
      flags = header.msg_flags

      cond do
        remote_engine != agent.engine_id ->
          report(agent, header, request_id, 4, user_name, nil)

        not Map.has_key?(agent.users, user_name) ->
          report(agent, header, request_id, 3, user_name, nil)

        true ->
          user = agent.users[user_name] |> with_agent_time(agent)

          cond do
            level_too_low?(user, flags) ->
              report(agent, header, request_id, 1, user_name, nil)

            flags.auth and not in_time_window?(agent, params) ->
              # authenticated so the manager can trust the boots/time we send
              report(agent, header, request_id, 2, user_name, user)

            true ->
              decode_with_user(packet, header, user, agent, request_id)
          end
      end
    end
  end

  @doc "Encodes the device's response PDU for the request context returned by `decode_request/2`."
  @spec encode_response(map(), map(), t()) :: {:ok, binary()} | {:error, term()}
  def encode_response(response_pdu, ctx, %__MODULE__{} = agent) do
    user = with_agent_time(ctx.user, agent)

    message = %{
      version: 3,
      msg_id: ctx.msg_id,
      msg_max_size: 65507,
      msg_flags: %{auth: ctx.flags.auth, priv: ctx.flags.priv, reportable: false},
      msg_security_model: 3,
      msg_security_parameters: <<>>,
      msg_data: %{
        context_engine_id: agent.engine_id,
        context_name: ctx.context_name,
        pdu: response_pdu
      }
    }

    V3Encoder.encode_message(message, user)
  end

  ## internals

  defp decode_with_user(packet, header, user, agent, request_id) do
    case V3Encoder.decode_message(packet, user) do
      {:ok, message} ->
        pdu = message.msg_data.pdu

        ctx = %{
          msg_id: header.msg_id,
          flags: header.msg_flags,
          user: user,
          context_name: message.msg_data.context_name
        }

        {:request, pdu, ctx}

      {:error, reason} when reason in [:authentication_failed, :authentication_mismatch] ->
        report(agent, header, request_id, 5, user.security_name, nil)

      {:error, reason} when reason in [:decryption_failed, :decryption_error, :invalid_padding] ->
        report(agent, header, request_id, 6, user.security_name, user)

      {:error, _reason} when header.msg_flags.priv ->
        # authenticated but the scoped PDU did not decrypt to anything valid:
        # the sender's privacy key differs from ours (RFC 3414 3.2 step 8)
        report(agent, header, request_id, 6, user.security_name, user)

      {:error, reason} ->
        Logger.debug("USM agent: dropping undecodable v3 request: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # usmStats<N>: 1 unsupportedSecLevels, 2 notInTimeWindows, 3 unknownUserNames,
  # 4 unknownEngineIDs, 5 wrongDigests, 6 decryptionErrors
  defp report(agent, header, request_id, stat, user_name, auth_user) do
    counter = Map.get(agent.stats, stat, 0) + 1

    report_pdu = %{
      type: :report,
      request_id: request_id,
      error_status: 0,
      error_index: 0,
      varbinds: [{@usm_stats ++ [stat, 0], :counter32, counter}]
    }

    {flags, user} =
      case auth_user do
        nil -> {%{auth: false, priv: false, reportable: false}, plain_user(agent, user_name)}
        user -> {%{auth: true, priv: false, reportable: false}, user}
      end

    message = %{
      version: 3,
      msg_id: header.msg_id,
      msg_max_size: 65507,
      msg_flags: flags,
      msg_security_model: 3,
      msg_security_parameters: <<>>,
      msg_data: %{context_engine_id: agent.engine_id, context_name: "", pdu: report_pdu}
    }

    case V3Encoder.encode_message(message, user) do
      {:ok, packet} -> {:report, packet}
      {:error, reason} -> {:error, {:report_encoding_failed, reason}}
    end
  end

  defp plain_user(agent, user_name) do
    %{
      security_name: user_name,
      auth_protocol: :none,
      priv_protocol: :none,
      auth_key: <<>>,
      priv_key: <<>>,
      engine_id: agent.engine_id,
      engine_boots: agent.engine_boots,
      engine_time: engine_time(agent)
    }
  end

  defp with_agent_time(user, agent) do
    Map.merge(user, %{
      engine_id: agent.engine_id,
      engine_boots: agent.engine_boots,
      engine_time: engine_time(agent)
    })
  end

  defp level_too_low?(user, flags) do
    (user.auth_protocol != :none and not flags.auth) or
      (user.priv_protocol != :none and not flags.priv) or
      (flags.priv and user.priv_protocol == :none) or
      (flags.auth and user.auth_protocol == :none)
  end

  defp in_time_window?(agent, params) do
    boots = Map.get(params, :authoritative_engine_boots, 0)
    time = Map.get(params, :authoritative_engine_time, 0)
    boots == agent.engine_boots and abs(time - engine_time(agent)) <= @time_window
  end

  # The request id is inside the (possibly encrypted) scoped PDU; reports for
  # unauthenticated or unreadable requests use 0, which managers accept.
  defp request_id_from(packet, %{msg_flags: %{priv: false}}) do
    case V3Encoder.decode_message(packet, nil) do
      {:ok, %{msg_data: %{pdu: %{request_id: id}}}} -> id
      _ -> 0
    end
  end

  defp request_id_from(_packet, _header), do: 0

  defp build_user(spec, engine_id) do
    spec = Map.new(spec)
    name = spec[:name] || spec["name"]

    if is_binary(name) and name != "" do
      config =
        [
          auth_protocol: spec[:auth] || spec[:auth_protocol],
          auth_password: spec[:auth_password],
          priv_protocol: spec[:priv] || spec[:priv_protocol],
          priv_password: spec[:priv_password],
          engine_id: engine_id
        ]
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      Security.create_user(name, config)
    else
      {:error, :name_required}
    end
  end
end
