#!/usr/bin/env elixir

# Network Routing Diagnostic Script
# This script helps diagnose :ehostunreach errors by checking routing and network configuration

defmodule NetworkRoutingDebugger do
  require Logger
  import Bitwise

  @target "192.168.88.234"
  @target_port 161

  def run do
    IO.puts("\n=== Network Routing Diagnostic Tool ===")
    IO.puts("Target: #{@target}:#{@target_port}")
    IO.puts("Diagnosing :ehostunreach error...")
    IO.puts("=" |> String.duplicate(50))

    # Enable debug logging
    Logger.configure(level: :debug)

    tests = [
      {"Check Network Interfaces", &check_network_interfaces/0},
      {"Check Routing Table", &check_routing_table/0},
      {"Check ARP Table", &check_arp_table/0},
      {"Check DNS Resolution", &check_dns_resolution/0},
      {"Test Raw Ping", &test_raw_ping/0},
      {"Test Route to Target", &test_route_to_target/0},
      {"Check Default Gateway", &check_default_gateway/0},
      {"Check Firewall Status", &check_firewall_status/0},
      {"Test Socket Binding Options", &test_socket_binding/0},
      {"Test Different Socket Options", &test_socket_variations/0},
      {"Compare Working vs Broken State", &compare_network_state/0}
    ]

    results = Enum.map(tests, fn {name, test_fn} ->
      IO.puts("\n--- #{name} ---")

      try do
        case test_fn.() do
          :ok ->
            IO.puts("✓ PASS")
            {name, :pass}
          {:ok, result} ->
            IO.puts("✓ PASS: #{result}")
            {name, :pass}
          {:error, reason} ->
            IO.puts("✗ FAIL: #{reason}")
            {name, {:fail, reason}}
          {:warning, message} ->
            IO.puts("⚠ WARNING: #{message}")
            {name, {:warning, message}}
        end
      rescue
        e ->
          IO.puts("✗ ERROR: #{inspect(e)}")
          {name, {:error, e}}
      end
    end)

    print_diagnosis(results)
  end

  defp check_network_interfaces do
    case :inet.getif() do
      {:ok, interfaces} ->
        IO.puts("Active network interfaces:")

        Enum.each(interfaces, fn {ip, _broadcast, netmask} ->
          ip_str = :inet.ntoa(ip)
          mask_str = :inet.ntoa(netmask)
          IO.puts("  #{ip_str}/#{mask_str}")

          # Check if target is in same subnet
          if same_subnet?(ip, netmask, @target) do
            IO.puts("    ⚠ Target #{@target} is in same subnet - should be directly reachable")
          end
        end)

        :ok

      {:error, reason} ->
        {:error, "Failed to get interfaces: #{inspect(reason)}"}
    end
  end

  defp check_routing_table do
    case System.cmd("netstat", ["-rn"]) do
      {output, 0} ->
        IO.puts("Routing table:")
        IO.puts(String.slice(output, 0, 1000))  # Limit output

        # Check for default route
        if String.contains?(output, "default") or String.contains?(output, "0.0.0.0") do
          IO.puts("✓ Default route found")
        else
          IO.puts("⚠ No default route found")
        end

        :ok

      {error, _} ->
        {:error, "Failed to get routing table: #{String.trim(error)}"}
    end
  end

  defp check_arp_table do
    case System.cmd("arp", ["-a"]) do
      {output, 0} ->
        IO.puts("ARP table entries:")

        lines = String.split(output, "\n")
        target_entries = Enum.filter(lines, fn line ->
          String.contains?(line, @target)
        end)

        if Enum.empty?(target_entries) do
          IO.puts("  No ARP entry for #{@target}")
        else
          Enum.each(target_entries, fn entry ->
            IO.puts("  #{String.trim(entry)}")
          end)
        end

        :ok

      {error, _} ->
        {:warning, "ARP check failed: #{String.trim(error)}"}
    end
  end

  defp check_dns_resolution do
    case :inet.gethostbyname(String.to_charlist(@target)) do
      {:ok, {:hostent, _name, _aliases, :inet, 4, [ip | _]}} ->
        resolved_ip = :inet.ntoa(ip)
        IO.puts("DNS resolution: #{@target} -> #{resolved_ip}")
        :ok

      {:error, :nxdomain} ->
        IO.puts("No DNS record for #{@target} (trying as IP address)")

        # Try parsing as IP address
        case :inet.parse_address(String.to_charlist(@target)) do
          {:ok, _ip} ->
            IO.puts("✓ Valid IP address format")
            :ok
          {:error, :einval} ->
            {:error, "Invalid IP address format"}
        end

      {:error, reason} ->
        {:error, "DNS resolution failed: #{inspect(reason)}"}
    end
  end

  defp test_raw_ping do
    case System.cmd("ping", ["-c", "1", "-W", "3000", @target]) do
      {output, 0} ->
        IO.puts("Ping successful:")
        # Extract key info from ping output
        lines = String.split(output, "\n")
        stats_line = Enum.find(lines, fn line ->
          String.contains?(line, "packet loss")
        end)
        if stats_line, do: IO.puts("  #{String.trim(stats_line)}")
        :ok

      {error, _} ->
        IO.puts("Ping failed:")
        IO.puts("  #{String.trim(error)}")
        {:error, "Ping unreachable"}
    end
  end

  defp test_route_to_target do
    # Try different route commands based on OS
    commands = [
      ["route", "get", @target],
      ["ip", "route", "get", @target],
      ["traceroute", "-m", "3", @target]
    ]

    Enum.find_value(commands, fn cmd ->
      case System.cmd(List.first(cmd), List.delete_at(cmd, 0)) do
        {output, 0} ->
          IO.puts("Route to #{@target}:")
          IO.puts(String.slice(output, 0, 500))
          :ok

        {_error, _} ->
          nil
      end
    end) || {:error, "No route command worked"}
  end

  defp check_default_gateway do
    case System.cmd("route", ["-n", "get", "default"]) do
      {output, 0} ->
        IO.puts("Default gateway info:")
        lines = String.split(output, "\n")
        gateway_line = Enum.find(lines, fn line ->
          String.contains?(line, "gateway:")
        end)
        if gateway_line, do: IO.puts("  #{String.trim(gateway_line)}")
        :ok

      {error, _} ->
        {:warning, "Gateway check failed: #{String.trim(error)}"}
    end
  end

  defp check_firewall_status do
    # Check different firewall systems
    firewall_checks = [
      {"pfctl", ["-s", "nat"], "macOS PF firewall"},
      {"iptables", ["-L", "-n"], "Linux iptables"},
      {"ufw", ["status"], "UFW firewall"}
    ]

    results = Enum.map(firewall_checks, fn {cmd, args, desc} ->
      case System.cmd(cmd, args) do
        {output, 0} ->
          IO.puts("#{desc}: Active")
          if String.length(output) > 0 do
            IO.puts("  #{String.slice(output, 0, 200)}...")
          end
          :active

        {_error, _} ->
          :not_found
      end
    end)

    active_firewalls = Enum.count(results, fn r -> r == :active end)

    if active_firewalls > 0 do
      {:warning, "#{active_firewalls} firewall(s) active - may block traffic"}
    else
      :ok
    end
  end

  defp test_socket_binding do
    IO.puts("Testing different socket binding options:")

    # Test 1: Basic socket
    test_socket_option("Basic UDP socket", fn ->
      :gen_udp.open(0, [:binary, :inet, {:active, false}])
    end)

    # Test 2: Reuse address
    test_socket_option("Socket with reuse address", fn ->
      :gen_udp.open(0, [:binary, :inet, {:active, false}, {:reuseaddr, true}])
    end)

    # Test 3: Specific interface binding
    case :inet.getif() do
      {:ok, interfaces} ->
        {first_ip, _, _} = List.first(interfaces)
        ip_str = :inet.ntoa(first_ip)

        test_socket_option("Socket bound to #{ip_str}", fn ->
          :gen_udp.open(0, [:binary, :inet, {:active, false}, {:ip, first_ip}])
        end)

      _ ->
        IO.puts("  Could not test interface-specific binding")
    end

    :ok
  end

  defp test_socket_option(description, socket_fn) do
    case socket_fn.() do
      {:ok, socket} ->
        # Try to send a test packet
        test_data = "test"
        case :gen_udp.send(socket, String.to_charlist(@target), @target_port, test_data) do
          :ok ->
            IO.puts("  ✓ #{description}: Send successful")
          {:error, reason} ->
            IO.puts("  ✗ #{description}: Send failed - #{inspect(reason)}")
        end
        :gen_udp.close(socket)

      {:error, reason} ->
        IO.puts("  ✗ #{description}: Socket creation failed - #{inspect(reason)}")
    end
  end

  defp test_socket_variations do
    IO.puts("Testing socket variations that might work:")

    variations = [
      {"IPv4 explicit", [:inet]},
      {"IPv6 fallback", [:inet6]},
      {"Dual stack", [:inet, :inet6]},
      {"No broadcast", [{:broadcast, false}]},
      {"Larger buffers", [{:recbuf, 65536}, {:sndbuf, 65536}]},
      {"Priority", [{:priority, 1}]},
      {"Nodelay", [{:nodelay, true}]}
    ]

    Enum.each(variations, fn {desc, opts} ->
      case :gen_udp.open(0, [:binary, {:active, false}] ++ opts) do
        {:ok, socket} ->
          case :gen_udp.send(socket, String.to_charlist(@target), @target_port, "test") do
            :ok ->
              IO.puts("  ✓ #{desc}: Works")
            {:error, reason} ->
              IO.puts("  ✗ #{desc}: #{inspect(reason)}")
          end
          :gen_udp.close(socket)

        {:error, reason} ->
          IO.puts("  ✗ #{desc}: Socket failed - #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp compare_network_state do
    IO.puts("Network state comparison:")

    # Check if we're in a different network state than when scripts worked
    case :inet.getif() do
      {:ok, current_interfaces} ->
        IO.puts("Current network interfaces: #{length(current_interfaces)}")

        # Check if any interface can reach target subnet
        reachable = Enum.any?(current_interfaces, fn {ip, _, netmask} ->
          same_subnet?(ip, netmask, @target)
        end)

        if reachable do
          IO.puts("  ✓ Target should be reachable on local subnet")
        else
          IO.puts("  ⚠ Target not on any local subnet - needs routing")
        end

        :ok

      {:error, reason} ->
        {:error, "Cannot check network state: #{inspect(reason)}"}
    end
  end

  defp same_subnet?(local_ip, netmask, target_ip_str) do
    case :inet.parse_address(String.to_charlist(target_ip_str)) do
      {:ok, target_ip} ->
        local_network = apply_netmask(local_ip, netmask)
        target_network = apply_netmask(target_ip, netmask)
        local_network == target_network

      _ ->
        false
    end
  end

  defp apply_netmask({a, b, c, d}, {ma, mb, mc, md}) do
    {a &&& ma, b &&& mb, c &&& mc, d &&& md}
  end

  defp print_diagnosis(results) do
    IO.puts("\n" <> "=" |> String.duplicate(50))
    IO.puts("DIAGNOSIS SUMMARY")
    IO.puts("=" |> String.duplicate(50))

    failures = Enum.filter(results, fn {_, status} ->
      case status do
        {:fail, _} -> true
        {:error, _} -> true
        _ -> false
      end
    end)

    warnings = Enum.filter(results, fn {_, status} ->
      case status do
        {:warning, _} -> true
        _ -> false
      end
    end)

    IO.puts("Issues found: #{length(failures)} failures, #{length(warnings)} warnings")

    if length(failures) > 0 do
      IO.puts("\nCRITICAL ISSUES:")
      Enum.each(failures, fn {name, {_type, reason}} ->
        IO.puts("  ✗ #{name}: #{reason}")
      end)
    end

    if length(warnings) > 0 do
      IO.puts("\nWARNINGS:")
      Enum.each(warnings, fn {name, {_type, message}} ->
        IO.puts("  ⚠ #{name}: #{message}")
      end)
    end

    IO.puts("\nTROUBLESHOOTING STEPS:")
    IO.puts("1. Check if target device is actually reachable:")
    IO.puts("   ping #{@target}")
    IO.puts("2. Check routing table for path to target:")
    IO.puts("   route -n get #{@target}")
    IO.puts("3. Verify network interface is up and configured:")
    IO.puts("   ifconfig")
    IO.puts("4. Check if VPN or network changes occurred:")
    IO.puts("   sudo dscacheutil -flushcache (macOS)")
    IO.puts("5. Try connecting to target from different terminal:")
    IO.puts("   nc -u #{@target} #{@target_port}")
    IO.puts("6. Check system logs for network errors:")
    IO.puts("   tail -f /var/log/system.log | grep -i network")

    IO.puts("\nPOSSIBLE SOLUTIONS:")
    IO.puts("• Restart network services: sudo ifconfig en0 down && sudo ifconfig en0 up")
    IO.puts("• Flush DNS cache: sudo dscacheutil -flushcache")
    IO.puts("• Check VPN connection if using one")
    IO.puts("• Verify target device is still at #{@target}")
    IO.puts("• Try from a different network interface")
    IO.puts("• Check if network subnet has changed")
  end
end

# Run the network diagnostics
NetworkRoutingDebugger.run()
