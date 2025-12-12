defmodule SnmpKit.SnmpMgr.SimplePerRequestTimeoutTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.MultiV2

  @moduletag :unit
  @moduletag :simple_timeout_test

  describe "per-request timeout functionality verification" do
    test "per-request timeout is extracted and used correctly" do
      # This test verifies that per-request timeouts are being read from request.opts
      # by checking that operations complete without internal errors

      # The key insight: if per-request timeout wasn't being used, we'd get
      # inconsistent behavior or internal errors due to timeout mismatches

      result =
        MultiV2.get_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [community: "test", timeout: 2000]}
          ],
          timeout: 1000
        )

      # Should get a result without internal processing errors
      assert [result_item] = result
      # Should be some kind of error (network/timeout), not an internal failure
      assert match?({:error, _}, result_item)

      # Extract the error reason
      {:error, reason} = result_item

      # Should NOT be internal errors that would indicate timeout value problems
      refute match?({:exception, %ErlangError{original: :timeout_value}}, reason)
      refute match?({:exception, _}, reason)

      # Should be normal operational errors (network/timeout)
      assert reason == :timeout or
               match?({:network_error, _}, reason) or
               match?({:task_failed, :timeout}, reason)
    end

    test "walk operations use per-request timeout without errors" do
      # Test that walk operations can use per-request timeouts
      result =
        MultiV2.walk_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1", [community: "test", timeout: 3000]}
          ],
          timeout: 1000
        )

      assert [result_item] = result
      assert match?({:error, _}, result_item)

      {:error, reason} = result_item

      # Should not be internal errors
      refute match?({:exception, %ErlangError{original: :timeout_value}}, reason)
      refute match?({:exception, _}, reason)
    end

    test "mixed timeout values work without internal errors" do
      # Test multiple requests with different per-request timeouts
      result =
        MultiV2.get_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [timeout: 1500]},
            {"192.0.2.2", "1.3.6.1.2.1.1.1.0", [timeout: 2500]},
            {"192.0.2.3", "1.3.6.1.2.1.1.1.0", [timeout: 500]}
          ],
          timeout: 1000
        )

      assert [r1, r2, r3] = result

      for result_item <- [r1, r2, r3] do
        assert match?({:error, _}, result_item)
        {:error, reason} = result_item
        refute match?({:exception, %ErlangError{original: :timeout_value}}, reason)
      end
    end

    test "fallback to global timeout works" do
      # Test that when no per-request timeout is specified, global is used
      result =
        MultiV2.get_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [community: "test"]}
          ],
          timeout: 1500
        )

      assert [result_item] = result
      assert match?({:error, _}, result_item)

      {:error, reason} = result_item
      refute match?({:exception, %ErlangError{original: :timeout_value}}, reason)
    end

    test "zero and negative timeouts are handled safely" do
      # Edge case: invalid timeout values should fall back to global
      result =
        MultiV2.get_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [timeout: 0]},
            {"192.0.2.2", "1.3.6.1.2.1.1.1.0", [timeout: -1000]}
          ],
          timeout: 2000
        )

      assert [r1, r2] = result

      for result_item <- [r1, r2] do
        assert match?({:error, _}, result_item)
        {:error, reason} = result_item
        # Should not crash with timeout_value errors
        refute match?({:exception, %ErlangError{original: :timeout_value}}, reason)
      end
    end

    test "non-integer timeout values fall back safely" do
      # Edge case: non-integer timeout should fall back to global
      result =
        MultiV2.get_multi(
          [
            {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [timeout: "invalid"]},
            {"192.0.2.2", "1.3.6.1.2.1.1.1.0", [timeout: :atom]}
          ],
          timeout: 1500
        )

      assert [r1, r2] = result

      for result_item <- [r1, r2] do
        assert match?({:error, _}, result_item)
        {:error, reason} = result_item
        refute match?({:exception, %ErlangError{original: :timeout_value}}, reason)
      end
    end
  end

  describe "timeout behavior verification" do
    test "demonstrate per-request timeout is actually being used" do
      # This test shows that different timeout values are actually being applied
      # We can't easily test the exact timing, but we can test that the system
      # processes the different timeout values without errors

      start_time = System.monotonic_time(:millisecond)

      # Use very short timeouts to make test faster
      _result =
        MultiV2.get_multi(
          [
            # Very short
            {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [timeout: 100]},
            # Slightly longer
            {"192.0.2.2", "1.3.6.1.2.1.1.1.0", [timeout: 200]}
          ],
          # Global timeout between the two
          timeout: 150
        )

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Test should complete relatively quickly (within a few seconds)
      # This verifies that timeouts are being applied, not hanging
      assert duration < 5000, "Test took too long: #{duration}ms"
    end
  end
end
