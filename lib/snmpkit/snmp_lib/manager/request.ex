defmodule SnmpKit.SnmpLib.Manager.Request do
  @moduledoc """
  Socket handling and the request/response cycle for `SnmpKit.SnmpLib.Manager`:
  encoding the PDU into a message, sending with retries, and waiting for the
  response whose request id matches while ignoring stray datagrams.
  """

  require Logger

  @default_community "public"
  @default_version :v2c
  @default_timeout 5_000
  @default_retries 3
  @default_port 161

  # Socket management
  def create_socket(opts, host \\ nil) do
    socket_opts =
      opts
      |> Keyword.take([:local_port, :bind_address, :recbuf, :sndbuf])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Keyword.put_new(:family, family_for(host))

    case SnmpKit.SnmpLib.Transport.create_client_socket(socket_opts) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:error, {:socket_error, reason}}
    end
  end

  # The socket family must match the destination: resolve the host once here.
  defp family_for(nil), do: :inet
  defp family_for(host), do: SnmpKit.SnmpLib.Transport.target_family(host)

  def close_socket(socket) do
    SnmpKit.SnmpLib.Transport.close_socket(socket)
  end

  def perform_snmp_request(socket, host, pdu, opts) do
    community = opts[:community] || @default_community
    version = opts[:version] || @default_version
    timeout = opts[:timeout] || @default_timeout
    retries = normalize_retries(opts[:retries] || @default_retries)
    port_option = opts[:port] || @default_port

    # Parse target to handle both host:port strings and :port option
    {parsed_host, parsed_port} =
      case SnmpKit.SnmpLib.Utils.parse_target(host) do
        {:ok, %{host: h, port: p}} ->
          # Check if host contained a port specification
          if host_contains_port?(host) do
            # Host:port format - use parsed port (backward compatibility)
            {h, p}
          else
            # Host without port - use :port option
            {h, port_option}
          end

        {:error, _} ->
          # Parse failed - use original host and :port option
          {host, port_option}
      end

    if version in [:v3, 3] do
      with {:ok, target_address} <- SnmpKit.SnmpLib.Transport.resolve_address(parsed_host) do
        SnmpKit.SnmpLib.Manager.V3.perform(
          socket,
          target_address,
          parsed_port,
          pdu,
          Keyword.merge(opts, timeout: timeout, retries: retries)
        )
      end
    else
      perform_community_request(
        socket,
        parsed_host,
        parsed_port,
        pdu,
        community,
        version,
        timeout,
        retries
      )
    end
  end

  defp perform_community_request(
         socket,
         parsed_host,
         parsed_port,
         pdu,
         community,
         version,
         timeout,
         retries
       ) do
    message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, version)
    Logger.debug("Built SNMP message: #{inspect(message)}")

    with {:ok, target_address} <- SnmpKit.SnmpLib.Transport.resolve_address(parsed_host),
         {:ok, packet} <- SnmpKit.SnmpLib.PDU.encode_message(message) do
      Logger.debug("Encoded PDU packet for transmission")

      case send_and_receive_with_retries(
             socket,
             target_address,
             parsed_port,
             packet,
             pdu.request_id,
             timeout,
             retries
           ) do
        {:ok, response_message} ->
          Logger.debug("Received response packet from network")
          Logger.debug("Decoded response message: #{inspect(response_message)}")
          {:ok, response_message}

        {:error, network_reason} = network_error ->
          Logger.error("Network operation failed: #{inspect(network_reason)}")
          network_error
      end
    else
      {:error, reason} = error ->
        Logger.error("PDU preparation failed: #{inspect(reason)}")
        error
    end
  end

  defp send_and_receive_with_retries(socket, host, port, packet, request_id, timeout, retries) do
    max_attempts = max(1, retries + 1)
    send_and_receive_attempt(socket, host, port, packet, request_id, timeout, max_attempts, 1)
  end

  defp normalize_retries(retries) when is_integer(retries) and retries >= 0, do: retries
  defp normalize_retries(_), do: @default_retries

  defp send_and_receive_attempt(
         socket,
         host,
         port,
         packet,
         request_id,
         timeout,
         max_attempts,
         attempt
       ) do
    case send_and_receive(socket, host, port, packet, request_id, timeout) do
      {:error, :timeout} when attempt < max_attempts ->
        Logger.debug(
          "Timeout waiting for response on attempt #{attempt}/#{max_attempts}; retrying"
        )

        send_and_receive_attempt(
          socket,
          host,
          port,
          packet,
          request_id,
          timeout,
          max_attempts,
          attempt + 1
        )

      result ->
        result
    end
  end

  def send_and_receive(socket, host, port, packet, request_id, timeout) do
    # Normal send-and-receive flow
    with :ok <- SnmpKit.SnmpLib.Transport.send_packet(socket, host, port, packet) do
      Logger.debug("Packet sent successfully, waiting for response (timeout: #{timeout}ms)")
      receive_matching_response(socket, host, port, request_id, timeout)
    else
      {:error, reason} ->
        Logger.debug("Error sending packet: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  defp receive_matching_response(socket, host, port, request_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    receive_matching_response_loop(socket, host, port, request_id, deadline)
  end

  defp receive_matching_response_loop(socket, host, port, request_id, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case SnmpKit.SnmpLib.Transport.receive_packet(socket, remaining) do
      {:ok, {response_packet, ^host, ^port}} ->
        Logger.debug("Received response packet: #{byte_size(response_packet)} bytes")

        case SnmpKit.SnmpLib.PDU.decode_message(response_packet) do
          {:ok, %{pdu: %{request_id: ^request_id}} = response_message} ->
            {:ok, response_message}

          {:ok, %{pdu: %{request_id: other_request_id}}} ->
            Logger.debug(
              "Ignoring SNMP response for request_id=#{inspect(other_request_id)} while waiting for #{inspect(request_id)}"
            )

            receive_matching_response_loop(socket, host, port, request_id, deadline)

          {:ok, response_message} ->
            Logger.debug(
              "Ignoring SNMP response without request_id: #{inspect(response_message)}"
            )

            receive_matching_response_loop(socket, host, port, request_id, deadline)

          {:error, decode_reason} ->
            Logger.debug("Ignoring undecodable SNMP packet: #{inspect(decode_reason)}")
            receive_matching_response_loop(socket, host, port, request_id, deadline)
        end

      {:ok, {_response_packet, from_addr, from_port}} ->
        Logger.debug(
          "Ignoring UDP packet from #{inspect(from_addr)}:#{from_port} while waiting for #{inspect(host)}:#{port}"
        )

        receive_matching_response_loop(socket, host, port, request_id, deadline)

      {:error, :timeout} = timeout_error ->
        Logger.debug("Timeout waiting for matching response")
        timeout_error

      {:error, reason} ->
        Logger.debug("Error receiving response: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  # Helper to determine if host string contains port specification
  defp host_contains_port?(host) when is_binary(host) do
    cond do
      # RFC 3986 bracket notation: [IPv6]:port
      String.starts_with?(host, "[") and String.contains?(host, "]:") ->
        # Check if it's valid [addr]:port format
        case String.split(host, "]:", parts: 2) do
          [_ipv6_part, port_part] ->
            case Integer.parse(port_part) do
              {port, ""} when port > 0 and port <= 65535 -> true
              _ -> false
            end

          _ ->
            false
        end

      # Plain IPv6 addresses (contain :: or multiple colons) - no port embedded
      String.contains?(host, "::") ->
        false

      host |> String.graphemes() |> Enum.count(&(&1 == ":")) > 1 ->
        false

      # IPv4 or simple hostname with port
      String.contains?(host, ":") ->
        # Single colon - check if part after colon looks like a port number
        case String.split(host, ":", parts: 2) do
          [_host_part, port_part] ->
            case Integer.parse(port_part) do
              {port, ""} when port > 0 and port <= 65535 -> true
              _ -> false
            end

          _ ->
            false
        end

      # No colon at all
      true ->
        false
    end
  end

  defp host_contains_port?(_), do: false
end
