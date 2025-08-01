defmodule SnmpKit.SnmpMgr.EngineV2Test do
  use ExUnit.Case, async: false
  
  alias SnmpKit.SnmpMgr.EngineV2
  
  setup do
    # Start the engine for each test
    {:ok, engine} = EngineV2.start_link(name: :test_engine_v2)
    
    on_exit(fn ->
      if Process.alive?(engine) do
        GenServer.stop(engine)
      end
    end)
    
    {:ok, engine: engine}
  end
  
  test "starts successfully", %{engine: engine} do
    assert Process.alive?(engine)
    assert EngineV2.pending_count(engine) == 0
  end
  
  test "registers and tracks requests", %{engine: engine} do
    # Register a request
    EngineV2.register_request(engine, 12345, self(), 5000)
    
    # Give it time to process
    Process.sleep(10)
    
    # Check it's tracked
    assert EngineV2.pending_count(engine) == 1
    
    stats = EngineV2.get_stats(engine)
    assert stats.pending_requests == 1
    assert stats.metrics.requests_registered == 1
  end
  
  test "unregisters requests", %{engine: engine} do
    # Register a request
    EngineV2.register_request(engine, 12345, self(), 5000)
    Process.sleep(10)
    
    assert EngineV2.pending_count(engine) == 1
    
    # Unregister it
    EngineV2.unregister_request(engine, 12345)
    Process.sleep(10)
    
    assert EngineV2.pending_count(engine) == 0
  end
  
  test "handles request timeouts", %{engine: engine} do
    # Register a request with short timeout
    EngineV2.register_request(engine, 12345, self(), 50)
    
    # Wait for timeout
    assert_receive {:snmp_timeout, 12345}, 100
    
    # Should be removed from pending
    assert EngineV2.pending_count(engine) == 0
    
    stats = EngineV2.get_stats(engine)
    assert stats.metrics.requests_timeout == 1
  end
  
  test "correlates responses to correct processes", %{engine: engine} do
    # Register a request
    EngineV2.register_request(engine, 12345, self(), 5000)
    Process.sleep(10)
    
    # Simulate receiving a UDP response by sending a pre-built message
    # This bypasses the UDP decoding and directly tests the correlation logic
    mock_response_data = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "test_value"}]
    send(engine, {:mock_response, 12345, mock_response_data})
    
    # Should receive the response
    assert_receive {:snmp_response, 12345, response_data}, 100
    
    # Should be removed from pending
    assert EngineV2.pending_count(engine) == 0
    
    stats = EngineV2.get_stats(engine)
    assert stats.metrics.requests_completed == 1
  end
  
  test "handles unknown request responses", %{engine: engine} do
    # Simulate receiving a response for unknown request
    mock_response_data = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "unknown_value"}]
    send(engine, {:mock_response, 99999, mock_response_data})
    
    # Give it time to process
    Process.sleep(10)
    
    stats = EngineV2.get_stats(engine)
    assert stats.metrics.unknown_responses == 1
  end
  
  test "handles malformed responses", %{engine: engine} do
    # Send malformed UDP data
    send(engine, {:udp, nil, {127, 0, 0, 1}, 161, "invalid_snmp_data"})
    
    # Give it time to process
    Process.sleep(10)
    
    stats = EngineV2.get_stats(engine)
    assert stats.metrics.decode_failures == 1
  end
  
  test "tracks multiple concurrent requests", %{engine: engine} do
    # Register multiple requests
    for i <- 1..5 do
      EngineV2.register_request(engine, i, self(), 5000)
    end
    
    Process.sleep(10)
    assert EngineV2.pending_count(engine) == 5
    
    # Send responses for some of them
    for i <- [1, 3, 5] do
      mock_response_data = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, "value_#{i}"}]
      send(engine, {:mock_response, i, mock_response_data})
    end
    
    # Should receive the responses
    for i <- [1, 3, 5] do
      assert_receive {:snmp_response, ^i, _data}, 100
    end
    
    Process.sleep(10)
    
    # Should have 2 pending (2 and 4)
    assert EngineV2.pending_count(engine) == 2
    
    stats = EngineV2.get_stats(engine)
    assert stats.metrics.requests_completed == 3
  end
  
  # Helper function to build mock SNMP response
  defp build_mock_snmp_response(request_id, value) do
    # Build a minimal SNMP response that can be decoded
    # This is a simplified version - in practice would use proper PDU building
    varbind = {[1, 3, 6, 1, 2, 1, 1, 1, 0], :octet_string, value}
    pdu = %{
      request_id: request_id,
      varbinds: [varbind]
    }
    message = %{
      version: :v2c,
      community: "public",
      pdu: pdu
    }
    
    # This would normally be encoded properly, but for testing we'll
    # mock the decode process by sending a pre-structured message
    case SnmpKit.SnmpLib.PDU.encode_message(message) do
      {:ok, encoded} -> encoded
      _ -> "mock_response_#{request_id}"
    end
  end
end