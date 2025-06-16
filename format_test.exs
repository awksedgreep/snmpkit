#!/usr/bin/env elixir

# Simple test to see ACTUAL response formats from SNMP operations
# This will help us understand what we're getting vs what we expect

Mix.install([
  {:snmpkit, path: "."}
])

defmodule FormatTest do
  require Logger

  def run do
    IO.puts("=== SNMP Response Format Test ===\n")

    # Simple test data
    oid_map = %{
      "1.3.6.1.2.1.1.1.0" => "Test Device",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.999",
      "1.3.6.1.2.1.1.3.0" => 12345
    }

    IO.puts("Creating test device...")
    case SnmpKit.SnmpSim.ProfileLoader.load_profile(:test, {:manual, oid_map}) do
      {:ok, profile} ->
        case SnmpKit.Sim.start_device(profile, port: 7777) do
          {:ok, _device} ->
            IO.puts("✅ Device started\n")
            test_actual_formats("127.0.0.1:7777")
          {:error, reason} ->
            IO.puts("❌ Device failed: #{inspect(reason)}")
        end
      {:error, reason} ->
        IO.puts("❌ Profile failed: #{inspect(reason)}")
    end
  end

  defp test_actual_formats(target) do
    IO.puts("Testing ACTUAL response formats...\n")

    # Test 1: Individual GET
    IO.puts("1. GET operation:")
    case SnmpKit.SNMP.get_with_type(target, "1.3.6.1.2.1.1.1.0", timeout: 5000) do
      result ->
        IO.puts("   Raw result: #{inspect(result)}")
        case result do
          {:ok, {oid, type, value}} ->
            IO.puts("   ✅ 3-tuple: OID=#{inspect(oid)}, TYPE=#{inspect(type)}, VALUE=#{inspect(value)}")
          {:ok, {oid, value}} ->
            IO.puts("   ❌ 2-tuple: OID=#{inspect(oid)}, VALUE=#{inspect(value)} (TYPE LOST!)")
          {:ok, other} ->
            IO.puts("   ❓ Other format: #{inspect(other)}")
          {:error, reason} ->
            IO.puts("   ❌ Error: #{inspect(reason)}")
        end
    end

    IO.puts("")

    # Test 2: GET_NEXT
    IO.puts("2. GET_NEXT operation:")
    case SnmpKit.SNMP.get_next(target, "1.3.6.1.2.1.1", timeout: 5000) do
      result ->
        IO.puts("   Raw result: #{inspect(result)}")
        case result do
          {:ok, {oid, type, value}} ->
            IO.puts("   ✅ 3-tuple: OID=#{inspect(oid)}, TYPE=#{inspect(type)}, VALUE=#{inspect(value)}")
          {:ok, {oid, value}} ->
            IO.puts("   ❌ 2-tuple: OID=#{inspect(oid)}, VALUE=#{inspect(value)} (TYPE LOST!)")
          {:ok, other} ->
            IO.puts("   ❓ Other format: #{inspect(other)}")
          {:error, reason} ->
            IO.puts("   ❌ Error: #{inspect(reason)}")
        end
    end

    IO.puts("")

    # Test 3: WALK (default version)
    IO.puts("3. WALK operation (default):")
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", timeout: 5000) do
      {:ok, results} ->
        IO.puts("   Got #{length(results)} results:")
        Enum.with_index(results) |> Enum.each(fn {result, index} ->
          IO.puts("   [#{index}] Raw: #{inspect(result)}")
          case result do
            {oid, type, value} ->
              IO.puts("       ✅ 3-tuple: OID=#{inspect(oid)}, TYPE=#{inspect(type)}, VALUE=#{inspect(value)}")
            {oid, value} ->
              IO.puts("       ❌ 2-tuple: OID=#{inspect(oid)}, VALUE=#{inspect(value)} (TYPE LOST!)")
            other ->
              IO.puts("       ❓ Other: #{inspect(other)}")
          end
        end)
      {:error, reason} ->
        IO.puts("   ❌ Error: #{inspect(reason)}")
    end

    IO.puts("")

    # Test 4: WALK v1 explicitly
    IO.puts("4. WALK operation (v1 explicit):")
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v1, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   Got #{length(results)} results:")
        Enum.with_index(results) |> Enum.each(fn {result, index} ->
          IO.puts("   [#{index}] Raw: #{inspect(result)}")
          case result do
            {oid, type, value} ->
              IO.puts("       ✅ 3-tuple: OID=#{inspect(oid)}, TYPE=#{inspect(type)}, VALUE=#{inspect(value)}")
            {oid, value} ->
              IO.puts("       ❌ 2-tuple: OID=#{inspect(oid)}, VALUE=#{inspect(value)} (TYPE LOST!)")
            other ->
              IO.puts("       ❓ Other: #{inspect(other)}")
          end
        end)
      {:error, reason} ->
        IO.puts("   ❌ Error: #{inspect(reason)}")
    end

    IO.puts("")

    # Test 5: WALK v2c explicitly
    IO.puts("5. WALK operation (v2c explicit):")
    case SnmpKit.SNMP.walk(target, "1.3.6.1.2.1.1", version: :v2c, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   Got #{length(results)} results:")
        Enum.with_index(results) |> Enum.each(fn {result, index} ->
          IO.puts("   [#{index}] Raw: #{inspect(result)}")
          case result do
            {oid, type, value} ->
              IO.puts("       ✅ 3-tuple: OID=#{inspect(oid)}, TYPE=#{inspect(type)}, VALUE=#{inspect(value)}")
            {oid, value} ->
              IO.puts("       ❌ 2-tuple: OID=#{inspect(oid)}, VALUE=#{inspect(value)} (TYPE LOST!)")
            other ->
              IO.puts("       ❓ Other: #{inspect(other)}")
          end
        end)
      {:error, reason} ->
        IO.puts("   ❌ Error: #{inspect(reason)}")
    end

    IO.puts("")

    # Test 6: GET_BULK
    IO.puts("6. GET_BULK operation:")
    case SnmpKit.SNMP.get_bulk(target, "1.3.6.1.2.1.1", version: :v2c, max_repetitions: 5, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   Got #{length(results)} results:")
        Enum.with_index(results) |> Enum.each(fn {result, index} ->
          IO.puts("   [#{index}] Raw: #{inspect(result)}")
          case result do
            {oid, type, value} ->
              IO.puts("       ✅ 3-tuple: OID=#{inspect(oid)}, TYPE=#{inspect(type)}, VALUE=#{inspect(value)}")
            {oid, value} ->
              IO.puts("       ❌ 2-tuple: OID=#{inspect(oid)}, VALUE=#{inspect(value)} (TYPE LOST!)")
            other ->
              IO.puts("       ❓ Other: #{inspect(other)}")
          end
        end)
      {:error, reason} ->
        IO.puts("   ❌ Error: #{inspect(reason)}")
    end

    IO.puts("\n=== FORMAT ANALYSIS ===")
    IO.puts("✅ = Good (3-tuple with type information)")
    IO.puts("❌ = Bad (2-tuple without type information)")
    IO.puts("❓ = Unknown format")
    IO.puts("")
    IO.puts("Type information is CRITICAL for SNMP!")
    IO.puts("Without it, you can't distinguish:")
    IO.puts("- String '123' vs Integer 123 vs TimeTicks 123")
    IO.puts("- Counter32 vs Gauge32 vs Integer")
    IO.puts("- Different string encodings")
  end
end

# Disable debug logging for cleaner output
Logger.configure(level: :warn)

FormatTest.run()
