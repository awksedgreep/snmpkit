#!/usr/bin/env elixir

# SNMP Connectivity Debugging Script
# This script helps diagnose SNMP connectivity issues by testing each layer
# from basic network connectivity up to full SNMP protocol communication.

defmodule SNMPDebugger do
  require Logger

  @target "192.168.88.234"
  @test_oid [1, 3, 6, 1, 2, 1, 1, 1, 0]  # sysDescr
  @community "public"

  def run do
    IO.puts("\n=== SNMP Connectivity Diagnostic Tool ===")
    IO.puts("Target: #{@target}")
    IO.puts("Test OID: #{inspect(@test_oid)}")
    IO.puts("Community: #{@community}")
    IO.puts("=" |> String.duplicate(50))

    # Enable debug logging
    Logger.configure(level: :debug)

    tests = [
      {"Basic Network Connectivity", &test_ping/0},
      {"UDP Port 161 Accessibility", &test_port_161/0},
      {"Raw UDP Socket Creation", &test_socket_creation/0},
      {"Raw UDP Packet Transmission", &test_raw_udp_send/0},
      {"SNMP Message Building", &test_snmp_message_build/0},
      {"SNMP Message Encoding", &test_snmp_message_encode/0},
      {"Full SNMP GET Request", &test_snmp_get_request/0},
      {"Full SNMP GETBULK Request", &test_snmp_bulk_request/0},
      {"SNMP Bulk Walk", &test_bulk_walk/0}
    ]

    results = Enum.map(tests, fn {name, test_fn} ->
      IO.puts("\n--- #{name} ---")

      try do
        case test_fn.() do
          :ok ->
            IO.puts("✓ PASS")
            {name, :pass}
          {:ok, result} ->
            IO.puts("✓ PASS: #{inspect(result)}")
            {name, :pass}
          {:error, reason} ->
            IO.puts("✗ FAIL: #{inspect(reason)}")
            {name, {:fail, reason}}
          error ->
            IO.puts("✗ FAIL: #{inspect(error)}")
            {name, {:fail, error}}
        end
      rescue
        e ->
          IO.puts("✗ ERROR: #{inspect(e)}")
          {name, {:error, e}}
      end
    end)

    print_summary(results)
  end

  defp test_ping do
    case System.cmd("ping", ["-c", "1", "-W", "3000", @target]) do
      {_output, 0} -> :ok
      {output, _} -> {:error, "Ping failed: #{String.trim(output)}"}
    end
  end

  defp test_port_161 do
    case System.cmd("nc", ["-z", "-u", "-w", "3", @target, "161"]) do
      {_output, 0} -> :ok
      {output, _} -> {:error, "Port 161 not accessible: #{String.trim(output)}"}
    end
  end

  defp test_socket_creation do
    case :gen_udp.open(0, [:binary, :inet, {:active, false}]) do
      {:ok, socket} ->
        {:ok, {_ip, port}} = :inet.sockname(socket)
        :gen_udp.close(socket)
        {:ok, "Socket created on port #{port}"}
      {:error, reason} ->
        {:error, "Socket creation failed: #{inspect(reason)}"}
    end
  end

  defp test_raw_udp_send do
    {:ok, socket} = :gen_udp.open(0, [:binary, :inet, {:active, false}])
    test_data = "test_packet_#{System.unique_integer()}"

    result = case :gen_udp.send(socket, String.to_charlist(@target), 161, test_data) do
      :ok -> {:ok, "UDP packet sent successfully"}
      {:error, reason} -> {:error, "UDP send failed: #{inspect(reason)}"}
    end

    :gen_udp.close(socket)
    result
  end

  defp test_snmp_message_build do
    try do
      pdu = SnmpKit.SnmpLib.PDU.build_get_request(@test_oid, 12345)
      message = SnmpKit.SnmpLib.PDU.build_message(pdu, @community, :v1)

      if message.version == 0 and message.community == @community do
        {:ok, "SNMP message built correctly"}
      else
        {:error, "SNMP message has incorrect fields: #{inspect(message)}"}
      end
    rescue
      e -> {:error, "SNMP message build failed: #{inspect(e)}"}
    end
  end

  defp test_snmp_message_encode do
    try do
      pdu = SnmpKit.SnmpLib.PDU.build_get_request(@test_oid, 12345)
      message = SnmpKit.SnmpLib.PDU.build_message(pdu, @community, :v1)

      case SnmpKit.SnmpLib.PDU.encode_message(message) do
        {:ok, packet} when is_binary(packet) ->
          {:ok, "SNMP message encoded to #{byte_size(packet)} bytes"}
        {:ok, other} ->
          {:error, "Encoding returned non-binary: #{inspect(other)}"}
        {:error, reason} ->
          {:error, "Encoding failed: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "SNMP message encode failed: #{inspect(e)}"}
    end
  end

  defp test_snmp_get_request do
    IO.puts("Attempting SNMP GET with detailed logging...")
    Logger.configure(level: :debug)

    # Add some debug output to trace execution
    IO.puts("Creating SNMP GET request...")

    result = SnmpKit.SnmpLib.Manager.get(@target, @test_oid,
      community: @community,
      version: :v1,
      timeout: 5000
    )

    case result do
      {:ok, {type, value}} ->
        {:ok, "SNMP GET successful: #{type} = #{inspect(value)}"}
      {:error, :timeout} ->
        {:error, "SNMP GET timed out - device may not be responding or packets not reaching target"}
      {:error, reason} ->
        {:error, "SNMP GET failed: #{inspect(reason)}"}
    end
  end

  defp test_snmp_bulk_request do
    IO.puts("Attempting SNMP GETBULK with detailed logging...")
    Logger.configure(level: :debug)

    result = SnmpKit.SnmpLib.Manager.get_bulk(@target, @test_oid,
      community: @community,
      version: :v2c,
      timeout: 5000,
      max_repetitions: 5
    )

    case result do
      {:ok, results} when is_list(results) ->
        {:ok, "SNMP GETBULK successful: #{length(results)} results"}
      {:error, :timeout} ->
        {:error, "SNMP GETBULK timed out"}
      {:error, reason} ->
        {:error, "SNMP GETBULK failed: #{inspect(reason)}"}
    end
  end

  defp test_bulk_walk do
    IO.puts("Attempting bulk walk with detailed logging...")
    Logger.configure(level: :debug)

    result = SnmpKit.SnmpMgr.bulk_walk(@target, [1, 3, 6])

    case result do
      {:ok, results} when is_list(results) ->
        {:ok, "Bulk walk successful: #{length(results)} results"}
      {:error, reason} ->
        {:error, "Bulk walk failed: #{inspect(reason)}"}
    end
  end

  defp print_summary(results) do
    IO.puts("\n" <> "=" |> String.duplicate(50))
    IO.puts("DIAGNOSTIC SUMMARY")
    IO.puts("=" |> String.duplicate(50))

    passes = Enum.count(results, fn {_, status} -> status == :pass end)
    total = length(results)

    Enum.each(results, fn {name, status} ->
      case status do
        :pass -> IO.puts("✓ #{name}")
        {:fail, reason} -> IO.puts("✗ #{name}: #{inspect(reason)}")
        {:error, error} -> IO.puts("⚠ #{name}: #{inspect(error)}")
      end
    end)

    IO.puts("\nResults: #{passes}/#{total} tests passed")

    if passes < total do
      IO.puts("\nTROUBLESHOoting RECOMMENDATIONS:")
      print_recommendations(results)
    else
      IO.puts("\n✓ All tests passed! SNMP connectivity should be working.")
    end
  end

  defp print_recommendations(results) do
    failed_tests = Enum.filter(results, fn {_, status} -> status != :pass end)

    Enum.each(failed_tests, fn {name, _status} ->
      case name do
        "Basic Network Connectivity" ->
          IO.puts("• Check network connectivity to #{@target}")
          IO.puts("• Verify the target IP address is correct")
          IO.puts("• Check routing table and network configuration")

        "UDP Port 161 Accessibility" ->
          IO.puts("• SNMP agent may not be running on #{@target}")
          IO.puts("• Port 161 may be blocked by firewall")
          IO.puts("• Try: sudo ufw allow 161/udp (if using UFW)")

        "Raw UDP Socket Creation" ->
          IO.puts("• System may have socket permission issues")
          IO.puts("• Check ulimit settings")

        "Raw UDP Packet Transmission" ->
          IO.puts("• Local firewall may be blocking outbound UDP")
          IO.puts("• Check with: sudo pfctl -s rules (macOS) or iptables -L (Linux)")

        "SNMP Message Building" ->
          IO.puts("• SNMP library may have configuration issues")
          IO.puts("• Try recompiling the project: mix deps.compile --force")

        "SNMP Message Encoding" ->
          IO.puts("• ASN.1 encoding issue in SNMP library")
          IO.puts("• Check for corrupted dependencies")

        "Full SNMP GET Request" ->
          IO.puts("• Device may not respond to SNMP requests")
          IO.puts("• Wrong community string (try 'private' or device-specific)")
          IO.puts("• SNMP version mismatch (try both v1 and v2c)")
          IO.puts("• Device SNMP may be disabled or configured differently")

        "Full SNMP GETBULK Request" ->
          IO.puts("• Device may not support SNMP v2c GETBULK operations")
          IO.puts("• Some older devices only support SNMP v1")
          IO.puts("• Try regular walk instead of bulk walk")

        "SNMP Bulk Walk" ->
          IO.puts("• Use regular walk: SnmpKit.SnmpMgr.walk(#{inspect(@target)}, [1,3,6])")
          IO.puts("• Try different starting OID")
          IO.puts("• Check if device supports bulk operations")

        _ ->
          IO.puts("• Check logs for specific error details")
      end
      IO.puts("")
    end)

    IO.puts("GENERAL TROUBLESHOOTING:")
    IO.puts("• Run with tcpdump to see if packets are being sent:")
    IO.puts("  sudo tcpdump -i any -n udp port 161")
    IO.puts("• Test with snmpwalk command-line tool:")
    IO.puts("  snmpwalk -v2c -c public #{@target} 1.3.6")
    IO.puts("• Check device SNMP configuration")
    IO.puts("• Verify community string and SNMP version support")
  end
end

# Run the diagnostics
SNMPDebugger.run()
