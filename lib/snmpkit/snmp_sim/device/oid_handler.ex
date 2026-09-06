defmodule SnmpKit.SnmpSim.Device.OidHandler do
  @moduledoc """
  OID handling and value generation for SNMP device simulation.
  Handles dynamic OID value generation, interface statistics, and MIB walking.
  """
  # Suppress Dialyzer warnings for pattern matches and guards
  @dialyzer [
    {:nowarn_function, get_dynamic_oid_value: 2},
    {:nowarn_function, walk_oid_recursive: 4}
  ]
  require Logger
  alias SnmpKit.SnmpSim.Device.Metrics
  alias SnmpKit.SnmpSim.MIB.SharedProfiles

  # I'll move the OID handling functions here from device.ex
  # This will be populated in the next step

  @doc """
  Extracts OID from SNMP PDU variable binding.

  ## Parameters
  - `varbind` - SNMP variable binding containing OID and value

  ## Returns
  - `oid` - Successfully extracted OID
  """
  def extract_oid(varbind) do
    case varbind do
      {oid, _type, _value} ->
        oid

      {oid, _value} ->
        oid

      _ ->
        ""
    end
  end

  @doc """
  Converts OID list to string representation.

  ## Parameters
  - `oid` - List of integers representing OID

  ## Returns
  - String representation of OID (e.g., "1.3.6.1.2.1.1.1.0")
  """
  def oid_to_string(oid) when is_list(oid), do: Enum.join(oid, ".")
  def oid_to_string(oid) when is_binary(oid), do: oid
  def oid_to_string(oid), do: to_string(oid)

  @doc """
  Converts string OID to list of integers.

  ## Parameters
  - `oid_string` - String representation of OID

  ## Returns
  - List of integers representing OID
  """
  def string_to_oid_list(oid_string) when is_binary(oid_string) do
    case oid_string do
      "" ->
        []

      _ ->
        try do
          oid_string
          |> String.split(".")
          |> Enum.map(&String.to_integer/1)
        rescue
          _ -> []
        end
    end
  end

  def string_to_oid_list(oid) when is_list(oid), do: oid
  def string_to_oid_list(oid), do: oid

  @doc """
  Extracts type and value from SNMP variable binding.

  ## Parameters
  - `varbind` - SNMP variable binding

  ## Returns
  - `{type, value}` - Tuple containing SNMP type and value
  """
  def extract_type_and_value({type, value}) do
    {type, value}
  end

  def extract_type_and_value(value) when is_binary(value) do
    {:octet_string, value}
  end

  def extract_type_and_value(value) when is_integer(value) do
    {:integer, value}
  end

  def extract_type_and_value(value) do
    {:unknown, value}
  end

  @doc """
  Gets OID value based on device state and OID.

  ## Parameters
  - `oid` - OID as list of integers or binary string
  - `state` - Device state containing configuration and counters or device type

  ## Returns
  - `{:ok, value}` - Successfully retrieved OID value
  - `{:error, reason}` - Failed to retrieve OID value
  """
  def get_oid_value(oid, state)
      when is_list(oid) and is_map(state) and is_map_key(state, :oid_map) do
    # Update last access time
    _new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    # Convert list OID to string to match walk parser format
    oid_string = oid_to_string(oid)
    get_oid_value_from_map(oid_string, state.oid_map)
  end

  def get_oid_value(oid, state)
      when is_binary(oid) and is_map(state) and is_map_key(state, :oid_map) do
    # Update last access time
    _new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    # OID is already a string, use directly
    get_oid_value_from_map(oid, state.oid_map)
  end

  def get_oid_value(oid, device_struct)
      when is_list(oid) and is_map(device_struct) and is_map_key(device_struct, :device_type) do
    oid_string = oid_to_string(oid)

    # DOCSIS upgrade OIDs overrides for :cable_modem
    case {device_struct.device_type, oid_string} do
      {:cable_modem, "1.3.6.1.2.1.69.1.3.2.0"} ->
        # docsIfDocsDevSwOperStatus (read-only)
        {:ok, {oid_string, :integer, Map.get(device_struct.upgrade, :oper_status, 1)}}

      {:cable_modem, "1.3.6.1.2.1.69.1.3.3.0"} ->
        # docsDevSwServer (IpAddress; read-write)
        server_str = Map.get(device_struct.upgrade, :server, "0.0.0.0")
        {:ok, {oid_string, :ip_address, ip_string_to_binary(server_str)}}

      {:cable_modem, "1.3.6.1.2.1.69.1.3.1.0"} ->
        # docsDevSwAdminStatus (INTEGER; read-write)
        {:ok, {oid_string, :integer, Map.get(device_struct.upgrade, :admin_status, 2)}}

      _ ->
        # Check if device has walk data loaded in SharedProfiles
        if Map.get(device_struct, :has_walk_data, false) do
          # SharedProfiles accepts the device type as-is (atom or string)
          device_type_atom = device_struct.device_type

          case SnmpKit.SnmpSim.MIB.SharedProfiles.get_oid_value(
                 device_type_atom,
                 oid_string,
                 device_struct
               ) do
            {:ok, {type, value}} -> {:ok, {oid_string, type, value}}
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, :no_such_name}
        end
    end
  end

  def get_oid_value(oid, device_struct)
      when is_binary(oid) and is_map(device_struct) and is_map_key(device_struct, :device_type) do
    # DOCSIS upgrade OIDs overrides for :cable_modem
    case {device_struct.device_type, oid} do
      {:cable_modem, "1.3.6.1.2.1.69.1.3.1.0"} ->
        {:ok, {oid, :integer, Map.get(device_struct.upgrade, :admin_status, 2)}}

      {:cable_modem, "1.3.6.1.2.1.69.1.3.3.0"} ->
        server_str = Map.get(device_struct.upgrade, :server, "0.0.0.0")
        {:ok, {oid, :ip_address, ip_string_to_binary(server_str)}}

      {:cable_modem, "1.3.6.1.2.1.69.1.3.4.0"} ->
        {:ok, {oid, :octet_string, Map.get(device_struct.upgrade, :filename, "")}}

      _ ->
        # Check if device has walk data loaded in SharedProfiles
        if Map.get(device_struct, :has_walk_data, false) do
          # SharedProfiles accepts the device type as-is (atom or string)
          device_type_atom = device_struct.device_type

          case SnmpKit.SnmpSim.MIB.SharedProfiles.get_oid_value(
                 device_type_atom,
                 oid,
                 device_struct
               ) do
            {:ok, {type, value}} -> {:ok, {oid, type, value}}
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, :no_such_name}
        end
    end
  end

  def get_oid_value(oid, unknown) do
    Logger.error(
      "Unexpected input to get_oid_value/2: oid=#{inspect(oid)}, unknown=#{inspect(unknown)}"
    )

    {:error, :no_such_name}
  end

  defp get_oid_value_from_map(oid_key, oid_map) do
    case Map.get(oid_map, oid_key) do
      nil ->
        {:error, :no_such_name}

      %{type: type, value: value} ->
        {:ok, {type, value}}

      # Handle simple string values
      value when is_binary(value) ->
        {:ok, {"STRING", value}}

      # Handle simple integer values
      value when is_integer(value) ->
        {:ok, {"INTEGER", value}}

      # Handle other simple values
      value ->
        {:ok, {"STRING", to_string(value)}}
    end
  end

  @doc """
  Gets dynamic OID value based on device state and OID.

  ## Parameters
  - `oid` - OID as string
  - `state` - Device state containing configuration and counters

  ## Returns
  - `{:ok, {type, value}}` - Successfully retrieved OID value with type
  - `{:error, reason}` - Failed to retrieve OID value
  """
  def get_dynamic_oid_value(oid, state) do
    Logger.debug("get_dynamic_oid_value called with oid: #{inspect(oid)}")
    # Normalize OID to string format using SnmpKit.SnmpLib.OID
    oid_string =
      case oid do
        oid when is_binary(oid) ->
          oid

        oid when is_list(oid) ->
          Enum.join(oid, ".")

        _ ->
          raise ArgumentError, "Invalid OID format: #{inspect(oid)}"
      end

    Logger.debug("get_dynamic_oid_value called with oid_string: #{inspect(oid_string)}")

    # Check for manual OID map first (only if non-empty)
    cond do
      Map.has_key?(state, :oid_map) and is_map(state.oid_map) and map_size(state.oid_map) > 0 ->
        Logger.debug("Device has manual oid_map, checking for OID: #{oid_string}")

        case get_oid_value_from_map(oid_string, state.oid_map) do
          {:ok, {type, value}} ->
            Logger.debug(
              "Found in manual oid_map: type=#{inspect(type)}, value=#{inspect(value)}"
            )

            atom_type = convert_snmp_type(type)
            {:ok, {oid_string, atom_type, value}}

          {:error, :no_such_name} ->
            Logger.debug("Not found in manual oid_map")
            {:error, :no_such_name}
        end

      Map.get(state, :has_walk_data, false) ->
        Logger.debug("Device has walk data, checking SharedProfiles")

        case SharedProfiles.get_oid_value(state.device_type, oid_string, state) do
          {:ok, {type, value}} ->
            Logger.debug(
              "Found in SharedProfiles: type=#{inspect(type)}, value=#{inspect(value)}"
            )

            {:ok, {oid_string, convert_snmp_type(type), value}}

          _ ->
            Logger.debug("Not found in SharedProfiles, returning error")
            {:error, :no_such_name}
        end

      true ->
        Logger.debug("Device has no walk data, checking fallback OIDs")
        # Legacy device without walk data - special-case DOCSIS upgrade scalars and other basics
        # IMPORTANT: If a profile was explicitly provided but contains no OIDs,
        # do NOT serve built-in defaults for RFC1213 system group. Return no_such_name instead.
        cond do
          # DOCSIS modem upgrade scalars (support manual modem without walk)
          state.device_type == :cable_modem and oid_string == "1.3.6.1.2.1.69.1.3.2.0" ->
            {:ok, {oid_string, :integer, Map.get(state.upgrade, :oper_status, 5)}}

          state.device_type == :cable_modem and oid_string == "1.3.6.1.2.1.69.1.3.3.0" ->
            # docsDevSwServer as IpAddress; encode as 4-octet binary for SNMP encoder
            server_str = Map.get(state.upgrade, :server, "0.0.0.0")
            {:ok, {oid_string, :ip_address, ip_string_to_binary(server_str)}}

          state.device_type == :cable_modem and oid_string == "1.3.6.1.2.1.69.1.3.4.0" ->
            {:ok, {oid_string, :octet_string, Map.get(state.upgrade, :filename, "(unknown)")}}

          state.device_type == :cable_modem and oid_string == "1.3.6.1.2.1.69.1.3.1.0" ->
            {:ok, {oid_string, :integer, Map.get(state.upgrade, :admin_status, 2)}}

          # If profile was provided but empty, suppress system defaults
          Map.get(state, :profile_provided, false) and
            map_size(Map.get(state, :oid_map, %{})) == 0 and
              String.starts_with?(oid_string, "1.3.6.1.2.1.1.") ->
            {:error, :no_such_name}

          # Fallback to basic system OIDs if not found in SharedProfiles
          oid_string == "1.3.6.1.2.1.1.1.0" ->
            Logger.debug("Matched sysDescr OID")
            # sysDescr - system description (OCTET STRING)
            device_type_str =
              case state.device_type do
                :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
                :cmts -> "Cisco CMTS Cable Modem Termination System"
                :router -> "Cisco Router"
                _ -> "SNMP Simulator Device"
              end

            {:ok, {oid_string, :octet_string, device_type_str}}

          oid_string == "1.3.6.1.2.1.1.2.0" ->
            # sysObjectID - object identifier (OBJECT IDENTIFIER)
            {:ok, {oid_string, :object_identifier, [1, 3, 6, 1, 4, 1, 1, 1]}}

          oid_string == "1.3.6.1.2.1.1.3.0" ->
            # sysUpTime - calculate based on uptime_start
            uptime_ticks = Metrics.calculate_uptime_ticks(state)
            {:ok, {oid_string, :timeticks, uptime_ticks}}

          oid_string == "1.3.6.1.2.1.1.4.0" ->
            # sysContact - contact info (OCTET STRING)
            {:ok, {oid_string, :octet_string, "admin@example.com"}}

          oid_string == "1.3.6.1.2.1.1.5.0" ->
            # sysName - system name (OCTET STRING)
            device_name = state.device_id || "device_#{state.port}"
            {:ok, {oid_string, :octet_string, device_name}}

          oid_string == "1.3.6.1.2.1.1.6.0" ->
            # sysLocation - location (OCTET STRING)
            {:ok, {oid_string, :octet_string, "Customer Premises"}}

          oid_string == "1.3.6.1.2.1.1.7.0" ->
            # sysServices - services (INTEGER)
            {:ok, {oid_string, :integer, 2}}

          oid_string == "1.3.6.1.2.1.2.1.0" ->
            # ifNumber - number of network interfaces (INTEGER)
            {:ok, {oid_string, :integer, 2}}

          true ->
            {:error, :no_such_name}
        end
    end
  end

  @doc """
  Finds the next OID in lexicographic order for SNMP GetNext operations.

  ## Parameters
  - `oid` - Starting OID as list of integers
  - `state` - Device state

  ## Returns
  - `{:ok, {next_oid, type, value}}` - Next OID with its type and value
  - `{:error, :end_of_mib}` - No more OIDs available
  """
  def get_next_oid_value(device_type, oid, state) do
    # Check if device has walk data loaded in SharedProfiles
    cond do
      Map.has_key?(state, :oid_map) ->
        get_next_oid_value_from_map(oid, state.oid_map)

      Map.get(state, :has_walk_data, false) ->
        oid_string = oid_to_string(oid)
        device_type_atom = device_type

        case SnmpKit.SnmpSim.MIB.SharedProfiles.get_next_oid(device_type_atom, oid_string) do
          {:ok, next_oid_string} ->
            case SnmpKit.SnmpSim.MIB.SharedProfiles.get_oid_value(
                   device_type_atom,
                   next_oid_string,
                   state
                 ) do
              {:ok, {type, value}} ->
                next_oid_list = string_to_oid_list(next_oid_string)
                {:ok, {next_oid_list, type, value}}

              {:error, reason} ->
                {:error, reason}
            end

          :end_of_mib ->
            {:error, :end_of_mib}

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        # no profile and no manual objects: nothing to walk
        {:error, :end_of_mib_view}
    end
  end

  defp get_next_oid_value_from_map(oid, oid_map) do
    oid_string = oid_to_string(oid)

    # Use proper lexicographic OID sorting instead of string sorting
    oid_keys =
      Map.keys(oid_map)
      |> Enum.filter(fn oid_key ->
        case validate_and_parse_oid(oid_key) do
          {:ok, _} -> true
          {:error, _} -> false
        end
      end)
      |> Enum.sort_by(fn oid_key ->
        {:ok, parts} = validate_and_parse_oid(oid_key)
        parts
      end)

    case find_next_oid(oid_keys, oid_string) do
      {:ok, next_oid_string} ->
        case Map.get(oid_map, next_oid_string) do
          %{type: type, value: value} ->
            {:ok, {string_to_oid_list(next_oid_string), convert_snmp_type(type), value}}

          # Handle simple string values
          value when is_binary(value) ->
            {:ok, {string_to_oid_list(next_oid_string), :octet_string, value}}

          # Handle simple integer values
          value when is_integer(value) ->
            {:ok, {string_to_oid_list(next_oid_string), :integer, value}}

          # Handle other simple values
          value ->
            {:ok, {string_to_oid_list(next_oid_string), :octet_string, to_string(value)}}
        end

      {:error, :not_found} ->
        {:error, :end_of_mib_view}
    end
  end

  defp find_next_oid(oids, oid) do
    # Validate input OID format first
    case validate_and_parse_oid(oid) do
      {:error, _} ->
        {:error, :invalid_oid}

      {:ok, oid_parts} ->
        # Sort OIDs numerically by converting to integer lists for comparison
        # Filter out any invalid OIDs during sorting
        sorted_oids =
          oids
          |> Enum.filter(fn oid_str ->
            case validate_and_parse_oid(oid_str) do
              {:ok, _} -> true
              {:error, _} -> false
            end
          end)
          |> Enum.sort_by(fn oid_str ->
            {:ok, parts} = validate_and_parse_oid(oid_str)
            parts
          end)

        case Enum.find_index(sorted_oids, &(&1 == oid)) do
          nil ->
            # If exact match not found, find the first OID numerically after the requested one
            next_index =
              Enum.find_index(sorted_oids, fn candidate_oid ->
                {:ok, candidate_parts} = validate_and_parse_oid(candidate_oid)
                compare_oid_lists(candidate_parts, oid_parts) == :gt
              end)

            if next_index, do: {:ok, Enum.at(sorted_oids, next_index)}, else: {:error, :not_found}

          index ->
            # If exact match found, get the next one if it exists
            if index + 1 < length(sorted_oids),
              do: {:ok, Enum.at(sorted_oids, index + 1)},
              else: {:error, :not_found}
        end
    end
  end

  # Helper function to validate and parse OID string
  defp validate_and_parse_oid(oid) when is_binary(oid) do
    case oid do
      "" ->
        {:error, :empty_oid}

      _ ->
        try do
          parts =
            oid
            |> String.split(".")
            |> Enum.map(&String.to_integer/1)

          {:ok, parts}
        rescue
          _ -> {:error, :invalid_oid_format}
        end
    end
  end

  defp validate_and_parse_oid(_), do: {:error, :invalid_oid_type}

  # Helper function to compare OID lists numerically
  defp compare_oid_lists([], []), do: :eq
  defp compare_oid_lists([], _), do: :lt
  defp compare_oid_lists(_, []), do: :gt
  defp compare_oid_lists([h1 | _t1], [h2 | _t2]) when h1 < h2, do: :lt
  defp compare_oid_lists([h1 | _t1], [h2 | _t2]) when h1 > h2, do: :gt
  defp compare_oid_lists([h1 | t1], [h2 | t2]) when h1 == h2, do: compare_oid_lists(t1, t2)

  @doc """
  Walks OID values for SNMP MIB walking.

  ## Parameters
  - `oid` - Starting OID as list of integers
  - `state` - Device state

  ## Returns
  - `{:ok, oid_values}` - List of OID values
  """
  def walk_oid_values(oid, state) do
    # Simple walk implementation - get next OIDs until end of MIB or outside subtree
    # For testing purposes, we'll walk through available OIDs starting from the given OID
    # but stay within the requested subtree
    walk_oid_recursive(oid, oid, state, [])
  end

  def walk_oid_recursive(oid, root_oid, state, acc) when length(acc) < 100 do
    case get_next_oid_value(state.device_type, oid, state) do
      {:ok, {next_oid, type, value}} ->
        # Check if next_oid is still within the root subtree
        within_subtree = oid_within_subtree?(next_oid, root_oid)

        if within_subtree do
          # Continue walking within the subtree
          walk_oid_recursive(next_oid, root_oid, state, [{next_oid, {type, value}} | acc])
        else
          # Reached outside the subtree, return what we have accumulated
          finish_walk(acc)
        end

      {:error, :end_of_mib_view} ->
        # Reached end of MIB, return what we have accumulated
        finish_walk(acc)

      {:error, _reason} ->
        # Some other error occurred, return what we have so far
        finish_walk(acc)
    end
  end

  def walk_oid_recursive(_oid, _root_oid, _state, acc) do
    # Limit recursion depth to prevent infinite loops
    finish_walk(acc)
  end

  defp finish_walk(acc) do
    # Sort results by OID to ensure lexicographical order
    sorted_results =
      acc
      |> Enum.reverse()
      |> Enum.sort_by(fn {oid, _value} ->
        # Convert OID to list of integers for proper numerical sorting
        case oid do
          oid_list when is_list(oid_list) ->
            oid_list

          oid_string when is_binary(oid_string) ->
            oid_string
            |> String.split(".")
            |> Enum.map(&String.to_integer/1)
        end
      end)

    {:ok, sorted_results}
  end

  defp oid_within_subtree?(oid, root_oid) do
    # Convert OIDs to strings if they aren't already
    oid_str = if is_binary(oid), do: oid, else: Enum.join(oid, ".")
    subtree_str = if is_binary(root_oid), do: root_oid, else: Enum.join(root_oid, ".")

    # Check if the OID starts with the subtree OID
    String.starts_with?(oid_str, subtree_str <> ".") or oid_str == subtree_str
  end

  # Helper function to convert SNMP type strings to proper atoms
  defp convert_snmp_type(type) when is_atom(type), do: type

  defp convert_snmp_type(type) when is_binary(type) do
    case String.upcase(type) do
      "OCTET STRING" -> :octet_string
      "STRING" -> :octet_string
      "INTEGER" -> :integer
      "COUNTER32" -> :counter32
      "GAUGE32" -> :gauge32
      "TIMETICKS" -> :timeticks
      "COUNTER64" -> :counter64
      "IP ADDRESS" -> :ip_address
      "IPADDRESS" -> :ip_address
      "OPAQUE" -> :opaque
      "OBJECT IDENTIFIER" -> :object_identifier
      "OID" -> :object_identifier
      "NULL" -> :null
      other -> existing_type_atom(other)
    end
  end

  defp convert_snmp_type(_), do: :octet_string

  # Type names come from walk files: use an existing atom or fall back rather
  # than creating atoms from external input.
  defp existing_type_atom(type) do
    String.to_existing_atom(String.downcase(type))
  rescue
    ArgumentError -> :octet_string
  end

  defp ip_string_to_binary(str) when is_binary(str) do
    case String.split(str, ".") do
      [a, b, c, d] ->
        with {ai, ""} <- Integer.parse(a),
             true <- ai >= 0 and ai <= 255,
             {bi, ""} <- Integer.parse(b),
             true <- bi >= 0 and bi <= 255,
             {ci, ""} <- Integer.parse(c),
             true <- ci >= 0 and ci <= 255,
             {di, ""} <- Integer.parse(d),
             true <- di >= 0 and di <= 255 do
          <<ai, bi, ci, di>>
        else
          _ -> <<0, 0, 0, 0>>
        end

      _ ->
        <<0, 0, 0, 0>>
    end
  end
end
