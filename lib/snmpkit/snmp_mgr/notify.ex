defmodule SnmpKit.SnmpMgr.Notify do
  @moduledoc """
  Sends SNMP notifications: v2c/v1 traps (fire and forget) and v2c informs
  (acknowledged by the receiver).

  Reachable through `SnmpKit.SNMP.send_trap/4` and `SnmpKit.SNMP.send_inform/4`.
  The counterpart that receives them is `SnmpKit.Trap`.

  ## Trap OIDs and varbinds

  `trap_oid` is an OID list, a dotted string, or a name known to the MIB
  registry (`"linkDown"`, `"coldStart"`, ...). Varbinds are `{oid, type, value}`
  tuples whose OID may likewise be a list, string or name. The mandatory
  `sysUpTime.0` and `snmpTrapOID.0` varbinds of an SNMPv2 notification are
  added for you.

  ## Options

  - `:community` - default from `SnmpKit.SnmpMgr.Config`
  - `:version` - `:v2c` (default) or `:v1`
  - `:uptime` - sysUpTime in centiseconds; defaults to the VM's uptime
  - `:timeout`, `:retries` - inform acknowledgement wait (default 5000 ms, 1 retry)
  - `:request_id` - request id for v2c notifications; random by default

  SNMPv1 traps carry different fields. They are derived from the trap OID per
  RFC 3584 (`1.3.6.1.6.3.1.1.5.N` becomes generic trap `N - 1`; anything else
  is enterprise-specific with the enterprise OID and specific trap taken from
  the OID) and can be overridden with `:enterprise`, `:generic_trap`,
  `:specific_trap` and `:agent_addr` (an IPv4 tuple, default `{127, 0, 0, 1}`).
  """

  alias SnmpKit.SnmpLib.{HostParser, OID, PDU}
  alias SnmpKit.SnmpMgr.Config

  @default_port 162
  @snmp_traps_prefix [1, 3, 6, 1, 6, 3, 1, 1, 5]
  @max_request_id 2_147_483_647

  @type varbind :: {term(), atom(), term()}

  @doc """
  Sends a trap to `target` (host, `"host:port"`, or `{host, port}`; port
  defaults to 162). Returns `:ok` once the datagram is handed to the socket.
  """
  @spec send_trap(term(), term(), [varbind()], keyword()) :: :ok | {:error, term()}
  def send_trap(target, trap_oid, varbinds \\ [], opts \\ []) do
    with {:ok, {ip, port}} <- resolve_target(target),
         {:ok, message} <- build_notification(:trap, trap_oid, varbinds, opts),
         {:ok, packet} <- PDU.encode_message(message) do
      with_socket(fn socket -> :gen_udp.send(socket, ip, port, packet) end)
    end
  end

  @doc """
  Sends an inform and waits for the receiver's acknowledgement. Returns `:ok`
  on acknowledgement, `{:error, :timeout}` when none arrives within
  `timeout:` across `retries:` attempts.
  """
  @spec send_inform(term(), term(), [varbind()], keyword()) :: :ok | {:error, term()}
  def send_inform(target, trap_oid, varbinds \\ [], opts \\ []) do
    if Keyword.get(opts, :version, :v2c) == :v1 do
      {:error, {:unsupported_operation, :inform_requires_v2c}}
    else
      with {:ok, {ip, port}} <- resolve_target(target),
           {:ok, message} <- build_notification(:inform, trap_oid, varbinds, opts),
           {:ok, packet} <- PDU.encode_message(message) do
        request_id = message.pdu.request_id
        timeout = Keyword.get(opts, :timeout, Config.get_default_timeout())
        retries = Keyword.get(opts, :retries, 1)

        with_socket(fn socket ->
          await_ack(socket, ip, port, packet, request_id, timeout, retries)
        end)
      end
    end
  end

  @doc """
  Builds the message (`%{version, community, pdu}`) for a trap or inform
  without sending it. Useful for tests and for agents with their own socket.
  """
  @spec build_notification(:trap | :inform, term(), [varbind()], keyword()) ::
          {:ok, PDU.message()} | {:error, term()}
  def build_notification(kind, trap_oid, varbinds, opts \\ []) do
    community = Keyword.get(opts, :community, Config.get_default_community())
    version = Keyword.get(opts, :version, :v2c)
    uptime = Keyword.get(opts, :uptime, vm_uptime_ticks())

    with {:ok, trap_oid} <- resolve_oid(trap_oid),
         {:ok, varbinds} <- normalize_varbinds(varbinds) do
      case {kind, version} do
        {:trap, :v1} ->
          {enterprise, generic, specific} = v1_trap_fields(trap_oid, opts)
          agent_addr = Keyword.get(opts, :agent_addr, {127, 0, 0, 1})
          pdu = PDU.build_trap_v1(enterprise, agent_addr, generic, specific, uptime, varbinds)
          {:ok, PDU.build_message(pdu, community, :v1)}

        {:trap, _} ->
          pdu = PDU.build_trap_v2(uptime, trap_oid, varbinds, request_id(opts))
          {:ok, PDU.build_message(pdu, community, :v2c)}

        {:inform, _} ->
          pdu = PDU.build_inform(uptime, trap_oid, varbinds, request_id(opts))
          {:ok, PDU.build_message(pdu, community, :v2c)}
      end
    end
  end

  @doc "The BEAM's uptime in SNMP TimeTicks (centiseconds), used when no `:uptime` is given."
  @spec vm_uptime_ticks() :: non_neg_integer()
  def vm_uptime_ticks do
    {wall_clock_ms, _} = :erlang.statistics(:wall_clock)
    rem(div(wall_clock_ms, 10), 4_294_967_296)
  end

  # -- helpers -------------------------------------------------------------

  defp resolve_target({host, port}) when is_integer(port), do: HostParser.parse(host, port)
  defp resolve_target(target), do: HostParser.parse(target, @default_port)

  defp resolve_oid(oid) when is_list(oid), do: {:ok, oid}

  defp resolve_oid(oid) when is_binary(oid) do
    case OID.string_to_list(oid) do
      {:ok, list} ->
        {:ok, list}

      _ ->
        case SnmpKit.SnmpMgr.MIB.resolve(oid) do
          {:ok, list} -> {:ok, list}
          {:error, reason} -> {:error, {:invalid_oid, oid, reason}}
        end
    end
  end

  defp resolve_oid(other), do: {:error, {:invalid_oid, other}}

  defp normalize_varbinds(varbinds) do
    Enum.reduce_while(varbinds, {:ok, []}, fn
      {oid, type, value}, {:ok, acc} ->
        case resolve_oid(oid) do
          {:ok, list} -> {:cont, {:ok, [{list, type, value} | acc]}}
          error -> {:halt, error}
        end

      other, _ ->
        {:halt, {:error, {:invalid_varbind, other}}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  # RFC 3584 section 3.2: map an SNMPv2 trap OID onto v1 trap fields
  defp v1_trap_fields(trap_oid, opts) do
    {enterprise, generic, specific} =
      case trap_oid do
        [1, 3, 6, 1, 6, 3, 1, 1, 5, n] when n in 1..6 ->
          {@snmp_traps_prefix, n - 1, 0}

        oid ->
          case Enum.reverse(oid) do
            [specific, 0 | rest] -> {Enum.reverse(rest), 6, specific}
            [specific | rest] -> {Enum.reverse(rest), 6, specific}
          end
      end

    {Keyword.get(opts, :enterprise, enterprise), Keyword.get(opts, :generic_trap, generic),
     Keyword.get(opts, :specific_trap, specific)}
  end

  defp request_id(opts) do
    Keyword.get_lazy(opts, :request_id, fn -> :rand.uniform(@max_request_id) end)
  end

  defp with_socket(fun) do
    case :gen_udp.open(0, [:binary, {:active, false}]) do
      {:ok, socket} ->
        try do
          fun.(socket)
        after
          :gen_udp.close(socket)
        end

      {:error, reason} ->
        {:error, {:socket_error, reason}}
    end
  end

  defp await_ack(socket, ip, port, packet, request_id, timeout, retries_left) do
    with :ok <- :gen_udp.send(socket, ip, port, packet) do
      deadline = System.monotonic_time(:millisecond) + timeout

      case receive_ack(socket, request_id, deadline) do
        :ok ->
          :ok

        {:error, :timeout} when retries_left > 0 ->
          await_ack(socket, ip, port, packet, request_id, timeout, retries_left - 1)

        error ->
          error
      end
    end
  end

  defp receive_ack(socket, request_id, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      case :gen_udp.recv(socket, 0, remaining) do
        {:ok, {_ip, _port, data}} ->
          case PDU.decode_message(data) do
            {:ok, %{pdu: %{type: :get_response, request_id: ^request_id}}} -> :ok
            _ -> receive_ack(socket, request_id, deadline)
          end

        {:error, :timeout} ->
          {:error, :timeout}

        {:error, reason} ->
          {:error, {:socket_error, reason}}
      end
    end
  end
end
