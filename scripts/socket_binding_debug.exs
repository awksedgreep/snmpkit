#!/usr/bin/env elixir

# Socket Binding Diagnostic Script
# This script investigates why UDP sockets work for some users but not others
# Focus: Interface binding, routing, and socket options

defmodule SocketBindingDebug do
  require Logger

  @target "192.168.88.234"
  @target_port 161

  def run do
    IO.puts("""

    🔍 Socket Binding Diagnostic Tool
    =================================

    Investigating why UDP sockets work for some users but not others.
    Target: #{@target}:#{@target_port}

    This will test different socket binding approaches to find the
    root cause of :ehostunreach errors.

    """)

    Logger.configure(level: :debug)

    tests = [
      {"System Network State", &check_system_network_state/0},
      {"Interface Detection", &detect_network_interfaces/0},
      {"Routing Analysis", &analyze_routing/0},
      {"Socket Binding Variations", &test_socket_binding_variations/0},
      {"Interface-Specific Binding", &test_interface_specific_binding/0},
      {"Socket Option Combinations", &test_socket_option_combinations/0},
      {"Kernel Route Cache", &check_kernel_route_cache/0},
      {"Compare Working vs Broken", &compare_socket_states/0}
    ]

    Enum.each(tests, fn {name, test_fn} ->
      IO.puts("\n--- #{name} ---")

      try do
        case test_fn.() do
          :ok -> IO.puts("✓ OK")
          {:ok, result} -> IO.puts("✓ OK: #{result}")
          {:error, reason} -> IO.puts("✗ ERROR: #{reason}")
          {:warning, msg} -> IO.puts("⚠ WARNING: #{msg}")
        end
      rescue
        e -> IO.puts("✗ EXCEPTION: #{inspect(e)}")
      end
    end)
  end

  defp check_system_network_state do
    # Check basic connectivity
    case System.cmd("ping", ["-c", "1", "-W", "1000", @target]) do
      {_output, 0} ->
        {:ok, "Ping successful - basic connectivity works"}
      {error, _} ->
        {:error, "Ping failed: #{String.trim(error)}"}
    end
  end

  defp detect_network_interfaces do
    case :inet.getif() do
      {:ok, interfaces} ->
        IO.puts("Network interfaces found:")

        Enum.each(interfaces, fn {ip, broadcast, netmask} ->
          ip_str = :inet.ntoa(ip)
          broadcast_str = :inet.ntoa(broadcast)
          netmask_str = :inet.ntoa(netmask)

          # Check if target is in this subnet
          in_subnet = in_same_subnet?(ip, netmask, @target)
          subnet_indicator = if in_subnet, do: " ← TARGET SUBNET", else: ""

          IO.puts("  #{ip_str} broadcast #{broadcast_str} netmask #{netmask_str}#{subnet_indicator}")
        end)

        # Find the interface that should reach the target
        target_interface = Enum.find(interfaces, fn {ip, _, netmask} ->
          in_same_subnet?(ip, netmask, @target)
        end)

        case target_interface do
          {ip, _, _} ->
            {:ok, "Target should be reachable via interface #{:inet.ntoa(ip)}"}
          nil ->
            {:warning, "Target not in any local subnet - requires routing"}
        end

      {:error, reason} ->
        {:error, "Cannot get interfaces: #{inspect(reason)}"}
    end
  end

  defp analyze_routing do
    # Check routing table for target
    case System.cmd("route", ["-n", "get", @target]) do
      {output, 0} ->
        IO.puts("Route to target:")
        lines = String.split(output, "\n")

        # Extract key routing information
        interface = extract_route_info(lines, "interface:")
        gateway = extract_route_info(lines, "gateway:")

        IO.puts("  Interface: #{interface || "unknown"}")
        IO.puts("  Gateway: #{gateway || "direct"}")

        {:ok, "Route exists via #{interface || "unknown"}"}

      {error, _} ->
        {:error, "Route lookup failed: #{String.trim(error)}"}
    end
  end

  defp test_socket_binding_variations do
    IO.puts("Testing different socket binding approaches:")

    variations = [
      {"Default (0.0.0.0:0)", []},
      {"Explicit IPv4", [:inet]},
      {"No reuse addr", [{:reuseaddr, false}]},
      {"Larger buffers", [{:recbuf, 65536}, {:sndbuf, 65536}]},
      {"Raw mode", [{:mode, :binary}]},
      {"Explicit broadcast", [{:broadcast, true}]},
      {"No delay", [{:nodelay, true}]}
    ]

    results = Enum.map(variations, fn {desc, opts} ->
      result = test_socket_with_options(desc, opts)
      {desc, result}
    end)

    successful = Enum.count(results, fn {_, result} -> result == :ok end)

    if successful > 0 do
      {:ok, "#{successful}/#{length(variations)} variations worked"}
    else
      {:error, "No socket variations worked"}
    end
  end

  defp test_interface_specific_binding do
    case :inet.getif() do
      {:ok, interfaces} ->
        IO.puts("Testing binding to specific interfaces:")

        results = Enum.map(interfaces, fn {ip, _, _} ->
          ip_str = :inet.ntoa(ip)
          result = test_socket_bound_to_interface(ip_str, ip)
          IO.puts("  #{ip_str}: #{format_result(result)}")
          result
        end)

        successful = Enum.count(results, &(&1 == :ok))
        {:ok, "#{successful}/#{length(interfaces)} interfaces worked"}

      {:error, reason} ->
        {:error, "Cannot get interfaces: #{inspect(reason)}"}
    end
  end

  defp test_socket_option_combinations do
    IO.puts("Testing socket option combinations that might fix routing:")

    # These are combinations that might help with routing issues
    combinations = [
      {"Minimal options", [:binary, {:active, false}]},
      {"Explicit family", [:binary, :inet, {:active, false}]},
      {"With IP_RECVDSTADDR", [:binary, :inet, {:active, false}, {:ip_recvdstaddr, true}]},
      {"Raw UDP", [:binary, :inet, {:active, false}, {:mode, :binary}]},
      {"Large buffers + reuse", [:binary, :inet, {:active, false}, {:reuseaddr, true}, {:recbuf, 131072}]}
    ]

    results = Enum.map(combinations, fn {desc, opts} ->
      result = test_raw_socket_with_options(desc, opts)
      {desc, result}
    end)

    successful = Enum.count(results, fn {_, result} -> result == :ok end)

    if successful > 0 do
      {:ok, "#{successful}/#{length(combinations)} combinations worked"}
    else
      {:error, "No socket option combinations worked"}
    end
  end

  defp check_kernel_route_cache do
    IO.puts("Checking kernel routing state:")

    # Check ARP table
    case System.cmd("arp", ["-a"]) do
      {output, 0} ->
        if String.contains?(output, @target) do
          IO.puts("✓ ARP entry exists for target")
        else
          IO.puts("⚠ No ARP entry for target")
        end
      {_, _} ->
        IO.puts("? Cannot check ARP table")
    end

    # Check if we can resolve the route
    case System.cmd("ping", ["-c", "1", "-I", "auto", @target]) do
      {_output, 0} ->
        {:ok, "Ping with interface selection works"}
      {error, _} ->
        {:warning, "Ping with interface selection failed: #{String.trim(error)}"}
    end
  end

  defp compare_socket_states do
    IO.puts("Comparing working vs non-working socket states:")

    # Create a socket and check its state
    case :gen_udp.open(0, [:binary, :inet, {:active, false}]) do
      {:ok, socket} ->
        # Get detailed socket information
        socket_info = get_detailed_socket_info(socket)
        IO.puts("Socket details:")
        Enum.each(socket_info, fn {key, value} ->
          IO.puts("  #{key}: #{inspect(value)}")
        end)

        # Try the send operation
        result = :gen_udp.send(socket, String.to_charlist(@target), @target_port, "test")
        IO.puts("Send result: #{inspect(result)}")

        :gen_udp.close(socket)

        case result do
          :ok -> {:ok, "Socket send works"}
          {:error, reason} -> {:error, "Socket send fails: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Cannot create socket: #{inspect(reason)}"}
    end
  end

  # Helper functions

  defp in_same_subnet?(local_ip, netmask, target_ip_str) do
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
    import Bitwise
    {a &&& ma, b &&& mb, c &&& mc, d &&& md}
  end

  defp extract_route_info(lines, prefix) do
    lines
    |> Enum.find(fn line -> String.contains?(line, prefix) end)
    |> case do
      nil -> nil
      line ->
        line
        |> String.split(":")
        |> List.last()
        |> String.trim()
    end
  end

  defp test_socket_with_options(desc, extra_opts) do
    base_opts = [:binary, :inet, {:active, false}]
    opts = base_opts ++ extra_opts

    case :gen_udp.open(0, opts) do
      {:ok, socket} ->
        result = :gen_udp.send(socket, String.to_charlist(@target), @target_port, "test")
        :gen_udp.close(socket)

        case result do
          :ok ->
            IO.puts("  ✓ #{desc}: Success")
            :ok
          {:error, reason} ->
            IO.puts("  ✗ #{desc}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("  ✗ #{desc}: Socket creation failed - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp test_socket_bound_to_interface(ip_str, ip_tuple) do
    opts = [:binary, :inet, {:active, false}, {:ip, ip_tuple}]

    case :gen_udp.open(0, opts) do
      {:ok, socket} ->
        result = :gen_udp.send(socket, String.to_charlist(@target), @target_port, "test")
        :gen_udp.close(socket)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_raw_socket_with_options(desc, opts) do
    case :gen_udp.open(0, opts) do
      {:ok, socket} ->
        result = :gen_udp.send(socket, String.to_charlist(@target), @target_port, "test")
        :gen_udp.close(socket)

        case result do
          :ok ->
            IO.puts("  ✓ #{desc}: Success")
            :ok
          {:error, reason} ->
            IO.puts("  ✗ #{desc}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("  ✗ #{desc}: Socket creation failed - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_detailed_socket_info(socket) do
    info = []

    # Socket name (local address)
    info = case :inet.sockname(socket) do
      {:ok, {ip, port}} ->
        [{"local_address", "#{:inet.ntoa(ip)}:#{port}"} | info]
      _ ->
        [{"local_address", "unknown"} | info]
    end

    # Socket options
    opts_to_check = [:active, :broadcast, :reuseaddr, :recbuf, :sndbuf, :type]

    info = Enum.reduce(opts_to_check, info, fn opt, acc ->
      case :inet.getopts(socket, [opt]) do
        {:ok, [{^opt, value}]} ->
          [{to_string(opt), value} | acc]
        _ ->
          [{to_string(opt), "unknown"} | acc]
      end
    end)

    info
  end

  defp format_result(:ok), do: "✓ Success"
  defp format_result({:error, reason}), do: "✗ #{inspect(reason)}"
  defp format_result(other), do: "? #{inspect(other)}"
end

# Run the diagnostic
SocketBindingDebug.run()
