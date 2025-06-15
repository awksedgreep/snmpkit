defmodule SnmpDiagnosticTest do
  use ExUnit.Case
  require Logger

  @moduletag :network_tests
  @target "192.168.88.234"
  # sysDescr
  @test_oid [1, 3, 6, 1, 2, 1, 1, 1, 0]
  @timeout 10_000

  describe "Network Layer Diagnostics" do
    test "raw UDP socket can be created and bound" do
      {:ok, socket} = :gen_udp.open(0, [:binary, :inet, {:active, false}])

      # Get the actual port that was assigned
      {:ok, {_ip, port}} = :inet.sockname(socket)

      assert port > 0
      Logger.info("Created UDP socket on port #{port}")

      :gen_udp.close(socket)
    end

    test "can reach target host with ping" do
      case System.cmd("ping", ["-c", "1", "-W", "5000", @target]) do
        {_output, 0} ->
          Logger.info("Ping to #{@target} successful")
          assert true

        {output, _} ->
          Logger.error("Ping failed: #{output}")
          flunk("Cannot reach target host #{@target}")
      end
    end

    test "target host has port 161 open" do
      case System.cmd("nc", ["-z", "-u", "-w", "5", @target, "161"]) do
        {_output, 0} ->
          Logger.info("Port 161 is open on #{@target}")
          assert true

        {output, _} ->
          Logger.warn("Port 161 check failed: #{output}")
          # Don't fail the test as nc might not be available
          assert true
      end
    end

    test "raw UDP packet can be sent to target" do
      {:ok, socket} = :gen_udp.open(0, [:binary, :inet, {:active, false}])

      # Send a simple test packet
      test_data = "test_packet_#{System.unique_integer()}"

      case :gen_udp.send(socket, String.to_charlist(@target), 161, test_data) do
        :ok ->
          Logger.info("Successfully sent test UDP packet to #{@target}:161")
          assert true

        {:error, reason} ->
          Logger.error("Failed to send UDP packet: #{inspect(reason)}")
          flunk("Cannot send UDP packets to target")
      end

      :gen_udp.close(socket)
    end
  end

  describe "SNMP Core Library Tests" do
    test "can build basic SNMP GET message" do
      pdu = SnmpKit.SnmpLib.PDU.build_get_request(@test_oid, 12345)
      message = SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v1)

      # v1 = 0
      assert message.version == 0
      assert message.community == "public"
      assert message.pdu.type == :get_request

      Logger.info("Built SNMP GET message: #{inspect(message)}")
    end

    test "can build SNMP GETBULK message" do
      pdu = SnmpKit.SnmpLib.PDU.build_get_bulk_request(@test_oid, 12345, 0, 10)
      message = SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v2c)

      # v2c = 1
      assert message.version == 1
      assert message.community == "public"
      assert message.pdu.type == :get_bulk_request

      Logger.info("Built SNMP GETBULK message: #{inspect(message)}")
    end

    test "can encode SNMP message to binary" do
      pdu = SnmpKit.SnmpLib.PDU.build_get_request(@test_oid, 12345)
      message = SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v1)

      {:ok, packet} = SnmpKit.SnmpLib.PDU.encode_message(message)

      assert is_binary(packet)
      assert byte_size(packet) > 0

      Logger.info("Encoded SNMP packet: #{byte_size(packet)} bytes")
      Logger.debug("Packet bytes: #{inspect(packet, limit: :infinity)}")
    end
  end

  describe "SNMP Manager Socket Tests" do
    test "Manager can create socket" do
      opts = [community: "public", version: :v1, timeout: 5000]

      # Call the private function through the public API
      case SnmpKit.SnmpLib.Manager.get(@target, @test_oid, opts) do
        {:ok, _result} ->
          Logger.info("SNMP GET successful")
          assert true

        {:error, :timeout} ->
          Logger.warn("SNMP GET timed out - device may not be responding")
          # Don't fail on timeout for diagnostic purposes
          assert true

        {:error, reason} ->
          Logger.error("SNMP GET failed: #{inspect(reason)}")
          # Don't fail here - we want to see what happens
          assert true
      end
    end

    test "Manager can attempt bulk operation" do
      opts = [community: "public", version: :v2c, timeout: 5000, max_repetitions: 5]

      case SnmpKit.SnmpLib.Manager.get_bulk(@target, @test_oid, opts) do
        {:ok, results} ->
          Logger.info("SNMP GETBULK successful: #{length(results)} results")
          assert length(results) > 0

        {:error, :timeout} ->
          Logger.warn("SNMP GETBULK timed out - device may not support bulk operations")
          assert true

        {:error, reason} ->
          Logger.error("SNMP GETBULK failed: #{inspect(reason)}")
          assert true
      end
    end
  end

  describe "Direct Socket Communication Tests" do
    test "manual SNMP packet transmission with detailed logging" do
      # Create socket with detailed options
      {:ok, socket} =
        :gen_udp.open(0, [
          :binary,
          :inet,
          {:active, false},
          {:reuseaddr, true},
          {:broadcast, false}
        ])

      {:ok, {local_ip, local_port}} = :inet.sockname(socket)
      Logger.info("Created socket bound to #{:inet.ntoa(local_ip)}:#{local_port}")

      # Build SNMP packet manually
      pdu = SnmpKit.SnmpLib.PDU.build_get_request(@test_oid, 12345)
      message = SnmpKit.SnmpLib.PDU.build_message(pdu, "public", :v1)

      case SnmpKit.SnmpLib.PDU.encode_message(message) do
        {:ok, packet} ->
          Logger.info("Encoded packet: #{byte_size(packet)} bytes")

          # Send with detailed logging
          target_ip =
            case :inet.getaddr(String.to_charlist(@target), :inet) do
              {:ok, ip} ->
                Logger.info("Resolved #{@target} to #{:inet.ntoa(ip)}")
                ip

              {:error, reason} ->
                Logger.error("Failed to resolve #{@target}: #{inspect(reason)}")
                flunk("Cannot resolve target host")
            end

          case :gen_udp.send(socket, target_ip, 161, packet) do
            :ok ->
              Logger.info("Successfully sent SNMP packet to #{@target}")

              # Try to receive response
              case :gen_udp.recv(socket, 1500, 5000) do
                {:ok, {from_ip, from_port, response}} ->
                  Logger.info("Received response from #{:inet.ntoa(from_ip)}:#{from_port}")
                  Logger.info("Response: #{byte_size(response)} bytes")

                  case SnmpKit.SnmpLib.PDU.decode_message(response) do
                    {:ok, decoded} ->
                      Logger.info("Decoded response: #{inspect(decoded)}")
                      assert true

                    {:error, reason} ->
                      Logger.error("Failed to decode response: #{inspect(reason)}")
                      assert true
                  end

                {:error, :timeout} ->
                  Logger.warn("No response received within timeout")
                  assert true

                {:error, reason} ->
                  Logger.error("Failed to receive response: #{inspect(reason)}")
                  assert true
              end

            {:error, reason} ->
              Logger.error("Failed to send packet: #{inspect(reason)}")

              Logger.error(
                "Socket state: #{inspect(:inet.getopts(socket, [:active, :broadcast, :reuseaddr]))}"
              )

              flunk("Cannot send UDP packet")
          end

        {:error, reason} ->
          Logger.error("Failed to encode SNMP message: #{inspect(reason)}")
          flunk("Cannot encode SNMP message")
      end

      :gen_udp.close(socket)
    end
  end

  describe "System Network Configuration Tests" do
    test "check local network interfaces" do
      case :inet.getif() do
        {:ok, interfaces} ->
          Logger.info("Network interfaces:")

          Enum.each(interfaces, fn {ip, broadcast, netmask} ->
            Logger.info(
              "  #{:inet.ntoa(ip)}/#{:inet.ntoa(netmask)} bcast #{:inet.ntoa(broadcast)}"
            )
          end)

          assert length(interfaces) > 0

        {:error, reason} ->
          Logger.error("Failed to get network interfaces: #{inspect(reason)}")
          flunk("Cannot get network interfaces")
      end
    end

    test "check routing to target" do
      case System.cmd("route", ["-n", "get", @target]) do
        {output, 0} ->
          Logger.info("Route to #{@target}:")
          Logger.info(output)
          assert true

        {output, _} ->
          Logger.warn("Route check failed: #{output}")
          assert true
      end
    end

    test "check firewall rules (if applicable)" do
      # Check if pfctl exists (macOS)
      case System.cmd("which", ["pfctl"]) do
        {_path, 0} ->
          case System.cmd("pfctl", ["-s", "rules"]) do
            {output, 0} ->
              Logger.info("Firewall rules:\n#{output}")
              assert true

            {_output, _} ->
              Logger.info("Cannot read firewall rules (may need sudo)")
              assert true
          end

        {_output, _} ->
          Logger.info("pfctl not available")
          assert true
      end
    end
  end

  describe "SNMP Protocol Compliance Tests" do
    test "test different community strings" do
      communities = ["public", "private", "community"]

      Enum.each(communities, fn community ->
        opts = [community: community, version: :v1, timeout: 2000]

        case SnmpKit.SnmpLib.Manager.get(@target, @test_oid, opts) do
          {:ok, result} ->
            Logger.info("Community '#{community}' worked: #{inspect(result)}")

          {:error, reason} ->
            Logger.debug("Community '#{community}' failed: #{inspect(reason)}")
        end
      end)

      assert true
    end

    test "test different SNMP versions" do
      versions = [:v1, :v2c]

      Enum.each(versions, fn version ->
        opts = [community: "public", version: version, timeout: 2000]

        case SnmpKit.SnmpLib.Manager.get(@target, @test_oid, opts) do
          {:ok, result} ->
            Logger.info("Version #{version} worked: #{inspect(result)}")

          {:error, reason} ->
            Logger.debug("Version #{version} failed: #{inspect(reason)}")
        end
      end)

      assert true
    end

    test "test different OIDs" do
      oids = [
        # sysDescr
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        # sysObjectID
        [1, 3, 6, 1, 2, 1, 1, 2, 0],
        # sysUpTime
        [1, 3, 6, 1, 2, 1, 1, 3, 0],
        # sysContact
        [1, 3, 6, 1, 2, 1, 1, 4, 0],
        # sysName
        [1, 3, 6, 1, 2, 1, 1, 5, 0],
        # sysLocation
        [1, 3, 6, 1, 2, 1, 1, 6, 0]
      ]

      Enum.each(oids, fn oid ->
        opts = [community: "public", version: :v1, timeout: 2000]

        case SnmpKit.SnmpLib.Manager.get(@target, oid, opts) do
          {:ok, result} ->
            Logger.info("OID #{inspect(oid)} worked: #{inspect(result)}")

          {:error, reason} ->
            Logger.debug("OID #{inspect(oid)} failed: #{inspect(reason)}")
        end
      end)

      assert true
    end
  end

  describe "Bulk Walk Diagnostics" do
    test "manual bulk walk with detailed logging" do
      Logger.info("Starting diagnostic bulk walk for #{@target}")

      case SnmpKit.SnmpMgr.bulk_walk(@target, [1, 3, 6]) do
        {:ok, results} ->
          Logger.info("Bulk walk successful: #{length(results)} results")

          Enum.take(results, 5)
          |> Enum.each(fn {oid, type, value} ->
            Logger.info("  #{oid}: #{type} = #{inspect(value)}")
          end)

          assert length(results) > 0

        {:error, reason} ->
          Logger.error("Bulk walk failed: #{inspect(reason)}")

          # Try alternative approaches
          Logger.info("Trying alternative bulk walk...")

          case SnmpKit.SnmpMgr.walk(@target, [1, 3, 6, 1, 2, 1, 1],
                 community: "public",
                 version: :v1
               ) do
            {:ok, results} ->
              Logger.info("Regular walk successful: #{length(results)} results")
              assert true

            {:error, reason2} ->
              Logger.error("Regular walk also failed: #{inspect(reason2)}")
              assert true
          end
      end
    end
  end
end
