defmodule SnmpKit.SnmpSim.Core.Server do
  @moduledoc """
  High-performance UDP server for SNMP request handling.
  Supports concurrent packet processing with minimal latency.
  """

  use GenServer
  require Logger
  alias SnmpKit.SnmpLib.PDU, as: PDU
  alias SnmpKit.SnmpSim.Device.OidHandler

  # Suppress Dialyzer warnings for async functions and pattern matches
  @dialyzer [
    {:nowarn_function, process_snmp_request_async: 5},
    {:nowarn_function, send_response_async: 4}
  ]

  defstruct [
    :socket,
    :port,
    :device_handler,
    :community,
    :stats
  ]

  @default_community "public"
  @socket_opts [:binary, {:active, true}, {:reuseaddr, true}, {:ip, {0, 0, 0, 0}}]

  @doc """
  Start an SNMP UDP server on the specified port.

  ## Options

  - `:community` - SNMP community string (default: "public")
  - `:device_handler` - Module or function to handle device requests
  - `:socket_opts` - Additional socket options

  ## Examples

      {:ok, server} = SnmpKit.SnmpSim.Core.Server.start_link(9001,
        community: "public",
        device_handler: &MyDevice.handle_request/2
      )

  """
  def start_link(port, opts \\ []) do
    GenServer.start_link(__MODULE__, {port, opts})
  end

  @doc """
  Get server statistics.
  """
  def get_stats(server_pid) do
    GenServer.call(server_pid, :get_stats)
  end

  @doc """
  Update the device handler function.
  """
  def set_device_handler(server_pid, handler) do
    GenServer.call(server_pid, {:set_device_handler, handler})
  end

  # GenServer callbacks

  @impl true
  def init({port, opts}) do
    community = Keyword.get(opts, :community, @default_community)
    device_handler = Keyword.get(opts, :device_handler)
    socket_opts = Keyword.get(opts, :socket_opts, []) ++ @socket_opts

    case :gen_udp.open(port, socket_opts) do
      {:ok, socket} ->
        # Debug: Check socket info
        case :inet.sockname(socket) do
          {:ok, {ip, bound_port}} ->
            Logger.info(
              "SNMP server started on port #{port}, socket bound to #{:inet.ntoa(ip)}:#{bound_port}"
            )

          {:error, reason} ->
            Logger.error("Failed to get socket name: #{inspect(reason)}")
        end

        state = %__MODULE__{
          socket: socket,
          port: port,
          device_handler: device_handler,
          community: community,
          stats: init_stats()
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start SNMP server on port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call({:set_device_handler, handler}, _from, state) do
    new_state = %{state | device_handler: handler}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:udp, socket, client_ip, client_port, packet}, %{socket: socket} = state) do
    Logger.debug(
      "Received UDP packet from #{:inet.ntoa(client_ip)}:#{client_port}, #{byte_size(packet)} bytes"
    )

    # Update stats
    new_stats = update_stats(state.stats, :packets_received)
    final_state = %{state | stats: new_stats}

    # Process SNMP packet asynchronously for better throughput
    # Pass server PID to avoid process identity issues
    server_pid = self()

    Task.start(fn ->
      handle_snmp_packet_async(server_pid, state, client_ip, client_port, packet)
    end)

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:udp_closed, socket}, %{socket: socket} = state) do
    Logger.warning("SNMP server socket closed unexpectedly")
    {:stop, :socket_closed, state}
  end

  @impl true
  def handle_info({:update_stats, stat_type}, state) do
    new_stats = update_stats(state.stats, stat_type)
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info({:update_stats, stat_type, value}, state) do
    new_stats = update_stats(state.stats, stat_type, value)
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    :gen_udp.close(state.socket)
    :ok
  end

  # Private functions

  defp handle_snmp_packet_async(server_pid, state, client_ip, client_port, packet) do
    start_time = :erlang.monotonic_time()

    # Debug: Log raw packet information
    packet_size = byte_size(packet)
    packet_hex = Base.encode16(packet)
    Logger.debug("Received SNMP packet from #{format_ip(client_ip)}:#{client_port}")
    Logger.debug("Packet size: #{packet_size} bytes")
    Logger.debug("Packet hex: #{packet_hex}")

    try do
      case PDU.decode_message(packet) do
        {:ok, message} ->
          Logger.debug("Decoded SNMP message: #{inspect(message)}")

          if validate_community(message, state.community) do
            Logger.debug("Processing PDU: #{inspect(message.pdu)}")
            # Create a complete PDU structure with version and community for handlers
            # Convert varbinds from {oid, type, value} to {oid, value} format for backward compatibility
            variable_bindings =
              case message.pdu.varbinds do
                varbinds when is_list(varbinds) ->
                  Enum.map(varbinds, fn
                    {oid, _type, value} -> {oid, value}
                    {oid, value} -> {oid, value}
                  end)
              end

            complete_pdu = %{
              # Convert message version to PDU version: 0->1 (SNMPv1), 1->2 (SNMPv2c)
              version: message.version + 1,
              community: message.community,
              type: message.pdu.type,
              request_id: message.pdu.request_id,
              error_status: message.pdu[:error_status] || 0,
              error_index: message.pdu[:error_index] || 0,
              varbinds: variable_bindings,
              max_repetitions: message.pdu[:max_repetitions] || 0,
              non_repeaters: message.pdu[:non_repeaters] || 0
            }

            process_snmp_request_async(server_pid, state, client_ip, client_port, complete_pdu)
          else
            Logger.warning("Invalid community string from #{format_ip(client_ip)}:#{client_port}")
            send(server_pid, {:update_stats, :auth_failures})
          end

        {:error, reason} ->
          Logger.warning(
            "Failed to decode SNMP packet from #{format_ip(client_ip)}:#{client_port}: #{inspect(reason)}"
          )

          Logger.warning("Raw packet (#{packet_size} bytes): #{packet_hex}")
          send(server_pid, {:update_stats, :decode_errors})
      end
    rescue
      error ->
        Logger.error("Error processing SNMP packet: #{inspect(error)}")
        Logger.error("Stacktrace: #{inspect(__STACKTRACE__)}")
        send(server_pid, {:update_stats, :processing_errors})
    end

    # Track processing time
    end_time = :erlang.monotonic_time()
    processing_time = :erlang.convert_time_unit(end_time - start_time, :native, :microsecond)
    send(server_pid, {:update_stats, :processing_times, processing_time})
  end

  defp process_snmp_request_async(server_pid, state, client_ip, client_port, pdu) do
    case state.device_handler do
      nil ->
        # No device handler - send generic error
        # genErr
        error_response = PDU.create_error_response(pdu, 5, 0)
        send_response_async(state, client_ip, client_port, error_response)
        send(server_pid, {:update_stats, :error_responses})

      handler when is_function(handler, 2) ->
        # Function handler
        case handler.(pdu, %{client_ip: client_ip, client_port: client_port}) do
          {:ok, response_pdu} ->
            Logger.debug("Device returned response: #{inspect(response_pdu)}")
            Logger.debug("Server: Device returned response PDU: #{inspect(response_pdu)}")
            send_response_async(state, client_ip, client_port, response_pdu)
            send(server_pid, {:update_stats, :successful_responses})

          %{type: _type} = response_pdu when is_map(response_pdu) ->
            # Direct PDU response from walk processors
            Logger.debug("Device returned direct response: #{inspect(response_pdu)}")
            Logger.debug("Server: Device returned direct response PDU: #{inspect(response_pdu)}")
            send_response_async(state, client_ip, client_port, response_pdu)
            send(server_pid, {:update_stats, :successful_responses})

          {:error, error_status} ->
            error_response = PDU.create_error_response(pdu, error_status, 0)
            send_response_async(state, client_ip, client_port, error_response)
            send(server_pid, {:update_stats, :error_responses})
        end

      {module, function} ->
        # Module/function handler
        case apply(module, function, [pdu, %{client_ip: client_ip, client_port: client_port}]) do
          {:ok, response_pdu} ->
            Logger.debug("Device returned response: #{inspect(response_pdu)}")
            Logger.debug("Server: Device returned response PDU: #{inspect(response_pdu)}")
            send_response_async(state, client_ip, client_port, response_pdu)
            send(server_pid, {:update_stats, :successful_responses})

          {:error, error_status} ->
            error_response = PDU.create_error_response(pdu, error_status, 0)
            send_response_async(state, client_ip, client_port, error_response)
            send(server_pid, {:update_stats, :error_responses})
        end

      pid when is_pid(pid) ->
        # GenServer handler (e.g., Device process)
        # Check if process is alive before attempting to call it
        if Process.alive?(pid) do
          try do
            Logger.debug("Calling device handler with PDU: #{inspect(pdu)}")

            case GenServer.call(
                   pid,
                   {:handle_snmp, pdu, %{client_ip: client_ip, client_port: client_port}},
                   5000
                 ) do
              {:ok, response_pdu} ->
                Logger.debug("Device returned response: #{inspect(response_pdu)}")
                Logger.debug("Server: Device returned response PDU: #{inspect(response_pdu)}")
                send_response_async(state, client_ip, client_port, response_pdu)
                send(server_pid, {:update_stats, :successful_responses})

              {:error, error_status} ->
                Logger.debug("Device returned error: #{inspect(error_status)}")
                error_response = PDU.create_error_response(pdu, error_status, 0)
                send_response_async(state, client_ip, client_port, error_response)
                send(server_pid, {:update_stats, :error_responses})
            end
          catch
            :exit, {:timeout, _} ->
              Logger.warning(
                "Device process #{inspect(pid)} timed out responding to SNMP request"
              )

              # genErr
              error_response = PDU.create_error_response(pdu, 5, 0)
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :timeout_errors})

            :exit, {:noproc, _} ->
              # Device process has died between alive check and call
              Logger.warning("Device process #{inspect(pid)} died during SNMP request")
              # genErr
              error_response = PDU.create_error_response(pdu, 5, 0)
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :dead_process_errors})

            :exit, {:normal, _} ->
              # Device process shut down normally
              Logger.info("Device process #{inspect(pid)} shut down normally during request")
              # genErr
              error_response = PDU.create_error_response(pdu, 5, 0)
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :dead_process_errors})

            :exit, {:shutdown, _} ->
              # Device process was shutdown
              Logger.info("Device process #{inspect(pid)} was shutdown during request")
              # genErr
              error_response = PDU.create_error_response(pdu, 5, 0)
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :dead_process_errors})

            :exit, reason ->
              # Other exit reasons
              Logger.warning(
                "Device process #{inspect(pid)} exited with reason: #{inspect(reason)}"
              )

              # genErr
              error_response = PDU.create_error_response(pdu, 5, 0)
              send_response_async(state, client_ip, client_port, error_response)
              send(server_pid, {:update_stats, :error_responses})
          end
        else
          # Process is not alive
          Logger.warning("Device process #{inspect(pid)} is not alive")
          # genErr
          error_response = PDU.create_error_response(pdu, 5, 0)
          send_response_async(state, client_ip, client_port, error_response)
          send(server_pid, {:update_stats, :dead_process_errors})
        end
    end
  end

  defp send_response_async(state, client_ip, client_port, response_pdu) do
    community = Map.get(response_pdu, :community, "public")
    version = Map.get(response_pdu, :version, 0)

    # Normalize varbinds for SNMP library compatibility
    normalized_pdu = normalize_varbinds(response_pdu)

    # Debug logging
    Logger.debug("Response PDU before encoding: #{inspect(normalized_pdu)}")
    Logger.debug("Server: Response PDU before encoding: #{inspect(normalized_pdu)}")

    response_message =
      case version do
        1 ->
          # PDU version 1 = SNMPv1 -> message version 0
          PDU.build_message(normalized_pdu, community, :v1)

        2 ->
          # PDU version 2 = SNMPv2c -> message version 1
          PDU.build_message(normalized_pdu, community, :v2c)

        _ ->
          # Default to SNMPv1 for version 0 or unknown versions
          PDU.build_message(normalized_pdu, community, :v1)
      end

    Logger.debug("Response message before encoding: #{inspect(response_message)}")
    Logger.debug("Server: Response message before encoding: #{inspect(response_message)}")

    case PDU.encode_message(response_message) do
      {:ok, encoded_packet} ->
        Logger.debug("Server: Successfully encoded packet, sending response")
        :gen_udp.send(state.socket, client_ip, client_port, encoded_packet)

      {:error, reason} ->
        Logger.error("Failed to encode SNMP response: #{inspect(reason)}")
        Logger.error("Response message that failed: #{inspect(response_message)}")
    end
  end

  defp validate_community(message, expected_community) do
    message.community == expected_community
  end

  defp format_ip({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  defp format_ip(ip) when is_binary(ip) do
    ip
  end

  defp init_stats do
    %{
      packets_received: 0,
      packets_sent: 0,
      successful_responses: 0,
      error_responses: 0,
      auth_failures: 0,
      decode_errors: 0,
      encode_errors: 0,
      send_errors: 0,
      processing_errors: 0,
      timeout_errors: 0,
      dead_process_errors: 0,
      processing_times: [],
      started_at: DateTime.utc_now()
    }
  end

  defp update_stats(stats, :processing_times, time) do
    # Keep only the last 1000 processing times for memory efficiency
    times = [time | stats.processing_times] |> Enum.take(1000)
    Map.put(stats, :processing_times, times)
  end

  defp update_stats(stats, counter_key, _value) when is_atom(counter_key) do
    Map.update(stats, counter_key, 1, &(&1 + 1))
  end

  defp update_stats(stats, counter_key) when is_atom(counter_key) do
    Map.update(stats, counter_key, 1, &(&1 + 1))
  end

  # Normalize varbinds for SNMP library compatibility
  defp normalize_varbinds(pdu) do
    normalized_varbinds =
      Enum.map(pdu.varbinds || [], fn
        # Handle 2-tuple format {oid, :null} - normalize OID
        {oid, :null} ->
          normalized_oid = normalize_oid(oid)
          {normalized_oid, :null, nil}

        # Handle 2-tuple format {oid, string_value} - assume octet_string type
        {oid, value} when is_binary(value) ->
          normalized_oid = normalize_oid(oid)
          {normalized_oid, :octet_string, value}

        # Handle 2-tuple format with integer -> INTEGER
        {oid, value} when is_integer(value) ->
          normalized_oid = normalize_oid(oid)
          {normalized_oid, :integer, value}

        # Handle 2-tuple ip tuple -> IpAddress (4-octet binary)
        {oid, {a, b, c, d} = ip}
            when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) ->
          normalized_oid = normalize_oid(oid)
          case validate_ip_tuple(ip) do
            :ok -> {normalized_oid, :ip_address, <<a, b, c, d>>}
            {:error, _} -> {normalized_oid, :ip_address, <<0, 0, 0, 0>>}
          end

        # Handle 3-tuple format {oid, type, value}
        {oid, type, value} ->
          normalized_oid = normalize_oid(oid)
          normalized_value = normalize_varbind_value(type, value)
          {normalized_oid, type, normalized_value}
      end)

    Map.put(pdu, :varbinds, normalized_varbinds)
  end

  # Convert string OIDs to integer lists
  defp normalize_oid(oid) when is_binary(oid) do
    OidHandler.string_to_oid_list(oid)
  end

  defp normalize_oid(oid) when is_list(oid), do: oid
  defp normalize_oid(oid), do: oid

  # Convert varbind values to formats expected by snmp_lib
  defp normalize_varbind_value(:object_identifier, value) when is_binary(value) do
    # Convert string OID to OID list, handling both dotted notation and named OIDs
    case parse_oid_string(value) do
      {:ok, oid_list} -> oid_list
      # Fallback to original function
      {:error, _} -> OidHandler.string_to_oid_list(value)
    end
  end

  # Normalize IpAddress value from string or tuple to 4-octet binary
  defp normalize_varbind_value(:ip_address, value) when is_binary(value) do
    parts = String.split(value, ".")
    case parts do
      [a, b, c, d] ->
        with {ai, ""} <- Integer.parse(a), true <- ai in 0..255,
             {bi, ""} <- Integer.parse(b), true <- bi in 0..255,
             {ci, ""} <- Integer.parse(c), true <- ci in 0..255,
             {di, ""} <- Integer.parse(d), true <- di in 0..255 do
          <<ai, bi, ci, di>>
        else
          _ -> <<0, 0, 0, 0>>
        end
      _ -> <<0, 0, 0, 0>>
    end
  end

  defp normalize_varbind_value(:ip_address, {a, b, c, d} = ip)
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    case validate_ip_tuple(ip) do
      :ok -> <<a, b, c, d>>
      {:error, _} -> <<0, 0, 0, 0>>
    end
  end

  defp normalize_varbind_value(:end_of_mib_view, {:end_of_mib_view, nil}) do
    # Convert {:end_of_mib_view, nil} to just nil
    nil
  end

  defp normalize_varbind_value(:end_of_mib_view, _value) do
    # Any other end_of_mib_view value should be nil
    nil
  end

  defp normalize_varbind_value(_type, value) do
    # For all other types, return value as-is
    value
  end

  defp validate_ip_tuple({a, b, c, d}) do
    if a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 do
      :ok
    else
      {:error, :invalid_ip}
    end
  end

  # Simple OID string parser - converts dotted notation to list
  defp parse_oid_string(oid_string) when is_binary(oid_string) do
    try do
      cond do
        # Handle specific known OID mappings
        String.contains?(oid_string, "SNMPv2-SMI::enterprises.4491.2.4.1") ->
          {:ok, [1, 3, 6, 1, 4, 1, 4491, 2, 4, 1]}

        # Handle dotted notation (1.3.6.1.2.1.1.1.0)
        String.contains?(oid_string, ".") and String.match?(oid_string, ~r/^\d+(\.\d+)*$/) ->
          parts = String.split(oid_string, ".")
          oid_list = Enum.map(parts, &String.to_integer/1)
          {:ok, oid_list}

        # For other named OIDs, use a default mapping
        true ->
          {:ok, [1, 3, 6, 1, 4, 1, 4491, 2, 4, 1]}
      end
    rescue
      _ -> {:error, :invalid_oid}
    end
  end
end
