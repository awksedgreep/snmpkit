defmodule SnmpKit.Trap do
  @moduledoc """
  Receives SNMP notifications (SNMPv1 traps, SNMPv2c traps and informs) and
  hands each one to a handler.

      {:ok, receiver} = SnmpKit.Trap.start_link(port: 162, handler: &MyApp.Alerts.handle/1)

      # or in a supervision tree
      children = [{SnmpKit.Trap, port: 162, handler: {MyApp.Alerts, :handle, []}}]

  Informs are acknowledged automatically. SNMPv3 notifications are counted
  under `:unsupported` and dropped.

  ## Options

  - `:port` - UDP port to bind (default 162; use 0 for an ephemeral port and
    read it back with `port/1`)
  - `:bind_address` - interface to bind (default `"0.0.0.0"`)
  - `:handler` - `fun/1`, `{module, function, extra_args}` (the notification
    is prepended to `extra_args`), or a pid that receives
    `{:snmp_trap, notification}`
  - `:communities` - list of accepted community strings; `nil` (default)
    accepts any
  - `:acknowledge_informs` - default `true`
  - `:include_names`, `:include_formatted` - varbind enrichment, as for
    `SnmpKit.SNMP` calls
  - `:name` - GenServer registration

  ## Notifications

  Each notification is a map:

      %{
        kind: :trap | :inform,
        version: :v1 | :v2c,
        community: "public",
        source: {{192, 168, 1, 10}, 49152},   # sender address and port
        agent_address: {192, 168, 1, 10},     # v1: the agent-addr field
        trap_oid: [1, 3, 6, 1, 6, 3, 1, 1, 5, 3],
        trap_name: "linkDown",                # nil when unknown
        uptime: 123456,                       # sysUpTime, centiseconds
        request_id: 42,                       # v2c only
        enterprise: nil,                      # v1 only
        generic_trap: nil, specific_trap: nil,# v1 only
        varbinds: [%{oid: ..., type: ..., value: ..., name: ..., formatted: ...}],
        received_at: ~U[...]
      }

  For SNMPv2c the `sysUpTime.0` and `snmpTrapOID.0` varbinds are kept in
  `:varbinds` as well as lifted into `:uptime` and `:trap_oid`. For SNMPv1
  the trap OID is derived per RFC 3584.
  """

  use GenServer
  require Logger

  alias SnmpKit.SnmpLib.{OID, PDU}
  alias SnmpKit.SnmpMgr.Format

  @sys_uptime_oid [1, 3, 6, 1, 2, 1, 1, 3, 0]
  @snmp_trap_oid [1, 3, 6, 1, 6, 3, 1, 1, 4, 1, 0]
  @snmp_traps_prefix [1, 3, 6, 1, 6, 3, 1, 1, 5]

  @type notification :: map()

  defstruct [:socket, :port, :handler, :communities, :ack, :enrich_opts, stats: %{}]

  ## API

  @doc "Starts a receiver. See the module documentation for options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :port, 162)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc "The UDP port the receiver is bound to."
  @spec port(GenServer.server()) :: :inet.port_number()
  def port(server), do: GenServer.call(server, :port)

  @doc """
  Counters: `:received`, `:traps`, `:informs`, `:acknowledged`,
  `:decode_errors`, `:rejected_community`, `:unsupported`, `:handler_errors`.
  """
  @spec stats(GenServer.server()) :: map()
  def stats(server), do: GenServer.call(server, :stats)

  @doc "Stops the receiver and closes its socket."
  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  ## GenServer

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 162)
    bind = Keyword.get(opts, :bind_address, "0.0.0.0")

    with {:ok, ip} <- SnmpKit.SnmpLib.Transport.resolve_address(bind),
         {:ok, socket} <-
           :gen_udp.open(port, [
             :binary,
             {:active, true},
             {:ip, ip},
             {:reuseaddr, true},
             {:recbuf, 262_144}
           ]),
         {:ok, bound_port} <- :inet.port(socket) do
      state = %__MODULE__{
        socket: socket,
        port: bound_port,
        handler: Keyword.get(opts, :handler),
        communities: Keyword.get(opts, :communities),
        ack: Keyword.get(opts, :acknowledge_informs, true),
        enrich_opts: Keyword.take(opts, [:include_names, :include_formatted]),
        stats: %{
          received: 0,
          traps: 0,
          informs: 0,
          acknowledged: 0,
          decode_errors: 0,
          rejected_community: 0,
          unsupported: 0,
          handler_errors: 0
        }
      }

      Logger.info("SNMP trap receiver listening on #{:inet.ntoa(ip)}:#{bound_port}")
      {:ok, state}
    else
      {:error, reason} -> {:stop, {:cannot_bind, port, reason}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}
  def handle_call(:stats, _from, state), do: {:reply, state.stats, state}

  @impl true
  def handle_info({:udp, socket, ip, port, data}, %{socket: socket} = state) do
    state = bump(state, :received)

    case PDU.decode_message(data) do
      {:ok, %{version: 3}} ->
        {:noreply, bump(state, :unsupported)}

      {:ok, %{pdu: %{type: type}} = message}
      when type in [:trap, :snmpv2_trap, :inform_request] ->
        if accepted_community?(state, message.community) do
          {:noreply, deliver(state, message, ip, port)}
        else
          {:noreply, bump(state, :rejected_community)}
        end

      {:ok, _other_pdu} ->
        {:noreply, bump(state, :unsupported)}

      {:error, reason} ->
        Logger.debug(
          "Trap receiver: undecodable packet from #{:inet.ntoa(ip)}:#{port}: #{inspect(reason)}"
        )

        {:noreply, bump(state, :decode_errors)}
    end
  end

  def handle_info({:udp_closed, socket}, %{socket: socket} = state) do
    {:stop, :socket_closed, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{socket: socket}) when socket != nil, do: :gen_udp.close(socket)
  def terminate(_reason, _state), do: :ok

  ## Internal

  defp accepted_community?(%{communities: nil}, _community), do: true
  defp accepted_community?(%{communities: list}, community), do: community in list

  defp deliver(state, %{pdu: pdu} = message, ip, port) do
    notification = notification(message, ip, port, state.enrich_opts)

    state =
      case pdu.type do
        :inform_request -> state |> bump(:informs) |> maybe_acknowledge(message, ip, port)
        _ -> bump(state, :traps)
      end

    dispatch(state.handler, notification)
    state
  end

  defp maybe_acknowledge(%{ack: false} = state, _message, _ip, _port), do: state

  defp maybe_acknowledge(state, %{community: community, pdu: pdu} = message, ip, port) do
    response = PDU.build_response(pdu.request_id, 0, 0, pdu.varbinds)
    version = if message.version == 0, do: :v1, else: :v2c

    with {:ok, packet} <- PDU.encode_message(PDU.build_message(response, community, version)),
         :ok <- :gen_udp.send(state.socket, ip, port, packet) do
      bump(state, :acknowledged)
    else
      error ->
        Logger.warning("Trap receiver: could not acknowledge inform: #{inspect(error)}")
        state
    end
  end

  defp dispatch(nil, _notification), do: :ok
  defp dispatch(pid, notification) when is_pid(pid), do: send(pid, {:snmp_trap, notification})

  defp dispatch(handler, notification) do
    spawn(fn ->
      try do
        case handler do
          fun when is_function(fun, 1) -> fun.(notification)
          {mod, fun, args} -> apply(mod, fun, [notification | args])
        end
      rescue
        e -> Logger.error("Trap handler raised: #{Exception.message(e)}")
      end
    end)

    :ok
  end

  defp notification(
         %{version: 0, community: community, pdu: %{type: :trap} = pdu},
         ip,
         port,
         enrich_opts
       ) do
    trap_oid = v1_trap_oid(pdu.enterprise, pdu.generic_trap, pdu.specific_trap)

    %{
      kind: :trap,
      version: :v1,
      community: community,
      source: {ip, port},
      agent_address: ip_tuple(pdu.agent_addr, ip),
      trap_oid: trap_oid,
      trap_name: trap_name(trap_oid, enrich_opts),
      uptime: pdu.time_stamp,
      request_id: nil,
      enterprise: pdu.enterprise,
      generic_trap: pdu.generic_trap,
      specific_trap: pdu.specific_trap,
      varbinds: Format.enrich_varbinds(pdu.varbinds, enrich_opts),
      received_at: DateTime.utc_now()
    }
  end

  defp notification(%{community: community, pdu: pdu}, ip, port, enrich_opts) do
    trap_oid = varbind_value(pdu.varbinds, @snmp_trap_oid) |> normalize_oid_value()

    %{
      kind: if(pdu.type == :inform_request, do: :inform, else: :trap),
      version: :v2c,
      community: community,
      source: {ip, port},
      agent_address: ip,
      trap_oid: trap_oid,
      trap_name: trap_name(trap_oid, enrich_opts),
      uptime: varbind_value(pdu.varbinds, @sys_uptime_oid),
      request_id: pdu.request_id,
      enterprise: nil,
      generic_trap: nil,
      specific_trap: nil,
      varbinds: Format.enrich_varbinds(pdu.varbinds, enrich_opts),
      received_at: DateTime.utc_now()
    }
  end

  # RFC 3584 section 3.1
  defp v1_trap_oid(_enterprise, generic, _specific) when generic in 0..5,
    do: @snmp_traps_prefix ++ [generic + 1]

  defp v1_trap_oid(enterprise, _generic, specific), do: enterprise ++ [0, specific]

  defp varbind_value(varbinds, oid) do
    Enum.find_value(varbinds, fn {vb_oid, _type, value} ->
      if normalize_oid_value(vb_oid) == oid, do: value
    end)
  end

  defp normalize_oid_value(oid) when is_list(oid), do: oid

  defp normalize_oid_value(oid) when is_binary(oid) do
    case OID.string_to_list(oid) do
      {:ok, list} -> list
      _ -> nil
    end
  end

  defp normalize_oid_value(_), do: nil

  defp trap_name(nil, _opts), do: nil

  defp trap_name(oid, opts) do
    if Keyword.get(opts, :include_names, true) do
      case SnmpKit.SnmpMgr.MIB.reverse_lookup(oid) do
        {:ok, name} -> name
        _ -> nil
      end
    end
  end

  defp ip_tuple(<<a, b, c, d>>, _fallback), do: {a, b, c, d}
  defp ip_tuple({_, _, _, _} = ip, _fallback), do: ip
  defp ip_tuple(_, fallback), do: fallback

  defp bump(state, key), do: %{state | stats: Map.update!(state.stats, key, &(&1 + 1))}
end
