defmodule SnmpKit.SnmpMgr.RequestIdGeneratorTest do
  use ExUnit.Case, async: false
  
  alias SnmpKit.SnmpMgr.RequestIdGenerator
  
  setup do
    # Start the generator for each test
    {:ok, pid} = RequestIdGenerator.start_link(name: :test_generator)
    
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)
    
    {:ok, generator: pid}
  end
  
  test "generates sequential IDs starting from 1" do
    RequestIdGenerator.reset()
    
    assert RequestIdGenerator.next_id() == 1
    assert RequestIdGenerator.next_id() == 2
    assert RequestIdGenerator.next_id() == 3
  end
  
  test "current_value returns counter without incrementing" do
    RequestIdGenerator.reset()
    
    assert RequestIdGenerator.current_value() == 0
    RequestIdGenerator.next_id()
    assert RequestIdGenerator.current_value() == 1
    assert RequestIdGenerator.current_value() == 1  # Should not increment
  end
  
  test "reset sets counter back to 0" do
    RequestIdGenerator.next_id()
    RequestIdGenerator.next_id()
    
    assert RequestIdGenerator.current_value() > 0
    
    RequestIdGenerator.reset()
    assert RequestIdGenerator.current_value() == 0
    assert RequestIdGenerator.next_id() == 1
  end
  
  test "wraps around at max value" do
    RequestIdGenerator.reset()
    
    # Set counter near max (1,000,000)
    :ets.insert(:snmp_request_id_counter, {:counter, 999_999})
    
    assert RequestIdGenerator.next_id() == 1_000_000
    assert RequestIdGenerator.next_id() == 1  # Should wrap around
  end
  
  test "thread safety with concurrent access" do
    RequestIdGenerator.reset()
    
    # Spawn multiple processes generating IDs concurrently
    parent = self()
    
    tasks = for i <- 1..10 do
      Task.async(fn ->
        ids = for _ <- 1..100, do: RequestIdGenerator.next_id()
        send(parent, {:ids, i, ids})
      end)
    end
    
    # Collect all generated IDs
    all_ids = 
      for task <- tasks, reduce: [] do
        acc ->
          receive do
            {:ids, _i, ids} -> acc ++ ids
          end
      end
    
    # Wait for all tasks to complete
    Task.await_many(tasks)
    
    # Verify all IDs are unique
    assert length(all_ids) == length(Enum.uniq(all_ids))
    
    # Verify they're in reasonable range
    assert Enum.all?(all_ids, fn id -> id > 0 and id <= 1_000_000 end)
  end
  
  test "handles missing table gracefully" do
    # Stop the generator to simulate missing table
    GenServer.stop(:test_generator)
    
    # Should return random fallback value
    id = RequestIdGenerator.next_id()
    assert is_integer(id)
    assert id > 0
    assert id <= 1_000_000
  end
end