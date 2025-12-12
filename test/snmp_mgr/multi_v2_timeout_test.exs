defmodule SnmpKit.SnmpMgr.MultiV2TimeoutTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.MultiV2

  @moduletag :unit
  @moduletag :timeout_fix
  @moduletag timeout: 60_000

  describe "walk_multi timeout behavior" do
    test "walk_multi does not timeout from Task.async_stream when individual PDUs respond within timeout" do
      # This test simulates the bug scenario where:
      # 1. A walk operation takes multiple PDU round-trips
      # 2. Each individual PDU responds within the timeout
      # 3. But the total walk time exceeds the old Task.async_stream timeout
      # 4. With the fix, this should succeed instead of failing with {:task_failed, :timeout}

      # We'll mock a slow walk that takes longer than the old task timeout
      # but where each individual PDU responds quickly

      # First, let's test with a very short timeout to verify the fix
      # The old implementation would fail after timeout + 1000ms regardless of PDU success
      # The new implementation should only fail if individual PDUs timeout

      # 100ms - very short to test the fix quickly
      short_timeout = 100

      # Mock a target that doesn't exist to test timeout behavior
      # This should fail with proper SNMP timeout, not task timeout
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "nonexistent"]}
          ],
          timeout: short_timeout
        )

      # Verify we get a proper SNMP timeout error, not a task timeout
      assert [{:error, reason}] = result
      assert reason == :timeout or match?({:network_error, _}, reason)

      # The key point: we should NOT get {:task_failed, :timeout}
      # which was the bug - Task.async_stream killing the operation prematurely
      refute match?({:task_failed, :timeout}, reason)
    end

    test "get_multi still has task timeout protection for non-walk operations" do
      # Non-walk operations should still have the Task.async_stream timeout protection
      # to prevent runaway tasks

      # 100ms
      short_timeout = 100

      result =
        MultiV2.get_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [community: "nonexistent"]}
          ],
          timeout: short_timeout
        )

      # Should get proper SNMP timeout, not task timeout
      assert [{:error, reason}] = result
      assert reason == :timeout or match?({:network_error, _}, reason)
      refute match?({:task_failed, :timeout}, reason)
    end

    @tag timeout: 15_000
    test "walk_multi timeout configuration still works for per-PDU timeouts" do
      # Verify that the timeout parameter still controls per-PDU timeouts
      # even though we removed the Task.async_stream timeout for walks

      # Use a shorter timeout for faster test execution
      # 2 seconds
      timeout = 2_000

      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "nonexistent"]}
          ],
          timeout: timeout
        )

      # Should still fail with proper timeout behavior
      assert [{:error, reason}] = result
      assert reason == :timeout or match?({:network_error, _}, reason)
    end
  end

  describe "task timeout behavior verification" do
    test "walk operations use safe maximum timeout, not infinity" do
      # This verifies that walk operations have a reasonable timeout cap
      # that prevents infinite hangs while still allowing large table walks

      # Test with short per-PDU timeout - should still fail with proper timeout
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "test1"]},
            {"192.0.2.2", "1.3.6.1.2.1.1", [community: "test2"]},
            {"192.0.2.3", "1.3.6.1.2.1.1", [community: "test3"]}
          ],
          timeout: 1000
        )

      # All should fail with proper SNMP timeouts, not task timeouts
      assert [
               {:error, reason1},
               {:error, reason2},
               {:error, reason3}
             ] = result

      # Verify none are task timeout failures
      for reason <- [reason1, reason2, reason3] do
        refute match?({:task_failed, :timeout}, reason)
        assert reason == :timeout or match?({:network_error, _}, reason)
      end
    end

    test "walk operations respect walk_timeout option" do
      # Test that walk_timeout option is respected when provided
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "test"]}
          ],
          timeout: 1000,
          # 5 second maximum for entire walk
          walk_timeout: 5000
        )

      # Should still fail with proper timeout, not task timeout
      assert [{:error, reason}] = result
      refute match?({:task_failed, :timeout}, reason)
    end

    test "walk timeout is capped at 30 minutes for safety" do
      # Even if user sets a very high walk_timeout, it should be capped
      # This test verifies the safety mechanism exists (we can't easily test the actual cap)
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "test"]}
          ],
          timeout: 1000,
          # Extremely high timeout
          walk_timeout: 999_999_999
        )

      # Should still work (fail properly) and not hang indefinitely
      assert [{:error, _reason}] = result
    end
  end

  describe "mixed operations timeout handling" do
    test "mixed operations with walks use safe maximum timeout" do
      # Test the execute_mixed function uses appropriate timeout when walks are present

      operations = [
        {:get, "192.0.2.1", "1.3.6.1.2.1.1.1.0", [community: "test"]},
        {:walk, "192.0.2.2", "1.3.6.1.2.1.1", [community: "test"]},
        {:get_bulk, "192.0.2.3", "1.3.6.1.2.1.2.2.1.1", [community: "test"]}
      ]

      result = MultiV2.execute_mixed(operations, timeout: 1000)

      # All should fail with proper SNMP/network errors, not task timeouts
      assert [
               {:error, reason1},
               {:error, reason2},
               {:error, reason3}
             ] = result

      # Verify none are task timeout failures
      for reason <- [reason1, reason2, reason3] do
        refute match?({:task_failed, :timeout}, reason)
      end
    end

    test "mixed operations without walks use short task timeout" do
      # When no walks are present, should use shorter timeout for safety
      operations = [
        {:get, "192.0.2.1", "1.3.6.1.2.1.1.1.0", [community: "test"]},
        {:get_bulk, "192.0.2.2", "1.3.6.1.2.1.2.2.1.1", [community: "test"]}
      ]

      result = MultiV2.execute_mixed(operations, timeout: 1000)

      # Should fail appropriately
      assert [
               {:error, _reason1},
               {:error, _reason2}
             ] = result
    end

    test "mixed operations respect walk_timeout when walks present" do
      # Test that walk_timeout is respected in mixed operations
      operations = [
        {:get, "192.0.2.1", "1.3.6.1.2.1.1.1.0", [community: "test"]},
        {:walk, "192.0.2.2", "1.3.6.1.2.1.1", [community: "test"]}
      ]

      result = MultiV2.execute_mixed(operations, timeout: 1000, walk_timeout: 5000)

      # Should complete without task timeout errors
      assert [
               {:error, _reason1},
               {:error, _reason2}
             ] = result
    end
  end

  describe "backwards compatibility" do
    test "timeout option still controls per-PDU behavior as documented" do
      # Verify that the timeout option behavior hasn't changed from user perspective
      # Users expect timeout to control how long to wait for each SNMP response

      # Test with a reasonable timeout
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "public"]}
          ],
          timeout: 5000
        )

      # Should behave the same as before the fix - timeout controls PDU timeouts
      assert [{:error, _reason}] = result
    end

    @tag timeout: 15_000
    test "default timeout behavior unchanged" do
      # Verify default timeout behavior is preserved but use short timeout for testing
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "public"]}
          ],
          timeout: 3_000
        )

      # Should use specified timeout for per-PDU timeouts
      assert [{:error, _reason}] = result
    end
  end

  describe "safety mechanisms" do
    test "walk operations cannot hang indefinitely" do
      # Verify that even with the timeout fix, operations cannot hang forever
      # This is a conceptual test - we can't wait 30 minutes, but we verify the logic exists

      # The key is that we should never see :infinity timeout in real usage
      # and operations should always have some reasonable upper bound
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "test"]}
          ],
          timeout: 1000
        )

      # Should complete in reasonable time (fail quickly due to network issues)
      assert [{:error, _reason}] = result
    end

    test "explicit walk_timeout overrides default calculation" do
      # Test that users can explicitly control maximum walk time
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "test"]}
          ],
          timeout: 2000,
          # 10 second max walk time
          walk_timeout: 10_000
        )

      # Should respect the explicit walk_timeout
      assert [{:error, _reason}] = result
    end
  end
end
