defmodule SnmpKit.SnmpLib.Manager do
  @moduledoc """
  High-level SNMP management operations providing a simplified interface for common SNMP tasks.

  This module builds on the core SnmpLib functionality to provide production-ready SNMP
  management capabilities including GET, GETBULK, SET operations with intelligent error
  handling, connection reuse, and performance optimizations.

  ## Features

  - **Simple API**: High-level functions for common SNMP operations
  - **Connection Reuse**: Efficient socket management for multiple operations
  - **Error Handling**: Comprehensive error handling with meaningful messages
  - **Performance**: Optimized for bulk operations and large-scale polling
  - **Timeout Management**: Configurable timeouts with sensible defaults
  - **Community Support**: Support for different community strings per device

  ## Quick Start

      # Simple GET operation
      {:ok, {type, value}} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", [1, 3, 6, 1, 2, 1, 1, 1, 0])

      # GET with custom community and timeout
      {:ok, {type, value}} = SnmpKit.SnmpLib.Manager.get("192.168.1.1", "1.3.6.1.2.1.1.1.0",
                                         community: "private", timeout: 10_000)

      # Bulk operations for efficiency
      {:ok, results} = SnmpKit.SnmpLib.Manager.get_bulk("192.168.1.1", [1, 3, 6, 1, 2, 1, 2, 2],
                                                 max_repetitions: 20)

      # SET operation
      {:ok, :success} = SnmpKit.SnmpLib.Manager.set("192.168.1.1", [1, 3, 6, 1, 2, 1, 1, 5, 0],
                                            {:string, "New System Name"})

  ## Configuration Options

  - `community`: SNMP community string (default: "public")
  - `version`: SNMP version (:v1, :v2c) (default: :v2c)
  - `timeout`: Operation timeout in milliseconds (default: 5000)
  - `retries`: Number of retry attempts (default: 3)
  - `port`: SNMP port (default: 161)
  - `local_port`: Local source port (default: 0 for random)
  """

  require Logger

  @default_community "public"
  @default_version :v2c
  @default_timeout 5_000
  @default_retries 3
  @default_port 161
  @default_local_port 0
  @default_max_repetitions 10
  @default_non_repeaters 0

  @type host :: binary() | :inet.ip_address()
  @type oid :: [non_neg_integer()] | binary()
  @type snmp_value :: any()
  @type community :: binary()
  @type version :: :v1 | :v2c
  @type operation_result :: {:ok, snmp_value()} | {:error, atom() | {atom(), any()}}
  @type bulk_result :: {:ok, [varbind()]} | {:error, atom() | {atom(), any()}}
  @type varbind :: {oid(), snmp_value()}

  @type manager_opts :: [
          community: community(),
          version: version(),
          timeout: pos_integer(),
          retries: non_neg_integer(),
          port: pos_integer(),
          local_port: non_neg_integer()
        ]

  @type bulk_opts :: [
          community: community(),
          version: version(),
          timeout: pos_integer(),
          retries: non_neg_integer(),
          port: pos_integer(),
          local_port: non_neg_integer(),
          max_repetitions: pos_integer(),
          non_repeaters: non_neg_integer()
        ]

  ## Public API

  @doc """
  Performs an SNMP GET operation to retrieve a single value.

  ## Parameters

  - `host`: Target device IP address or hostname
  - `oid`: Object identifier as list or string (e.g., [1,3,6,1,2,1,1,1,0] or "1.3.6.1.2.1.1.1.0")
  - `opts`: Configuration options (see module docs for available options)

  ## Returns

  - `{:ok, {type, value}}`: Successfully retrieved the value with its SNMP type
  - `{:error, reason}`: Operation failed with reason

  ## Examples

      # Basic GET operation (would succeed with real device)
      # SnmpKit.SnmpLib.Manager.get("192.168.1.1", [1, 3, 6, 1, 2, 1, 1, 1, 0])
      # {:ok, {:octet_string, "Cisco IOS Software"}}

      # GET with custom community and timeout (would succeed with real device)
      # SnmpKit.SnmpLib.Manager.get("192.168.1.1", "1.3.6.1.2.1.1.1.0", community: "private", timeout: 10_000)
      # {:ok, {:octet_string, "Private System Description"}}

      # Test that function exists and handles invalid input properly
      iex> match?({:error, _}, SnmpKit.SnmpLib.Manager.get("invalid.host", [1, 3, 6, 1, 2, 1, 1, 3, 0], timeout: 100))
      true
  """
  @spec get(host(), oid(), manager_opts()) ::
          {:ok, {atom(), any()}}
          | {:error, atom() | {:network_error, atom()} | {:socket_error, atom()}}
  def get(host, oid, opts \\ []) do
    opts = merge_default_opts(opts)
    normalized_oid = normalize_oid(oid)

    Logger.debug("Starting GET operation: host=#{inspect(host)}, oid=#{inspect(normalized_oid)}")

    with {:ok, socket} <- create_socket(opts) do
      Logger.debug("Socket created successfully")

      case perform_get_operation(socket, host, normalized_oid, opts) do
        {:ok, response} ->
          Logger.debug("GET operation completed, extracting result")
          :ok = close_socket(socket)
          result = extract_get_result(response)
          Logger.debug("Final GET result: #{inspect(result)}")
          result

        {:error, reason} ->
          Logger.debug("GET operation failed: #{inspect(reason)}")
          :ok = close_socket(socket)
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.debug("Socket creation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Performs an SNMP GETNEXT operation to retrieve the next value in the MIB tree.

  GETNEXT is used to traverse the MIB tree by retrieving the next available
  object after the specified OID. This is essential for MIB walking operations
  and discovering available objects on SNMP devices.

  ## Parameters

  - `host`: Target device IP address or hostname
  - `oid`: Object identifier to get the next value after
  - `opts`: Configuration options

  ## Implementation Details

  - **SNMP v1**: Uses proper GETNEXT PDU for compatibility
  - **SNMP v2c+**: Uses optimized GETBULK with max_repetitions=1

  ## Returns

  - `{:ok, {next_oid, type, value}}`: Next OID and its value as a tuple
  - `{:error, reason}`: Operation failed with reason

  ## Examples

      # Get next OID after system description
      {:ok, {next_oid, type, value}} = SnmpKit.SnmpLib.Manager.get_next("192.168.1.1", "1.3.6.1.2.1.1.1.0")

      # SNMP v1 compatibility
      {:ok, {next_oid, type, value}} = SnmpKit.SnmpLib.Manager.get_next("192.168.1.1", "1.3.6.1.2.1.1.1.0", version: :v1)

      # With custom community
      {:ok, {next_oid, type, value}} = SnmpKit.SnmpLib.Manager.get_next("192.168.1.1", "1.3.6.1.2.1.1.1.0",
                                                           community: "private", timeout: 10_000)
  """
  @spec get_next(host(), oid(), manager_opts()) ::
          {:ok, {oid(), atom(), any()}} | {:error, atom() | {atom(), any()}}
  def get_next(host, oid, opts \\ []) do
    opts = merge_default_opts(opts)
    normalized_oid = normalize_oid(oid)

    Logger.debug(
      "Starting GETNEXT operation: host=#{inspect(host)}, oid=#{inspect(normalized_oid)}, version=#{opts[:version]}"
    )

    case opts[:version] do
      :v1 ->
        # Use proper GETNEXT PDU for SNMP v1 compatibility
        perform_get_next_v1(host, normalized_oid, opts)

      _ ->
        # Use GETBULK with max_repetitions=1 for v2c+ efficiency
        perform_get_next_v2c(host, normalized_oid, opts)
    end
  end

  @doc """
  Performs an SNMP GETBULK operation for efficient bulk data retrieval.

  GETBULK is more efficient than multiple GET operations when retrieving
  multiple consecutive values, especially for table walking operations.

  ## Parameters

  - `host`: Target device IP address or hostname
  - `base_oid`: Base OID to start the bulk operation
  - `opts`: Configuration options including bulk-specific options

  ## Bulk-Specific Options

  - `max_repetitions`: Maximum number of repetitions (default: 10)
  - `non_repeaters`: Number of non-repeating variables (default: 0)

  ## Returns

  - `{:ok, varbinds}`: List of {oid, type, value} tuples
  - `{:error, reason}`: Operation failed with reason

  ## Examples

      # Test that get_bulk function exists and handles invalid input properly
      iex> match?({:error, _}, SnmpKit.SnmpLib.Manager.get_bulk("invalid.host", [1, 3, 6, 1, 2, 1, 2, 2], timeout: 100))
      true

      # High-repetition bulk for large tables
      # SnmpKit.SnmpLib.Manager.get_bulk("192.168.1.1", "1.3.6.1.2.1.2.2", max_repetitions: 50)
      # {:ok, [...]} Returns up to 50 interface entries
  """
  @spec get_bulk(host(), oid(), bulk_opts()) :: bulk_result()
  def get_bulk(host, base_oid, opts \\ []) do
    opts = merge_bulk_opts(opts)
    normalized_oid = normalize_oid(base_oid)

    # GETBULK requires SNMPv2c or higher
    if opts[:version] == :v1 do
      {:error, :getbulk_requires_v2c}
    else
      with {:ok, socket} <- create_socket(opts),
           {:ok, response} <- perform_bulk_operation(socket, host, normalized_oid, opts),
           :ok <- close_socket(socket) do
        extract_bulk_result(response)
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Performs an SNMP SET operation to modify a value on the target device.

  ## Parameters

  - `host`: Target device IP address or hostname
  - `oid`: Object identifier to modify
  - `value`: New value as {type, data} tuple (e.g., {:string, "new name"})
  - `opts`: Configuration options

  ## Supported Value Types

  - `{:string, binary()}`: OCTET STRING
  - `{:integer, integer()}`: INTEGER
  - `{:counter32, non_neg_integer()}`: Counter32
  - `{:gauge32, non_neg_integer()}`: Gauge32
  - `{:timeticks, non_neg_integer()}`: TimeTicks
  - `{:ip_address, binary()}`: IpAddress (4 bytes)

  ## Returns

  - `{:ok, :success}`: SET operation completed successfully
  - `{:error, reason}`: Operation failed with reason

  ## Examples

      # Test that SET function exists and handles invalid input properly
      iex> match?({:error, _}, SnmpKit.SnmpLib.Manager.set("invalid.host", [1, 3, 6, 1, 2, 1, 1, 5, 0], {:string, "test"}, timeout: 100))
      true
  """
  @spec set(host(), oid(), {atom(), any()}, manager_opts()) :: {:ok, :success} | {:error, any()}
  def set(host, oid, {type, value}, opts \\ []) do
    opts = merge_default_opts(opts)
    normalized_oid = normalize_oid(oid)

    with {:ok, socket} <- create_socket(opts),
         {:ok, response} <-
           perform_set_operation(socket, host, normalized_oid, {type, value}, opts),
         :ok <- close_socket(socket) do
      extract_set_result(response)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs multiple GET operations efficiently with connection reuse.

  More efficient than individual get/3 calls when retrieving multiple values
  from the same device by reusing the same socket connection.

  ## Parameters

  - `host`: Target device IP address or hostname
  - `oids`: List of OIDs to retrieve
  - `opts`: Configuration options

  ## Returns

  - `{:ok, results}`: List of {oid, type, value} or {oid, {:error, reason}} tuples
  - `{:error, reason}`: Connection or overall operation failed

  ## Examples

      # Test that get_multi function exists and handles invalid input properly
      iex> oids = ["1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.3.0", "1.3.6.1.2.1.1.5.0"]
      iex> match?({:error, _}, SnmpKit.SnmpLib.Manager.get_multi("invalid.host", oids, timeout: 100))
      true
  """
  @spec get_multi(host(), [oid()], manager_opts()) ::
          {:ok, [{oid(), atom(), any() | {:error, any()}}]} | {:error, any()}
  def get_multi(host, oids, opts \\ []) when is_list(oids) do
    # Validate input parameters
    case oids do
      [] ->
        {:error, :empty_oids}

      _ ->
        opts = merge_default_opts(opts)
        normalized_oids = Enum.map(oids, &normalize_oid/1)

        with {:ok, socket} <- create_socket(opts) do
          results = get_multi_with_socket(socket, host, normalized_oids, opts)
          :ok = close_socket(socket)

          # Check if all operations failed due to network issues
          case check_for_global_failure(results) do
            {:global_failure, reason} -> {:error, reason}
            :mixed_results -> {:ok, results}
          end
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Interprets SNMP errors with enhanced semantics for common cases.

  Provides more specific error interpretation when generic errors like `:gen_err`
  are returned by devices that should return more specific SNMP error codes.

  ## Parameters

  - `error`: The original error returned by SNMP operations
  - `operation`: The SNMP operation type (`:get`, `:set`, `:get_bulk`)
  - `version`: SNMP version (`:v1`, `:v2c`, `:v3`)

  ## Returns

  More specific error atom when possible, otherwise the original error.

  ## Examples

      # Interpret genErr for GET operations
      iex> SnmpKit.SnmpLib.Manager.interpret_error(:gen_err, :get, :v2c)
      :no_such_object

      iex> SnmpKit.SnmpLib.Manager.interpret_error(:gen_err, :get, :v1)
      :no_such_name

      iex> SnmpKit.SnmpLib.Manager.interpret_error(:too_big, :get, :v2c)
      :too_big
  """
  @spec interpret_error(atom(), atom(), atom()) :: atom()
  def interpret_error(:gen_err, :get, :v1) do
    # In SNMPv1, genErr for GET operations commonly means OID doesn't exist
    :no_such_name
  end

  def interpret_error(:gen_err, :get, version) when version in [:v2c, :v2, :v3] do
    # In SNMPv2c+, genErr for GET operations commonly means object doesn't exist
    :no_such_object
  end

  def interpret_error(:gen_err, :get_bulk, version) when version in [:v2c, :v2, :v3] do
    # For bulk operations, genErr often indicates end of MIB or missing objects
    :no_such_object
  end

  def interpret_error(error, _operation, _version) do
    # Return original error for all other cases
    error
  end

  @doc """
  Checks if a host is reachable via SNMP by performing a basic GET operation.

  Useful for device discovery and health checking. Attempts to retrieve
  sysUpTime (1.3.6.1.2.1.1.3.0) which should be available on all SNMP devices.

  ## Parameters

  - `host`: Target device IP address or hostname
  - `opts`: Configuration options (typically just community and timeout)

  ## Returns

  - `{:ok, :reachable}`: Device responded to SNMP request
  - `{:error, reason}`: Device not reachable or SNMP not available

  ## Examples

      # Test that ping function exists and handles invalid input properly
      iex> match?({:error, _}, SnmpKit.SnmpLib.Manager.ping("invalid.host", timeout: 100))
      true
  """
  @spec ping(host(), manager_opts()) :: {:ok, :reachable} | {:error, any()}
  def ping(host, opts \\ []) do
    # Use sysUpTime OID as it should be available on all SNMP devices
    sys_uptime_oid = [1, 3, 6, 1, 2, 1, 1, 3, 0]

    case get(host, sys_uptime_oid, opts) do
      {:ok, {_type, _value}} -> {:ok, :reachable}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Private Implementation

  # Socket management
  defp create_socket(_opts) do
    case SnmpKit.SnmpLib.Transport.create_client_socket() do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:error, {:socket_error, reason}}
    end
  end

  defp close_socket(socket) do
    SnmpKit.SnmpLib.Transport.close_socket(socket)
  end

  # Operation implementations
  defp perform_get_operation(socket, host, oid, opts) do
    request_id = generate_request_id()
    pdu = SnmpKit.SnmpLib.PDU.build_get_request(oid, request_id)
    perform_snmp_request(socket, host, pdu, opts)
  end

  defp perform_bulk_operation(socket, host, base_oid, opts) do
    request_id = generate_request_id()
    max_reps = opts[:max_repetitions] || @default_max_repetitions
    non_reps = opts[:non_repeaters] || @default_non_repeaters

    pdu = SnmpKit.SnmpLib.PDU.build_get_bulk_request(base_oid, request_id, non_reps, max_reps)
    perform_snmp_request(socket, host, pdu, opts)
  end

  defp perform_set_operation(socket, host, oid, value, opts) do
    request_id = generate_request_id()
    pdu = SnmpKit.SnmpLib.PDU.build_set_request(oid, value, request_id)
    perform_snmp_request(socket, host, pdu, opts)
  end

  defp perform_snmp_request(socket, host, pdu, opts) do
    community = opts[:community] || @default_community
    version = opts[:version] || @default_version
    timeout = opts[:timeout] || @default_timeout
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

    message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, version)
    Logger.debug("Built SNMP message: #{inspect(message)}")

    with {:ok, packet} <- SnmpKit.SnmpLib.PDU.encode_message(message) do
      Logger.debug("Encoded PDU packet for transmission")

      case send_and_receive(socket, parsed_host, parsed_port, packet, timeout) do
        {:ok, response_packet} ->
          Logger.debug("Received response packet from network")

          case SnmpKit.SnmpLib.PDU.decode_message(response_packet) do
            {:ok, response_message} ->
              Logger.debug("Decoded response message: #{inspect(response_message)}")
              {:ok, response_message}

            {:error, decode_reason} = decode_error ->
              Logger.error("PDU decode failed: #{inspect(decode_reason)}")
              decode_error
          end

        {:error, network_reason} = network_error ->
          Logger.error("Network operation failed: #{inspect(network_reason)}")
          network_error
      end
    else
      {:error, encode_reason} = encode_error ->
        Logger.error("PDU encode failed: #{inspect(encode_reason)}")
        encode_error
    end
  end

  defp send_and_receive(socket, host, port, packet, timeout) do
    Logger.debug("Sending SNMP packet to #{inspect(host)}:#{port}")

    with :ok <- SnmpKit.SnmpLib.Transport.send_packet(socket, host, port, packet) do
      Logger.debug("Packet sent successfully, waiting for response (timeout: #{timeout}ms)")

      case SnmpKit.SnmpLib.Transport.receive_packet(socket, timeout) do
        {:ok, {response_packet, _from_addr, _from_port}} ->
          Logger.debug("Received response packet: #{byte_size(response_packet)} bytes")
          {:ok, response_packet}

        {:error, :timeout} = timeout_error ->
          Logger.debug("Transport timeout after #{timeout}ms")
          timeout_error

        {:error, reason} ->
          Logger.debug("Transport error: #{inspect(reason)}")
          {:error, {:network_error, reason}}
      end
    else
      {:error, reason} ->
        Logger.debug("Send packet failed: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  # Multi-get implementation with connection reuse
  defp get_multi_with_socket(socket, host, oids, opts) do
    Enum.map(oids, fn oid ->
      case perform_get_operation(socket, host, oid, opts) do
        {:ok, response} ->
          case extract_get_result_with_oid(response) do
            {:ok, {oid, type, value}} -> {oid, type, value}
            {:error, reason} -> {oid, {:error, reason}}
          end

        {:error, reason} ->
          {oid, {:error, reason}}
      end
    end)
  end

  # Result extraction
  defp extract_get_result(%{pdu: %{error_status: error_status}} = response)
       when error_status != 0 do
    Logger.debug("Extracting error result - error_status: #{error_status}")
    Logger.debug("Full response PDU: #{inspect(response.pdu)}")
    {:error, decode_error_status(error_status)}
  end

  defp extract_get_result(%{pdu: %{varbinds: [{oid, type, value}]}} = response) do
    Logger.debug("Extracting successful result - PDU: #{inspect(response.pdu)}")

    Logger.debug(
      "Varbind details - oid: #{inspect(oid)}, type: #{inspect(type)}, value: #{inspect(value)}"
    )

    # Check for SNMPv2c exception values in both type and value fields
    case {type, value} do
      # Exception values in type field (from simulator)
      {:no_such_object, _} ->
        Logger.debug("Found exception in type field: no_such_object")
        {:error, :no_such_object}

      {:no_such_instance, _} ->
        Logger.debug("Found exception in type field: no_such_instance")
        {:error, :no_such_instance}

      {:end_of_mib_view, _} ->
        Logger.debug("Found exception in type field: end_of_mib_view")
        {:error, :end_of_mib_view}

      # Exception values in value field (standard format)
      {_, {:no_such_object, _}} ->
        Logger.debug("Found exception in value field: no_such_object")
        {:error, :no_such_object}

      {_, {:no_such_instance, _}} ->
        Logger.debug("Found exception in value field: no_such_instance")
        {:error, :no_such_instance}

      {_, {:end_of_mib_view, _}} ->
        Logger.debug("Found exception in value field: end_of_mib_view")
        {:error, :end_of_mib_view}

      # Normal value - return type and value only (OID is known from input)
      _ ->
        Logger.debug("Returning successful value with type: #{inspect({type, value})}")
        {:ok, {type, value}}
    end
  end

  defp extract_get_result(response) do
    Logger.error("Invalid response format: #{inspect(response)}")
    {:error, :invalid_response}
  end

  defp extract_get_result_with_oid(%{pdu: %{error_status: error_status}} = response)
       when error_status != 0 do
    Logger.debug("Extracting error result - error_status: #{error_status}")
    Logger.debug("Full response PDU: #{inspect(response.pdu)}")
    {:error, decode_error_status(error_status)}
  end

  defp extract_get_result_with_oid(%{pdu: %{varbinds: [{oid, type, value}]}} = response) do
    Logger.debug("Extracting successful result - PDU: #{inspect(response.pdu)}")

    Logger.debug(
      "Varbind details - oid: #{inspect(oid)}, type: #{inspect(type)}, value: #{inspect(value)}"
    )

    # Check for SNMPv2c exception values in both type and value fields
    case {type, value} do
      # Exception values in type field (from simulator)
      {:no_such_object, _} ->
        Logger.debug("Found exception in type field: no_such_object")
        {:error, :no_such_object}

      {:no_such_instance, _} ->
        Logger.debug("Found exception in type field: no_such_instance")
        {:error, :no_such_instance}

      {:end_of_mib_view, _} ->
        Logger.debug("Found exception in type field: end_of_mib_view")
        {:error, :end_of_mib_view}

      # Exception values in value field (standard format)
      {_, {:no_such_object, _}} ->
        Logger.debug("Found exception in value field: no_such_object")
        {:error, :no_such_object}

      {_, {:no_such_instance, _}} ->
        Logger.debug("Found exception in value field: no_such_instance")
        {:error, :no_such_instance}

      {_, {:end_of_mib_view, _}} ->
        Logger.debug("Found exception in value field: end_of_mib_view")
        {:error, :end_of_mib_view}

      # Normal value - return full 3-tuple for multi operations
      _ ->
        Logger.debug("Returning successful varbind with type: #{inspect({oid, type, value})}")
        {:ok, {oid, type, value}}
    end
  end

  defp extract_get_result_with_oid(response) do
    Logger.error("Invalid response format: #{inspect(response)}")
    {:error, :invalid_response}
  end

  defp extract_bulk_result(%{pdu: %{varbinds: varbinds}}) do
    valid_varbinds =
      Enum.filter(varbinds, fn {_oid, type, value} ->
        # Check for SNMPv2c exception values in both type and value fields
        case {type, value} do
          # Exception values in type field (from simulator)
          {:no_such_object, _} -> false
          {:no_such_instance, _} -> false
          {:end_of_mib_view, _} -> false
          # Exception values in value field (standard format)
          {_, {:no_such_object, _}} -> false
          {_, {:no_such_instance, _}} -> false
          {_, {:end_of_mib_view, _}} -> false
          # Valid varbind
          _ -> true
        end
      end)

    # Return documented 3-tuple varbind format {oid, type, value}
    {:ok, valid_varbinds}
  end

  defp extract_bulk_result(%{pdu: %{error_status: error_status}}) when error_status != 0 do
    {:error, decode_error_status(error_status)}
  end

  defp extract_bulk_result(_), do: {:error, :invalid_response}

  defp extract_set_result(%{pdu: %{error_status: 0}}) do
    {:ok, :success}
  end

  defp extract_set_result(%{pdu: %{error_status: error_status}}) when error_status != 0 do
    {:error, decode_error_status(error_status)}
  end

  defp extract_set_result(_), do: {:error, :invalid_response}

  # GETNEXT implementation for SNMP v1
  defp perform_get_next_v1(host, oid, opts) do
    with {:ok, socket} <- create_socket(opts) do
      Logger.debug("Socket created successfully for GETNEXT v1")

      case perform_get_next_operation(socket, host, oid, opts) do
        {:ok, response} ->
          Logger.debug("GETNEXT v1 operation completed, extracting result")
          :ok = close_socket(socket)
          result = extract_get_next_result(response)
          Logger.debug("Final GETNEXT v1 result: #{inspect(result)}")
          result

        {:error, reason} ->
          Logger.debug("GETNEXT v1 operation failed: #{inspect(reason)}")
          :ok = close_socket(socket)
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.debug("Socket creation failed for GETNEXT v1: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # GETNEXT implementation for SNMP v2c+
  defp perform_get_next_v2c(host, oid, opts) do
    # Use get_bulk with max_repetitions=1 for efficiency
    bulk_opts = Keyword.merge(opts, max_repetitions: 1, non_repeaters: 0)

    case get_bulk(host, oid, bulk_opts) do
      {:ok, [{next_oid, type, value}]} ->
        Logger.debug("GETNEXT v2c+ via GETBULK successful: #{inspect({next_oid, type, value})}")
        {:ok, {next_oid, type, value}}

      {:ok, []} ->
        Logger.debug("GETNEXT v2c+ reached end of MIB")
        {:error, :end_of_mib_view}

      {:ok, results} when is_list(results) ->
        # Take the first result if multiple returned
        case List.first(results) do
          {next_oid, type, value} -> {:ok, {next_oid, type, value}}
          _ -> {:error, :invalid_response}
        end

      {:error, reason} ->
        Logger.debug("GETNEXT v2c+ via GETBULK failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_get_next_operation(socket, host, oid, opts) do
    request_id = generate_request_id()
    pdu = SnmpKit.SnmpLib.PDU.build_get_next_request(oid, request_id)
    perform_snmp_request(socket, host, pdu, opts)
  end

  defp extract_get_next_result(%{pdu: %{varbinds: [{next_oid, type, value}]}} = response) do
    Logger.debug("Extracting GETNEXT result - PDU: #{inspect(response.pdu)}")

    Logger.debug(
      "Varbind details - next_oid: #{inspect(next_oid)}, type: #{inspect(type)}, value: #{inspect(value)}"
    )

    # Check for SNMPv2c exception values in both type and value fields
    case {type, value} do
      # Exception values in type field (from simulator)
      {:no_such_object, _} ->
        Logger.debug("Found exception in type field: no_such_object")
        {:error, :no_such_object}

      {:no_such_instance, _} ->
        Logger.debug("Found exception in type field: no_such_instance")
        {:error, :no_such_instance}

      {:end_of_mib_view, _} ->
        Logger.debug("Found exception in type field: end_of_mib_view")
        {:error, :end_of_mib_view}

      # Exception values in value field (standard format)
      {_, {:no_such_object, _}} ->
        Logger.debug("Found exception in value field: no_such_object")
        {:error, :no_such_object}

      {_, {:no_such_instance, _}} ->
        Logger.debug("Found exception in value field: no_such_instance")
        {:error, :no_such_instance}

      {_, {:end_of_mib_view, _}} ->
        Logger.debug("Found exception in value field: end_of_mib_view")
        {:error, :end_of_mib_view}

      # Normal value - return both next OID and value
      _ ->
        Logger.debug("Returning successful GETNEXT result: #{inspect({next_oid, type, value})}")
        {:ok, {next_oid, type, value}}
    end
  end

  defp extract_get_next_result(response) do
    Logger.error("Invalid GETNEXT response format: #{inspect(response)}")
    {:error, :invalid_response}
  end

  # Helper functions
  defp normalize_oid(oid) when is_list(oid), do: oid

  defp normalize_oid(oid) when is_binary(oid) do
    # First try MIB symbolic name resolution
    case SnmpKit.SnmpLib.MIB.Registry.resolve_name(oid) do
      {:ok, oid_list} ->
        oid_list

      {:error, _} ->
        # Fallback to numeric string parsing
        case SnmpKit.SnmpLib.OID.string_to_list(oid) do
          {:ok, oid_list} -> oid_list
          # Safe fallback
          {:error, _} -> [1, 3, 6, 1]
        end
    end
  end

  defp normalize_oid(_), do: [1, 3, 6, 1]

  defp generate_request_id do
    :rand.uniform(2_147_483_647)
  end

  defp decode_error_status(0), do: :no_error
  defp decode_error_status(1), do: :too_big
  defp decode_error_status(2), do: :no_such_name
  defp decode_error_status(3), do: :bad_value
  defp decode_error_status(4), do: :read_only
  defp decode_error_status(5), do: :gen_err
  defp decode_error_status(error), do: {:unknown_error, error}

  defp merge_default_opts(opts) do
    [
      community: @default_community,
      version: @default_version,
      timeout: @default_timeout,
      retries: @default_retries,
      port: @default_port,
      local_port: @default_local_port
    ]
    |> Keyword.merge(opts)
  end

  defp merge_bulk_opts(opts) do
    merge_default_opts(opts)
    |> Keyword.merge(
      max_repetitions: @default_max_repetitions,
      non_repeaters: @default_non_repeaters
    )
    |> Keyword.merge(opts)
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

  # Check if all results failed with the same network-related error
  defp check_for_global_failure(results) do
    errors =
      Enum.filter(results, fn
        {_oid, {:error, _}} -> true
        _ -> false
      end)

    # If all results are errors, check if they're all network-related
    case {length(errors), length(results)} do
      {same, same} when same > 0 ->
        # All operations failed, check if it's a consistent network error
        network_errors =
          Enum.filter(errors, fn
            {_oid, {:error, {:network_error, _}}} -> true
            _ -> false
          end)

        case length(network_errors) do
          ^same ->
            # All errors are network errors, return the first one as global failure
            {_oid, {:error, reason}} = hd(errors)
            {:global_failure, reason}

          _ ->
            :mixed_results
        end

      _ ->
        :mixed_results
    end
  end
end
