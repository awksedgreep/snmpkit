defmodule SnmpKit.SnmpMgr.EngineGuardTest do
  @moduledoc """
  The Engine refuses a request id that is still pending, answers
  `{:error, :services_not_started}` instead of exiting when it is not
  running, and never hands callers a nil IPv6 socket.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.{Engine, Multi, V2Walk}

  @moduletag :unit

  @table :snmp_request_id_counter
  @sys_descr [1, 3, 6, 1, 2, 1, 1, 1, 0]

  defp stop_quietly(pid) do
    GenServer.stop(pid)
  catch
    :exit, _ -> :ok
  end

  describe "request id reuse" do
    setup do
      :ok = SnmpKit.SnmpMgr.ensure_started()

      {:ok, engine} =
        Engine.start_link(name: :"engine_guard_#{System.unique_integer([:positive])}")

      on_exit(fn -> stop_quietly(engine) end)
      %{engine: engine}
    end

    test "a second registration of a pending id is refused and the first caller keeps its response",
         %{engine: engine} do
      assert :ok = Engine.register_request(engine, 777, self(), 5_000)

      parent = self()

      spawn_link(fn ->
        send(parent, {:other, Engine.register_request(engine, 777, self(), 60_000)})

        receive do
          message -> send(parent, {:other_got, message})
        end
      end)

      assert_receive {:other, {:error, :request_id_in_use}}
      assert Engine.pending_count(engine) == 1

      send(engine, {:mock_response, 777, [{@sys_descr, :octet_string, "x"}]})

      assert_receive {:snmp_response, 777, [{@sys_descr, :octet_string, "x"}]}
      refute_receive {:other_got, _}, 100
      assert Engine.pending_count(engine) == 0
    end

    test "a refused registration leaves the first one's timer in place", %{engine: engine} do
      assert :ok = Engine.register_request(engine, 778, self(), 100)
      assert {:error, :request_id_in_use} = Engine.register_request(engine, 778, self(), 60_000)

      assert_receive {:snmp_timeout, 778}, 1_000
      assert Engine.pending_count(engine) == 0
    end

    test "register_next_request skips a wrapped id that is still pending", %{engine: engine} do
      # Next ids: 1_000_000 then (after the wrap) 1
      :ets.insert(@table, {:counter, 999_999})
      assert :ok = Engine.register_request(engine, 1_000_000, self(), 5_000)

      assert {:ok, 1} = Engine.register_next_request(engine, self(), 5_000)
      assert Engine.pending_count(engine) == 2
    end
  end

  describe "when the engine is not running" do
    test "every Engine call returns {:error, :services_not_started}" do
      missing = :engine_guard_missing

      assert {:error, :services_not_started} = Engine.get_stats(missing)
      assert {:error, :services_not_started} = Engine.health_check(missing)
      assert {:error, :services_not_started} = Engine.get_socket(missing)
      assert {:error, :services_not_started} = Engine.get_socket(missing, :inet6)
      assert {:error, :services_not_started} = Engine.get_port(missing)
      assert {:error, :services_not_started} = Engine.get_buffer_stats(missing)
      assert {:error, :services_not_started} = Engine.pending_count(missing)
      assert {:error, :services_not_started} = Engine.register_request(missing, 1, self(), 100)
      assert {:error, :services_not_started} = Engine.register_next_request(missing, self(), 100)
    end

    test "V2Walk.walk and walk_multi return {:error, :services_not_started}" do
      :ok = SnmpKit.SnmpMgr.ensure_started()
      GenServer.stop(Engine)
      on_exit(fn -> :ok = SnmpKit.SnmpMgr.ensure_started() end)

      request = %{target: "127.0.0.1", oid: "1.3.6.1.2.1.1", opts: []}

      assert {:error, :services_not_started} = V2Walk.walk(request, 100)
      assert [{:error, :services_not_started}] = V2Walk.walk_multi([request], timeout: 100)
      assert [] = V2Walk.walk_multi([])
    end
  end

  describe "IPv6 socket" do
    test "get_socket(engine, :inet6) is a socket or an error tuple, never nil" do
      {:ok, engine} = Engine.start_link(name: :engine_guard_inet6)
      on_exit(fn -> stop_quietly(engine) end)

      case Engine.get_socket(engine, :inet6) do
        socket when is_port(socket) -> assert Engine.get_socket(engine, :inet6) == socket
        {:error, reason} -> assert reason != nil
      end
    end

    test "an IPv6 socket that cannot be opened is a clean error for every caller" do
      :ok = SnmpKit.SnmpMgr.ensure_started()
      GenServer.stop(Engine)

      # An IPv6 address nothing here is bound to, so the open fails
      {:ok, engine} =
        Engine.start_link(name: Engine, inet6_opts: [ip: {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}])

      on_exit(fn ->
        stop_quietly(engine)
        :ok = SnmpKit.SnmpMgr.ensure_started()
      end)

      assert {:error, reason} = Engine.get_socket(engine, :inet6)
      assert reason != nil

      target = {0, 0, 0, 0, 0, 0, 0, 1}

      assert [{:error, {:ipv6_socket, ^reason}}] =
               Multi.get_multi([{target, "1.3.6.1.2.1.1.1.0"}], timeout: 200)

      assert [{:error, {:ipv6_socket, ^reason}}] =
               Multi.walk_multi([{target, "1.3.6.1.2.1.1"}], timeout: 200)

      assert {:error, {:ipv6_socket, ^reason}} =
               V2Walk.walk(%{target: target, oid: "1.3.6.1.2.1.1", opts: []}, 200)
    end
  end
end
