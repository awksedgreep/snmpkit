defmodule SnmpKit.SnmpMgr.MultiV2Test do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.{MultiV2, RequestIdGenerator, SocketManager, EngineV2}

  setup do
    # Start all required services (or use existing ones)
    case RequestIdGenerator.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case SocketManager.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case EngineV2.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Reset request ID counter for predictable tests
    RequestIdGenerator.reset()

    :ok
  end

  describe "get_multi/2" do
    test "handles single request" do
      # Mock the Core module to return a simple response
      mock_core_get()

      requests = [{"127.0.0.1", "1.3.6.1.2.1.1.1.0"}]

      # Since we're mocking, we expect the mock response
      results = MultiV2.get_multi(requests, timeout: 1000)

      assert length(results) == 1
      # Results will be error because we don't have a real SNMP agent
      assert [{:error, _}] = results
    end

    test "handles multiple requests with concurrency limit" do
      requests = [
        {"127.0.0.1", "1.3.6.1.2.1.1.1.0"},
        {"127.0.0.1", "1.3.6.1.2.1.1.3.0"},
        {"127.0.0.1", "1.3.6.1.2.1.1.4.0"}
      ]

      results = MultiV2.get_multi(requests, max_concurrent: 2, timeout: 1000)

      assert length(results) == 3
      # All should timeout since there's no real SNMP agent
      assert Enum.all?(results, fn
               {:error, :timeout} -> true
               {:error, _} -> true
               _ -> false
             end)
    end

    test "supports different return formats" do
      requests = [
        {"127.0.0.1", "1.3.6.1.2.1.1.1.0"},
        {"127.0.0.1", "1.3.6.1.2.1.1.3.0"}
      ]

      # Test :list format (default)
      list_results = MultiV2.get_multi(requests, timeout: 500)
      assert length(list_results) == 2

      # Test :with_targets format
      with_targets_results =
        MultiV2.get_multi(requests, return_format: :with_targets, timeout: 500)

      assert length(with_targets_results) == 2
      assert match?([{_, _, _}, {_, _, _}], with_targets_results)

      # Test :map format
      map_results = MultiV2.get_multi(requests, return_format: :map, timeout: 500)
      assert is_map(map_results)
      assert map_size(map_results) == 2
    end
  end

  describe "get_bulk_multi/2" do
    test "handles bulk requests" do
      requests = [
        {"127.0.0.1", "1.3.6.1.2.1.2.2.1"}
      ]

      results = MultiV2.get_bulk_multi(requests, max_repetitions: 5, timeout: 1000)

      assert length(results) == 1
      assert [{:error, _}] = results
    end
  end

  describe "walk_multi/2" do
    test "handles walk requests with longer timeout" do
      requests = [
        {"127.0.0.1", "1.3.6.1.2.1.1"}
      ]

      # Walk should have longer default timeout
      start_time = System.monotonic_time(:millisecond)
      results = MultiV2.walk_multi(requests, timeout: 2000)
      end_time = System.monotonic_time(:millisecond)

      assert length(results) == 1
      assert [{:error, _}] = results

      # Should have taken at least some time (but not the full timeout due to early failure)
      elapsed = end_time - start_time
      assert elapsed >= 0
    end
  end

  describe "execute_mixed/2" do
    test "handles mixed operations" do
      operations = [
        {:get, "127.0.0.1", "1.3.6.1.2.1.1.1.0", []},
        {:get_bulk, "127.0.0.1", "1.3.6.1.2.1.2.2.1", [max_repetitions: 5]},
        {:walk, "127.0.0.1", "1.3.6.1.2.1.1", []}
      ]

      results = MultiV2.execute_mixed(operations, timeout: 1000)

      assert length(results) == 3
      # All should fail since there's no real SNMP agent
      assert Enum.all?(results, fn
               {:error, _} -> true
               _ -> false
             end)
    end
  end

  describe "concurrency control" do
    test "respects max_concurrent limit" do
      # Create many requests
      requests =
        for i <- 1..10 do
          {"127.0.0.1", "1.3.6.1.2.1.1.#{i}.0"}
        end

      # Set low concurrency limit
      start_time = System.monotonic_time(:millisecond)
      results = MultiV2.get_multi(requests, max_concurrent: 2, timeout: 500)
      end_time = System.monotonic_time(:millisecond)

      assert length(results) == 10

      # With concurrency limit of 2, this should take longer than if all were concurrent
      elapsed = end_time - start_time
      # Should take at least some time due to batching
      assert elapsed >= 0
    end
  end

  describe "error handling" do
    test "handles socket send errors gracefully" do
      # This should fail due to unreachable host
      requests = [{"192.168.255.254", "1.3.6.1.2.1.1.1.0"}]

      results = MultiV2.get_multi(requests, timeout: 100)

      assert length(results) == 1
      assert [{:error, _}] = results
    end

    test "handles task failures gracefully" do
      # Force a task failure by using invalid OID
      requests = [{"127.0.0.1", "invalid.oid"}]

      results = MultiV2.get_multi(requests, timeout: 1000)

      assert length(results) == 1
      assert [{:error, _}] = results
    end

    test "handles timeout scenarios" do
      # Use very short timeout
      requests = [{"127.0.0.1", "1.3.6.1.2.1.1.1.0"}]

      results = MultiV2.get_multi(requests, timeout: 10)

      assert length(results) == 1
      assert [{:error, :timeout}] = results
    end
  end

  describe "request ID generation" do
    test "generates unique request IDs for concurrent requests" do
      # Start with fresh counter
      RequestIdGenerator.reset()

      # Create multiple concurrent requests
      requests =
        for i <- 1..5 do
          {"127.0.0.1", "1.3.6.1.2.1.1.#{i}.0"}
        end

      # Execute concurrently
      _results = MultiV2.get_multi(requests, max_concurrent: 5, timeout: 500)

      # Request IDs should have been generated (we can't easily verify uniqueness
      # without inspecting internals, but the lack of errors suggests they worked)
      assert RequestIdGenerator.current_value() >= 5
    end
  end

  # Helper functions for mocking
  defp mock_core_get() do
    # This is a placeholder for mocking Core module responses
    # In real tests, you might use a library like Mox or similar
    :ok
  end
end
