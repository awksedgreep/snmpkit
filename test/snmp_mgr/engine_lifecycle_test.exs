defmodule SnmpKit.SnmpMgr.EngineLifecycleTest do
  @moduledoc """
  Exercises the Engine's request lifecycle guarantees: one reply per request,
  timer and monitor cleanup, pool bookkeeping, socket release on shutdown and
  the opt-in per-target circuit breaker.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.Engine

  @moduletag :unit
  @moduletag :engine

  # RFC 5737 TEST-NET-1: never routed, so requests time out instead of failing fast
  @blackhole "192.0.2.1"

  defp start_engine(opts \\ []) do
    name = :"engine_lifecycle_#{System.unique_integer([:positive])}"
    {:ok, pid} = Engine.start_link(Keyword.merge([name: name, request_timeout: 100], opts))
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  defp pending(engine), do: :sys.get_state(engine).pending_requests

  test "a timed-out request gets exactly one reply and leaves no pending state" do
    engine = start_engine()
    request = %{type: :get, target: @blackhole, oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}

    assert {:error, reason} = Engine.submit_request(engine, request, timeout: 100)
    assert reason in [:timeout, :enetunreach, :ehostunreach]
    assert pending(engine) == %{}
    # No stray second reply / timeout message reaches the caller
    refute_receive _, 200
  end

  test "a send failure is reported once and removes the pending entry" do
    engine = start_engine()
    request = %{type: :get, target: "invalid.host.test", oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}

    assert {:error, reason} = Engine.submit_request(engine, request, timeout: 1_000)
    assert reason != :timeout
    assert pending(engine) == %{}
    refute_receive _, 1_200
  end

  test "a response cancels the timeout timer" do
    engine = start_engine(request_timeout: 200)
    request = %{type: :get, target: @blackhole, oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}
    parent = self()

    spawn_link(fn ->
      send(parent, {:result, Engine.submit_request(engine, request, timeout: 5_000)})
    end)

    # Wait for the request to be registered, then answer it out of band
    assert [{request_id, %{timer_ref: timer}}] =
             wait_until(fn -> Map.to_list(pending(engine)) end, &(&1 != []))

    send(
      engine,
      {:mock_response, request_id, [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "x"}]}
    )

    assert_receive {:result, {:ok, _}}, 2_000
    assert pending(engine) == %{}
    assert Process.read_timer(timer) == false
  end

  test "a caller that dies is forgotten without a reply" do
    engine = start_engine(request_timeout: 5_000)
    request = %{type: :get, target: @blackhole, oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}

    caller = spawn(fn -> Engine.submit_request(engine, request, timeout: 5_000) end)

    assert [{_id, %{monitor_ref: mref}}] =
             wait_until(fn -> Map.to_list(pending(engine)) end, &(&1 != []))

    assert is_reference(mref)

    Process.exit(caller, :kill)
    assert %{} == wait_until(fn -> pending(engine) end, &(&1 == %{}))
  end

  test "stopping the engine closes its shared socket and fails pending callers" do
    engine = start_engine(request_timeout: 5_000)
    socket = :sys.get_state(engine).shared_socket
    assert is_port(socket)

    request = %{type: :get, target: @blackhole, oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}
    parent = self()

    spawn(fn ->
      send(parent, {:result, Engine.submit_request(engine, request, timeout: 5_000)})
    end)

    wait_until(fn -> pending(engine) end, &(&1 != %{}))

    assert :ok = Engine.stop(engine)
    assert_receive {:result, {:error, :engine_stopped}}, 1_000
    assert :erlang.port_info(socket) == :undefined
  end

  test "circuit breaker is off unless configured" do
    engine = start_engine()
    request = %{type: :get, target: @blackhole, oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}

    for _ <- 1..3 do
      assert {:error, reason} = Engine.submit_request(engine, request, timeout: 50)
      assert reason != :circuit_breaker_open
    end

    assert Engine.get_stats(engine).open_circuit_breakers == 0
  end

  test "configured circuit breaker opens after the failure threshold and recovers" do
    engine = start_engine(circuit_breaker: [threshold: 2, recovery_timeout: 300])
    request = %{type: :get, target: @blackhole, oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}

    # Unroutable target: either a timeout or an immediate network error, both
    # count as failures.
    assert {:error, first} = Engine.submit_request(engine, request, timeout: 50)
    assert first != :circuit_breaker_open
    assert {:error, second} = Engine.submit_request(engine, request, timeout: 50)
    assert second != :circuit_breaker_open
    assert {:error, :circuit_breaker_open} = Engine.submit_request(engine, request, timeout: 50)
    assert Engine.get_stats(engine).open_circuit_breakers == 1

    # Other targets are unaffected
    other = %{request | target: "192.0.2.2"}
    assert {:error, reason} = Engine.submit_request(engine, other, timeout: 50)
    assert reason != :circuit_breaker_open

    # After the recovery timeout a probe request is let through again
    Process.sleep(350)
    assert {:error, reason} = Engine.submit_request(engine, request, timeout: 50)
    assert reason != :circuit_breaker_open
  end

  test "batch requests release their pool connection when they complete" do
    engine = start_engine(pool_size: 2, batch_timeout: 10)

    requests =
      for _ <- 1..3, do: %{type: :get, target: @blackhole, oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}

    assert {:ok, results} = Engine.submit_batch(engine, requests, timeout: 100)
    assert length(results) == 3
    assert Enum.all?(results, &match?({:error, _}, &1))

    assert pending(engine) == %{}
    assert :sys.get_state(engine).pending_batches == %{}

    for conn <- Engine.get_pool_status(engine) do
      assert conn.active_requests == 0
      assert conn.status == :idle
    end

    # Pool errors were counted against the connections that carried them
    assert Enum.sum(Enum.map(Engine.get_pool_status(engine), & &1.error_count)) == 3
  end

  defp wait_until(fun, pred, attempts \\ 100) do
    value = fun.()

    cond do
      pred.(value) ->
        value

      attempts == 0 ->
        value

      true ->
        Process.sleep(10)
        wait_until(fun, pred, attempts - 1)
    end
  end
end
