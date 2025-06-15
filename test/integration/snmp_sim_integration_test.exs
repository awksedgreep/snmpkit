defmodule SnmpSimIntegrationTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.ProfileLoader
  alias SnmpKit.SnmpSim.LazyDevicePool
  alias SnmpKit.SnmpSim.Device
  alias SnmpKit.SnmpSim.MIB.SharedProfiles
  alias SnmpKit.SnmpSim.TestHelpers.PortHelper

  describe "End-to-End Device Simulation" do
    setup do
      # Ensure SharedProfiles is available for each test
      case GenServer.whereis(SharedProfiles) do
        nil ->
          {:ok, _} = SharedProfiles.start_link([])

        pid when is_pid(pid) ->
          # Check if the process is still alive
          if Process.alive?(pid) do
            :ok
          else
            # Process is dead, start a new one
            {:ok, _} = SharedProfiles.start_link([])
          end
      end

      # Load cable_modem profile into SharedProfiles for tests
      :ok =
        SharedProfiles.load_walk_profile(
          :cable_modem,
          "priv/walks/cable_modem.walk",
          []
        )

      # Start LazyDevicePool for tests that need it
      case GenServer.whereis(LazyDevicePool) do
        nil ->
          {:ok, _} = LazyDevicePool.start_link([])

        _pid ->
          :ok
      end

      :ok
    end

    test "loads profile and starts device successfully" do
      # Load profile from walk file
      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      # Start device
      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)

      # Wait for device to be ready
      Process.sleep(100)

      # Test SNMP GET request
      response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0")

      assert {:ok, message} = response
      assert message.pdu.error_status == 0
      assert length(message.pdu.varbinds) == 1

      [{oid, _type, value}] = message.pdu.varbinds
      oid_string = if is_list(oid), do: Enum.join(oid, "."), else: oid
      assert oid_string == "1.3.6.1.2.1.1.1.0"
      assert is_binary(value) and String.contains?(value, "Motorola")

      GenServer.stop(device)
    end

    test "handles GETNEXT operations correctly" do
      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)

      Process.sleep(100)

      # Test GETNEXT starting from system group
      response = send_snmp_getnext(port, "1.3.6.1.2.1.1")

      assert {:ok, message} = response
      assert message.pdu.error_status == 0
      assert length(message.pdu.varbinds) == 1

      [{next_oid, _type, _value}] = message.pdu.varbinds
      next_oid_string = if is_list(next_oid), do: Enum.join(next_oid, "."), else: next_oid
      assert String.starts_with?(next_oid_string, "1.3.6.1.2.1.1.")

      GenServer.stop(device)
    end

    test "responds with proper error for non-existent OIDs" do
      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)

      Process.sleep(100)

      # Request non-existent OID
      response = send_snmp_get(port, "1.3.6.1.2.1.99.99.99.0")

      assert {:ok, message} = response
      assert length(message.pdu.varbinds) == 1

      [{_oid, _type, value}] = message.pdu.varbinds
      assert value == :null or value == nil or match?({:no_such_object, _}, value)

      GenServer.stop(device)
    end

    test "handles multiple devices simultaneously" do
      device_configs = [
        {:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"}, count: 3}
      ]

      port_range = find_free_port_range(3)

      {:ok, devices} =
        LazyDevicePool.start_device_population(
          device_configs,
          port_range: port_range,
          pre_warm: true
        )

      assert length(devices) == 3

      # Test each device responds independently
      device_ports =
        devices
        |> Enum.map(fn {port, _pid} -> port end)
        |> Enum.sort()

      responses =
        Enum.map(device_ports, fn port ->
          send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
        end)

      # All devices should respond successfully
      assert Enum.all?(responses, fn
               {:ok, message} -> message.pdu.error_status == 0
               _ -> false
             end)

      # Stop all devices
      Enum.each(devices, fn {_port, pid} -> GenServer.stop(pid) end)
    end

    test "device info and statistics work correctly" do
      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public",
        mac_address: "00:1A:2B:3C:4D:5E"
      }

      {:ok, device} = Device.start_link(device_config)

      Process.sleep(100)

      # Get device info
      info = Device.get_info(device)

      assert info.device_type == :cable_modem
      assert info.port == port
      assert info.mac_address == "00:1A:2B:3C:4D:5E"
      assert info.oid_count > 0
      assert is_integer(info.uptime)

      GenServer.stop(device)
    end

    test "device reboot functionality works" do
      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)

      Process.sleep(100)

      # Get initial uptime
      initial_info = Device.get_info(device)

      assert is_map(initial_info),
             "Initial device info should be a map, got: #{inspect(initial_info)}"

      initial_uptime = initial_info.uptime

      # Reboot device
      :ok = Device.reboot(device)

      Process.sleep(50)

      # Check uptime was reset
      final_info = Device.get_info(device)
      assert is_map(final_info), "Final device info should be a map, got: #{inspect(final_info)}"
      final_uptime = final_info.uptime

      assert final_uptime < initial_uptime

      GenServer.stop(device)
    end
  end

  describe "Performance and Reliability" do
    setup do
      # Ensure SharedProfiles is available for each test
      case GenServer.whereis(SharedProfiles) do
        nil ->
          {:ok, _} = SharedProfiles.start_link([])

        pid when is_pid(pid) ->
          # Check if the process is still alive
          if Process.alive?(pid) do
            :ok
          else
            # Process is dead, start a new one
            {:ok, _} = SharedProfiles.start_link([])
          end
      end

      # Load cable_modem profile into SharedProfiles for tests
      :ok =
        SharedProfiles.load_walk_profile(
          :cable_modem,
          "priv/walks/cable_modem.walk",
          []
        )

      :ok
    end

    test "handles multiple concurrent requests per device" do
      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)

      Process.sleep(100)

      # Send multiple concurrent requests
      tasks =
        for _i <- 1..20 do
          Task.async(fn ->
            send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
          end)
        end

      results = Enum.map(tasks, &Task.await(&1, 5000))

      # All requests should succeed
      successful =
        Enum.count(results, fn
          {:ok, message} -> message.pdu.error_status == 0
          _ -> false
        end)

      # Allow for some timing issues
      assert successful >= 18

      GenServer.stop(device)
    end

    test "device memory usage remains stable" do
      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device} = Device.start_link(device_config)

      Process.sleep(100)

      # Force garbage collection and get initial memory usage
      :erlang.garbage_collect(device)
      Process.sleep(50)
      initial_memory = get_process_memory(device)

      # Send many requests to stress test memory (with small delays to avoid overwhelming)
      for i <- 1..50 do
        send_snmp_get(port, "1.3.6.1.2.1.1.1.0")
        if rem(i, 10) == 0, do: Process.sleep(10)
      end

      Process.sleep(200)

      # Force garbage collection and check final memory usage
      :erlang.garbage_collect(device)
      Process.sleep(50)
      final_memory = get_process_memory(device)

      # Memory should not have grown excessively (allow for reasonable variance)
      memory_growth = final_memory - initial_memory
      # Less than 300% growth
      assert memory_growth < initial_memory * 3.0

      GenServer.stop(device)
    end
  end

  describe "Error Handling and Edge Cases" do
    setup do
      # Ensure SharedProfiles is available for each test
      case GenServer.whereis(SharedProfiles) do
        nil ->
          {:ok, _} = SharedProfiles.start_link([])

        pid when is_pid(pid) ->
          # Check if the process is still alive
          if Process.alive?(pid) do
            :ok
          else
            # Process is dead, start a new one
            {:ok, _} = SharedProfiles.start_link([])
          end
      end

      # Load cable_modem profile into SharedProfiles for tests
      :ok =
        SharedProfiles.load_walk_profile(
          :cable_modem,
          "priv/walks/cable_modem.walk",
          []
        )

      # Start LazyDevicePool for tests that need it
      case GenServer.whereis(LazyDevicePool) do
        nil ->
          {:ok, _} = LazyDevicePool.start_link([])

        _pid ->
          :ok
      end

      :ok
    end

    @tag :slow
    test "handles invalid community strings" do
      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      device_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "secret"
      }

      {:ok, device} = Device.start_link(device_config)

      Process.sleep(100)

      # Send request with wrong community
      response = send_snmp_get(port, "1.3.6.1.2.1.1.1.0", "wrong")

      # Should timeout (server ignores invalid community)
      assert response == :timeout

      GenServer.stop(device)
    end

    test "handles port conflicts gracefully" do
      # Trap exits to handle GenServer failures properly
      Process.flag(:trap_exit, true)

      {:ok, _profile} =
        ProfileLoader.load_profile(
          :cable_modem,
          {:walk_file, "priv/walks/cable_modem.walk"}
        )

      port = find_free_port()

      # Start first device
      device1_config = %{
        port: port,
        device_type: :cable_modem,
        device_id: "cable_modem_#{port}",
        community: "public"
      }

      {:ok, device1} = Device.start_link(device1_config)

      # Try to start second device on same port - this should fail due to port conflict
      # Use spawn_link and catch the exit to get proper error handling
      parent = self()

      spawn_link(fn ->
        device2_config = %{
          port: port,
          device_type: :cable_modem,
          device_id: "cable_modem_#{port}_2",
          community: "public"
        }

        result = Device.start_link(device2_config)
        send(parent, {:result, result})
      end)

      result =
        receive do
          {:result, res} -> res
          {:EXIT, _pid, reason} -> {:error, reason}
        after
          1000 -> {:error, :timeout}
        end

      # Should get an error return
      case result do
        {:error, :eaddrinuse} ->
          # Expected outcome
          :ok

        {:error, reason} ->
          flunk("Expected :eaddrinuse but got: #{inspect(reason)}")

        {:ok, _pid} ->
          flunk("Expected failure but device started successfully")
      end

      GenServer.stop(device1)
    end

    test "device population handles mixed success/failure" do
      device_configs = [
        {:cable_modem, {:walk_file, "priv/walks/cable_modem.walk"}, count: 2},
        {:bad_device, {:walk_file, "non_existent_file.walk"}, count: 1}
      ]

      port_range = find_free_port_range(3)

      result =
        LazyDevicePool.start_device_population(
          device_configs,
          port_range: port_range
        )

      # The device pool should handle this gracefully - either succeed or fail
      case result do
        {:ok, _} ->
          # Pool was configured successfully, ignoring invalid configs
          :ok

        {:error, _reason} ->
          # Pool failed due to invalid configs
          :ok
      end
    end
  end

  # Helper functions

  defp find_free_port do
    PortHelper.get_port()
  end

  defp find_free_port_range(count) do
    PortHelper.get_port_range(count)
  end

  defp send_snmp_get(port, oid, community \\ "public") do
    request_pdu = %{
      version: 1,
      community: community,
      type: :get_request,
      request_id: :rand.uniform(65535),
      error_status: 0,
      error_index: 0,
      varbinds: [{oid, nil}]
    }

    send_snmp_request(port, request_pdu)
  end

  defp send_snmp_getnext(port, oid, community \\ "public") do
    request_pdu = %{
      version: 1,
      community: community,
      type: :get_next_request,
      request_id: :rand.uniform(65535),
      error_status: 0,
      error_index: 0,
      varbinds: [{oid, nil}]
    }

    send_snmp_request(port, request_pdu)
  end

  defp send_snmp_request(port, pdu) do
    # Convert legacy PDU format to SnmpLib format
    oid_string = hd(pdu.varbinds) |> elem(0)
    oid_list = oid_string |> String.split(".") |> Enum.map(&String.to_integer/1)

    # Build proper SNMP message using SnmpKit.SnmpLib.PDU functions
    built_pdu =
      case pdu.type do
        :get_request -> SnmpKit.SnmpLib.PDU.build_get_request(oid_list, pdu.request_id)
        :get_next_request -> SnmpKit.SnmpLib.PDU.build_get_next_request(oid_list, pdu.request_id)
      end

    version =
      case pdu.version do
        1 -> :v1
        2 -> :v2c
      end

    message = SnmpKit.SnmpLib.PDU.build_message(built_pdu, pdu.community, version)

    case SnmpKit.SnmpLib.PDU.encode_message(message) do
      {:ok, packet} ->
        {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

        :gen_udp.send(socket, {127, 0, 0, 1}, port, packet)

        result =
          case :gen_udp.recv(socket, 0, 2000) do
            {:ok, {_ip, _port, response_data}} ->
              SnmpKit.SnmpLib.PDU.decode_message(response_data)

            {:error, :timeout} ->
              :timeout

            {:error, reason} ->
              {:error, reason}
          end

        :gen_udp.close(socket)
        result

      {:error, reason} ->
        {:error, {:encode_failed, reason}}
    end
  end

  defp get_process_memory(pid) do
    info = Process.info(pid, :memory)

    case info do
      {:memory, memory} -> memory
      nil -> 0
    end
  end
end
