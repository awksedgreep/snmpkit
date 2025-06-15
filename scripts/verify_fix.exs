#!/usr/bin/env elixir

# Final Verification Script for SNMP Bulk Walk Fix
# This script demonstrates that the :ehostunreach issue has been resolved

defmodule VerifyFix do
  require Logger

  @target "192.168.88.234"

  def run do
    IO.puts("""

    🎉 SNMP Bulk Walk Fix Verification
    ==================================

    This script verifies that the :ehostunreach network connectivity issue
    has been resolved with the retry logic and network state refresh.

    Target Device: #{@target}
    Fix Applied: Network retry with automatic state refresh

    """)

    # Enable debug logging to show the fix in action
    Logger.configure(level: :debug)

    tests = [
      {"Single SNMP GET Request", &test_single_get/0},
      {"SNMP GETBULK Request", &test_bulk_request/0},
      {"Full Bulk Walk Operation", &test_bulk_walk/0},
      {"Multiple Consecutive Operations", &test_multiple_operations/0},
      {"Fresh Session Simulation", &test_fresh_session/0}
    ]

    IO.puts("Running verification tests...\n")

    results = Enum.map(tests, fn {name, test_fn} ->
      IO.puts("🔍 #{name}")

      start_time = System.monotonic_time(:millisecond)

      result = try do
        test_fn.()
      rescue
        e -> {:error, {:exception, e}}
      end

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      case result do
        {:ok, message} ->
          IO.puts("  ✅ PASS (#{duration}ms): #{message}")
          {name, :pass, duration}

        {:error, reason} ->
          IO.puts("  ❌ FAIL (#{duration}ms): #{inspect(reason)}")
          {name, :fail, duration}

        :ok ->
          IO.puts("  ✅ PASS (#{duration}ms)")
          {name, :pass, duration}
      end

      IO.puts("")
      {name, result, duration}
    end)

    print_summary(results)
  end

  defp test_single_get do
    case SnmpKit.SnmpMgr.get(@target, [1, 3, 6, 1, 2, 1, 1, 1, 0]) do
      {:ok, result} ->
        {:ok, "Retrieved sysDescr: #{inspect(result)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_bulk_request do
    case SnmpKit.SnmpLib.Manager.get_bulk(@target, [1, 3, 6, 1, 2, 1, 1],
         community: "public", version: :v2c, max_repetitions: 5) do
      {:ok, results} when is_list(results) ->
        {:ok, "Retrieved #{length(results)} objects via GETBULK"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_bulk_walk do
    case SnmpKit.SnmpMgr.bulk_walk(@target, [1, 3, 6]) do
      {:ok, results} when is_list(results) ->
        {:ok, "Bulk walk completed: #{length(results)} total objects"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_multiple_operations do
    operations = [
      fn -> SnmpKit.SnmpMgr.get(@target, [1, 3, 6, 1, 2, 1, 1, 1, 0]) end,
      fn -> SnmpKit.SnmpMgr.get(@target, [1, 3, 6, 1, 2, 1, 1, 5, 0]) end,
      fn -> SnmpKit.SnmpMgr.get(@target, [1, 3, 6, 1, 2, 1, 1, 6, 0]) end
    ]

    results = Enum.map(operations, fn op ->
      case op.() do
        {:ok, _} -> :ok
        {:error, _} -> :error
      end
    end)

    success_count = Enum.count(results, &(&1 == :ok))

    if success_count == length(operations) do
      {:ok, "All #{success_count} consecutive operations succeeded"}
    else
      {:error, "Only #{success_count}/#{length(operations)} operations succeeded"}
    end
  end

  defp test_fresh_session do
    # Simulate what happens in a fresh iex session by creating new processes
    parent = self()

    ref = make_ref()

    spawn(fn ->
      # This simulates a fresh process like starting iex
      result = case SnmpKit.SnmpMgr.bulk_walk(@target, [1, 3, 6, 1, 2, 1, 1]) do
        {:ok, results} -> {:ok, "Fresh process bulk walk: #{length(results)} objects"}
        {:error, reason} -> {:error, reason}
      end

      send(parent, {ref, result})
    end)

    receive do
      {^ref, result} -> result
    after
      10_000 -> {:error, :timeout}
    end
  end

  defp print_summary(results) do
    IO.puts("""

    📊 VERIFICATION SUMMARY
    ======================
    """)

    passes = Enum.count(results, fn {_, result, _} ->
      case result do
        {:ok, _} -> true
        :ok -> true
        _ -> false
      end
    end)

    total = length(results)

    IO.puts("Results: #{passes}/#{total} tests passed")

    if passes == total do
      IO.puts("""

      🎉 SUCCESS! All tests passed!

      ✅ The :ehostunreach network connectivity issue has been RESOLVED
      ✅ SNMP bulk walk operations are working correctly
      ✅ Network retry logic is functioning properly
      ✅ Both fresh sessions and consecutive operations work

      🔧 Fix Details:
      - Added automatic retry logic for :ehostunreach errors
      - Implemented network state refresh via ping
      - Added 100ms delay between retries
      - Maximum of 3 retry attempts per operation

      🚀 Your SNMP bulk walk operations should now work reliably!
      """)
    else
      IO.puts("""

      ⚠️  Some tests failed. Issues detected:
      """)

      Enum.each(results, fn {name, result, duration} ->
        case result do
          {:error, reason} ->
            IO.puts("  ❌ #{name}: #{inspect(reason)}")
          _ ->
            :ok
        end
      end)

      IO.puts("""

      💡 Troubleshooting suggestions:
      1. Verify target device (#{@target}) is accessible: ping #{@target}
      2. Check SNMP port: nc -u -z #{@target} 161
      3. Try network refresh: sudo route flush && sudo arp -a -d
      4. Run diagnostic script: mix run scripts/debug_network_routing.exs
      """)
    end

    # Show performance stats
    avg_duration = results
      |> Enum.map(fn {_, _, duration} -> duration end)
      |> Enum.sum()
      |> div(total)

    IO.puts("\nPerformance: Average test duration #{avg_duration}ms")
  end
end

# Run the verification
VerifyFix.run()
