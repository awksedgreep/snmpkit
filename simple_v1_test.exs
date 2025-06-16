#!/usr/bin/env elixir

# Simple test to isolate the v1 walk issue
# This will help identify exactly where the v1 walk logic breaks

Mix.install([
  {:snmpkit, path: "."}
])

defmodule SimpleV1Test do
  def run do
    IO.puts("=== Simple v1 Walk Test ===\n")

    # Create minimal test device
    oid_map = %{
      "1.3.6.1.2.1.1.1.0" => "Device A",
      "1.3.6.1.2.1.1.2.0" => "Device B"
    }

    case SnmpKit.SnmpSim.ProfileLoader.load_profile(:test, {:manual, oid_map}) do
      {:ok, profile} ->
        case SnmpKit.Sim.start_device(profile, port: 9995) do
          {:ok, _device} ->
            IO.puts("✅ Device started")
            test_operations()

          {:error, reason} ->
            IO.puts("❌ Device failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Profile failed: #{inspect(reason)}")
    end
  end

  defp test_operations do
    target = "127.0.0.1:9995"

    IO.puts("\n1. Testing individual GET_NEXT:")
    case SnmpKit.SNMP.get_next(target, "1.3.6.1.2.1.1", version: :v1) do
      {:ok, {oid, value}} ->
        IO.puts("   ✅ v1 GET_NEXT: #{inspect(oid)} = #{inspect(value)}")
      {:error, reason} ->
        IO.puts("   ❌ v1 GET_NEXT failed: #{inspect(reason)}")
    end

    IO.puts("\n2. Testing v1 walk:")
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v1) do
      {:ok, results} ->
        IO.puts("   ✅ v1 WALK: #{length(results)} results")
        Enum.each(results, fn result ->
          IO.puts("      #{inspect(result)}")
        end)
      {:error, reason} ->
        IO.puts("   ❌ v1 WALK failed: #{inspect(reason)}")
    end

    IO.puts("\n3. Testing v2c walk (for comparison):")
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c) do
      {:ok, results} ->
        IO.puts("   ✅ v2c WALK: #{length(results)} results")
        Enum.each(results, fn result ->
          IO.puts("      #{inspect(result)}")
        end)
      {:error, reason} ->
        IO.puts("   ❌ v2c WALK failed: #{inspect(reason)}")
    end

    IO.puts("\n4. Testing default walk:")
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1") do
      {:ok, results} ->
        IO.puts("   ✅ DEFAULT WALK: #{length(results)} results")
      {:error, reason} ->
        IO.puts("   ❌ DEFAULT WALK failed: #{inspect(reason)}")
    end

    IO.puts("\n=== Results Analysis ===")
    IO.puts("Expected: Individual GET_NEXT works, v1 walk should work too")
    IO.puts("If GET_NEXT works but walk doesn't, issue is in walk_from_oid function")
  end
end

SimpleV1Test.run()
