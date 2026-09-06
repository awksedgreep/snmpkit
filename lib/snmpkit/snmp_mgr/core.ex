defmodule SnmpKit.SnmpMgr.Core do
  @moduledoc """
  Core SNMP operations using Erlang's SNMP PDU functions directly.

  This module handles the low-level SNMP PDU encoding/decoding and UDP communication
  without requiring the heavyweight :snmpm manager process.

  ## Timeout Behavior

  All functions in this module use a single timeout parameter that controls
  the SNMP PDU timeout - how long to wait for a response to each individual
  SNMP packet sent to the target device.

  - **Default timeout**: 10 seconds (10,000 milliseconds)
  - **Timeout applies to**: Each individual SNMP PDU (GET, SET, GETBULK, etc.)
  - **Not applicable to**: Multi-PDU operations (use walk functions for those)

  For operations that may require multiple PDUs (like walking large tables),
  consider using the higher-level walk functions in `SnmpKit.SnmpMgr.Multi`
  which handle multi-PDU timeouts appropriately.
  """

  @type snmp_result :: {:ok, term()} | {:error, atom() | tuple()}
  @type target :: binary() | tuple() | map()
  @type oid :: binary() | list(non_neg_integer())
  @type opts :: keyword()

  @doc """
  Sends a GET request and returns the result in 3-tuple format.

  This function returns `{oid_string, type, value}` for consistency with
  other operations like walk, bulk, etc.
  """
  @spec send_get_request_with_type(target(), oid(), opts()) ::
          {:ok, {String.t(), atom(), any()}} | {:error, any()}
  def send_get_request_with_type(target, oid, opts \\ []) do
    SnmpKit.Telemetry.span(
      :request,
      %{operation: :get, target: target, oid: oid, version: Keyword.get(opts, :version)},
      fn -> do_send_get_request_with_type(target, oid, opts) end
    )
  end

  defp do_send_get_request_with_type(target, oid, opts) do
    {host, updated_opts} = split_target(target, opts)

    # Convert oid to proper format - always work with lists internally
    oid_parsed =
      case parse_oid(oid) do
        {:ok, oid_list} -> oid_list
        # Safe fallback
        {:error, _} -> [1, 3]
      end

    # Generate string representation only for final response
    oid_string = Enum.join(oid_parsed, ".")

    # Map options to snmp_lib format
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)

    case SnmpKit.SnmpLib.Manager.get(host, oid_parsed, snmp_lib_opts) do
      {:ok, {type, value}} ->
        {:ok, {oid_string, type, value}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves several objects from one target in a single GET PDU.

  Returns `{:ok, [{oid_string, type, value}]}` in request order. SNMPv2c
  exceptions are kept per element as the type (`:no_such_object`,
  `:no_such_instance`) with a `nil` value.
  """
  @spec send_get_varbinds(target(), [oid()], opts()) ::
          {:ok, [{String.t(), atom(), any()}]} | {:error, term()}
  def send_get_varbinds(target, oids, opts \\ []) when is_list(oids) do
    SnmpKit.Telemetry.span(
      :request,
      %{operation: :get, target: target, oid: oids, version: Keyword.get(opts, :version)},
      fn -> do_send_get_varbinds(target, oids, opts) end
    )
  end

  defp do_send_get_varbinds(target, oids, opts) do
    {host, updated_opts} = split_target(target, opts)

    with {:ok, oid_lists} <- parse_oids(oids) do
      snmp_lib_opts = map_options_to_snmp_lib(updated_opts)

      case SnmpKit.SnmpLib.Manager.get_varbinds(host, oid_lists, snmp_lib_opts) do
        {:ok, varbinds} ->
          {:ok,
           Enum.map(varbinds, fn {oid, type, value} -> {oid_to_string(oid), type, value} end)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Sets several objects on one target in a single SET PDU. `pairs` are
  `{oid, value}` with the same value forms `send_set_request/4` accepts.
  """
  @spec send_set_varbinds(target(), [{oid(), any()}], opts()) ::
          {:ok, :success} | {:error, term()}
  def send_set_varbinds(target, pairs, opts \\ []) when is_list(pairs) do
    SnmpKit.Telemetry.span(
      :request,
      %{
        operation: :set,
        target: target,
        oid: Enum.map(pairs, &elem(&1, 0)),
        version: Keyword.get(opts, :version)
      },
      fn -> do_send_set_varbinds(target, pairs, opts) end
    )
  end

  defp do_send_set_varbinds(target, pairs, opts) do
    {host, updated_opts} = split_target(target, opts)

    with {:ok, oid_lists} <- parse_oids(Enum.map(pairs, &elem(&1, 0))) do
      varbinds =
        Enum.zip_with(oid_lists, pairs, fn oid, {_, value} -> {oid, typed_set_value(value)} end)

      SnmpKit.SnmpLib.Manager.set_varbinds(host, varbinds, map_options_to_snmp_lib(updated_opts))
    end
  end

  defp parse_oids(oids) do
    Enum.reduce_while(oids, {:ok, []}, fn oid, {:ok, acc} ->
      case parse_oid(oid) do
        {:ok, list} -> {:cont, {:ok, [list | acc]}}
        {:error, reason} -> {:halt, {:error, {:invalid_oid, oid, reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp oid_to_string(oid) when is_list(oid), do: Enum.join(oid, ".")
  defp oid_to_string(oid), do: to_string(oid)

  @doc """
  Sends a GETNEXT request to retrieve the next OID in the MIB tree.

  Now uses the proper SnmpKit.SnmpLib.Manager.get_next/3 function which handles
  version-specific logic (GETNEXT for v1, GETBULK for v2c+) correctly.
  """
  @spec send_get_next_request(target(), oid(), opts()) :: snmp_result()
  def send_get_next_request(target, oid, opts \\ []) do
    SnmpKit.Telemetry.span(
      :request,
      %{operation: :get_next, target: target, oid: oid, version: Keyword.get(opts, :version)},
      fn -> do_send_get_next_request(target, oid, opts) end
    )
  end

  defp do_send_get_next_request(target, oid, opts) do
    {host, updated_opts} = split_target(target, opts)

    # Convert oid to proper format
    oid_parsed =
      case parse_oid(oid) do
        {:ok, oid_list} -> oid_list
        {:error, _} -> oid
      end

    # Map options to snmp_lib format
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)

    # Use the new SnmpKit.SnmpLib.Manager.get_next function which properly handles version logic
    case SnmpKit.SnmpLib.Manager.get_next(host, oid_parsed, snmp_lib_opts) do
      {:ok, {next_oid, type, value}} ->
        # ALWAYS preserve type information - this is critical for SNMP
        # Convert OID to string only for final response format
        next_oid_string =
          if is_list(next_oid) do
            Enum.join(next_oid, ".")
          else
            # Should not happen, but handle gracefully
            to_string(next_oid)
          end

        {:ok, {next_oid_string, type, value}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends an SNMP SET request and returns the response.

  ## Parameters
  - `target` - SNMP target (host, "host:port", or target map)
  - `oid` - Object identifier to set
  - `value` - Value to set (will be encoded based on type)
  - `opts` - Request options
    - `:timeout` - SNMP PDU timeout in milliseconds (default: 10000)
    - `:community` - SNMP community string (default: "public")
    - `:version` - SNMP version (:v1, :v2c) (default: :v2c)
  """
  @spec send_set_request(target(), oid(), term(), opts()) :: snmp_result()
  def send_set_request(target, oid, value, opts \\ []) do
    SnmpKit.Telemetry.span(
      :request,
      %{operation: :set, target: target, oid: oid, version: Keyword.get(opts, :version)},
      fn -> do_send_set_request(target, oid, value, opts) end
    )
  end

  defp do_send_set_request(target, oid, value, opts) do
    {host, updated_opts} = split_target(target, opts)

    # Convert oid to proper format
    oid_parsed =
      case parse_oid(oid) do
        {:ok, oid_list} -> oid_list
        {:error, _} -> oid
      end

    # Convert value to snmp_lib format expected by SnmpKit.SnmpLib.Manager
    typed_value = typed_set_value(value)

    # Map options to snmp_lib format
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)

    # Use SnmpKit.SnmpLib.Manager for the actual operation
    case SnmpKit.SnmpLib.Manager.set(host, oid_parsed, typed_value, snmp_lib_opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  # Value forms accepted by set: {type, value}, binary, integer, IPv4 tuple, other
  defp typed_set_value(value) do
    cond do
      # Already typed tuple - normalize type to manager's expected atoms
      match?({t, _v} when is_atom(t), value) ->
        normalize_manager_typed(value)

      is_binary(value) ->
        {:string, value}

      is_integer(value) ->
        {:integer, value}

      # IPv4 tuple
      match?(
        {a, b, c, d} when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d),
        value
      ) ->
        {:ip_address, value}

      true ->
        {:opaque, value}
    end
  end

  # Normalize typed values to the atoms that SnmpKit.SnmpLib.Manager expects
  defp normalize_manager_typed({type, val}) when is_atom(type) do
    mapped_type =
      case type do
        :string -> :string
        :octet_string -> :string
        :octetString -> :string
        :integer -> :integer
        :unsigned32 -> :integer
        :gauge32 -> :gauge32
        :counter32 -> :counter32
        :counter64 -> :counter64
        :timeticks -> :timeticks
        :timeTicks -> :timeticks
        :ip_address -> :ip_address
        :ipAddress -> :ip_address
        :object_identifier -> :object_identifier
        :objectId -> :object_identifier
        :oid -> :object_identifier
        :null -> :null
        :opaque -> :opaque
        other -> other
      end

    {mapped_type, val}
  end

  @doc """
  Sends an SNMP GETBULK request (SNMPv2c only).

  GETBULK is more efficient than multiple GETNEXT operations for retrieving
  multiple consecutive OIDs.

  ## Parameters
  - `target` - SNMP target (host, "host:port", or target map)
  - `oid` - Starting OID for bulk retrieval
  - `opts` - Request options
    - `:timeout` - SNMP PDU timeout in milliseconds (default: 10000)
    - `:max_repetitions` - Maximum number of OIDs to retrieve (default: 30)
    - `:community` - SNMP community string (default: "public")
    - `:version` - SNMP version (must be :v2c) (default: :v2c)
  """
  @spec send_get_bulk_request(target(), oid(), opts()) :: snmp_result()
  def send_get_bulk_request(target, oid, opts \\ []) do
    SnmpKit.Telemetry.span(
      :request,
      %{operation: :get_bulk, target: target, oid: oid, version: Keyword.get(opts, :version)},
      fn -> do_send_get_bulk_request(target, oid, opts) end
    )
  end

  defp do_send_get_bulk_request(target, oid, opts) do
    version = Keyword.get(opts, :version, :v2c)

    case version do
      v2 when v2 in [:v2c, :v3] ->
        # Parse target to extract host and port
        {host, updated_opts} = split_target(target, opts)

        # Convert oid to proper format
        oid_parsed =
          case parse_oid(oid) do
            {:ok, oid_list} -> oid_list
            {:error, _} -> oid
          end

        # Map options to snmp_lib format
        snmp_lib_opts = map_options_to_snmp_lib(updated_opts)

        # Use SnmpKit.SnmpLib.Manager for the actual operation
        case SnmpKit.SnmpLib.Manager.get_bulk(host, oid_parsed, snmp_lib_opts) do
          {:ok, results} ->
            # Process the results to extract varbinds in 3-tuple format
            {:ok, results}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :getbulk_requires_v2c}
    end
  end

  # Private functions for snmp_lib integration

  @spec map_options_to_snmp_lib(opts()) :: list()
  defp map_options_to_snmp_lib(opts) do
    # Map SnmpMgr options to SnmpKit.SnmpLib.Manager options
    mapped = []

    mapped =
      if community = Keyword.get(opts, :community),
        do: [{:community, community} | mapped],
        else: mapped

    mapped =
      if timeout = Keyword.get(opts, :timeout), do: [{:timeout, timeout} | mapped], else: mapped

    mapped =
      if retries = Keyword.get(opts, :retries), do: [{:retries, retries} | mapped], else: mapped

    mapped =
      if version = Keyword.get(opts, :version), do: [{:version, version} | mapped], else: mapped

    mapped = if port = Keyword.get(opts, :port), do: [{:port, port} | mapped], else: mapped

    # SNMPv3 (USM) options travel through untouched
    mapped =
      opts
      |> Keyword.take([
        :security_name,
        :auth_protocol,
        :auth_password,
        :priv_protocol,
        :priv_password,
        :security_level,
        :context_name,
        :engine_id
      ])
      |> Keyword.merge(mapped)

    mapped =
      if max_repetitions = Keyword.get(opts, :max_repetitions),
        do: [{:max_repetitions, max_repetitions} | mapped],
        else: mapped

    mapped =
      if non_repeaters = Keyword.get(opts, :non_repeaters),
        do: [{:non_repeaters, non_repeaters} | mapped],
        else: mapped

    mapped
  end

  @doc """
  Parses and normalizes an OID to internal list format.

  Converts external OID input (string or list) to internal list of integers format.
  This function establishes the API boundary - all external input is converted to
  internal list format here.
  """
  @spec parse_oid(oid()) :: {:ok, list(non_neg_integer())} | {:error, term()}
  def parse_oid(oid) when is_list(oid) do
    # Already a list - validate and return
    case SnmpKit.SnmpLib.OID.valid_oid?(oid) do
      :ok ->
        {:ok, oid}

      {:error, :empty_oid} ->
        # Empty list fallback
        {:ok, [1, 3]}

      {:error, _reason} ->
        case oid do
          # Single [1] is invalid, use [1,3]
          [1] -> {:ok, [1, 3]}
          _ -> {:error, :invalid_oid_list}
        end
    end
  end

  def parse_oid(oid) when is_binary(oid) do
    # Handle empty string case
    case String.trim(oid) do
      "" ->
        {:ok, [1, 3]}

      trimmed ->
        # Try MIB registry first for symbolic names like "sysDescr.0"
        case SnmpKit.MIB.Registry.resolve_name(trimmed) do
          {:ok, oid_list} when is_list(oid_list) and length(oid_list) > 0 ->
            {:ok, oid_list}

          {:error, _} ->
            # Try numeric string parsing
            case SnmpKit.SnmpLib.OID.string_to_list(trimmed) do
              {:ok, oid_list} when is_list(oid_list) and length(oid_list) > 0 ->
                {:ok, oid_list}

              {:error, _} ->
                # Fall back to MIB GenServer for container OIDs like "system", "interfaces"
                case SnmpKit.SnmpMgr.MIB.resolve(trimmed) do
                  {:ok, oid_list} when is_list(oid_list) -> {:ok, oid_list}
                  error -> error
                end
            end
        end
    end
  end

  def parse_oid(_), do: {:error, :invalid_oid_input}

  # Type information must never be inferred - it must be preserved from SNMP responses
  # Removing type inference functions to prevent loss of critical type information
  # Any SNMP operation that does not preserve type information should fail with an error

  # Private helper to check if target contains port specification
  # Splits "host:port" targets into host and a :port option. A port given in
  # the target string wins; otherwise the caller's :port option (or the
  # configured default) is kept. Several request paths used to overwrite the
  # :port option with Target.parse/1's default of 161, so `port:` was ignored.
  defp split_target(target, opts) do
    case SnmpKit.SnmpMgr.Target.parse(target) do
      {:ok, %{host: host, port: port}} ->
        if target_contains_port?(target) do
          {host, Keyword.put(opts, :port, port)}
        else
          {host, opts}
        end

      {:error, _reason} ->
        {target, opts}
    end
  end

  defp target_contains_port?(target) when is_binary(target) do
    cond do
      # RFC 3986 bracket notation: [IPv6]:port
      String.starts_with?(target, "[") and String.contains?(target, "]:") ->
        case String.split(target, "]:", parts: 2) do
          [_ipv6_part, port_part] ->
            case Integer.parse(port_part) do
              {port, ""} when port > 0 and port <= 65535 -> true
              _ -> false
            end

          _ ->
            false
        end

      # Plain IPv6 addresses (contain :: or multiple colons) - no port embedded
      String.contains?(target, "::") ->
        false

      target |> String.graphemes() |> Enum.count(&(&1 == ":")) > 1 ->
        false

      # IPv4 or simple hostname with port
      String.contains?(target, ":") ->
        case String.split(target, ":", parts: 2) do
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

  defp target_contains_port?(_), do: false
end
