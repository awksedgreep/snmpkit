defmodule SnmpKit.SnmpLib.Manager.V3 do
  @moduledoc """
  SNMPv3 (USM) request path for the manager: engine discovery, key
  localization, time synchronisation, and the report-driven retries RFC 3414
  requires.

  Used by `SnmpKit.SnmpLib.Manager.Request.perform_snmp_request/4` when the
  options carry `version: :v3`. Options:

  - `:security_name` - the USM user name (required)
  - `:auth_protocol` (`:md5`, `:sha1`, `:sha256`, `:sha384`, `:sha512`) and `:auth_password`
  - `:priv_protocol` (`:des`, `:aes128`, `:aes192`, `:aes256`) and `:priv_password`
  - `:security_level` - `:no_auth_no_priv`, `:auth_no_priv` or `:auth_priv`;
    derived from the protocols when omitted
  - `:context_name` - default `""`
  - `:engine_id` - skip discovery and use this authoritative engine id

  The result has the shape the v1/v2c path returns, `%{version: 3, community:
  security_name, pdu: pdu}`, so response extraction is shared.
  """

  require Logger

  alias SnmpKit.SnmpLib.PDU.V3Encoder
  alias SnmpKit.SnmpLib.Security
  alias SnmpKit.SnmpLib.Security.EngineCache

  @usm_stats_prefix [1, 3, 6, 1, 6, 3, 15, 1, 1]
  @report_names %{
    1 => :usm_stats_unsupported_sec_levels,
    2 => :usm_stats_not_in_time_windows,
    3 => :usm_stats_unknown_user_names,
    4 => :usm_stats_unknown_engine_ids,
    5 => :usm_stats_wrong_digests,
    6 => :usm_stats_decryption_errors
  }

  @doc "Sends `pdu` to `ip:port` over SNMPv3 and returns the response message."
  @spec perform(port(), :inet.ip_address(), :inet.port_number(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def perform(socket, ip, port, pdu, opts) do
    with {:ok, security_name} <- fetch_security_name(opts),
         {:ok, level} <- security_level(opts),
         {:ok, engine} <- engine(socket, ip, port, opts),
         {:ok, user} <- localized_user(security_name, engine, opts) do
      exchange(socket, ip, port, pdu, user, level, opts, 2)
    end
  end

  ## engine discovery and cache

  defp engine(socket, ip, port, opts) do
    case Keyword.get(opts, :engine_id) do
      nil ->
        case EngineCache.lookup({ip, port}) do
          nil -> discover(socket, ip, port, opts)
          entry -> {:ok, entry}
        end

      engine_id when is_binary(engine_id) ->
        {:ok,
         EngineCache.lookup({ip, port}) ||
           %{
             engine_id: engine_id,
             engine_boots: 0,
             time_offset: -System.monotonic_time(:second),
             learned_at: 0
           }}
    end
  end

  defp discover(socket, ip, port, opts) do
    msg_id = :rand.uniform(2_147_483_647)
    message = V3Encoder.create_discovery_message(msg_id)

    with {:ok, packet} <- V3Encoder.encode_message(message, nil),
         {:ok, response} <- send_receive(socket, ip, port, packet, msg_id, nil, opts),
         {:ok, engine_id} <- engine_id_of(response) do
      params = response.security_parameters || %{}
      boots = Map.get(params, :authoritative_engine_boots, 0)
      time = Map.get(params, :authoritative_engine_time, 0)
      EngineCache.store({ip, port}, engine_id, boots, time)
      {:ok, EngineCache.lookup({ip, port})}
    end
  end

  defp engine_id_of(%{msg_data: %{context_engine_id: id}}) when byte_size(id) > 0, do: {:ok, id}

  defp engine_id_of(%{security_parameters: %{authoritative_engine_id: id}})
       when byte_size(id) > 0,
       do: {:ok, id}

  defp engine_id_of(_), do: {:error, :no_engine_id_found}

  ## users

  defp localized_user(security_name, engine, opts) do
    config =
      opts
      |> Keyword.take([:auth_protocol, :auth_password, :priv_protocol, :priv_password])
      |> Keyword.put(:engine_id, engine.engine_id)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    with {:ok, user} <- Security.create_user(security_name, config) do
      {:ok, with_engine_time(user, engine)}
    end
  end

  defp with_engine_time(user, engine) do
    %{user | engine_boots: engine.engine_boots, engine_time: EngineCache.current_time(engine)}
  end

  defp fetch_security_name(opts) do
    case Keyword.get(opts, :security_name) do
      name when is_binary(name) and name != "" -> {:ok, name}
      _ -> {:error, :security_name_required}
    end
  end

  defp security_level(opts) do
    auth = Keyword.get(opts, :auth_protocol, :none)
    priv = Keyword.get(opts, :priv_protocol, :none)

    level =
      Keyword.get_lazy(opts, :security_level, fn ->
        cond do
          priv not in [nil, :none] -> :auth_priv
          auth not in [nil, :none] -> :auth_no_priv
          true -> :no_auth_no_priv
        end
      end)

    cond do
      level == :auth_priv and priv in [nil, :none] ->
        {:error, :priv_protocol_required}

      level in [:auth_priv, :auth_no_priv] and auth in [nil, :none] ->
        {:error, :auth_protocol_required}

      level in [:no_auth_no_priv, :auth_no_priv, :auth_priv] ->
        {:ok, level}

      true ->
        {:error, {:invalid_security_level, level}}
    end
  end

  ## the exchange, with report handling

  defp exchange(_socket, _ip, _port, _pdu, _user, _level, _opts, 0),
    do: {:error, :too_many_reports}

  defp exchange(socket, ip, port, pdu, user, level, opts, attempts_left) do
    msg_id = :rand.uniform(2_147_483_647)
    flags = %{auth: level != :no_auth_no_priv, priv: level == :auth_priv, reportable: true}

    message = %{
      version: 3,
      msg_id: msg_id,
      msg_max_size: 65507,
      msg_flags: flags,
      msg_security_model: 3,
      msg_security_parameters: <<>>,
      msg_data: %{
        context_engine_id: user.engine_id,
        context_name: Keyword.get(opts, :context_name, ""),
        pdu: pdu
      }
    }

    with {:ok, packet} <- V3Encoder.encode_message(message, user),
         {:ok, response} <- send_receive(socket, ip, port, packet, msg_id, user, opts) do
      case response.msg_data.pdu do
        %{type: :report} = report ->
          handle_report(report, response, socket, ip, port, pdu, user, level, opts, attempts_left)

        response_pdu ->
          {:ok, %{version: 3, community: user.security_name, pdu: response_pdu}}
      end
    end
  end

  defp handle_report(report, response, socket, ip, port, pdu, user, level, opts, attempts_left) do
    name = report_name(report)
    params = response.security_parameters || %{}

    case name do
      kind when kind in [:usm_stats_not_in_time_windows, :usm_stats_unknown_engine_ids] ->
        engine_id = Map.get(params, :authoritative_engine_id, user.engine_id)
        boots = Map.get(params, :authoritative_engine_boots, 0)
        time = Map.get(params, :authoritative_engine_time, 0)
        EngineCache.store({ip, port}, engine_id, boots, time)
        engine = EngineCache.lookup({ip, port})

        Logger.debug("SNMPv3 #{kind} from #{:inet.ntoa(ip)}: resynchronised, retrying")

        with {:ok, user} <- localized_user(user.security_name, engine, opts) do
          exchange(socket, ip, port, pdu, user, level, opts, attempts_left - 1)
        end

      other ->
        {:error, {:usm_report, other}}
    end
  end

  defp report_name(%{varbinds: [{oid, _type, _value} | _]}) do
    case oid do
      list when is_list(list) ->
        report_name_for(list)

      string when is_binary(string) ->
        case SnmpKit.SnmpLib.OID.string_to_list(string) do
          {:ok, list} -> report_name_for(list)
          _ -> :unknown_report
        end
    end
  end

  defp report_name(_), do: :unknown_report

  defp report_name_for(oid) do
    case oid do
      @usm_stats_prefix ++ [n, 0] -> Map.get(@report_names, n, :unknown_report)
      _ -> {:report, oid}
    end
  end

  ## sending and receiving

  # A discovery/report reply comes with no or partial security; decode with
  # the user when we have one, else headers only.
  defp send_receive(socket, ip, port, packet, msg_id, user, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)
    retries = max(Keyword.get(opts, :retries, 1), 0)
    attempt(socket, ip, port, packet, msg_id, user, timeout, retries + 1)
  end

  defp attempt(_socket, _ip, _port, _packet, _msg_id, _user, _timeout, 0), do: {:error, :timeout}

  defp attempt(socket, ip, port, packet, msg_id, user, timeout, attempts) do
    with :ok <- SnmpKit.SnmpLib.Transport.send_packet(socket, ip, port, packet) do
      deadline = System.monotonic_time(:millisecond) + timeout

      case receive_loop(socket, ip, port, msg_id, user, deadline) do
        {:error, :timeout} ->
          attempt(socket, ip, port, packet, msg_id, user, timeout, attempts - 1)

        other ->
          other
      end
    end
  end

  defp receive_loop(socket, ip, port, msg_id, user, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case SnmpKit.SnmpLib.Transport.receive_packet(socket, remaining) do
      {:ok, {data, ^ip, ^port}} ->
        case V3Encoder.decode_message_header(data) do
          {:ok, %{msg_id: ^msg_id} = header} ->
            decode_body(data, header, user)

          _ ->
            receive_loop(socket, ip, port, msg_id, user, deadline)
        end

      {:ok, _other_sender} ->
        receive_loop(socket, ip, port, msg_id, user, deadline)

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  # Reports may be unauthenticated even when we asked for auth; decode with the
  # user first and fall back to a plain decode for report-style replies.
  defp decode_body(data, header, user) do
    case V3Encoder.decode_message(data, user) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} when header.msg_flags.auth == false and header.msg_flags.priv == false ->
        case V3Encoder.decode_message(data, nil) do
          {:ok, message} -> {:ok, message}
          _ -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
