#!/usr/bin/env elixir

# Focused test to debug SNMPv1 walk issues
# This tests specifically why explicit v1 walks fail

Mix.install([
  {:snmpkit, path: "."}
])

defmodule V1SpecificDebugger do
  require Logger

  def run do
    IO.puts("=== SNMPv1 Specific Walk Debugging ===\n")

    # Create a simple test device
    oid_map = %{
      "1.3.6.1.2.1.1.1.0" => "Test Device v1",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.999",
      "1.3.6.1.2.1.1.3.0" => 54321
    }

    IO.puts("1. Creating test device with #{map_size(oid_map)} OIDs...")

    case SnmpKit.SnmpSim.ProfileLoader.load_profile(:test, {:manual, oid_map}) do
      {:ok, profile} ->
        case SnmpKit.Sim.start_device(profile, port: 9996) do
          {:ok, device} ->
            IO.puts("   ✅ Device started on port 9996")
            debug_v1_specific(device)

          {:error, reason} ->
            IO.puts("   ❌ Failed to start device: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("   ❌ Failed to load profile: #{inspect(reason)}")
    end
  end

  defp debug_v1_specific(_device) do
    target = "127.0.0.1:9996"
    oid = "1.3.6.1.2.1.1"

    IO.puts("\n2. Testing why explicit v1 walks fail:")

    # Test 1: Individual v1 GET_NEXT
    IO.puts("\nTest 1: Individual v1 GET_NEXT operations")
    case SnmpKit.SNMP.get_next(target, oid, version: :v1, timeout: 5000) do
      {:ok, {next_oid, value}} ->
        IO.puts("   ✅ v1 GET_NEXT: #{next_oid} = #{inspect(value)}")
      {:error, reason} ->
        IO.puts("   ❌ v1 GET_NEXT failed: #{inspect(reason)}")
    end

    # Test 2: v1 walk with minimal options
    IO.puts("\nTest 2: v1 walk with minimal options")
    case SnmpKit.SNMP.walk(target, oid, version: :v1, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   ✅ v1 WALK (minimal): #{length(results)} results")
        if length(results) > 0 do
          IO.puts("      First: #{inspect(hd(results))}")
        end
      {:error, reason} ->
        IO.puts("   ❌ v1 WALK (minimal) failed: #{inspect(reason)}")
    end

    # Test 3: v1 walk with max_iterations (new parameter)
    IO.puts("\nTest 3: v1 walk with max_iterations")
    case SnmpKit.SNMP.walk(target, oid, version: :v1, max_iterations: 10, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   ✅ v1 WALK (max_iterations): #{length(results)} results")
        if length(results) > 0 do
          IO.puts("      First: #{inspect(hd(results))}")
        end
      {:error, reason} ->
        IO.puts("   ❌ v1 WALK (max_iterations) failed: #{inspect(reason)}")
    end

    # Test 4: v1 walk with max_repetitions (should be ignored)
    IO.puts("\nTest 4: v1 walk with max_repetitions (should be ignored)")
    case SnmpKit.SNMP.walk(target, oid, version: :v1, max_repetitions: 10, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   ✅ v1 WALK (max_repetitions): #{length(results)} results")
        if length(results) > 0 do
          IO.puts("      First: #{inspect(hd(results))}")
        end
      {:error, reason} ->
        IO.puts("   ❌ v1 WALK (max_repetitions) failed: #{inspect(reason)}")
    end

    # Test 5: Compare with v2c walk
    IO.puts("\nTest 5: Compare with v2c walk")
    case SnmpKit.SNMP.walk(target, oid, version: :v2c, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   ✅ v2c WALK: #{length(results)} results")
        if length(results) > 0 do
          IO.puts("      First: #{inspect(hd(results))}")
        end
      {:error, reason} ->
        IO.puts("   ❌ v2c WALK failed: #{inspect(reason)}")
    end

    # Test 6: Default walk (should use v2c now)
    IO.puts("\nTest 6: Default walk (should use v2c)")
    case SnmpKit.SNMP.walk(target, oid, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   ✅ DEFAULT WALK: #{length(results)} results")
        if length(results) > 0 do
          IO.puts("      First: #{inspect(hd(results))}")
        end
      {:error, reason} ->
        IO.puts("   ❌ DEFAULT WALK failed: #{inspect(reason)}")
    end

    # Test 7: Manual iteration with v1 GET_NEXT
    IO.puts("\nTest 7: Manual v1 walk simulation")
    manual_v1_walk(target, oid)

    IO.puts("\n=== Analysis ===")
    IO.puts("If individual GET_NEXT works but walk fails, the issue is in walk_from_oid logic")
    IO.puts("If manual iteration works but walk fails, the issue is in parameter handling")
  end

  defp manual_v1_walk(target, start_oid) do
    results = []
    current_oid = start_oid
    max_iterations = 5

    final_results = Enum.reduce_while(1..max_iterations, {current_oid, results}, fn iteration, {oid, acc} ->
      IO.puts("   Manual iteration #{iteration}: GET_NEXT(#{oid})")

      case SnmpKit.SNMP.get_next(target, oid, version: :v1, timeout: 5000) do
        {:ok, {next_oid, value}} ->
          if String.starts_with?(next_oid, start_oid) do
            new_acc = [{next_oid, value} | acc]
            IO.puts("      ✅ Got: #{next_oid} = #{inspect(value)}")
            {:cont, {next_oid, new_acc}}
          else
            IO.puts("      ℹ️  Outside scope: #{next_oid}")
            {:halt, {oid, acc}}
          end

        {:error, reason} ->
          IO.puts("      ❌ Error: #{inspect(reason)}")
          {:halt, {oid, acc}}
      end
    end)

    case final_results do
      {_final_oid, final_acc} ->
        IO.puts("   Manual v1 walk result: #{length(final_acc)} results")
        if length(final_acc) > 0 do
          IO.puts("      Results: #{inspect(Enum.reverse(final_acc))}")
        end
    end
  end
end

# Disable debug logging for cleaner output
Logger.configure(level: :info)

V1SpecificDebugger.run()
