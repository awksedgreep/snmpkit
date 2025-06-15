#!/usr/bin/env elixir

# Test Exact SNMP Path Script
# This script replicates the exact same code path as the failing SNMP operation
# to isolate where the :ehostunreach error occurs

defmodule TestExactSNMPPath do
  require Logger

  @target "192.168.88.234"
  @target_port 161

  def run do
    IO.puts("""

    🔬 Testing Exact SNMP Code Path
    ===============================

    This script replicates the exact same sequence of calls that
    SnmpKit.SnmpMgr.bulk_walk uses to isolate where :ehostunreach occurs.

    Target: #{@target}:#{@target_port}

    """)

    Logger.configure(level: :debug)

    # Test each step in the exact sequence
    steps = [
      {"1. Direct UDP Send (baseline)", &test_direct_udp/0},
      {"2. Transport.create_client_socket", &test_transport_create_socket/0},
      {"3. Transport.send_packet", &test_transport_send_packet/0},
      {"4. Manager.get_bulk (raw)", &test_manager_get_bulk/0},
      {"5. Core.send_get_bulk_request", &test_core_send_bulk_request/0},
      {"6. AdaptiveWalk.bulk_walk", &test_adaptive_walk/0},
      {"7. SnmpMgr.bulk_walk (full)", &test_full_bulk_walk/0}
    ]

    results = Enum.map(steps, fn {name, test_fn} ->
      IO.puts("\n#{name}")
      IO.puts(String.duplicate("-", 50))

      start_time = System.monotonic_time(:millisecond)

      result = try do
        test_fn.()
      rescue
        e ->
          IO.puts("EXCEPTION: #{inspect(e)}")
          {:error, {:exception, e}}
      catch
        :exit, reason ->
          IO.puts("EXIT: #{inspect(reason)}")
          {:error, {:exit, reason}}
      end

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      case result do
        :ok ->
          IO.puts("✅ SUCCESS (#{duration}ms)")
          {name, :success, duration}
        {:ok, message} ->
          IO.puts("✅ SUCCESS (#{duration}ms): #{message}")
          {name, :success, duration}
        {:error, reason} ->
          IO.puts("❌ FAILED (#{duration}ms): #{inspect(reason)}")
          {name, :failed, duration}
      end

      {name, result, duration}
    end)

    print_analysis(results)
  end

  # Test 1: Direct UDP send (should work based on diagnostics)
  defp test_direct_udp do
    IO.puts("Creating raw UDP socket and sending packet...")

    {:ok, socket} = :gen_udp.open(0, [:binary, :inet, {:active, false}])

    {:ok, {local_ip, local_port}} = :inet.sockname(socket)
    IO.puts("Socket bound to #{:inet.ntoa(local_ip)}:#{local_port}")

    case :gen_udp.send(socket, String.to_charlist(@target), @target_port, "test") do
      :ok ->
        IO.puts("UDP send successful")
        :gen_udp.close(socket)
        :ok
      {:error, reason} ->
        IO.puts("UDP send failed: #{inspect(reason)}")
        :gen_udp.close(socket)
        {:error, reason}
    end
  end

  # Test 2: Use Transport.create_client_socket (exact same as SNMP code)
  defp test_transport_create_socket do
    IO.puts("Using SnmpKit.SnmpLib.Transport.create_client_socket...")

    case SnmpKit.SnmpLib.Transport.create_client_socket() do
      {:ok, socket} ->
        IO.puts("Transport socket created successfully")

        # Get socket details
        {:ok, {local_ip, local_port}} = :inet.sockname(socket)
        IO.puts("Transport socket bound to #{:inet.ntoa(local_ip)}:#{local_port}")

        # Now try to send using raw UDP through this socket
        case :gen_udp.send(socket, String.to_charlist(@target), @target_port, "test") do
          :ok ->
            IO.puts("Send through transport socket successful")
            SnmpKit.SnmpLib.Transport.close_socket(socket)
            :ok
          {:error, reason} ->
            IO.puts("Send through transport socket failed: #{inspect(reason)}")
            SnmpKit.SnmpLib.Transport.close_socket(socket)
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("Transport socket creation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Test 3: Use Transport.send_packet (exact Transport layer call)
  defp test_transport_send_packet do
    IO.puts("Using SnmpKit.SnmpLib.Transport.send_packet...")

    case SnmpKit.SnmpLib.Transport.create_client_socket() do
      {:ok, socket} ->
        IO.puts("Socket created, testing send_packet...")

        case SnmpKit.SnmpLib.Transport.send_packet(socket, @target, @target_port, "test") do
          :ok ->
            IO.puts("Transport.send_packet successful")
            SnmpKit.SnmpLib.Transport.close_socket(socket)
            :ok
          {:error, reason} ->
            IO.puts("Transport.send_packet failed: #{inspect(reason)}")
            SnmpKit.SnmpLib.Transport.close_socket(socket)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Test 4: Use Manager.get_bulk (raw call)
  defp test_manager_get_bulk do
    IO.puts("Using SnmpKit.SnmpLib.Manager.get_bulk directly...")

    case SnmpKit.SnmpLib.Manager.get_bulk(@target, [1, 3, 6],
           community: "public", version: :v2c, max_repetitions: 1) do
      {:ok, results} ->
        IO.puts("Manager.get_bulk successful: #{length(results)} results")
        :ok
      {:error, reason} ->
        IO.puts("Manager.get_bulk failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Test 5: Use Core.send_get_bulk_request
  defp test_core_send_bulk_request do
    IO.puts("Using SnmpKit.SnmpMgr.Core.send_get_bulk_request...")

    case SnmpKit.SnmpMgr.Core.send_get_bulk_request(@target, [1, 3, 6],
           community: "public", version: :v2c, max_repetitions: 1) do
      {:ok, results} ->
        IO.puts("Core.send_get_bulk_request successful: #{length(results)} results")
        :ok
      {:error, reason} ->
        IO.puts("Core.send_get_bulk_request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Test 6: Use AdaptiveWalk.bulk_walk
  defp test_adaptive_walk do
    IO.puts("Using SnmpKit.SnmpMgr.AdaptiveWalk.bulk_walk...")

    case SnmpKit.SnmpMgr.AdaptiveWalk.bulk_walk(@target, [1, 3, 6], max_entries: 10) do
      {:ok, results} ->
        IO.puts("AdaptiveWalk.bulk_walk successful: #{length(results)} results")
        :ok
      {:error, reason} ->
        IO.puts("AdaptiveWalk.bulk_walk failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Test 7: Full bulk_walk (the failing operation)
  defp test_full_bulk_walk do
    IO.puts("Using SnmpKit.SnmpMgr.bulk_walk (full operation)...")

    case SnmpKit.SnmpMgr.bulk_walk(@target, [1, 3, 6]) do
      {:ok, results} ->
        IO.puts("Full bulk_walk successful: #{length(results)} results")
        :ok
      {:error, reason} ->
        IO.puts("Full bulk_walk failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp print_analysis(results) do
    IO.puts("""

    🔍 ANALYSIS
    ===========
    """)

    # Find where it starts failing
    {successful, failed} = Enum.split_while(results, fn {_, result, _} ->
      case result do
        :ok -> true
        {:ok, _} -> true
        _ -> false
      end
    end)

    if length(failed) == 0 do
      IO.puts("🎉 ALL TESTS PASSED!")
      IO.puts("This means the issue is intermittent or environment-specific.")
      IO.puts("The socket binding and transport layers are working correctly.")
    else
      IO.puts("❌ FAILURE DETECTED!")

      if length(successful) > 0 do
        last_success = List.last(successful)
        {last_success_name, _, _} = last_success
        IO.puts("✅ Last successful step: #{last_success_name}")
      end

      if length(failed) > 0 do
        {first_failure_name, first_failure_result, _} = List.first(failed)
        IO.puts("❌ First failure at: #{first_failure_name}")
        IO.puts("   Error: #{inspect(first_failure_result)}")
      end

      IO.puts("\n📊 DIAGNOSIS:")

      cond do
        length(successful) == 0 ->
          IO.puts("• Issue is at the lowest level (raw UDP)")
          IO.puts("• Check network interface configuration")
          IO.puts("• Verify routing table")

        length(successful) == 1 ->
          IO.puts("• Raw UDP works but Transport layer fails")
          IO.puts("• Issue is in socket option configuration")
          IO.puts("• Check Transport.create_client_socket implementation")

        length(successful) >= 2 and length(successful) <= 3 ->
          IO.puts("• Transport layer works but Manager layer fails")
          IO.puts("• Issue might be in SNMP message building/encoding")
          IO.puts("• Check PDU construction")

        true ->
          IO.puts("• Lower layers work but high-level coordination fails")
          IO.puts("• Issue might be in AdaptiveWalk or SnmpMgr orchestration")
      end
    end

    # Performance analysis
    IO.puts("\n⏱️  PERFORMANCE:")
    total_time = Enum.map(results, fn {_, _, duration} -> duration end) |> Enum.sum()
    IO.puts("Total test time: #{total_time}ms")

    avg_time = if length(results) > 0, do: div(total_time, length(results)), else: 0
    IO.puts("Average per test: #{avg_time}ms")

    # Show specific timing for failed tests
    Enum.each(failed, fn {name, _, duration} ->
      IO.puts("#{name}: #{duration}ms (FAILED)")
    end)
  end
end

# Run the exact path test
TestExactSNMPPath.run()
