defmodule SnmpKit.TestSupport.FakeAgent do
  @moduledoc """
  A scripted SNMPv2c agent on a loopback UDP port.

  `start/1` takes a function `(request_number, request_pdu) -> varbinds` and
  answers every GETNEXT/GETBULK it receives with a `get_response` carrying
  those varbinds, so a test can hand a walk exactly the response it wants
  (an end-of-MIB marker in the middle of a page, the same OID over and over,
  ...). `requests/1` returns how many requests the agent has answered.
  """

  alias SnmpKit.SnmpLib.PDU

  @spec start((pos_integer(), map() -> [tuple()])) :: {pid(), :inet.port_number()}
  def start(reply) when is_function(reply, 2) do
    parent = self()

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_udp.open(0, [:binary, {:active, true}, {:ip, {127, 0, 0, 1}}])
        {:ok, port} = :inet.port(socket)
        send(parent, {:fake_agent_port, port})
        loop(socket, reply, 0)
      end)

    receive do
      {:fake_agent_port, port} -> {pid, port}
    after
      1_000 -> raise "fake agent did not start"
    end
  end

  @spec requests(pid()) :: non_neg_integer()
  def requests(pid) do
    send(pid, {:requests, self()})

    receive do
      {:requests, count} -> count
    after
      1_000 -> raise "fake agent did not answer"
    end
  end

  defp loop(socket, reply, count) do
    receive do
      {:udp, ^socket, ip, port, data} ->
        {:ok, %{pdu: pdu}} = PDU.decode_message(data)
        count = count + 1
        response = PDU.build_response(pdu.request_id, 0, 0, reply.(count, pdu))
        {:ok, packet} = PDU.encode_message(PDU.build_message(response, "public", :v2c))
        :ok = :gen_udp.send(socket, ip, port, packet)
        loop(socket, reply, count)

      {:requests, from} ->
        send(from, {:requests, count})
        loop(socket, reply, count)
    end
  end
end
