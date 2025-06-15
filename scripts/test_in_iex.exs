# Test script to run inside iex session to reproduce the :ehostunreach issue
# Usage:
# 1. Start iex: iex -S mix
# 2. Copy and paste this code into iex
# 3. Run: TestInIex.run()

defmodule TestInIex do
  require Logger

  @target "192.168.88.234"

  def run do
    IO.puts("=== Testing SNMP in IEX Session ===")
    IO.puts("Target: #{@target}")

    # Enable debug logging
    Logger.configure(level: :debug)

    IO.puts("\n1. Testing raw socket...")
    test_raw_socket()

    IO.puts("\n2. Testing simple SNMP GET...")
    test_simple_get()

    IO.puts("\n3. Testing bulk walk (the failing operation)...")
    test_bulk_walk()
  end

  def test_raw_socket do
    case :gen_udp.open(0, [:binary, :inet, {:active, false}]) do
      {:ok, socket} ->
        IO.puts("✓ Socket created")

        case :gen_udp.send(socket, '192.168.88.234', 161, "test") do
          :ok ->
            IO.puts("✓ Raw UDP send successful")
          {:error, reason} ->
            IO.puts("✗ Raw UDP send failed: #{inspect(reason)}")
        end

        :gen_udp.close(socket)

      {:error, reason} ->
        IO.puts("✗ Socket creation failed: #{inspect(reason)}")
    end
  end

  def test_simple_get do
    case SnmpKit.SnmpMgr.get(@target, [1,3,6,1,2,1,1,1,0]) do
      {:ok, result} ->
        IO.puts("✓ SNMP GET successful: #{inspect(result)}")
      {:error, reason} ->
        IO.puts("✗ SNMP GET failed: #{inspect(reason)}")
    end
  end

  def test_bulk_walk do
    case SnmpKit.SnmpMgr.bulk_walk(@target, [1,3,6]) do
      {:ok, results} ->
        IO.puts("✓ Bulk walk successful: #{length(results)} results")
      {:error, reason} ->
        IO.puts("✗ Bulk walk failed: #{inspect(reason)}")

        # If it's ehostunreach, do immediate diagnostics
        if reason == {:network_error, :ehostunreach} do
          IO.puts("\n🔍 IMMEDIATE DIAGNOSTICS:")

          # Check if ping still works
          case System.cmd("ping", ["-c", "1", @target]) do
            {_, 0} -> IO.puts("✓ Ping still works")
            {_, _} -> IO.puts("✗ Ping also failing")
          end

          # Check network interfaces
          case :inet.getif() do
            {:ok, interfaces} ->
              IO.puts("Active interfaces: #{length(interfaces)}")
              Enum.each(interfaces, fn {ip, _, _} ->
                IO.puts("  #{:inet.ntoa(ip)}")
              end)
            _ ->
              IO.puts("Cannot get interfaces")
          end

          # Try immediate retry
          IO.puts("Retrying immediately...")
          case :gen_udp.open(0, [:binary, :inet, {:active, false}]) do
            {:ok, socket} ->
              case :gen_udp.send(socket, '192.168.88.234', 161, "retry") do
                :ok -> IO.puts("✓ Immediate retry worked")
                {:error, r} -> IO.puts("✗ Immediate retry failed: #{inspect(r)}")
              end
              :gen_udp.close(socket)
            _ ->
              IO.puts("✗ Socket creation failed on retry")
          end
        end
    end
  end

  def check_network_state do
    IO.puts("\n=== Network State Check ===")

    # Check routing table for target
    case System.cmd("route", ["-n", "get", @target]) do
      {output, 0} ->
        IO.puts("Route to target:")
        IO.puts(String.slice(output, 0, 300))
      {error, _} ->
        IO.puts("Route check failed: #{error}")
    end

    # Check ARP entry
    case System.cmd("arp", ["-n", @target]) do
      {output, 0} ->
        IO.puts("ARP entry: #{String.trim(output)}")
      {error, _} ->
        IO.puts("ARP check failed: #{error}")
    end
  end

  def force_network_refresh do
    IO.puts("\n=== Forcing Network Refresh ===")
    IO.puts("You can try these commands in terminal:")
    IO.puts("sudo route flush")
    IO.puts("sudo arp -a -d")
    IO.puts("sudo dscacheutil -flushcache")
    IO.puts("sudo ifconfig en0 down && sudo ifconfig en0 up")
  end
end

# Instructions for use:
IO.puts("=== IEX Test Module Loaded ===")
IO.puts("Usage:")
IO.puts("  TestInIex.run()                 # Run all tests")
IO.puts("  TestInIex.test_bulk_walk()      # Test just the failing operation")
IO.puts("  TestInIex.check_network_state() # Check network configuration")
IO.puts("  TestInIex.force_network_refresh() # Show network refresh commands")
