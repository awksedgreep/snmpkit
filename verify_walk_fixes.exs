#!/usr/bin/env elixir

# Quick verification that walk fixes are working correctly
# This test verifies that our type preservation fixes haven't broken basic walk functionality

Mix.install([
  {:snmpkit, path: "."}
])

defmodule WalkFixVerification do
  require Logger

  @test_timeout 15_000
  @test_target "127.0.0.1"
  @test_port 1161

  def verify_fixes do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("WALK FUNCTIONALITY VERIFICATION")
    IO.puts("Checking that type preservation fixes work correctly")
    IO.puts(String.duplicate("=", 60))

    # Start simulator for testing
    case start_test_simulator() do
      {:ok, _pid} ->
        Process.sleep(2000)  # Give simulator time to start
        run_verification_tests()
      {:error, reason} ->
        IO.puts("⚠️  Could not start simulator: #{inspect(reason)}")
        IO.puts("Running basic module verification instead...")
        run_module_verification()
    end
  end

  defp run_verification_tests do
    tests = [
      {"Core Module Returns 3-Tuples", &test_core_returns_3_tuples/0},
      {"Walk Module Exists and Works", &test_walk_module_works/0},
      {"Walk Returns Non-Zero Results", &test_walk_returns_results/0},
      {"Walk Preserves Type Information", &test_walk_preserves_types/0},
      {"Walk Handles Different Versions", &test_walk_handles_versions/0}
    ]

    results = Enum.map(tests, fn {name, test_func} ->
      IO.puts("\nTesting: #{name}")
      try do
        case test_func.() do
          :ok ->
            IO.puts("✅ PASS - #{name}")
            true
          {:error, reason} ->
            IO.puts("❌ FAIL - #{name}: #{reason}")
            false
        end
      rescue
        e ->
          IO.puts("❌ ERROR - #{name}: #{inspect(e)}")
          false
      end
    end)

    passed = Enum.count(results, & &1)
    failed = length(results) - passed

    IO.puts("\n" <> String.duplicate("-", 60))
    IO.puts("VERIFICATION RESULTS: #{passed} passed, #{failed} failed")

    if failed == 0 do
      IO.puts("✅ ALL VERIFICATIONS PASSED - Walk fixes are working correctly!")
    else
      IO.puts("❌ SOME VERIFICATIONS FAILED - There may be issues with walk fixes")
    end

    failed == 0
  end

  defp run_module_verification do
    IO.puts("\nRunning basic module verification (no simulator)...")

    checks = [
      {"Walk module compiles", fn -> Code.ensure_compiled(SnmpKit.SnmpMgr.Walk) end},
      {"Core module compiles", fn -> Code.ensure_compiled(SnmpKit.SnmpMgr.Core) end},
      {"Bulk module compiles", fn -> Code.ensure_compiled(SnmpKit.SnmpMgr.Bulk) end},
      {"No type inference in Walk", fn -> not function_exported?(SnmpKit.SnmpMgr.Walk, :infer_snmp_type, 1) end},
      {"No type inference in Core", fn -> not function_exported?(SnmpKit.SnmpMgr.Core, :infer_snmp_type, 1) end},
      {"No type inference in Bulk", fn -> not function_exported?(SnmpKit.SnmpMgr.Bulk, :infer_snmp_type, 1) end}
    ]

    results = Enum.map(checks, fn {name, check_func} ->
      try do
        result = check_func.()
        if result do
          IO.puts("✅ #{name}")
          true
        else
          IO.puts("❌ #{name}")
          false
        end
      rescue
        e ->
          IO.puts("❌ #{name} - Error: #{inspect(e)}")
          false
      end
    end)

    passed = Enum.count(results, & &1)
    failed = length(results) - passed

    IO.puts("\nModule verification: #{passed} passed, #{failed} failed")
    failed == 0
  end

  # Test that Core module returns proper 3-tuples
  defp test_core_returns_3_tuples do
    case SnmpKit.SnmpMgr.Core.send_get_request_with_type(@test_target, "1.3.6.1.2.1.1.1.0",
                                                          port: @test_port, timeout: @test_timeout) do
      {:ok, {oid, type, value}} when is_binary(oid) and is_atom(type) ->
        IO.puts("   Core returned: {#{oid}, #{type}, #{inspect(value)}}")
        :ok
      {:ok, other} ->
        {:error, "Core returned unexpected format: #{inspect(other)}"}
      {:error, reason} ->
        {:error, "Core request failed: #{inspect(reason)}"}
    end
  end

  # Test that Walk module exists and has required functions
  defp test_walk_module_works do
    if function_exported?(SnmpKit.SnmpMgr.Walk, :walk, 3) do
      if function_exported?(SnmpKit.SnmpMgr.Walk, :walk_table, 3) do
        :ok
      else
        {:error, "walk_table/3 function not exported"}
      end
    else
      {:error, "walk/3 function not exported"}
    end
  end

  # Test that walk returns non-zero results
  defp test_walk_returns_results do
    case SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1",
                           port: @test_port, timeout: @test_timeout) do
      {:ok, results} when is_list(results) and length(results) > 0 ->
        IO.puts("   Walk returned #{length(results)} results")
        :ok
      {:ok, []} ->
        {:error, "Walk returned zero results - THIS IS THE MAIN BUG!"}
      {:ok, other} ->
        {:error, "Walk returned unexpected format: #{inspect(other)}"}
      {:error, reason} ->
        {:error, "Walk failed: #{inspect(reason)}"}
    end
  end

  # Test that walk preserves type information
  defp test_walk_preserves_types do
    case SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1",
                           port: @test_port, timeout: @test_timeout) do
      {:ok, results} when is_list(results) ->
        # Check every result for proper 3-tuple format
        case check_all_3_tuples(results) do
          :ok ->
            IO.puts("   All #{length(results)} results have proper type information")
            :ok
          {:error, violations} ->
            {:error, "Type preservation violations: #{inspect(violations)}"}
        end
      {:ok, other} ->
        {:error, "Walk returned unexpected format: #{inspect(other)}"}
      {:error, reason} ->
        {:error, "Walk failed: #{inspect(reason)}"}
    end
  end

  # Test that walk handles different SNMP versions
  defp test_walk_handles_versions do
    # Test v1
    v1_result = SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1",
                                  version: :v1, port: @test_port, timeout: @test_timeout)

    # Test v2c
    v2c_result = SnmpKit.SNMP.walk(@test_target, "1.3.6.1.2.1.1",
                                   version: :v2c, port: @test_port, timeout: @test_timeout)

    case {v1_result, v2c_result} do
      {{:ok, v1_results}, {:ok, v2c_results}} when length(v1_results) > 0 and length(v2c_results) > 0 ->
        IO.puts("   v1 returned #{length(v1_results)} results")
        IO.puts("   v2c returned #{length(v2c_results)} results")
        :ok
      {{:ok, []}, _} ->
        {:error, "v1 walk returned zero results"}
      {_, {:ok, []}} ->
        {:error, "v2c walk returned zero results"}
      {{:error, v1_error}, _} ->
        {:error, "v1 walk failed: #{inspect(v1_error)}"}
      {_, {:error, v2c_error}} ->
        {:error, "v2c walk failed: #{inspect(v2c_error)}"}
    end
  end

  # Helper function to check all results are 3-tuples
  defp check_all_3_tuples(results) do
    violations = Enum.reduce(results, [], fn result, acc ->
      case result do
        {oid, type, _value} when is_binary(oid) and is_atom(type) ->
          acc
        {oid, _value} ->
          ["2-tuple found for #{oid}" | acc]
        other ->
          ["Invalid format: #{inspect(other)}" | acc]
      end
    end)

    if Enum.empty?(violations) do
      :ok
    else
      {:error, violations}
    end
  end

  # Helper function to start test simulator
  defp start_test_simulator do
    try do
      simulator_config = %{
        port: @test_port,
        community: "public",
        version: :v2c
      }

      case SnmpKit.SnmpSim.start_link(simulator_config) do
        {:ok, pid} ->
          IO.puts("Started test simulator on port #{@test_port}")
          {:ok, pid}
        {:error, {:already_started, pid}} ->
          IO.puts("Test simulator already running")
          {:ok, pid}
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end
end

# Run the verification
WalkFixVerification.verify_fixes()
