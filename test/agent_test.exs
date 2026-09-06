defmodule SnmpKit.AgentTest do
  use ExUnit.Case, async: false

  alias SnmpKit.Agent
  alias SnmpKit.SNMP

  doctest SnmpKit.Agent.Table

  @enterprise [1, 3, 6, 1, 4, 1, 99_999]
  @if_entry [1, 3, 6, 1, 2, 1, 2, 2, 1]
  # hrSystemNumUsers.0 (HOST-RESOURCES-MIB is not built in)
  @num_users [1, 3, 6, 1, 2, 1, 25, 1, 5, 0]

  defmodule QueueStats do
    @behaviour SnmpKit.Agent.Handler

    def init(opts), do: {:ok, %{depth: Keyword.get(opts, :depth, 7)}}

    @suffixes [[1, 0], [2, 0], [3, 0]]

    def get([1, 0], ctx), do: {:ok, {:gauge32, ctx.depth}}
    def get([2, 0], _ctx), do: {:ok, {:counter64, 18_446_744_073_709_551_000}}
    def get([3, 0], _ctx), do: {:ok, {:string, "queue"}}
    def get(_, _ctx), do: {:error, :no_such_instance}

    def get_next(suffix, ctx) do
      case Enum.find(@suffixes, &(&1 > suffix)) do
        nil -> :end_of_subtree
        next -> with {:ok, value} <- get(next, ctx), do: {:ok, {next, value}}
      end
    end
  end

  defmodule Crashy do
    @behaviour SnmpKit.Agent.Handler
    def get(_, _), do: raise("boom")
    def get_next(_, _), do: raise("boom")
  end

  setup_all do
    {:ok, ports_agent} = Elixir.Agent.start_link(fn -> %{} end)

    rows = fn ->
      for {name, i} <- Enum.with_index(["lo", "eth0", "eth1"], 1) do
        {i, %{1 => i, 2 => name, 5 => 1_000_000_000 * i, 8 => 1}}
      end
    end

    {:ok, agent} =
      Agent.start_link(
        port: 0,
        bind_address: "127.0.0.1",
        communities: %{"public" => :read, "private" => :write},
        v3_users: [
          %{name: "reader", auth: :sha256, auth_password: "reader-auth"},
          %{
            name: "admin",
            auth: :sha256,
            auth_password: "admin-auth",
            priv: :aes128,
            priv_password: "admin-priv",
            access: :write
          }
        ],
        system: [
          descr: "agent under test",
          name: "agent-01",
          location: "lab",
          object_id: @enterprise ++ [1]
        ],
        subtrees: [
          {@enterprise ++ [1], QueueStats, depth: 3},
          {@if_entry, SnmpKit.Agent.Table,
           columns: [{1, :integer}, {2, :octet_string}, {5, :gauge32}, {8, :integer}],
           index: [:integer],
           rows: rows,
           set: fn index, column, {_type, value} ->
             Elixir.Agent.update(ports_agent, &Map.put(&1, {index, column}, value))
             :ok
           end}
        ]
      )

    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    port = Agent.port(agent)
    %{agent: agent, target: "127.0.0.1:#{port}", port: port, ports: ports_agent}
  end

  defp ro(opts \\ []), do: Keyword.merge([community: "public", timeout: 2_000], opts)
  defp rw(opts \\ []), do: Keyword.merge([community: "private", timeout: 2_000], opts)

  defp admin,
    do: [
      version: :v3,
      security_name: "admin",
      auth_protocol: :sha256,
      auth_password: "admin-auth",
      priv_protocol: :aes128,
      priv_password: "admin-priv",
      timeout: 2_000
    ]

  defp reader,
    do: [
      version: :v3,
      security_name: "reader",
      auth_protocol: :sha256,
      auth_password: "reader-auth",
      timeout: 2_000
    ]

  defp oid_string(%{oid: oid}) when is_list(oid), do: Enum.join(oid, ".")
  defp oid_string(%{oid: oid}) when is_binary(oid), do: oid

  describe "system group" do
    test "serves the configured scalars", %{target: target} do
      assert {:ok, %{value: "agent under test"}} = SNMP.get(target, "sysDescr.0", ro())
      assert {:ok, %{value: "agent-01"}} = SNMP.get(target, "sysName.0", ro())
      assert {:ok, %{type: :object_identifier}} = SNMP.get(target, "sysObjectID.0", ro())
      assert {:ok, %{type: :timeticks, value: ticks}} = SNMP.get(target, "sysUpTime.0", ro())
      assert is_integer(ticks) and ticks >= 0
    end

    test "walks in OID order and ends at the next subtree", %{target: target} do
      {:ok, rows} = SNMP.walk(target, "system", ro())
      assert Enum.map(rows, &oid_string/1) == for(n <- 1..7, do: "1.3.6.1.2.1.1.#{n}.0")
    end

    test "sysContact accepts SET from a write community and refuses a read one", %{target: target} do
      assert :ok = SNMP.set(target, "sysContact.0", "ops@example.com", rw())
      assert {:ok, %{value: "ops@example.com"}} = SNMP.get(target, "sysContact.0", ro())
      assert {:error, :no_access} = SNMP.set(target, "sysContact.0", "x", ro())
      assert {:error, :not_writable} = SNMP.set(target, "sysDescr.0", "x", rw())
      assert {:error, :wrong_type} = SNMP.set(target, "sysContact.0", 5, rw())
    end
  end

  describe "store" do
    test "put serves plain and computed values", %{agent: agent, target: target} do
      counter = :counters.new(1, [])
      :ok = Agent.put(agent, @num_users, :gauge32, fn -> :counters.get(counter, 1) end)
      :ok = Agent.put(agent, @enterprise ++ [2, 0], :string, "static")

      assert {:ok, %{value: 0}} = SNMP.get(target, @num_users, ro())
      :counters.add(counter, 1, 5)
      assert {:ok, %{value: 5}} = SNMP.get(target, @num_users, ro())
      assert {:ok, %{value: "static"}} = SNMP.get(target, @enterprise ++ [2, 0], ro())
      assert {:ok, {:gauge32, 5}} = Agent.get(agent, @num_users)

      :ok = Agent.delete(agent, @num_users)
      assert {:error, :no_such_object} = SNMP.get(target, @num_users, ro())
    end

    test "writable scalars take SET", %{agent: agent, target: target} do
      :ok = Agent.put(agent, @enterprise ++ [3, 0], :integer, 1, writable: true)
      assert :ok = SNMP.set(target, @enterprise ++ [3, 0], 42, rw())
      assert {:ok, {:integer, 42}} = Agent.get(agent, @enterprise ++ [3, 0])
    end
  end

  describe "handlers" do
    test "a registered module answers GET and GETNEXT below its prefix", %{target: target} do
      assert {:ok, %{value: 3}} = SNMP.get(target, @enterprise ++ [1, 1, 0], ro())
      {:ok, rows} = SNMP.walk(target, @enterprise ++ [1], ro())
      assert Enum.map(rows, & &1.value) == [3, 18_446_744_073_709_551_000, "queue"]
      assert {:error, :no_such_instance} = SNMP.get(target, @enterprise ++ [1, 9, 0], ro())
    end

    test "SNMPv1 hides Counter64 objects", %{target: target} do
      assert {:error, :no_such_name} =
               SNMP.get(target, @enterprise ++ [1, 2, 0], ro(version: :v1))

      {:ok, rows} = SNMP.walk(target, @enterprise ++ [1], ro(version: :v1))
      assert Enum.map(rows, & &1.value) == [3, "queue"]
    end

    test "the longest prefix wins and a walk crosses subtree boundaries", %{
      agent: agent,
      target: target
    } do
      :ok = Agent.put(agent, @enterprise ++ [1, 1, 0], :string, "shadowed by QueueStats")
      :ok = Agent.put(agent, @enterprise ++ [0, 0], :string, "before")
      :ok = Agent.put(agent, @enterprise ++ [5, 0], :string, "after")

      assert {:ok, %{value: 3}} = SNMP.get(target, @enterprise ++ [1, 1, 0], ro())
      {:ok, rows} = SNMP.walk(target, @enterprise, ro())
      values = Enum.map(rows, & &1.value)
      assert "before" == hd(values)
      assert "after" == List.last(values)
      assert 3 in values
      refute "shadowed by QueueStats" in values

      Agent.delete(agent, @enterprise ++ [1, 1, 0])
      Agent.delete(agent, @enterprise ++ [0, 0])
      Agent.delete(agent, @enterprise ++ [5, 0])
    end

    test "register, subtrees and unregister", %{agent: agent, target: target} do
      :ok = Agent.register(agent, @enterprise ++ [7], QueueStats, depth: 99)
      assert {@enterprise ++ [7], QueueStats} in Agent.subtrees(agent)
      assert {:ok, %{value: 99}} = SNMP.get(target, @enterprise ++ [7, 1, 0], ro())
      :ok = Agent.unregister(agent, @enterprise ++ [7])
      assert {:error, :no_such_object} = SNMP.get(target, @enterprise ++ [7, 1, 0], ro())
      assert {:error, {:not_a_handler, Enum}} = Agent.register(agent, @enterprise ++ [8], Enum)
    end

    test "a crashing handler yields genErr, not a dropped request", %{
      agent: agent,
      target: target
    } do
      :ok = Agent.register(agent, @enterprise ++ [9], Crashy)
      assert {:error, :gen_err} = SNMP.get(target, @enterprise ++ [9, 1, 0], ro())
      :ok = Agent.unregister(agent, @enterprise ++ [9])
    end
  end

  describe "tables" do
    test "get_table reads the rows the function produces", %{target: target} do
      assert {:ok, table} = SNMP.get_table(target, "ifTable", ro())
      assert table[2][2] == "eth0"
      assert table[3][5] == 3_000_000_000
      assert map_size(table) == 3
    end

    test "instances and columns", %{target: target} do
      assert {:ok, %{value: "eth1"}} = SNMP.get(target, "ifDescr.3", ro())
      assert {:error, :no_such_instance} = SNMP.get(target, "ifDescr.4", ro())
      assert {:error, :no_such_object} = SNMP.get(target, "ifType.1", ro())
      assert {:ok, %{value: "lo"}} = SNMP.get_next(target, "ifDescr", ro())
    end

    test "SET goes through the table's set function", %{target: target, ports: ports} do
      assert :ok = SNMP.set(target, "ifDescr.2", "uplink", rw())
      assert Elixir.Agent.get(ports, & &1[{2, 2}]) == "uplink"
      assert {:error, :no_creation} = SNMP.set(target, "ifDescr.9", "nope", rw())
      assert {:error, :wrong_type} = SNMP.set(target, "ifDescr.2", 1, rw())
    end

    test "encode_index" do
      assert SnmpKit.Agent.Table.encode_index(5, [:integer]) == [5]

      assert SnmpKit.Agent.Table.encode_index([{10, 0, 0, 1}, "ab"], [:ip_address, :string]) == [
               10,
               0,
               0,
               1,
               2,
               ?a,
               ?b
             ]

      assert SnmpKit.Agent.Table.encode_index(["ab"], [:implied_string]) == [?a, ?b]
      assert SnmpKit.Agent.Table.encode_index([[1, 3, 6]], [:oid]) == [3, 1, 3, 6]
    end
  end

  describe "GETBULK" do
    test "non-repeaters and repeaters", %{target: target} do
      assert {:ok, rows} = SNMP.get_bulk(target, "ifEntry", ro(max_repetitions: 5))
      assert length(rows) == 5
      assert Enum.map(rows, & &1.value) == [1, 2, 3, "lo", "eth0"]
    end

    test "runs off the end of the MIB with endOfMibView", %{target: target} do
      assert {:ok, rows} =
               SNMP.get_bulk(target, [1, 3, 6, 1, 4, 1, 99_999, 200], ro(max_repetitions: 5))

      assert rows == [] or Enum.all?(rows, &(&1.type == :end_of_mib_view))
    end

    test "a huge max_repetitions is trimmed to what fits in a datagram, never refused", %{
      agent: agent,
      target: target
    } do
      big =
        Enum.map(1..3_000, fn i ->
          {@enterprise ++ [50, i], :octet_string, String.duplicate("x", 40)}
        end)

      Enum.each(big, fn {oid, type, value} -> Agent.put(agent, oid, type, value) end)

      assert {:ok, rows} =
               SNMP.get_bulk(target, @enterprise ++ [50], ro(max_repetitions: 100_000))

      assert length(rows) > 500
      assert length(rows) < 3_000

      Enum.each(big, fn {oid, _, _} -> Agent.delete(agent, oid) end)
    end
  end

  describe "SNMPv1 semantics" do
    test "unknown objects are noSuchName and SET errors map per RFC 3584", %{target: target} do
      assert {:error, :no_such_name} =
               SNMP.get(target, @enterprise ++ [1, 9, 0], ro(version: :v1))

      assert {:error, :no_such_name} = SNMP.set(target, "sysContact.0", "x", ro(version: :v1))
      assert {:error, :bad_value} = SNMP.set(target, "sysContact.0", 5, rw(version: :v1))
      assert :ok = SNMP.set(target, "sysLocation.0", "lab-2", rw(version: :v1))
      assert {:ok, %{value: "lab-2"}} = SNMP.get(target, "sysLocation.0", ro(version: :v1))
    end
  end

  describe "SNMPv3" do
    test "users read and, with access: :write, set", %{target: target} do
      assert {:ok, %{value: "agent under test"}} = SNMP.get(target, "sysDescr.0", reader())
      assert {:error, :no_access} = SNMP.set(target, "sysName.0", "hacked", reader())
      assert :ok = SNMP.set(target, "sysName.0", "agent-v3", admin())
      assert {:ok, %{value: "agent-v3"}} = SNMP.get(target, "sysName.0", admin())
      assert :ok = SNMP.set(target, "sysName.0", "agent-01", admin())
      {:ok, rows} = SNMP.walk(target, "ifTable", admin())
      assert length(rows) == 12
    end

    test "engine id is stable and exposed", %{agent: agent, port: port} do
      assert {:ok, engine_id} =
               SnmpKit.SnmpLib.Security.USM.discover_engine("127.0.0.1",
                 port: port,
                 timeout: 2_000
               )

      assert engine_id == Agent.engine_id(agent)
    end
  end

  describe "access" do
    test "an unknown community gets no answer", %{target: target} do
      assert {:error, :timeout} =
               SNMP.get(target, "sysDescr.0", community: "nope", timeout: 300, retries: 0)
    end

    test "stats count requests", %{agent: agent, target: target} do
      {:ok, _} = SNMP.get(target, "sysDescr.0", ro())
      stats = Agent.stats(agent)
      assert stats.successful_responses > 0
      assert is_integer(stats.uptime)
    end
  end

  describe "notifications" do
    test "notify sends to the configured targets with the agent's uptime", %{agent: agent} do
      {:ok, receiver} =
        SnmpKit.Trap.start_link(port: 0, bind_address: "127.0.0.1", handler: self())

      trap_port = SnmpKit.Trap.port(receiver)

      assert :ok =
               Agent.notify(agent, "linkDown", [{"ifIndex.2", :integer, 2}],
                 targets: [{"127.0.0.1", trap_port}],
                 community: "traps"
               )

      assert_receive {:snmp_trap,
                      %{trap_name: "linkDown", community: "traps", uptime: uptime} = n},
                     2_000

      assert uptime <= Agent.uptime(agent)
      assert Enum.any?(n.varbinds, &(&1.value == 2))

      assert :ok =
               Agent.notify(agent, "linkUp", [],
                 targets: [%{host: "127.0.0.1", port: trap_port, inform: true}]
               )

      assert_receive {:snmp_trap, %{kind: :inform, trap_name: "linkUp"}}, 2_000
      GenServer.stop(receiver)
    end

    test "a failing target is reported", %{agent: agent} do
      assert {:error, [{_, _reason}]} =
               Agent.notify(agent, "coldStart", [],
                 targets: [{"127.0.0.1", 1}],
                 inform: true,
                 timeout: 200,
                 retries: 0
               )
    end
  end

  describe "supervision" do
    test "child_spec and name registration", %{} do
      spec = Agent.child_spec(port: 0, name: :named_agent_under_test)
      assert spec.id == :named_agent_under_test

      {:ok, pid} =
        Supervisor.start_link(
          [Agent.child_spec(port: 0, bind_address: "127.0.0.1", name: :named_agent_under_test)],
          strategy: :one_for_one
        )

      assert Agent.port(:named_agent_under_test) > 0

      assert {:ok, {:octet_string, "SnmpKit agent"}} =
               Agent.get(:named_agent_under_test, "sysDescr.0")

      Supervisor.stop(pid)
    end

    test "a port in use fails to start", %{port: port} do
      Process.flag(:trap_exit, true)
      assert {:error, :eaddrinuse} = Agent.start_link(port: port, bind_address: "127.0.0.1")
    end
  end
end
