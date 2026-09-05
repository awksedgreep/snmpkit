defmodule SnmpKit.SnmpMgr.EngineTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.Engine

  setup do
    # Start the engine for each test
    {:ok, engine} = Engine.start_link(name: :test_engine_v2)

    on_exit(fn ->
      # The engine traps exits and is linked to the test process, so it may
      # already be shutting down when on_exit runs.
      try do
        GenServer.stop(engine)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, engine: engine}
  end

  test "starts successfully", %{engine: engine} do
    assert Process.alive?(engine)
    assert Engine.pending_count(engine) == 0
  end

  test "registers and tracks requests", %{engine: engine} do
    # Register a request
    assert :ok = Engine.register_request(engine, 12345, self(), 5000)

    # Check it's tracked
    assert Engine.pending_count(engine) == 1

    stats = Engine.get_stats(engine)
    assert stats.pending_requests == 1
    assert stats.metrics.requests_registered == 1
  end

  test "unregisters requests", %{engine: engine} do
    # Register a request
    Engine.register_request(engine, 12345, self(), 5000)
    _ = :sys.get_state(engine)

    assert Engine.pending_count(engine) == 1

    # Unregister it
    Engine.unregister_request(engine, 12345)
    _ = :sys.get_state(engine)

    assert Engine.pending_count(engine) == 0
  end

  test "handles request timeouts", %{engine: engine} do
    # Register a request with short timeout
    Engine.register_request(engine, 12345, self(), 50)

    # Wait for timeout
    assert_receive {:snmp_timeout, 12345}, 100

    # Should be removed from pending
    assert Engine.pending_count(engine) == 0

    stats = Engine.get_stats(engine)
    assert stats.metrics.requests_timeout == 1
  end

  test "correlates responses to correct processes", %{engine: engine} do
    # Register a request
    Engine.register_request(engine, 12345, self(), 5000)
    _ = :sys.get_state(engine)

    # Simulate receiving a UDP response by sending a pre-built message
    # This bypasses the UDP decoding and directly tests the correlation logic
    mock_response_data = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "test_value"}]
    send(engine, {:mock_response, 12345, mock_response_data})

    # Should receive the response
    assert_receive {:snmp_response, 12345, _response_data}, 100

    # Should be removed from pending
    assert Engine.pending_count(engine) == 0

    stats = Engine.get_stats(engine)
    assert stats.metrics.requests_completed == 1
  end

  test "handles unknown request responses", %{engine: engine} do
    # Simulate receiving a response for unknown request
    mock_response_data = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "unknown_value"}]
    send(engine, {:mock_response, 99999, mock_response_data})

    # Synchronise on the engine mailbox so the message has been handled
    _ = :sys.get_state(engine)

    stats = Engine.get_stats(engine)
    assert stats.metrics.unknown_responses == 1
  end

  test "handles malformed responses", %{engine: engine} do
    # Send malformed UDP data
    send(engine, {:udp, nil, {127, 0, 0, 1}, 161, "invalid_snmp_data"})

    # Synchronise on the engine mailbox so the message has been handled
    _ = :sys.get_state(engine)

    stats = Engine.get_stats(engine)
    assert stats.metrics.decode_failures == 1
  end

  test "tracks multiple concurrent requests", %{engine: engine} do
    # Register multiple requests
    for i <- 1..5 do
      Engine.register_request(engine, i, self(), 5000)
    end

    _ = :sys.get_state(engine)
    assert Engine.pending_count(engine) == 5

    # Send responses for some of them
    for i <- [1, 3, 5] do
      mock_response_data = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "value_#{i}"}]
      send(engine, {:mock_response, i, mock_response_data})
    end

    # Should receive the responses
    for i <- [1, 3, 5] do
      assert_receive {:snmp_response, ^i, _data}, 100
    end

    _ = :sys.get_state(engine)

    # Should have 2 pending (2 and 4)
    assert Engine.pending_count(engine) == 2

    stats = Engine.get_stats(engine)
    assert stats.metrics.requests_completed == 3
  end
end
