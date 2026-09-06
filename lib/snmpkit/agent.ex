defmodule SnmpKit.Agent do
  @moduledoc """
  An SNMP agent: exposes your application's own data to managers over
  SNMPv1, v2c and v3.

      {:ok, agent} = SnmpKit.Agent.start_link(
        port: 1161,
        communities: %{"public" => :read, "private" => :write},
        system: [descr: "orders-api 3.2", name: "orders-01", location: "rack 4"]
      )

      SnmpKit.Agent.put(agent, "hrSystemNumUsers.0", :gauge32, fn -> MyApp.Sessions.count() end)
      SnmpKit.Agent.register(agent, [1, 3, 6, 1, 4, 1, 99999, 1], MyApp.QueueStats)

  Or in a supervision tree:

      children = [
        {SnmpKit.Agent, port: 161, communities: ["public"], name: MyApp.SnmpAgent,
         subtrees: [{"ifEntry", SnmpKit.Agent.Table, columns: ..., rows: &MyApp.Ports.rows/0}]}
      ]

  The MIB is made of *subtrees*, each served by a `SnmpKit.Agent.Handler`
  registered at an OID prefix. The longest matching prefix serves an object.
  Two handlers are built in: `SnmpKit.Agent.Store` for scalars (used by
  `put/4`, and pre-loaded with the `system` group) and `SnmpKit.Agent.Table`
  for tables backed by a function. Every request is answered in its own
  process, so handlers run concurrently.

  ## Options

  - `:port` - UDP port (default 161; 0 picks a free port, read it with `port/1`)
  - `:bind_address` - interface to bind (default all IPv4; an IPv6 address
    binds IPv6)
  - `:communities` - `"public"`, a list of read-only communities, or a map
    or keyword of community to `:read` | `:write` (default `"public"` read-only)
  - `:v3_users` - USM users as for `SnmpKit.Sim.start_device/2`
    (`%{name, auth, auth_password, priv, priv_password}`), plus an optional
    `access: :read | :write` (default `:read`)
  - `:engine_id` - SNMPv3 engine id (default derived from `:name` or the port)
  - `:system` - the `system` group: `descr`, `object_id`, `contact`, `name`,
    `location`, `services`; `sysUpTime` is computed. Contact, name and
    location accept SET from a `:write` principal
  - `:subtrees` - `{prefix, module}` or `{prefix, module, opts}` to register
    at start
  - `:notify_targets` - where `notify/4` sends: `"host"`, `"host:port"`,
    `{host, port}`, or `%{host:, port:, community:, version:, inform:}`
  - `:name` - GenServer registration
  - `:max_concurrent_requests`, `:max_packet_size` - as for the simulator server

  OIDs everywhere may be lists, dotted strings, or MIB names (`"sysName.0"`,
  `"ifEntry"`).

  ## Access control

  A principal (community or v3 user) is `:read` or `:write`. Reads are
  allowed to both; SET needs `:write`, otherwise the agent answers
  `noAccess` (`noSuchName` to SNMPv1). Requests from unknown communities
  are dropped, as SNMP requires.

  ## Notifications

  `notify/4` sends a v2c trap (or inform) to every configured target with
  the agent's `sysUpTime`:

      SnmpKit.Agent.notify(agent, "linkDown", [{"ifIndex.3", :integer, 3}])

  ## Telemetry

  Every request emits `[:snmpkit, :agent, :request]` with `%{duration}` and
  metadata `pdu_type`, `version`, `principal`, `error_status`, `varbinds`.
  """

  use GenServer

  alias SnmpKit.Agent.{Request, Store}
  alias SnmpKit.SnmpMgr.Notify
  alias SnmpKit.SnmpSim.Core.Server

  @system [1, 3, 6, 1, 2, 1, 1]
  @sys_uptime [1, 3, 6, 1, 2, 1, 1, 3, 0]

  @type agent :: GenServer.server()
  @type oid :: [non_neg_integer()] | String.t()

  defstruct [
    :server,
    :port,
    :meta,
    :store,
    :started_at,
    :engine_id,
    :notify_targets,
    subtrees: []
  ]

  ## API

  @doc "Starts an agent. See the module documentation for options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Registers `module` (a `SnmpKit.Agent.Handler`) for the subtree at `prefix`.
  `opts` go to the module's `init/1`, or become its `ctx` when it has none.
  Registering at a prefix that is already taken replaces the handler.
  """
  @spec register(agent(), oid(), module(), keyword()) :: :ok | {:error, term()}
  def register(agent, prefix, module, opts \\ []) do
    with {:ok, prefix} <- resolve_oid(prefix),
         {:ok, ctx} <- init_handler(module, opts) do
      GenServer.call(agent, {:register, prefix, module, ctx})
    end
  end

  @doc "Removes the handler registered at `prefix`."
  @spec unregister(agent(), oid()) :: :ok
  def unregister(agent, prefix) do
    with {:ok, prefix} <- resolve_oid(prefix) do
      GenServer.call(agent, {:unregister, prefix})
    end
  end

  @doc "The registered subtrees as `{prefix, module}`, most specific first."
  @spec subtrees(agent()) :: [{[non_neg_integer()], module()}]
  def subtrees(agent) do
    agent |> meta() |> lookup_subtrees() |> Enum.map(&{&1.prefix, &1.module})
  end

  @doc """
  Puts a scalar into the agent's store. `value` may be a zero-arity function,
  called on every read. `writable: true` allows SET from a `:write` principal.
  """
  @spec put(agent(), oid(), atom(), term(), keyword()) :: :ok | {:error, term()}
  def put(agent, oid, type, value, opts \\ []) do
    with {:ok, oid} <- resolve_oid(oid) do
      Store.put(store(agent), oid, type, value, opts)
    end
  end

  @doc "Removes a scalar from the store."
  @spec delete(agent(), oid()) :: :ok | {:error, term()}
  def delete(agent, oid) do
    with {:ok, oid} <- resolve_oid(oid), do: Store.delete(store(agent), oid)
  end

  @doc "The value the agent would answer a GET for `oid` with, from any subtree."
  @spec get(agent(), oid()) :: {:ok, {atom(), term()}} | {:error, term()}
  def get(agent, oid) do
    with {:ok, oid} <- resolve_oid(oid) do
      Request.lookup(oid, agent |> meta() |> lookup_subtrees())
    end
  end

  @doc "The object the agent would answer a GETNEXT for `oid` with."
  @spec next(agent(), oid()) ::
          {:ok, {[non_neg_integer()], atom(), term()}} | :end_of_mib_view | {:error, term()}
  def next(agent, oid) do
    with {:ok, oid} <- resolve_oid(oid) do
      Request.next(oid, agent |> meta() |> lookup_subtrees())
    end
  end

  @doc """
  Sends a notification to every configured target (or to `targets:` in
  `opts`). `trap` and varbind OIDs may be names. Options are those of
  `SnmpKit.SNMP.send_trap/4`; `inform: true` sends informs and waits for
  the acknowledgements. Returns `:ok`, or `{:error, [{target, reason}]}`
  listing the targets that failed.
  """
  @spec notify(agent(), term(), [{term(), atom(), term()}], keyword()) ::
          :ok | {:error, [{term(), term()}]}
  def notify(agent, trap, varbinds \\ [], opts \\ []) do
    info = GenServer.call(agent, :info)
    {targets, opts} = Keyword.pop(opts, :targets, info.notify_targets)
    {inform?, opts} = Keyword.pop(opts, :inform, false)
    opts = Keyword.put_new(opts, :uptime, info.uptime)

    failures =
      for target <- List.wrap(targets),
          {destination, target_opts} = notify_target(target),
          result =
            send_notification(
              inform?,
              destination,
              trap,
              varbinds,
              Keyword.merge(opts, target_opts)
            ),
          result != :ok do
        {target, elem(result, 1)}
      end

    if failures == [], do: :ok, else: {:error, failures}
  end

  @doc "The UDP port the agent listens on."
  @spec port(agent()) :: :inet.port_number()
  def port(agent), do: GenServer.call(agent, :info).port

  @doc "The agent's `sysUpTime` in centiseconds."
  @spec uptime(agent()) :: non_neg_integer()
  def uptime(agent), do: GenServer.call(agent, :info).uptime

  @doc "The SNMPv3 engine id."
  @spec engine_id(agent()) :: binary()
  def engine_id(agent), do: GenServer.call(agent, :info).engine_id

  @doc "Request and error counters, from the underlying server."
  @spec stats(agent()) :: map()
  def stats(agent), do: GenServer.call(agent, :stats)

  @doc "Stops the agent."
  @spec stop(agent()) :: :ok
  def stop(agent), do: GenServer.stop(agent)

  @doc "Resolves an OID list, dotted string or MIB name to an OID list."
  @spec resolve_oid(term()) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def resolve_oid(oid) when is_list(oid) do
    if Enum.all?(oid, &(is_integer(&1) and &1 >= 0)),
      do: {:ok, oid},
      else: {:error, {:invalid_oid, oid}}
  end

  def resolve_oid(oid) when is_binary(oid) do
    case SnmpKit.SnmpLib.OID.string_to_list(oid) do
      {:ok, list} ->
        {:ok, list}

      _ ->
        case SnmpKit.SnmpMgr.MIB.resolve(oid) do
          {:ok, list} -> {:ok, list}
          _ -> {:error, {:unknown_oid, oid}}
        end
    end
  end

  def resolve_oid(other), do: {:error, {:invalid_oid, other}}

  ## GenServer

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 161)
    meta = :ets.new(:snmpkit_agent_meta, [:set, :public, read_concurrency: true])
    store = Store.new_table()
    started_at = System.monotonic_time(:millisecond)

    communities = communities(Keyword.get(opts, :communities, "public"))

    Enum.each(communities, fn {name, level} ->
      :ets.insert(meta, {{:access, :community, name}, level})
    end)

    v3_users =
      opts
      |> Keyword.get(:v3_users, [])
      |> Enum.map(fn user ->
        user = Map.new(user)
        :ets.insert(meta, {{:access, :v3, user.name}, Map.get(user, :access, :read)})
        Map.delete(user, :access)
      end)

    device_id = to_string(Keyword.get(opts, :name) || "snmpkit-agent-#{port}")

    server_opts =
      [
        community: fn name -> :ets.member(meta, {:access, :community, name}) end,
        bind_address: Keyword.get(opts, :bind_address),
        device_handler: fn pdu, _client -> handle_request(pdu, meta) end,
        device_id: device_id
      ]
      |> maybe_put(:v3_users, if(v3_users == [], do: nil, else: v3_users))
      |> maybe_put(:engine_id, Keyword.get(opts, :engine_id))
      |> maybe_put(:max_concurrent_requests, Keyword.get(opts, :max_concurrent_requests))
      |> maybe_put(:max_packet_size, Keyword.get(opts, :max_packet_size))

    with {:ok, server} <- start_server(port, server_opts),
         {:ok, bound_port} <- bound_port(server, port) do
      engine_id =
        Keyword.get(opts, :engine_id) || SnmpKit.SnmpSim.Core.UsmAgent.derive_engine_id(device_id)

      state = %__MODULE__{
        server: server,
        port: bound_port,
        meta: meta,
        store: store,
        started_at: started_at,
        engine_id: engine_id,
        notify_targets: List.wrap(Keyword.get(opts, :notify_targets, []))
      }

      seed_system(store, Keyword.get(opts, :system, []), started_at)
      :ets.insert(meta, {:store, store})
      state = put_subtrees(state, [%{prefix: [], module: Store, ctx: %{table: store}}])

      case register_initial(state, Keyword.get(opts, :subtrees, [])) do
        {:ok, state} -> {:ok, state}
        {:error, reason} -> {:stop, reason}
      end
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:register, prefix, module, ctx}, _from, state) do
    subtrees =
      [
        %{prefix: prefix, module: module, ctx: ctx}
        | Enum.reject(state.subtrees, &(&1.prefix == prefix))
      ]

    {:reply, :ok, put_subtrees(state, subtrees)}
  end

  def handle_call({:unregister, prefix}, _from, state) do
    {:reply, :ok, put_subtrees(state, Enum.reject(state.subtrees, &(&1.prefix == prefix)))}
  end

  def handle_call(:info, _from, state) do
    info = %{
      port: state.port,
      uptime: uptime_ticks(state.started_at),
      engine_id: state.engine_id,
      notify_targets: state.notify_targets
    }

    {:reply, info, state}
  end

  def handle_call(:stats, _from, state) do
    stats = Server.get_stats(state.server)
    {:reply, Map.put(stats, :uptime, uptime_ticks(state.started_at)), state}
  end

  def handle_call(:meta, _from, state), do: {:reply, state.meta, state}

  @impl true
  def terminate(_reason, state) do
    if Process.alive?(state.server), do: GenServer.stop(state.server, :normal, 1000)
    :ok
  catch
    :exit, _ -> :ok
  end

  ## request path (runs in the server's worker process)

  defp handle_request(pdu, meta) do
    start = System.monotonic_time()
    subtrees = lookup_subtrees(meta)
    level = access_level(pdu, meta)
    response = Request.handle(pdu, subtrees, level)

    SnmpKit.Telemetry.execute([:agent, :request], %{duration: System.monotonic_time() - start}, %{
      pdu_type: pdu.type,
      version: pdu.version,
      principal: pdu.community,
      error_status: response.error_status,
      varbinds: length(response.varbinds)
    })

    {:ok, response}
  end

  defp access_level(%{version: 3, community: user}, meta), do: level(meta, {:access, :v3, user})

  defp access_level(%{community: community}, meta),
    do: level(meta, {:access, :community, community})

  defp level(meta, key) do
    case :ets.lookup(meta, key) do
      [{^key, level}] -> level
      [] -> :read
    end
  end

  defp lookup_subtrees(meta) do
    case :ets.lookup(meta, :subtrees) do
      [{:subtrees, subtrees}] -> subtrees
      [] -> []
    end
  end

  # longest prefix first, so the first match is the most specific
  defp put_subtrees(state, subtrees) do
    sorted = Enum.sort_by(subtrees, &length(&1.prefix), :desc)
    :ets.insert(state.meta, {:subtrees, sorted})
    %{state | subtrees: sorted}
  end

  ## helpers

  defp meta(agent), do: GenServer.call(agent, :meta)

  defp store(agent) do
    [{:store, store}] = :ets.lookup(meta(agent), :store)
    store
  end

  defp init_handler(module, opts) do
    cond do
      not Code.ensure_loaded?(module) -> {:error, {:handler_not_loaded, module}}
      not function_exported?(module, :get_next, 2) -> {:error, {:not_a_handler, module}}
      function_exported?(module, :init, 1) -> module.init(opts)
      true -> {:ok, opts}
    end
  end

  defp register_initial(state, specs) do
    Enum.reduce_while(specs, {:ok, state}, fn spec, {:ok, state} ->
      {prefix, module, opts} =
        case spec do
          {prefix, module} -> {prefix, module, []}
          {prefix, module, opts} -> {prefix, module, opts}
        end

      with {:ok, prefix} <- resolve_oid(prefix),
           {:ok, ctx} <- init_handler(module, opts) do
        subtree = %{prefix: prefix, module: module, ctx: ctx}
        {:cont, {:ok, put_subtrees(state, [subtree | state.subtrees])}}
      else
        {:error, reason} -> {:halt, {:error, {:subtree, prefix, reason}}}
      end
    end)
  end

  defp communities(name) when is_binary(name), do: [{name, :read}]

  defp communities(list) when is_list(list) do
    Enum.map(list, fn
      {name, level} when level in [:read, :write] -> {to_string(name), level}
      name when is_binary(name) -> {name, :read}
    end)
  end

  defp communities(%{} = map), do: communities(Map.to_list(map))

  defp seed_system(store, system, started_at) do
    system = Map.new(system)

    put = fn sub, type, value, opts ->
      Store.put(store, @system ++ [sub, 0], type, value, opts)
    end

    put.(1, :octet_string, Map.get(system, :descr, "SnmpKit agent"), [])
    put.(2, :object_identifier, Map.get(system, :object_id, [0, 0]), [])
    put.(3, :timeticks, fn -> uptime_ticks(started_at) end, [])
    put.(4, :octet_string, Map.get(system, :contact, ""), writable: true)
    put.(5, :octet_string, Map.get(system, :name, ""), writable: true)
    put.(6, :octet_string, Map.get(system, :location, ""), writable: true)
    put.(7, :integer, Map.get(system, :services, 72), [])
    :ok
  end

  @doc false
  def sys_uptime_oid, do: @sys_uptime

  defp uptime_ticks(started_at), do: div(System.monotonic_time(:millisecond) - started_at, 10)

  defp start_server(port, opts) do
    case Server.start_link(port, opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
      :ignore -> {:error, :server_ignored}
    end
  end

  defp bound_port(server, 0) do
    case :sys.get_state(server) do
      %{socket: socket} ->
        case :inet.port(socket) do
          {:ok, port} -> {:ok, port}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp bound_port(_server, port), do: {:ok, port}

  defp notify_target(%{} = target) do
    host = Map.fetch!(target, :host)
    port = Map.get(target, :port, 162)

    opts =
      target
      |> Map.take([:community, :version, :timeout, :retries])
      |> Map.to_list()

    {{host, port}, if(Map.get(target, :inform, false), do: [inform: true] ++ opts, else: opts)}
  end

  defp notify_target(target), do: {target, []}

  defp send_notification(inform?, destination, trap, varbinds, opts) do
    {inform?, opts} = Keyword.pop(opts, :inform, inform?)

    if inform?,
      do: Notify.send_inform(destination, trap, varbinds, opts),
      else: Notify.send_trap(destination, trap, varbinds, opts)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
