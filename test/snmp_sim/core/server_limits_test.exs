defmodule SnmpKit.SnmpSim.Core.ServerLimitsTest do
  @moduledoc """
  The simulator's UDP server must bound the work a burst of datagrams can
  create: a cap on concurrent handlers, a cap on datagram size, and handler
  crashes that turn into genErr responses instead of silent worker deaths.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.Core.Server
  alias SnmpKit.SnmpSim.TestHelpers.PortHelper

  defp get_packet(request_id \\ 1) do
    pdu = SnmpKit.SnmpLib.PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], request_id)

    {:ok, packet} =
      SnmpKit.SnmpLib.PDU.encode_message(SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v2c))

    packet
  end

  defp ok_handler(pdu, _ctx) do
    {:ok,
     %{
       version: pdu.version,
       community: pdu.community,
       type: :get_response,
       request_id: pdu.request_id,
       error_status: 0,
       error_index: 0,
       varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "ok"}]
     }}
  end

  defp wait_stats(server, pred, attempts \\ 100) do
    stats = Server.get_stats(server)

    cond do
      pred.(stats) ->
        stats

      attempts == 0 ->
        stats

      true ->
        Process.sleep(10)
        wait_stats(server, pred, attempts - 1)
    end
  end

  test "datagrams above max_packet_size are dropped before decoding" do
    port = PortHelper.get_port()
    {:ok, server} = Server.start_link(port, device_handler: &ok_handler/2, max_packet_size: 64)
    {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

    :gen_udp.send(socket, {127, 0, 0, 1}, port, :binary.copy(<<0x30>>, 200))
    stats = wait_stats(server, &(&1.oversized_packets == 1))
    assert stats.oversized_packets == 1
    assert stats.decode_errors == 0
    assert {:error, :timeout} = :gen_udp.recv(socket, 0, 100)

    # A normal request still works
    :gen_udp.send(socket, {127, 0, 0, 1}, port, get_packet())
    assert {:ok, {_, _, _response}} = :gen_udp.recv(socket, 0, 1000)

    :gen_udp.close(socket)
    GenServer.stop(server)
  end

  test "in-flight handlers are bounded and excess datagrams are shed" do
    port = PortHelper.get_port()
    test_pid = self()

    slow_handler = fn pdu, ctx ->
      send(test_pid, :handler_started)

      receive do
        :release -> :ok
      after
        2_000 -> :ok
      end

      ok_handler(pdu, ctx)
    end

    {:ok, server} =
      Server.start_link(port, device_handler: slow_handler, max_concurrent_requests: 2)

    {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

    for id <- 1..5, do: :gen_udp.send(socket, {127, 0, 0, 1}, port, get_packet(id))

    # Only two handlers may run; the other three datagrams are dropped
    assert_receive :handler_started, 1_000
    assert_receive :handler_started, 1_000
    refute_receive :handler_started, 200

    stats = wait_stats(server, &(&1.dropped_overload == 3))
    assert stats.dropped_overload == 3
    assert :sys.get_state(server).in_flight == 2

    # Releasing the handlers frees the slots
    for pid <- handler_pids(server), do: send(pid, :release)
    assert wait_stats(server, &(&1.successful_responses == 2)).successful_responses == 2
    assert wait_in_flight(server, 0) == 0

    # And new requests are accepted again
    :gen_udp.send(socket, {127, 0, 0, 1}, port, get_packet(9))
    assert_receive :handler_started, 1_000
    for pid <- handler_pids(server), do: send(pid, :release)

    :gen_udp.close(socket)
    GenServer.stop(server)
  end

  test "a crashing function handler yields genErr and releases its slot" do
    port = PortHelper.get_port()
    {:ok, server} = Server.start_link(port, device_handler: fn _pdu, _ctx -> raise "boom" end)
    {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

    :gen_udp.send(socket, {127, 0, 0, 1}, port, get_packet(7))
    assert {:ok, {_, _, response}} = :gen_udp.recv(socket, 0, 1000)
    {:ok, decoded} = SnmpKit.SnmpLib.PDU.decode_message(response)
    # genErr
    assert decoded.pdu.error_status == 5
    assert decoded.pdu.request_id == 7

    assert wait_stats(server, &(&1.processing_errors >= 1)).processing_errors >= 1
    assert wait_in_flight(server, 0) == 0

    :gen_udp.close(socket)
    GenServer.stop(server)
  end

  # Worker processes are the ones monitored by the server
  defp handler_pids(server) do
    {:monitors, monitors} = Process.info(server, :monitors)
    for {:process, pid} <- monitors, do: pid
  end

  defp wait_in_flight(server, expected, attempts \\ 100) do
    case :sys.get_state(server).in_flight do
      ^expected ->
        expected

      _ when attempts == 0 ->
        :sys.get_state(server).in_flight

      _ ->
        Process.sleep(10)
        wait_in_flight(server, expected, attempts - 1)
    end
  end
end
