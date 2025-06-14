defmodule SnmpKit.SnmpLib.TransportTest do
  use ExUnit.Case, async: false  # UDP sockets need sequential access
  
  alias SnmpKit.SnmpLib.Transport
  
  @moduletag :unit
  @moduletag :protocol
  @moduletag :phase_2

  # Use short timeouts as per testing rules
  @test_timeout 200

  describe "Socket creation and management" do
    test "creates client socket successfully" do
      {:ok, socket} = Transport.create_client_socket()
      assert is_port(socket)
      :ok = Transport.close_socket(socket)
    end

    test "creates server socket on specific port" do
      # Use ephemeral port to avoid conflicts
      {:ok, socket} = Transport.create_server_socket(0)
      assert is_port(socket)
      
      {:ok, {_address, port}} = Transport.get_socket_address(socket)
      assert port > 0
      
      :ok = Transport.close_socket(socket)
    end

    test "creates socket with custom options" do
      options = [{:recbuf, 32768}, {:active, true}]
      {:ok, socket} = Transport.create_client_socket(options)
      assert is_port(socket)
      :ok = Transport.close_socket(socket)
    end

    test "rejects invalid port numbers" do
      assert {:error, :invalid_port} = Transport.create_socket("0.0.0.0", 0)
      assert {:error, :invalid_port} = Transport.create_socket("0.0.0.0", 65536)
      assert {:error, :invalid_port} = Transport.create_socket("0.0.0.0", -1)
    end

    test "rejects invalid bind addresses" do
      assert {:error, _reason} = Transport.create_socket("999.999.999.999", 12345)
      assert {:error, _reason} = Transport.create_socket("invalid.address", 12345)
    end

    test "closes socket without errors" do
      {:ok, socket} = Transport.create_client_socket()
      assert :ok = Transport.close_socket(socket)
      
      # Closing again should still return :ok
      assert :ok = Transport.close_socket(socket)
    end
  end

  describe "Address resolution and validation" do
    test "resolves valid IP addresses" do
      {:ok, {127, 0, 0, 1}} = Transport.resolve_address("127.0.0.1")
      {:ok, {192, 168, 1, 1}} = Transport.resolve_address("192.168.1.1")
      {:ok, {0, 0, 0, 0}} = Transport.resolve_address("0.0.0.0")
    end

    test "resolves IP tuples" do
      {:ok, {192, 168, 1, 100}} = Transport.resolve_address({192, 168, 1, 100})
      {:ok, {127, 0, 0, 1}} = Transport.resolve_address({127, 0, 0, 1})
    end

    test "resolves localhost hostname" do
      {:ok, resolved} = Transport.resolve_address("localhost")
      # Should resolve to 127.0.0.1 or ::1, but we'll accept any valid result
      assert is_tuple(resolved)
      assert tuple_size(resolved) == 4
    end

    test "rejects invalid IP addresses" do
      assert {:error, :hostname_resolution_failed} = Transport.resolve_address("256.256.256.256")
      assert {:error, :invalid_ip_tuple} = Transport.resolve_address({256, 1, 1, 1})
      assert {:error, :invalid_ip_tuple} = Transport.resolve_address({1, 2, 3})
      assert {:error, :invalid_address_format} = Transport.resolve_address(12345)
    end

    test "validates port numbers correctly" do
      assert Transport.validate_port(1) == true
      assert Transport.validate_port(161) == true
      assert Transport.validate_port(65535) == true
      
      assert Transport.validate_port(0) == false
      assert Transport.validate_port(-1) == false
      assert Transport.validate_port(65536) == false
      assert Transport.validate_port("161") == false
    end

    test "formats endpoints correctly" do
      assert Transport.format_endpoint({192, 168, 1, 100}, 161) == "192.168.1.100:161"
      assert Transport.format_endpoint("localhost", 162) == "localhost:162"
    end

    test "gets socket address information" do
      {:ok, socket} = Transport.create_server_socket(0)
      {:ok, {address, port}} = Transport.get_socket_address(socket)
      
      assert is_tuple(address)
      assert tuple_size(address) == 4
      assert is_integer(port) and port > 0
      
      :ok = Transport.close_socket(socket)
    end
  end

  describe "Packet transmission" do
    test "sends and receives packets between sockets" do
      # Create server socket
      {:ok, server_socket} = Transport.create_server_socket(0)
      {:ok, {_server_addr, server_port}} = Transport.get_socket_address(server_socket)
      
      # Create client socket
      {:ok, client_socket} = Transport.create_client_socket()
      
      # Send packet from client to server
      test_data = "Hello SNMP"
      :ok = Transport.send_packet(client_socket, "127.0.0.1", server_port, test_data)
      
      # Receive packet on server
      {:ok, {received_data, from_addr, from_port}} = Transport.receive_packet(server_socket, @test_timeout)
      
      assert received_data == test_data
      assert is_tuple(from_addr)
      assert is_integer(from_port) and from_port > 0
      
      # Cleanup
      :ok = Transport.close_socket(server_socket)
      :ok = Transport.close_socket(client_socket)
    end

    test "handles receive timeout" do
      {:ok, socket} = Transport.create_client_socket()
      
      # Should timeout since no data is coming
      assert {:error, :timeout} = Transport.receive_packet(socket, 50)
      
      :ok = Transport.close_socket(socket)
    end

    test "validates packet data before sending" do
      {:ok, socket} = Transport.create_client_socket()
      
      assert {:error, :invalid_data} = Transport.send_packet(socket, "127.0.0.1", 12345, :not_binary)
      assert {:error, :invalid_data} = Transport.send_packet(socket, "127.0.0.1", 12345, 12345)
      
      :ok = Transport.close_socket(socket)
    end

    test "rejects invalid destination addresses for sending" do
      {:ok, socket} = Transport.create_client_socket()
      
      assert {:error, _reason} = Transport.send_packet(socket, "invalid.address", 12345, "data")
      assert {:error, :invalid_port} = Transport.send_packet(socket, "127.0.0.1", 0, "data")
      
      :ok = Transport.close_socket(socket)
    end
  end

  describe "Filtered packet reception" do
    test "receives packet matching filter" do
      {:ok, server_socket} = Transport.create_server_socket(0)
      {:ok, {_server_addr, server_port}} = Transport.get_socket_address(server_socket)
      
      {:ok, client_socket} = Transport.create_client_socket()
      {:ok, {client_addr, client_port}} = Transport.get_socket_address(client_socket)
      
      # Send packet
      test_data = "filtered packet"
      :ok = Transport.send_packet(client_socket, "127.0.0.1", server_port, test_data)
      
      # Filter for packets from client
      filter_fn = fn {_data, from_addr, _from_port} -> 
        from_addr == {127, 0, 0, 1}
      end
      
      {:ok, {received_data, _from_addr, _from_port}} = 
        Transport.receive_packet_filtered(server_socket, filter_fn, @test_timeout)
      
      assert received_data == test_data
      
      :ok = Transport.close_socket(server_socket)
      :ok = Transport.close_socket(client_socket)
    end

    test "times out when no packets match filter" do
      {:ok, socket} = Transport.create_client_socket()
      
      # Filter that never matches
      filter_fn = fn {_data, _from_addr, _from_port} -> false end
      
      assert {:error, :timeout} = 
        Transport.receive_packet_filtered(socket, filter_fn, 50)
      
      :ok = Transport.close_socket(socket)
    end
  end

  describe "Connectivity testing" do
    test "detects connectivity to localhost" do
      # Start a simple server
      {:ok, server_socket} = Transport.create_server_socket(0)
      {:ok, {_server_addr, server_port}} = Transport.get_socket_address(server_socket)
      
      # Spawn a task to respond to any packet
      server_task = Task.async(fn ->
        case Transport.receive_packet(server_socket, @test_timeout) do
          {:ok, {_data, from_addr, from_port}} ->
            Transport.send_packet(server_socket, from_addr, from_port, "response")
          _ -> :ok
        end
      end)
      
      # Test connectivity
      result = Transport.test_connectivity("127.0.0.1", server_port, @test_timeout)
      assert result == :ok
      
      # Cleanup
      Task.await(server_task, @test_timeout)
      :ok = Transport.close_socket(server_socket)
    end

    test "detects lack of connectivity to non-existent service" do
      # Use a port that's unlikely to be in use
      unused_port = 45678
      
      assert {:error, :timeout} = Transport.test_connectivity("127.0.0.1", unused_port, 50)
    end
  end

  describe "Socket statistics and information" do
    test "retrieves socket statistics" do
      {:ok, socket} = Transport.create_client_socket()
      
      {:ok, stats} = Transport.get_socket_stats(socket)
      
      assert is_map(stats)
      assert Map.has_key?(stats, :socket_info)
      assert Map.has_key?(stats, :port_info)
      assert Map.has_key?(stats, :statistics)
      
      :ok = Transport.close_socket(socket)
    end
  end

  describe "Utility functions" do
    test "returns standard SNMP ports" do
      assert Transport.snmp_agent_port() == 161
      assert Transport.snmp_trap_port() == 162
    end

    test "identifies SNMP ports" do
      assert Transport.is_snmp_port?(161) == true
      assert Transport.is_snmp_port?(162) == true
      assert Transport.is_snmp_port?(80) == false
      assert Transport.is_snmp_port?(443) == false
    end

    test "returns maximum SNMP payload size" do
      max_size = Transport.max_snmp_payload_size()
      assert is_integer(max_size)
      assert max_size > 1000  # Should be reasonable size
      assert max_size == 1472  # Ethernet MTU - IP - UDP headers
    end

    test "validates packet sizes" do
      assert Transport.valid_packet_size?(100) == true
      assert Transport.valid_packet_size?(1472) == true
      assert Transport.valid_packet_size?(2000) == false
      assert Transport.valid_packet_size?(0) == false
      assert Transport.valid_packet_size?(-1) == false
    end
  end

  describe "Error handling and edge cases" do
    test "handles concurrent socket operations" do
      # Create multiple sockets concurrently
      tasks = for i <- 1..10 do
        Task.async(fn ->
          {:ok, socket} = Transport.create_client_socket()
          {:ok, {_addr, port}} = Transport.get_socket_address(socket)
          :ok = Transport.close_socket(socket)
          {i, port}
        end)
      end
      
      results = Task.await_many(tasks, 1000)
      
      # All should succeed
      assert length(results) == 10
      for {i, port} <- results do
        assert is_integer(i)
        assert is_integer(port) and port > 0
      end
    end

    test "handles large packet transmission" do
      {:ok, server_socket} = Transport.create_server_socket(0)
      {:ok, {_server_addr, server_port}} = Transport.get_socket_address(server_socket)
      
      {:ok, client_socket} = Transport.create_client_socket()
      
      # Send large packet (but within limits)
      large_data = String.duplicate("A", 1400)
      :ok = Transport.send_packet(client_socket, "127.0.0.1", server_port, large_data)
      
      {:ok, {received_data, _from_addr, _from_port}} = 
        Transport.receive_packet(server_socket, @test_timeout)
      
      assert received_data == large_data
      assert byte_size(received_data) == 1400
      
      :ok = Transport.close_socket(server_socket)
      :ok = Transport.close_socket(client_socket)
    end

    test "handles empty packet transmission" do
      {:ok, server_socket} = Transport.create_server_socket(0)
      {:ok, {_server_addr, server_port}} = Transport.get_socket_address(server_socket)
      
      {:ok, client_socket} = Transport.create_client_socket()
      
      # Send empty packet
      :ok = Transport.send_packet(client_socket, "127.0.0.1", server_port, "")
      
      {:ok, {received_data, _from_addr, _from_port}} = 
        Transport.receive_packet(server_socket, @test_timeout)
      
      assert received_data == ""
      
      :ok = Transport.close_socket(server_socket)
      :ok = Transport.close_socket(client_socket)
    end

    test "handles socket operations on closed socket gracefully" do
      {:ok, socket} = Transport.create_client_socket()
      :ok = Transport.close_socket(socket)
      
      # Operations on closed socket should fail gracefully
      result = Transport.send_packet(socket, "127.0.0.1", 12345, "test")
      assert {:error, _reason} = result
    end
  end
end