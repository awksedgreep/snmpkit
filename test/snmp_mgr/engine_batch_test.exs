defmodule SnmpKit.SnmpMgr.EngineBatchTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.Engine

  setup do
    {:ok, engine} = Engine.start_link(name: :test_engine_batch)

    on_exit(fn ->
      if Process.alive?(engine) do
        GenServer.stop(engine)
      end
    end)

    {:ok, engine: engine}
  end

  test "submit_batch returns ordered results after all responses arrive", %{engine: engine} do
    requests = [
      %{type: :get, target: "device1", oid: "1.3.6.1.2.1.1.1.0", community: "public"},
      %{type: :get, target: "device2", oid: "1.3.6.1.2.1.1.1.0", community: "public"}
    ]

    caller = self()

    task =
      Task.async(fn ->
        send(caller, {:batch_reply, Engine.submit_batch(engine, requests, timeout: 1000)})
      end)

    Process.sleep(10)

    stats = Engine.get_stats(engine)
    request_ids = Map.keys(engine_pending_requests(engine))
    assert length(request_ids) == 2

    [request_id_a, request_id_b] = Enum.sort(request_ids)

    send(engine, {:mock_response, request_id_b, {"1.3.6.1.2.1.1.1.0", :octet_string, "second"}})
    refute_received {:batch_reply, _}

    send(engine, {:mock_response, request_id_a, {"1.3.6.1.2.1.1.1.0", :octet_string, "first"}})

    assert_receive {:batch_reply,
                    {:ok,
                     [
                       {:ok, {"1.3.6.1.2.1.1.1.0", :octet_string, "first"}},
                       {:ok, {"1.3.6.1.2.1.1.1.0", :octet_string, "second"}}
                     ]}},
                   200

    assert %{
             metrics: %{batches_submitted: 1, requests_completed: 2}
           } = Engine.get_stats(engine)

    Task.await(task)
    assert stats.metrics.requests_submitted == 2
  end

  defp engine_pending_requests(engine) do
    :sys.get_state(engine).pending_requests
  end
end
