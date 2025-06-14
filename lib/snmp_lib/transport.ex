defmodule SnmpLib.Transport do
  @moduledoc """
  UDP transport layer for SNMP communications.
  
  Provides socket management, connection utilities, and network operations
  for both SNMP managers and agents/simulators.
  
  ## Features
  
  - UDP socket creation and management
  - Address resolution and validation
  - Connection pooling and reuse
  - Timeout handling
  - Error recovery
  - Performance optimizations
  
  ## Examples
  
      # Create and use a socket
      {:ok, socket} = SnmpLib.Transport.create_socket("0.0.0.0", 161)
      {:ok, data} = SnmpLib.Transport.receive_packet(socket, 5000)
      :ok = SnmpLib.Transport.send_packet(socket, "192.168.1.100", 161, packet_data)
      :ok = SnmpLib.Transport.close_socket(socket)
      
      # Address utilities
      {:ok, {192, 168, 1, 100}} = SnmpLib.Transport.resolve_address("192.168.1.100")
      true = SnmpLib.Transport.validate_port(161)
  """

  require Logger

  @type socket :: :gen_udp.socket()
  @type address :: :inet.socket_address() | :inet.hostname() | binary()
  @type port_number :: :inet.port_number()
  @type packet_data :: binary()
  @type socket_options :: [:gen_udp.option()]

  # Default socket options
  @default_socket_options [
    {:active, false},
    {:reuseaddr, true}
  ]

  # Standard SNMP ports
  @snmp_agent_port 161
  @snmp_trap_port 162

  ## Socket Management

  @doc """
  Creates a UDP socket bound to the specified address and port.
  
  ## Parameters
  
  - `bind_address`: Address to bind to (use "0.0.0.0" for all interfaces)
  - `port`: Port number to bind to
  - `options`: Additional socket options (optional)
  
  ## Returns
  
  - `{:ok, socket}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      {:ok, socket} = SnmpLib.Transport.create_socket("0.0.0.0", 161)
      {:ok, client_socket} = SnmpLib.Transport.create_socket("0.0.0.0", 0, [{:active, true}])
  """
  @spec create_socket(binary() | :inet.socket_address(), port_number(), socket_options()) :: 
    {:ok, socket()} | {:error, atom()}
  def create_socket(bind_address, port, options \\ []) do
    case resolve_address(bind_address) do
      {:ok, resolved_address} ->
        case validate_port(port) do
          true ->
            merged_options = Keyword.merge(@default_socket_options, options)
            
            case :gen_udp.open(port, [:binary, {:ip, resolved_address} | merged_options]) do
              {:ok, socket} ->
                Logger.debug("Created UDP socket bound to #{format_endpoint(resolved_address, port)}")
                {:ok, socket}
              {:error, reason} ->
                Logger.error("Failed to create UDP socket: #{inspect(reason)}")
                {:error, reason}
            end
          false ->
            {:error, :invalid_port}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a client socket for outgoing SNMP requests.
  
  Uses an ephemeral port and optimizes settings for client use.
  
  ## Examples
  
      {:ok, socket} = SnmpLib.Transport.create_client_socket()
      {:ok, socket} = SnmpLib.Transport.create_client_socket([{:recbuf, 65536}])
  """
  @spec create_client_socket(socket_options()) :: {:ok, socket()} | {:error, atom()}
  def create_client_socket(options \\ []) do
    # Use ephemeral port (0) for client connections - bypass validation for ephemeral ports
    case resolve_address("0.0.0.0") do
      {:ok, resolved_address} ->
        client_options = Keyword.merge(@default_socket_options, [
          {:active, false},
          {:recbuf, 65536},  # Larger receive buffer for responses
          {:sndbuf, 8192}    # Smaller send buffer for requests
        ] ++ options)
        
        case :gen_udp.open(0, [:binary, {:ip, resolved_address} | client_options]) do
          {:ok, socket} ->
            Logger.debug("Created UDP socket bound to #{format_endpoint(resolved_address, 0)}")
            {:ok, socket}
          {:error, reason} ->
            Logger.error("Failed to create UDP socket: #{inspect(reason)}")
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a server socket for incoming SNMP requests.
  
  Optimizes settings for server use with proper buffer sizes.
  
  ## Examples
  
      {:ok, socket} = SnmpLib.Transport.create_server_socket(161)
      {:ok, socket} = SnmpLib.Transport.create_server_socket(161, "192.168.1.10")
  """
  @spec create_server_socket(port_number(), binary()) :: {:ok, socket()} | {:error, atom()}
  def create_server_socket(port, bind_address \\ "0.0.0.0") do
    server_options = [
      {:active, false},
      {:recbuf, 8192},   # Smaller receive buffer for requests
      {:sndbuf, 65536}   # Larger send buffer for responses
    ]
    
    # Allow port 0 for ephemeral ports in testing, but validate others
    if port == 0 do
      case resolve_address(bind_address) do
        {:ok, resolved_address} ->
          merged_options = Keyword.merge(@default_socket_options, server_options)
          
          case :gen_udp.open(port, [:binary, {:ip, resolved_address} | merged_options]) do
            {:ok, socket} ->
              Logger.debug("Created UDP socket bound to #{format_endpoint(resolved_address, port)}")
              {:ok, socket}
            {:error, reason} ->
              Logger.error("Failed to create UDP socket: #{inspect(reason)}")
              {:error, reason}
          end
        {:error, reason} ->
          {:error, reason}
      end
    else
      create_socket(bind_address, port, server_options)
    end
  end

  @doc """
  Sends a packet to the specified destination.
  
  ## Parameters
  
  - `socket`: UDP socket to send from
  - `dest_address`: Destination IP address or hostname
  - `dest_port`: Destination port number
  - `data`: Binary data to send
  
  ## Returns
  
  - `:ok` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      :ok = SnmpLib.Transport.send_packet(socket, "192.168.1.100", 161, packet_data)
      :ok = SnmpLib.Transport.send_packet(socket, {192, 168, 1, 100}, 161, packet_data)
  """
  @spec send_packet(socket(), address(), port_number(), packet_data()) :: 
    :ok | {:error, atom()}
  def send_packet(socket, dest_address, dest_port, data) 
      when is_binary(data) do
    case {resolve_address(dest_address), validate_port(dest_port)} do
      {{:ok, resolved_address}, true} ->
        case :gen_udp.send(socket, resolved_address, dest_port, data) do
          :ok ->
            Logger.debug("Sent #{byte_size(data)} bytes to #{format_endpoint(resolved_address, dest_port)}")
            :ok
          {:error, reason} ->
            Logger.error("Failed to send packet: #{inspect(reason)}")
            {:error, reason}
        end
      {{:error, reason}, _} ->
        {:error, reason}
      {_, false} ->
        {:error, :invalid_port}
    end
  end
  def send_packet(_, _, _, _), do: {:error, :invalid_data}

  @doc """
  Receives a packet from the socket with optional timeout.
  
  ## Parameters
  
  - `socket`: UDP socket to receive from
  - `timeout`: Timeout in milliseconds (default: 5000)
  
  ## Returns
  
  - `{:ok, {data, from_address, from_port}}` on success
  - `{:error, reason}` on failure or timeout
  
  ## Examples
  
      {:ok, {data, from_ip, from_port}} = SnmpLib.Transport.receive_packet(socket)
      {:ok, {data, from_ip, from_port}} = SnmpLib.Transport.receive_packet(socket, 10000)
  """
  @spec receive_packet(socket(), non_neg_integer()) :: 
    {:ok, {packet_data(), :inet.socket_address(), port_number()}} | {:error, atom()}
  def receive_packet(socket, timeout \\ 5000) when is_integer(timeout) and timeout >= 0 do
    case :gen_udp.recv(socket, 0, timeout) do
      {:ok, {from_address, from_port, data}} when is_binary(data) ->
        Logger.debug("Received #{byte_size(data)} bytes from #{format_endpoint(from_address, from_port)}")
        {:ok, {data, from_address, from_port}}
      {:ok, invalid_response} ->
        Logger.error("Invalid UDP response format: #{inspect(invalid_response)}")
        {:error, :invalid_response}
      {:error, :timeout} ->
        Logger.debug("Socket receive timeout after #{timeout}ms")
        {:error, :timeout}
      {:error, reason} ->
        Logger.error("Failed to receive packet: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Receives a packet with a custom filter function.
  
  Continues receiving until a packet matches the filter or timeout occurs.
  
  ## Parameters
  
  - `socket`: UDP socket to receive from
  - `filter_fn`: Function that returns true for desired packets
  - `timeout`: Total timeout in milliseconds
  - `per_recv_timeout`: Timeout per receive attempt (default: 1000ms)
  
  ## Examples
  
      # Wait for packet from specific address
      filter_fn = fn {_data, from_addr, _from_port} -> from_addr == {192, 168, 1, 100} end
      {:ok, {data, addr, port}} = SnmpLib.Transport.receive_packet_filtered(socket, filter_fn, 5000)
  """
  @spec receive_packet_filtered(socket(), function(), non_neg_integer(), non_neg_integer()) ::
    {:ok, {packet_data(), :inet.socket_address(), port_number()}} | {:error, atom()}
  def receive_packet_filtered(socket, filter_fn, timeout, per_recv_timeout \\ 1000) 
      when is_function(filter_fn, 1) do
    start_time = System.monotonic_time(:millisecond)
    receive_packet_filtered_loop(socket, filter_fn, timeout, per_recv_timeout, start_time)
  end

  @doc """
  Closes a UDP socket.
  
  ## Examples
  
      :ok = SnmpLib.Transport.close_socket(socket)
  """
  @spec close_socket(socket()) :: :ok
  def close_socket(socket) do
    :ok = :gen_udp.close(socket)
    Logger.debug("Closed UDP socket")
    :ok
  end

  ## Address and Network Utilities

  @doc """
  Resolves an address to an IP tuple.
  
  Accepts:
  - IP address strings (e.g., "192.168.1.1")
  - Hostnames (e.g., "localhost")
  - IP tuples (e.g., {192, 168, 1, 1})
  
  ## Examples
  
      iex> SnmpLib.Transport.resolve_address("192.168.1.1")
      {:ok, {192, 168, 1, 1}}
      
      iex> SnmpLib.Transport.resolve_address({192, 168, 1, 1})
      {:ok, {192, 168, 1, 1}}
  """
  @spec resolve_address(address()) :: {:ok, :inet.socket_address()} | {:error, atom()}
  def resolve_address(address) when is_tuple(address) do
    case address do
      {a, b, c, d} when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d)
                   and a >= 0 and a <= 255 and b >= 0 and b <= 255 
                   and c >= 0 and c <= 255 and d >= 0 and d <= 255 ->
        {:ok, address}
      _ ->
        {:error, :invalid_ip_tuple}
    end
  end

  def resolve_address(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, ip_tuple} ->
        {:ok, ip_tuple}
      {:error, :einval} ->
        # Try hostname resolution
        case :inet.gethostbyname(String.to_charlist(address)) do
          {:ok, {:hostent, _name, _aliases, :inet, 4, [ip_tuple | _]}} ->
            {:ok, ip_tuple}
          {:error, reason} ->
            Logger.error("Failed to resolve hostname #{address}: #{inspect(reason)}")
            {:error, :hostname_resolution_failed}
        end
    end
  end

  def resolve_address(_), do: {:error, :invalid_address_format}

  @doc """
  Validates a port number.
  
  ## Examples
  
      true = SnmpLib.Transport.validate_port(161)
      true = SnmpLib.Transport.validate_port(65535)
      true = SnmpLib.Transport.validate_port(0)
      false = SnmpLib.Transport.validate_port(65536)
  """
  @spec validate_port(term()) :: boolean()
  def validate_port(port) when is_integer(port) and port > 0 and port <= 65535, do: true
  def validate_port(_), do: false

  @doc """
  Formats an endpoint (address and port) as a string.
  
  ## Examples
  
      "192.168.1.100:161" = SnmpLib.Transport.format_endpoint({192, 168, 1, 100}, 161)
      "localhost:162" = SnmpLib.Transport.format_endpoint("localhost", 162)
  """
  @spec format_endpoint(address(), port_number()) :: binary()
  def format_endpoint(address, port) do
    address_str = case address do
      {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
      addr when is_binary(addr) -> addr
      _ -> inspect(address)
    end
    "#{address_str}:#{port}"
  end

  @doc """
  Gets the local address and port of a socket.
  
  ## Examples
  
      {:ok, {{127, 0, 0, 1}, 12345}} = SnmpLib.Transport.get_socket_address(socket)
  """
  @spec get_socket_address(socket()) :: {:ok, {:inet.socket_address(), port_number()}} | {:error, atom()}
  def get_socket_address(socket) do
    case :inet.sockname(socket) do
      {:ok, {address, port}} ->
        {:ok, {address, port}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Connection Management

  @doc """
  Tests connectivity to a destination by sending a test packet.
  
  This creates a temporary socket, sends a small packet, and waits for any response
  to verify network connectivity.
  
  ## Parameters
  
  - `dest_address`: Destination IP address or hostname
  - `dest_port`: Destination port number  
  - `timeout`: Timeout in milliseconds (default: 3000)
  
  ## Returns
  
  - `:ok` if connectivity is confirmed
  - `{:error, reason}` if connectivity fails
  
  ## Examples
  
      :ok = SnmpLib.Transport.test_connectivity("192.168.1.100", 161)
      {:error, :timeout} = SnmpLib.Transport.test_connectivity("10.0.0.1", 161, 1000)
  """
  @spec test_connectivity(address(), port_number(), non_neg_integer()) :: :ok | {:error, atom()}
  def test_connectivity(dest_address, dest_port, timeout \\ 3000) do
    case create_client_socket() do
      {:ok, socket} ->
        try do
          # Send a minimal packet to test connectivity
          test_packet = <<0x30, 0x02, 0x01, 0x00>>  # Minimal ASN.1 sequence
          
          case send_packet(socket, dest_address, dest_port, test_packet) do
            :ok ->
              # Wait for any response (even an error response indicates connectivity)
              case receive_packet(socket, timeout) do
                {:ok, _} -> :ok
                {:error, :timeout} -> {:error, :timeout}
                {:error, reason} -> {:error, reason}
              end
            {:error, reason} ->
              {:error, reason}
          end
        after
          close_socket(socket)
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a request packet and waits for a response.
  
  This creates a temporary socket, sends a packet, waits for the response,
  and returns the response data. Useful for SNMPv3 discovery and security operations.
  
  ## Parameters
  
  - `dest_address`: Destination IP address or hostname
  - `dest_port`: Destination port number
  - `request_data`: Binary request data to send
  - `timeout`: Timeout in milliseconds (default: 5000)
  
  ## Returns
  
  - `{:ok, response_data}` if request succeeds and response received
  - `{:error, reason}` if request fails or times out
  
  ## Examples
  
      {:ok, response} = SnmpLib.Transport.send_request("192.168.1.100", 161, request_packet, 5000)
      {:error, :timeout} = SnmpLib.Transport.send_request("10.0.0.1", 161, request_packet, 1000)
  """
  @spec send_request(address(), port_number(), packet_data(), non_neg_integer()) :: 
    {:ok, packet_data()} | {:error, atom()}
  def send_request(dest_address, dest_port, request_data, timeout \\ 5000) do
    case create_client_socket() do
      {:ok, socket} ->
        try do
          case send_packet(socket, dest_address, dest_port, request_data) do
            :ok ->
              case receive_packet(socket, timeout) do
                {:ok, {response_data, _from_addr, _from_port}} -> 
                  {:ok, response_data}
                {:error, reason} -> 
                  {:error, reason}
              end
            {:error, reason} ->
              {:error, reason}
          end
        after
          close_socket(socket)
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets socket statistics and information.
  
  ## Examples
  
      {:ok, stats} = SnmpLib.Transport.get_socket_stats(socket)
      # stats contains buffer sizes, packet counts, etc.
  """
  @spec get_socket_stats(socket()) :: {:ok, map()} | {:error, atom()}
  def get_socket_stats(socket) do
    try do
      case collect_socket_stats(socket) do
        {:ok, stats} -> {:ok, stats}
        {:error, reason} -> {:error, reason}
      end
    rescue
      error ->
        {:error, {:stats_error, error}}
    end
  end

  ## Utility Functions

  @doc """
  Returns standard SNMP port numbers.
  """
  @spec snmp_agent_port() :: port_number()
  def snmp_agent_port, do: @snmp_agent_port

  @spec snmp_trap_port() :: port_number()
  def snmp_trap_port, do: @snmp_trap_port

  @doc """
  Checks if a port number is a standard SNMP port.
  
  ## Examples
  
      true = SnmpLib.Transport.is_snmp_port?(161)
      true = SnmpLib.Transport.is_snmp_port?(162)
      false = SnmpLib.Transport.is_snmp_port?(80)
  """
  @spec is_snmp_port?(port_number()) :: boolean()
  def is_snmp_port?(port) when port in [@snmp_agent_port, @snmp_trap_port], do: true
  def is_snmp_port?(_), do: false

  @doc """
  Calculates network MTU considerations for SNMP packets.
  
  Returns recommended maximum payload size to avoid fragmentation.
  
  ## Examples
  
      1472 = SnmpLib.Transport.max_snmp_payload_size()  # Ethernet MTU - headers
  """
  @spec max_snmp_payload_size() :: non_neg_integer()
  def max_snmp_payload_size do
    # Ethernet MTU (1500) - IP header (20) - UDP header (8)
    1472
  end

  @doc """
  Validates if a packet size is suitable for SNMP transmission.
  
  ## Examples
  
      true = SnmpLib.Transport.valid_packet_size?(500)
      false = SnmpLib.Transport.valid_packet_size?(2000)
  """
  @spec valid_packet_size?(non_neg_integer()) :: boolean()
  def valid_packet_size?(size) when is_integer(size) and size > 0 do
    size <= max_snmp_payload_size()
  end
  def valid_packet_size?(_), do: false

  ## Private Helper Functions

  defp receive_packet_filtered_loop(socket, filter_fn, timeout, per_recv_timeout, start_time) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - start_time
    
    if elapsed >= timeout do
      {:error, :timeout}
    else
      remaining_timeout = min(per_recv_timeout, timeout - elapsed)
      
      case receive_packet(socket, remaining_timeout) do
        {:ok, {data, from_addr, from_port} = packet_info} ->
          if filter_fn.(packet_info) do
            {:ok, {data, from_addr, from_port}}
          else
            # Packet didn't match filter, continue waiting
            receive_packet_filtered_loop(socket, filter_fn, timeout, per_recv_timeout, start_time)
          end
        {:error, :timeout} ->
          # Continue waiting if we haven't exceeded total timeout
          receive_packet_filtered_loop(socket, filter_fn, timeout, per_recv_timeout, start_time)
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp collect_socket_stats(socket) do
    try do
      stats = %{
        socket_info: :inet.info(socket),
        port_info: :erlang.port_info(socket),
        statistics: :inet.getstat(socket)
      }
      {:ok, stats}
    rescue
      _ -> {:error, :stats_unavailable}
    end
  end
end