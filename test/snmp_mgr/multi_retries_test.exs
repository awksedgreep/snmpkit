defmodule SnmpKit.SnmpMgr.MultiRetriesTest do
  @moduledoc """
  `:retries` and `:timeout` on the shared-socket paths (`Multi.get_multi`,
  `Multi.walk_multi`, `V2Walk.walk`), and through `SnmpKit.SnmpMgr.*`.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpLib.PDU
  alias SnmpKit.SnmpMgr.{Multi, V2Walk}

  @moduletag :unit

  @root "1.3.6.1.2.1.1"
  @sys_descr [1, 3, 6, 1, 2, 1, 1, 1, 0]
  @sys_descr_str "1.3.6.1.2.1.1.1.0"
  @outside_root [1, 3, 6, 1, 2, 1, 2, 1, 0]

  setup do
    :ok = SnmpKit.SnmpMgr.ensure_started()
    :ok
  end

  # A UDP "agent" on 127.0.0.1 that ignores the first `drop` datagrams it
  # receives (all of them for :all) and answers every later one under the
  # request's own id.
  defp start_agent(drop) do
    parent = self()

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_udp.open(0, [:binary, {:ip, {127, 0, 0, 1}}, {:active, true}])
        {:ok, port} = :inet.port(socket)
        send(parent, {:agent_port, port})
        agent_loop(socket, drop, 0)
      end)

    port =
      receive do
        {:agent_port, port} -> port
      end

    {pid, "127.0.0.1:#{port}"}
  end

  defp agent_loop(socket, drop, seen) do
    receive do
      {:udp, ^socket, ip, port, data} ->
        seen = seen + 1

        if is_integer(drop) and seen > drop do
          {:ok, %{pdu: pdu}} = PDU.decode_message(data)
          response = PDU.build_response(pdu.request_id, 0, 0, response_varbinds(pdu))
          {:ok, packet} = PDU.encode_message(PDU.build_message(response, "public", :v2c))
          :ok = :gen_udp.send(socket, ip, port, packet)
        end

        agent_loop(socket, drop, seen)

      {:seen?, from} ->
        send(from, {:seen, seen})
        agent_loop(socket, drop, seen)
    end
  end

  # GET -> the requested object; GETBULK under the system root -> one object
  # in the subtree and one outside it, which ends the walk after one PDU.
  defp response_varbinds(%{type: :get_request, varbinds: [{oid, _, _} | _]}),
    do: [{oid, :octet_string, "ok"}]

  defp response_varbinds(%{type: :get_bulk_request}),
    do: [{@sys_descr, :octet_string, "ok"}, {@outside_root, :integer, 1}]

  defp datagrams_seen(agent) do
    send(agent, {:seen?, self()})

    receive do
      {:seen, seen} -> seen
    end
  end

  describe "a device that drops the first request" do
    test "get_multi succeeds with retries: 1 and times out with retries: 0" do
      {agent, target} = start_agent(1)

      assert [{:error, :timeout}] =
               Multi.get_multi([{target, @sys_descr_str}], timeout: 200, retries: 0)

      assert datagrams_seen(agent) == 1

      {agent, target} = start_agent(1)

      assert [{:ok, [%{oid: @sys_descr_str, value: "ok"}]}] =
               Multi.get_multi([{target, @sys_descr_str}], timeout: 200, retries: 1)

      assert datagrams_seen(agent) == 2
    end

    test "walk_multi succeeds with retries: 1 and times out with retries: 0" do
      {agent, target} = start_agent(1)

      assert [{:error, :timeout}] =
               Multi.walk_multi([{target, @root}], timeout: 200, retries: 0)

      assert datagrams_seen(agent) == 1

      {agent, target} = start_agent(1)

      assert [{:ok, [%{oid: @sys_descr_str, value: "ok"}]}] =
               Multi.walk_multi([{target, @root}], timeout: 200, retries: 1)

      assert datagrams_seen(agent) == 2
    end

    test "a single V2Walk.walk re-sends a timed-out step" do
      {agent, target} = start_agent(1)
      request = %{target: target, oid: @root, opts: [retries: 1]}

      assert {:ok, [{@sys_descr, :octet_string, "ok"}]} = V2Walk.walk(request, 200)
      assert datagrams_seen(agent) == 2

      {agent, target} = start_agent(1)
      request = %{target: target, oid: @root, opts: [retries: 0]}

      assert {:error, :timeout} = V2Walk.walk(request, 200)
      assert datagrams_seen(agent) == 1
    end

    test "per-request :retries overrides the call-level value" do
      {agent, target} = start_agent(1)

      assert [{:ok, _}] =
               Multi.get_multi([{target, @sys_descr_str, [retries: 1]}],
                 timeout: 200,
                 retries: 0
               )

      assert datagrams_seen(agent) == 2
    end
  end

  describe "SnmpKit.SnmpMgr entry points (through Config.merge_opts)" do
    test "get_multi honours explicit :timeout and :retries" do
      {agent, target} = start_agent(:all)

      started = System.monotonic_time(:millisecond)

      assert [{:error, :timeout}] =
               SnmpKit.SnmpMgr.get_multi([{target, @sys_descr_str}], timeout: 100, retries: 0)

      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed >= 100 and elapsed < 1_000
      assert datagrams_seen(agent) == 1

      started = System.monotonic_time(:millisecond)

      assert [{:error, :timeout}] =
               SnmpKit.SnmpMgr.get_multi([{target, @sys_descr_str}], timeout: 100, retries: 2)

      assert System.monotonic_time(:millisecond) - started >= 300
      assert datagrams_seen(agent) == 4
    end

    test "walk_multi honours explicit :timeout and :retries" do
      {agent, target} = start_agent(:all)

      started = System.monotonic_time(:millisecond)

      assert [{:error, :timeout}] =
               SnmpKit.SnmpMgr.walk_multi([{target, @root}], timeout: 100, retries: 0)

      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed >= 100 and elapsed < 1_000
      assert datagrams_seen(agent) == 1

      started = System.monotonic_time(:millisecond)

      assert [{:error, :timeout}] =
               SnmpKit.SnmpMgr.walk_multi([{target, @root}], timeout: 100, retries: 2)

      assert System.monotonic_time(:millisecond) - started >= 300
      assert datagrams_seen(agent) == 4
    end

    test "the default retry budget comes from Config" do
      {agent, target} = start_agent(1)

      # Config default retries: 1, so the dropped first PDU is re-sent once
      assert [{:ok, _}] = SnmpKit.SnmpMgr.get_multi([{target, @sys_descr_str}], timeout: 200)
      assert datagrams_seen(agent) == 2
    end
  end
end
