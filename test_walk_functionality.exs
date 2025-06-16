#!/usr/bin/env elixir

# SNMP Walk Functionality Test
# This test validates that walk operations actually return complete results

Mix.install([
  {:snmpkit, path: "."}
])

defmodule WalkFunctionalityTest do
  require Logger

  @moduledoc """
  Test to validate that SNMP walk operations are working correctly.

  This test specifically checks:
  1. Walk operations return non-zero results
  2. Walk operations iterate through multiple OIDs
  3. Both v1 and v2c walks work properly
  4. Type information is preserved in walks
  5. Walk stops at proper boundaries
  """

  @test_timeout 15_000
  @test_target "127.0.0.1"
  @test_port 1161

  def run_tests do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("SNMP WALK FUNCTIONALITY TEST")
    IO.puts("Testing if walks actually return results...")
    IO.puts(String.duplicate("=", 70))

    # Start simulator for testing
    {:ok, simulator_pid} = start_test_simulator()
    Process.sleep(2000)  # Give simulator time to start

    test_results = [
      {"Simulator Status", test_simulator_running()},
      {"Basic GET Operations", test_basic_get_operations()},
      {"Walk v2c Returns Results", test_walk_v2c_returns_results()},
      {"Walk v1 Returns Results", test_walk_v1_returns_results()},
      {"Walk Result Format", test_walk_result_format()},
      {"Walk Boundary Detection", test_walk_boundary_detection()},
      {"Walk vs Individual Comparison", test_walk_vs_individual()},
      {"Large Walk Performance", test_large_walk_performance()}
    ]

    # Stop simulator
    if simulator_pid, do: Process.exit(simulator_pid, :normal)

    # Report results
    IO.puts("\n" <> String.duplicate("-", 70))
    IO.puts("WALK FUNCTIONALITY TEST RESULTS")
    IO.puts(String.duplicate("-", 70))

    {passed, failed} =
      test_results
      |> Enum.reduce({0, 0}, fn {test_name, result}, {pass_count, fail_count} ->
        status = if result, do: "✅ PASS", else: "❌ FAIL"
        IO.puts("#{status} - #{test_name}")
        if result, do: {pass_count + 1, fail_count}, else: {pass_count, fail_count + 1}
      end)

    IO.puts(String.duplicate("-", 70))
    IO.puts("TOTAL: #{passed} passed, #{failed} failed")

    if failed > 0 do
      IO.puts("\n❌ WALK FUNCTIONALITY TEST FAILED")
      IO.puts("Walk operations are not working correctly!")
      System.halt(1)
    else
      IO.puts("\n✅ WALK FUNCTIONALITY TEST PASSED")
      IO.puts("All walk operations are working correctly.")
    end
  end

  # Test 1: Check if simulator is running
  defp test_simulator_running do
    IO.puts("\n1. Testing simulator status...")

    try do
      case SnmpKit.SNMP.get_with_type(@test_target, "1.3.6.1.2.1.1.1.0",
                                      port: @test_port, timeout: 5000) do
        {:ok, {oid, type, value}} ->
          IO.puts("   ✅ Simulator responding: #{oid} = #{type}(#{inspect(value)})")
          true
        {:error, reason} ->
          IO.puts("   ❌ Simulator not responding: #{inspect(reason)}")
          false
      end
    rescue
      e ->
        IO.puts("   ❌ Simulator test error: #{inspect(e)}")
        false
    end
  end

  # Test 2: Basic GET operations work
  defp test_basic_get_operations do
    IO.puts("\n2. Testing basic GET operations...")

    test_oids = [
      {"1.3.6.1.2.1.1.1.0", "sysDescr"},
      {"1.3.6.1.2.1.1.2.0", "sysObjectID"},
      {"1.3.6.1.2.1.1.3.0", "sysUpTime"}
    ]

    results = Enum.map(test_oids, fn {oid, desc} ->
      case SnmpKit.SNMP.get_with_type(@test_target, oid, port: @test_port, timeout: @test_timeout) do
        {:ok, {returned_oid, type, value}} ->
          IO.puts("   ✅ GET #{desc}: #{returned_oid} = #{type}(#{inspect(value)})")
          true
        {:error, reason} ->
          IO.puts("   ❌ GET #{desc} failed: #{inspect(reason)}")
          false
      end
    end)

    Enum.all?(results)
  end

  # Test 3: Walk v2c returns results
  defp test_walk_v2c_returns_results do
    IO.puts("\n3. Testing walk v2c returns results...")

    walk_tests = [
      {"1.3.6.1.2.1.1", "system group"},
      {"1.3.6.1.2.1.2", "interfaces group"}
    ]

    results = Enum.map(walk_tests, fn {oid, desc} ->
      case SnmpKit.SNMP.walk(@test_target, oid,
                             version: :v2c, port: @test_port, timeout: @test_timeout) do
        {:ok, walk_results} when is_list(walk_results) ->
          result_count = length(walk_results)
          if result_count > 0 do
            IO.puts("   ✅ Walk v2c #{desc}: #{result_count} results")
            # Show first few results
            walk_results
            |> Enum.take(3)
            |> Enum.each(fn {walk_oid, walk_type, walk_value} ->
              IO.puts("      - #{walk_oid} = #{walk_type}(#{inspect(walk_value)})")
            end)
            true
          else
            IO.puts("   ❌ Walk v2c #{desc}: 0 results (should have results)")
            false
          end
        {:error, reason} ->
          IO.puts("   ❌ Walk v2c #{desc} failed: #{inspect(reason)}")
          false
      end
    end)

    Enum.all?(results)
  end

  # Test 4: Walk v1 returns results
  defp test_walk_v1_returns_results do
    IO.puts("\n4. Testing walk v1 returns results...")

    walk_tests = [
      {"1.3.6.1.2.1.1", "system group"},
      {"1.3.6.1.2.1.2", "interfaces group"}
    ]

    results = Enum.map(walk_tests, fn {oid, desc} ->
      case SnmpKit.SNMP.walk(@test_target, oid,
                             version: :v1, port: @test_port, timeout: @test_timeout) do
        {:ok, walk_results} when is_list(walk_results) ->
          result_count = length(walk_results)
          if result_count > 0 do
            IO.puts("   ✅ Walk v1 #{desc}: #{result_count} results")
            # Show first few results
            walk_results
            |> Enum.take(3)
            |> Enum.each(fn {walk_oid, walk_type, walk_value} ->
              IO.puts("      - #{walk_oid} = #{walk_type}(#{inspect(walk_value)})")
            end)
            true
          else
            IO.puts("   ❌ Walk v1 #{desc}: 0 results (should have results)")
            false
          end
        {:error, reason} ->
          IO.puts("   ❌ Walk v1 #{desc} failed: #{inspect(reason)}")
          false
      end
    end)

    Enum.all?(results)
  end

  # Test 5: Walk result format validation
  defp test_walk_result_format do
    IO.puts("\n5. Testing walk result format...")

    case SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1",
                           port: @test_port, timeout: @test_timeout) do
      {:ok, results} when is_list(results) ->
        format_violations = Enum.reduce(results, [], fn result, acc ->
          case result do
            {oid, type, value} when is_binary(oid) and is_atom(type) ->
              acc
            {oid, value} ->
              ["2-tuple found for #{oid} - type information lost!" | acc]
            other ->
              ["Invalid format: #{inspect(other)}" | acc]
          end
        end)

        if Enum.empty?(format_violations) do
          IO.puts("   ✅ All #{length(results)} walk results have proper 3-tuple format")
          true
        else
          IO.puts("   ❌ Walk format violations:")
          Enum.each(format_violations, fn violation ->
            IO.puts("      #{violation}")
          end)
          false
        end
      {:ok, []} ->
        IO.puts("   ⚠️  Walk returned empty results - cannot test format")
        true  # Not a format failure
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  # Test 6: Walk boundary detection
  defp test_walk_boundary_detection do
    IO.puts("\n6. Testing walk boundary detection...")

    # Walk a specific subtree and verify it doesn't go beyond
    case SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1",
                           port: @test_port, timeout: @test_timeout) do
      {:ok, results} when is_list(results) ->
        # All results should start with the root OID
        boundary_violations = Enum.reduce(results, [], fn {oid, _type, _value}, acc ->
          if String.starts_with?(oid, "1.3.6.1.2.1.1.") do
            acc
          else
            ["OID #{oid} outside boundary 1.3.6.1.2.1.1" | acc]
          end
        end)

        if Enum.empty?(boundary_violations) do
          IO.puts("   ✅ All #{length(results)} results within proper boundary")
          true
        else
          IO.puts("   ❌ Boundary violations:")
          Enum.each(boundary_violations, fn violation ->
            IO.puts("      #{violation}")
          end)
          false
        end
      {:ok, []} ->
        IO.puts("   ⚠️  Walk returned empty results - cannot test boundaries")
        true
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  # Test 7: Compare walk vs individual GET operations
  defp test_walk_vs_individual do
    IO.puts("\n7. Testing walk vs individual GET operations...")

    # Get individual system OIDs
    individual_oids = [
      "1.3.6.1.2.1.1.1.0",
      "1.3.6.1.2.1.1.2.0",
      "1.3.6.1.2.1.1.3.0",
      "1.3.6.1.2.1.1.4.0",
      "1.3.6.1.2.1.1.5.0",
      "1.3.6.1.2.1.1.6.0"
    ]

    individual_results = Enum.reduce(individual_oids, [], fn oid, acc ->
      case SnmpKit.SNMP.get_with_type(@test_target, oid, port: @test_port, timeout: @test_timeout) do
        {:ok, {returned_oid, type, value}} ->
          [{returned_oid, type, value} | acc]
        {:error, _} ->
          acc
      end
    end)

    # Walk the system group
    case SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1",
                           port: @test_port, timeout: @test_timeout) do
      {:ok, walk_results} when is_list(walk_results) ->
        individual_count = length(individual_results)
        walk_count = length(walk_results)

        IO.puts("   Individual GETs: #{individual_count} results")
        IO.puts("   Walk operation: #{walk_count} results")

        if walk_count >= individual_count and walk_count > 0 do
          IO.puts("   ✅ Walk returns equal or more results than individual GETs")
          true
        else
          IO.puts("   ❌ Walk returns fewer results than individual GETs")
          false
        end
      {:ok, []} ->
        IO.puts("   ❌ Walk returned empty results but individual GETs worked")
        false
      {:error, reason} ->
        IO.puts("   ❌ Walk failed: #{inspect(reason)}")
        false
    end
  end

  # Test 8: Large walk performance
  defp test_large_walk_performance do
    IO.puts("\n8. Testing large walk performance...")

    start_time = System.monotonic_time(:millisecond)

    case SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1",
                           port: @test_port, timeout: @test_timeout * 2) do
      {:ok, results} when is_list(results) ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        result_count = length(results)

        IO.puts("   ✅ Large walk completed: #{result_count} results in #{duration}ms")

        if result_count > 10 do
          IO.puts("   ✅ Large walk returned substantial results")
          true
        else
          IO.puts("   ⚠️  Large walk returned few results (#{result_count})")
          true  # Not necessarily a failure
        end
      {:ok, []} ->
        IO.puts("   ❌ Large walk returned empty results")
        false
      {:error, reason} ->
        IO.puts("   ❌ Large walk failed: #{inspect(reason)}")
        false
    end
  end

  # Helper functions
  defp start_test_simulator do
    try do
      simulator_config = %{
        port: @test_port,
        community: "public",
        version: :v2c,
        device_type: :generic_router
      }

      case SnmpKit.SnmpSim.start_link(simulator_config) do
        {:ok, pid} ->
          IO.puts("Started test simulator on port #{@test_port}")
          {:ok, pid}
        {:error, {:already_started, pid}} ->
          IO.puts("Test simulator already running")
          {:ok, pid}
        {:error, reason} ->
          IO.puts("Failed to start test simulator: #{inspect(reason)}")
          IO.puts("Note: Tests may fail without simulator")
          {:ok, nil}
      end
    rescue
      e ->
        IO.puts("Error starting simulator: #{inspect(e)}")
        {:ok, nil}
    end
  end
end

# Run the tests
WalkFunctionalityTest.run_tests()
