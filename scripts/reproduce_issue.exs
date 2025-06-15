#!/usr/bin/env elixir

# Minimal reproduction script for :ehostunreach issue
# This script attempts to reproduce the exact same conditions as the failing iex session

defmodule ReproduceIssue do
  require Logger

  @target "192.168.88.234"
  @target_port 161

  def run do
    IO.puts("=== Reproducing :ehostunreach Issue ===")
    IO.puts("Target: #{@target}:#{@target_port}")
    IO.puts("Simulating fresh iex session conditions...")
    IO.puts("")

    # Enable debug logging like in iex
    Logger.configure(level: :debug)

    # Test sequence that matches your failing scenario
    tests = [
      {"Direct Socket Test", &test_direct_socket/0},
      {"Transport Layer Test", &test_transport_layer/0},
      {"Manager Layer Test", &test_manager_layer/0},
      {"Full SNMP Test", &test_full_snmp/0},
      {"Bulk Walk Test", &test_bulk_walk/0}
    ]

    IO.puts("Running test sequence...")

    Enum.each(tests, fn {name, test_fn} ->
      IO.puts("\n--- #{name} ---")

      try do
        case test_fn.() do
          :ok ->
            IO.puts("✓ SUCCESS")
          {:ok, result} ->
            IO.puts("✓ SUCCESS: #{result}")
          {:error, reason} ->
            IO.puts("✗ FAILED: #{inspect(reason)}")

            # If this is the ehostunreach error, do detailed analysis
            if reason in [:ehostunreach, {:network_error, :ehostunreach}] do
              analyze_ehostunreach_error()
            end
        end
      rescue
        e ->
          IO.puts("✗ EXCEPTION: #{inspect(e)}")
      end

      # Small delay between tests
      Process.sleep(100)
    end)

    IO.puts("\n=== Analysis Complete ===")
  end

  defp test_direct_socket do
    IO.puts("Creating raw UDP socket and attempting send...")

    case :gen_udp.open(0, [:binary, :inet, {:active, false}]) do
      {:ok, socket} ->
        IO.puts("Socket created successfully")

        # Get socket info
        case :inet.sockname(socket) do
          {:ok, {local_ip, local_port}} ->
            IO.puts("Bound to #{:inet.ntoa(local_ip)}:#{local_port}")
        end

        # Try to send test packet
        test_data = "test_packet"
        result = :gen_udp.send(socket, String.to_charlist(@target), @target_port, test_data)

        :gen_udp.close(socket)

        case result do
          :ok -> {:ok, "Raw socket send successful"}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:socket_creation_failed, reason}}
    end
  end

  defp test_transport_layer do
    IO.puts("Testing SnmpKit.SnmpLib.Transport layer...")

    case SnmpKit.SnmpLib.Transport.create_client_socket() do
      {:ok, socket} ->
        IO.puts("Transport socket created")

        test_data = "transport_test"
        result = SnmpKit.SnmpLib.Transport.send_packet(socket, @target, @target_port, test_data)

        SnmpKit.SnmpLib.Transport.close_socket(socket)

        case result do
          :ok -> {:ok, "Transport layer send successful"}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:transport_socket_failed, reason}}
    end
  end

  defp test_manager_layer do
    IO.puts("Testing SnmpKit.SnmpLib.Manager layer...")

    # Try a simple GET request
    case SnmpKit.SnmpLib.Manager.get(@target, [1, 3, 6, 1, 2, 1, 1, 1, 0],
         community: "public", version: :v1, timeout: 5000) do
      {:ok, result} ->
        {:ok, "Manager GET successful: #{inspect(result)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_full_snmp do
    IO.puts("Testing full SNMP GET via SnmpKit.SnmpMgr...")

    case SnmpKit.SnmpMgr.get(@target, [1, 3, 6, 1, 2, 1, 1, 1, 0]) do
      {:ok, result} ->
        {:ok, "Full SNMP GET successful: #{inspect(result)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_bulk_walk do
    IO.puts("Testing bulk walk - the failing operation...")

    case SnmpKit.SnmpMgr.bulk_walk(@target, [1, 3, 6]) do
      {:ok, results} ->
        {:ok, "Bulk walk successful: #{length(results)} results"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp analyze_ehostunreach_error do
    IO.puts("\n🔍 ANALYZING :ehostunreach ERROR...")

    # Check network state at the moment of failure
    IO.puts("Network state at time of failure:")

    # Check interfaces
    case :inet.getif() do
      {:ok, interfaces} ->
        IO.puts("Active interfaces:")
        Enum.each(interfaces, fn {ip, _bcast, netmask} ->
          IO.puts("  #{:inet.ntoa(ip)}/#{:inet.ntoa(netmask)}")
        end)
      {:error, reason} ->
        IO.puts("Cannot get interfaces: #{inspect(reason)}")
    end

    # Check if target is reachable via ping at this exact moment
    IO.puts("Testing ping at moment of failure...")
    case System.cmd("ping", ["-c", "1", "-W", "1000", @target]) do
      {_output, 0} ->
        IO.puts("✓ Ping still works - routing is available")
      {error, _} ->
        IO.puts("✗ Ping failed: #{String.trim(error)}")
    end

    # Check ARP table
    case System.cmd("arp", ["-n", @target]) do
      {output, 0} ->
        IO.puts("ARP entry: #{String.trim(output)}")
      {error, _} ->
        IO.puts("ARP lookup failed: #{String.trim(error)}")
    end

    # Check if it's a timing issue by retrying immediately
    IO.puts("Retrying socket operation immediately...")
    case :gen_udp.open(0, [:binary, :inet, {:active, false}]) do
      {:ok, socket} ->
        case :gen_udp.send(socket, String.to_charlist(@target), @target_port, "retry") do
          :ok ->
            IO.puts("✓ Retry successful - may be timing/state related")
          {:error, reason} ->
            IO.puts("✗ Retry failed with same error: #{inspect(reason)}")
        end
        :gen_udp.close(socket)
      {:error, reason} ->
        IO.puts("✗ Socket creation failed on retry: #{inspect(reason)}")
    end

    # Check socket table state
    IO.puts("Checking system socket state...")
    case System.cmd("netstat", ["-an"]) do
      {output, 0} ->
        udp_sockets = output
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "udp"))
        |> length()
        IO.puts("Active UDP sockets: #{udp_sockets}")
      {_error, _} ->
        IO.puts("Cannot check socket state")
    end

    IO.puts("\n💡 POSSIBLE CAUSES:")
    IO.puts("1. Socket table full or corrupted")
    IO.puts("2. Network interface state change")
    IO.puts("3. Kernel routing cache issue")
    IO.puts("4. Process socket limit reached")
    IO.puts("5. Network interface flapping")
    IO.puts("6. VPN or network configuration change")

    IO.puts("\n🔧 SUGGESTED FIXES:")
    IO.puts("1. Restart network interface: sudo ifconfig en0 down && sudo ifconfig en0 up")
    IO.puts("2. Flush routing cache: sudo route flush")
    IO.puts("3. Flush ARP cache: sudo arp -a -d")
    IO.puts("4. Check system limits: ulimit -n")
    IO.puts("5. Restart network services: sudo networksetup -setnetworkserviceenabled Wi-Fi off && sudo networksetup -setnetworkserviceenabled Wi-Fi on")
  end
end

# Run the reproduction test
ReproduceIssue.run()
