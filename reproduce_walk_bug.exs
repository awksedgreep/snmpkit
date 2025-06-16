#!/usr/bin/env elixir

# Script to reproduce the SNMP walk bug described in SNMP_WALK_CLIENT_BUG.md
#
# This script demonstrates that:
# 1. Device-level walk operations work correctly
# 2. Client-side SNMP.walk operations fail (return 0 results)
# 3. Individual SNMP operations work correctly

Mix.install([
  {:snmpkit, path: "."}
])

defmodule WalkBugReproduction do
  require Logger

  def run do
    IO.puts("=== SNMP Walk Bug Reproduction ===\n")

    # Create a test device with manual OID map
    oid_map = %{
      "1.3.6.1.2.1.1.1.0" => "ARRIS SURFboard SB8200 DOCSIS 3.1 Cable Modem",
      "1.3.6.1.2.1.1.2.0" => "1.3.6.1.4.1.4115.1.20.1.1.2.2",
      "1.3.6.1.2.1.1.3.0" => 123456,
      "1.3.6.1.2.1.1.4.0" => "admin@example.com",
      "1.3.6.1.2.1.2.1.0" => 2,
      "1.3.6.1.2.1.2.2.1.1.1" => 1,
      "1.3.6.1.2.1.2.2.1.1.2" => 2,
      "1.3.6.1.2.1.2.2.1.2.1" => "eth0",
      "1.3.6.1.2.1.2.2.1.2.2" => "eth1"
    }

    IO.puts("1. Creating test device with #{map_size(oid_map)} OIDs...")

    # Load profile and start device
    case SnmpKit.SnmpSim.ProfileLoader.load_profile(:test, {:manual, oid_map}) do
      {:ok, profile} ->
        IO.puts("   ✅ Profile loaded successfully")

        case SnmpKit.Sim.start_device(profile, port: 9999) do
          {:ok, device} ->
            IO.puts("   ✅ Device started on port 9999")
            run_tests(device)

          {:error, reason} ->
            IO.puts("   ❌ Failed to start device: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("   ❌ Failed to load profile: #{inspect(reason)}")
    end
  end

  defp run_tests(device) do
    target = "127.0.0.1:9999"

    IO.puts("\n2. Testing device-level operations (these should work):")

    # Test device-level walk operations
    test_device_walk(device, "1.3.6.1.2.1.1", "system group")
    test_device_walk(device, "1.3.6.1.2.1.2", "interfaces group")
    test_device_walk(device, "1.3.6.1.2.1", "mib-2 group")

    IO.puts("\n3. Testing individual SNMP operations (these should work):")

    # Test individual SNMP operations
    test_individual_snmp_get(target, "1.3.6.1.2.1.1.1.0")
    test_individual_snmp_get_next(target, "1.3.6.1.2.1.1")
    test_individual_snmp_get_bulk(target, "1.3.6.1.2.1.1")

    IO.puts("\n4. Testing client-side SNMP.walk operations (THE BUG - these should fail):")

    # Test client-side walk operations (the broken ones)
    test_client_walk(target, "1.3.6.1.2.1.1", "system group (default)")
    test_client_walk(target, "1.3.6.1.2.1.1", "system group", version: :v1)
    test_client_walk(target, "1.3.6.1.2.1.1", "system group", version: :v2c)
    test_client_walk(target, "1.3.6.1.2.1.2", "interfaces group", version: :v2c)

    IO.puts("\n5. Testing with different walk options:")

    # Test with various options
    test_client_walk_with_options(target, "1.3.6.1.2.1.1")

    IO.puts("\n=== Summary ===")
    IO.puts("Expected behavior:")
    IO.puts("- Device-level operations: ✅ Working (return multiple results)")
    IO.puts("- Individual SNMP operations: ✅ Working")
    IO.puts("- Client SNMP.walk operations: ❌ Broken (return 0 results)")
    IO.puts("\nThis demonstrates the bug described in SNMP_WALK_CLIENT_BUG.md")
  end

  defp test_device_walk(device, oid, description) do
    case GenServer.call(device, {:walk_oid, oid}, 10_000) do
      {:ok, results} ->
        IO.puts("   ✅ Device walk(#{description}): #{length(results)} results")
        if length(results) > 0 do
          IO.puts("      First result: #{inspect(hd(results))}")
        end

      {:error, reason} ->
        IO.puts("   ❌ Device walk(#{description}): #{inspect(reason)}")
    end
  end

  defp test_individual_snmp_get(target, oid) do
    case SnmpKit.SNMP.get(target, oid, version: :v2c, timeout: 5000) do
      {:ok, value} ->
        IO.puts("   ✅ SNMP.get(#{oid}): #{inspect(value)}")

      {:error, reason} ->
        IO.puts("   ❌ SNMP.get(#{oid}): #{inspect(reason)}")
    end
  end

  defp test_individual_snmp_get_next(target, oid) do
    case SnmpKit.SNMP.get_next(target, oid, version: :v2c, timeout: 5000) do
      {:ok, {next_oid, value}} ->
        IO.puts("   ✅ SNMP.get_next(#{oid}): #{next_oid} = #{inspect(value)}")

      {:error, reason} ->
        IO.puts("   ❌ SNMP.get_next(#{oid}): #{inspect(reason)}")
    end
  end

  defp test_individual_snmp_get_bulk(target, oid) do
    case SnmpKit.SNMP.get_bulk(target, oid, version: :v2c, max_repetitions: 10, timeout: 5000) do
      {:ok, results} ->
        IO.puts("   ✅ SNMP.get_bulk(#{oid}): #{length(results)} results")
        if length(results) > 0 do
          IO.puts("      First result: #{inspect(hd(results))}")
        end

      {:error, reason} ->
        IO.puts("   ❌ SNMP.get_bulk(#{oid}): #{inspect(reason)}")
    end
  end

  defp test_client_walk(target, oid, description, opts \\ []) do
    opts = Keyword.merge([timeout: 5000], opts)
    version = Keyword.get(opts, :version, :v1)

    case SnmpKit.SNMP.walk(target, oid, opts) do
      {:ok, results} ->
        if length(results) > 0 do
          IO.puts("   ✅ SNMP.walk(#{description}, #{version}): #{length(results)} results")
          IO.puts("      First result: #{inspect(hd(results))}")
        else
          IO.puts("   ❌ SNMP.walk(#{description}, #{version}): 0 results (BUG!)")
        end

      {:error, reason} ->
        IO.puts("   ❌ SNMP.walk(#{description}, #{version}): #{inspect(reason)}")
    end
  end

  defp test_client_walk_with_options(target, oid) do
    options_to_test = [
      [version: :v1, max_repetitions: 10],
      [version: :v1, max_repetitions: 100],
      [version: :v2c, max_repetitions: 10],
      [version: :v2c, max_repetitions: 20],
      [version: :v2c, max_repetitions: 100]
    ]

    Enum.each(options_to_test, fn opts ->
      version = Keyword.get(opts, :version)
      max_rep = Keyword.get(opts, :max_repetitions)
      test_opts = Keyword.merge([timeout: 5000], opts)

      case SnmpKit.SNMP.walk(target, oid, test_opts) do
        {:ok, results} ->
          status = if length(results) > 0, do: "✅", else: "❌"
          IO.puts("   #{status} walk(#{version}, max_rep: #{max_rep}): #{length(results)} results")

        {:error, reason} ->
          IO.puts("   ❌ walk(#{version}, max_rep: #{max_rep}): #{inspect(reason)}")
      end
    end)
  end
end

# Enable debug logging to see SNMP protocol details
Logger.configure(level: :info)

WalkBugReproduction.run()
