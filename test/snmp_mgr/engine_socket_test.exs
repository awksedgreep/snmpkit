defmodule SnmpKit.SnmpMgr.EngineSocketTest do
  @moduledoc "The Engine owns the shared UDP socket and correlates responses that arrive on it."
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.Engine

  setup do
    {:ok, engine} =
      Engine.start_link(name: :"engine_socket_#{System.unique_integer([:positive])}")

    on_exit(fn ->
      try do
        GenServer.stop(engine)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, engine: engine}
  end

  test "exposes a bound UDP socket and stats", %{engine: engine} do
    socket = Engine.get_socket(engine)
    assert is_port(socket)
    assert Engine.get_port(engine) > 0

    stats = Engine.get_stats(engine)
    assert stats.buffer_size == 4 * 1024 * 1024
    assert Map.has_key?(stats, :socket_stats)
    assert stats.pending_requests == 0

    assert Engine.health_check(engine).status == :healthy
  end

  test "custom buffer size and port options" do
    {:ok, engine} = Engine.start_link(name: :engine_socket_custom, buffer_size: 1024 * 1024)
    assert Engine.get_stats(engine).buffer_size == 1024 * 1024
    GenServer.stop(engine)
  end

  test "correlates a real datagram to the registered caller", %{engine: engine} do
    request_id = 4242
    :ok = Engine.register_request(engine, request_id, self(), 2_000)

    pdu =
      SnmpKit.SnmpLib.PDU.build_response(request_id, 0, 0, [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "x"}
      ])

    {:ok, packet} =
      SnmpKit.SnmpLib.PDU.encode_message(SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v2c))

    {:ok, sender} = :gen_udp.open(0, [:binary])
    :gen_udp.send(sender, {127, 0, 0, 1}, Engine.get_port(engine), packet)

    assert_receive {:snmp_response, ^request_id, [{_, :octet_string, "x"}]}, 2_000
    assert Engine.pending_count(engine) == 0
    assert Engine.get_stats(engine).metrics.responses_received == 1
    :gen_udp.close(sender)
  end

  test "drops ICMP-style and empty datagrams and counts them", %{engine: engine} do
    socket = Engine.get_socket(engine)
    send(engine, {:udp, socket, {:unspec, ""}, 0, ""})
    send(engine, {:udp, socket, {127, 0, 0, 1}, 161, ""})
    _ = :sys.get_state(engine)

    metrics = Engine.get_stats(engine).metrics
    assert metrics.icmp_errors_dropped == 1
    assert metrics.empty_packets_dropped == 1
    assert metrics.decode_failures == 0
  end

  test "stopping the engine closes the socket", %{engine: engine} do
    socket = Engine.get_socket(engine)
    :ok = Engine.stop(engine)
    assert Port.info(socket) == nil
  end
end
