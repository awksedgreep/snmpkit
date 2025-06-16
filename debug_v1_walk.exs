#!/usr/bin/env elixir

# Debug script to understand why SNMPv1 walk operations fail
# while SNMPv2c walk operations work correctly

Mix.install([
  {:snmpkit, path: "."}
])

defmodule V1WalkDebugger do
  require Logger

  def run do
    IO.puts("=== SNMPv1 Walk Debugging ===\n")

    # Create a test device
    oid_map = %{
      "1.3.6.1.2.1.1.1.0" => "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.4115.1.20.1.1.2.2",
      "1.3.6.1.2.1.1.3.0" => 123456,
      "1.3.6.1.2.1.1.4.0" => "admin@example.com"
    }

    IO.puts("1. Creating test device...")

    case SnmpKit.SnmpSim.ProfileLoader.load_profile(:test, {:manual, oid_map}) do
      {:ok, profile} ->
        case SnmpKit.Sim.start_device(profile, port: 9998) do
          {:ok, device} ->
            IO.puts("   ✅ Device started on port 9998")
            debug_v1_walk(device)

          {:error, reason} ->
            IO.puts("   ❌ Failed to start device: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("   ❌ Failed to load profile: #{inspect(reason)}")
    end
  end

  defp debug_v1_walk(device) do
    target = "127.0.0.1:9998"
    start_oid = "1.3.6.1.2.1.1"

    IO.puts("\n2. Testing individual v1 operations:")

    # Test individual v1 GET_NEXT operations
    test_get_next_sequence(target, start_oid)

    IO.puts("\n3. Testing v1 walk internals:")

    # Test the walk implementation step by step
    debug_walk_implementation(target, start_oid)

    IO.puts("\n4. Comparing v1 vs v2c responses:")

    # Compare responses between versions
    compare_versions(target, start_oid)

    IO.puts("\n5. Testing edge cases:")

    # Test various edge cases
    test_edge_cases(target)
  end

  defp test_get_next_sequence(target, start_oid) do
    IO.puts("   Testing manual GET_NEXT sequence:")

    current_oid = start_oid
    results = []
    max_iterations = 10

    Enum.reduce_while(1..max_iterations, {current_oid, results}, fn iteration, {oid, acc} ->
      IO.puts("   Iteration #{iteration}: GET_NEXT(#{oid})")

      case SnmpKit.SNMP.get_next(target, oid, version: :v1, timeout: 5000) do
        {:ok, {next_oid, value}} ->
          IO.puts("      ✅ Got: #{next_oid} = #{inspect(value)}")

          # Check if still in scope
          if String.starts_with?(next_oid, start_oid) do
            new_acc = [{next_oid, value} | acc]
            {:cont, {next_oid, new_acc}}
          else
            IO.puts("      ℹ️  Walked outside scope, stopping")
            {:halt, {next_oid, acc}}
          end

        {:error, reason} ->
          IO.puts("      ❌ Error: #{inspect(reason)}")
          {:halt, {oid, acc}}
      end
    end)
  end

  defp debug_walk_implementation(target, start_oid) do
    IO.puts("   Debugging walk_from_oid implementation:")

    # Test OID resolution
    case SnmpKit.SnmpMgr.Core.parse_oid(start_oid) do
      {:ok, oid_list} ->
        IO.puts("   ✅ OID parsed: #{start_oid} -> #{inspect(oid_list)}")

        # Test first GET_NEXT call
        case SnmpKit.SnmpMgr.Core.send_get_next_request(target, oid_list, version: :v1, timeout: 5000) do
          {:ok, {next_oid_string, value}} ->
            IO.puts("   ✅ First GET_NEXT: #{next_oid_string} = #{inspect(value)}")

            # Test OID parsing of response
            case SnmpKit.SnmpLib.OID.string_to_list(next_oid_string) do
              {:ok, next_oid_list} ->
                IO.puts("   ✅ Response OID parsed: #{next_oid_string} -> #{inspect(next_oid_list)}")

                # Test scope checking
                in_scope = List.starts_with?(next_oid_list, oid_list)
                IO.puts("   ℹ️  In scope check: #{inspect(next_oid_list)} starts_with #{inspect(oid_list)} = #{in_scope}")

              {:error, parse_error} ->
                IO.puts("   ❌ Failed to parse response OID: #{inspect(parse_error)}")
            end

          {:error, request_error} ->
            IO.puts("   ❌ First GET_NEXT failed: #{inspect(request_error)}")
        end

      {:error, oid_error} ->
        IO.puts("   ❌ Failed to parse start OID: #{inspect(oid_error)}")
    end
  end

  defp compare_versions(target, start_oid) do
    IO.puts("   Comparing v1 vs v2c for same OID:")

    # Test v1
    case SnmpKit.SNMP.get_next(target, start_oid, version: :v1, timeout: 5000) do
      {:ok, {v1_oid, v1_value}} ->
        IO.puts("   ✅ v1 GET_NEXT: #{v1_oid} = #{inspect(v1_value)}")

      {:error, v1_error} ->
        IO.puts("   ❌ v1 GET_NEXT failed: #{inspect(v1_error)}")
    end

    # Test v2c
    case SnmpKit.SNMP.get_next(target, start_oid, version: :v2c, timeout: 5000) do
      {:ok, {v2c_oid, v2c_value}} ->
        IO.puts("   ✅ v2c GET_NEXT: #{v2c_oid} = #{inspect(v2c_value)}")

      {:error, v2c_error} ->
        IO.puts("   ❌ v2c GET_NEXT failed: #{inspect(v2c_error)}")
    end

    # Test v1 walk
    case SnmpKit.SNMP.walk(target, start_oid, version: :v1, timeout: 5000) do
      {:ok, v1_results} ->
        IO.puts("   ✅ v1 WALK: #{length(v1_results)} results")

      {:error, v1_walk_error} ->
        IO.puts("   ❌ v1 WALK failed: #{inspect(v1_walk_error)}")
    end

    # Test v2c walk
    case SnmpKit.SNMP.walk(target, start_oid, version: :v2c, timeout: 5000) do
      {:ok, v2c_results} ->
        IO.puts("   ✅ v2c WALK: #{length(v2c_results)} results")

      {:error, v2c_walk_error} ->
        IO.puts("   ❌ v2c WALK failed: #{inspect(v2c_walk_error)}")
    end
  end

  defp test_edge_cases(target) do
    edge_cases = [
      {"1.3.6.1.2.1.1.1.0", "exact leaf OID"},
      {"1.3.6.1.2.1.1.1", "partial OID"},
      {"1.3.6.1.2.1.1.5", "non-existent branch"},
      {"1.3.6.1.2.1.99", "way outside scope"}
    ]

    Enum.each(edge_cases, fn {oid, description} ->
      IO.puts("   Testing #{description} (#{oid}):")

      case SnmpKit.SNMP.get_next(target, oid, version: :v1, timeout: 5000) do
        {:ok, {next_oid, value}} ->
          IO.puts("      ✅ v1: #{next_oid} = #{inspect(value)}")

        {:error, reason} ->
          IO.puts("      ❌ v1: #{inspect(reason)}")
      end
    end)
  end
end

# Enable debug logging
Logger.configure(level: :debug)

V1WalkDebugger.run()
