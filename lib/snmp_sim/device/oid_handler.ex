defmodule SnmpSim.Device.OidHandler do
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
  alias SnmpSim.MIB.SharedProfiles

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
  def get_oid_value(oid, state) when is_list(oid) and is_map(state) and is_map_key(state, :oid_map) do
    # Update last access time
    _new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    # Convert list OID to string to match walk parser format
    oid_string = oid_to_string(oid)
    get_oid_value_from_map(oid_string, state.oid_map)
  end

  def get_oid_value(oid, state) when is_binary(oid) and is_map(state) and is_map_key(state, :oid_map) do
    # Update last access time
    _new_state = %{state | last_access: System.monotonic_time(:millisecond)}
    # OID is already a string, use directly
    get_oid_value_from_map(oid, state.oid_map)
  end

  def get_oid_value(device_type, oid) when is_atom(device_type) and is_binary(oid) do
    oid_list = string_to_oid_list(oid)
    case get_device_specific_value(device_type, oid_list) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, :no_such_name}
    end
  end

  def get_oid_value(device_type, oid) when is_atom(device_type) and is_list(oid) do
    case get_device_specific_value(device_type, oid) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, :no_such_name}
    end
  end

  def get_oid_value(oid, device_struct) when is_list(oid) and is_map(device_struct) and is_map_key(device_struct, :device_type) do
    # Check if device has walk data loaded in SharedProfiles
    if Map.get(device_struct, :has_walk_data, false) do
      # Convert device_type to atom since SharedProfiles uses atoms as keys
      device_type_atom = if is_binary(device_struct.device_type), do: String.to_atom(device_struct.device_type), else: device_struct.device_type
      oid_string = oid_to_string(oid)
      case SnmpSim.MIB.SharedProfiles.get_oid_value(device_type_atom, oid_string, device_struct) do
        {:ok, {type, value}} -> {:ok, {oid_string, type, value}}
        {:error, reason} -> {:error, reason}
      end
    else
      case get_device_specific_value(device_struct.device_type, oid) do
        {:ok, value} -> {:ok, value}
        {:error, _} -> {:error, :no_such_name}
      end
    end
  end

  def get_oid_value(oid, device_struct) when is_binary(oid) and is_map(device_struct) and is_map_key(device_struct, :device_type) do
    # Check if device has walk data loaded in SharedProfiles
    if Map.get(device_struct, :has_walk_data, false) do
      # Convert device_type to atom since SharedProfiles uses atoms as keys
      device_type_atom = if is_binary(device_struct.device_type), do: String.to_atom(device_struct.device_type), else: device_struct.device_type
      case SnmpSim.MIB.SharedProfiles.get_oid_value(device_type_atom, oid, device_struct) do
        {:ok, {type, value}} -> {:ok, {oid, type, value}}
        {:error, reason} -> {:error, reason}
      end
    else
      oid_list = string_to_oid_list(oid)
      case get_device_specific_value(device_struct.device_type, oid_list) do
        {:ok, value} -> {:ok, value}
        {:error, _} -> {:error, :no_such_name}
      end
    end
  end

  def get_oid_value(oid, unknown) do
    Logger.error("Unexpected input to get_oid_value/2: oid=#{inspect(oid)}, unknown=#{inspect(unknown)}")
    {:error, :no_such_name}
  end

  defp get_oid_value_from_map(oid_key, oid_map) do
    case Map.get(oid_map, oid_key) do
      nil ->
        {:error, :no_such_name}
      value ->
        {:ok, value}
    end
  end

  defp get_device_specific_value(device_type, oid_list) do
    oid_string = Enum.join(oid_list, ".")
    case oid_string do
      # System group OIDs (1.3.6.1.2.1.1.x.0)
      "1.3.6.1.2.1.1.1.0" -> # sysDescr.0
        device_type_str =
          case device_type do
            :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
            :cmts -> "Cisco CMTS Cable Modem Termination System"
            :router -> "Cisco Router"
            :switch -> "SNMP Simulator Device"
            _ -> "SNMP Simulator Device"
          end
        {:ok, {oid_string, :octet_string, device_type_str}}
      "1.3.6.1.2.1.1.2.0" -> # sysObjectID.0
        {:ok, {oid_string, :object_identifier, [1, 3, 6, 1, 4, 1, 1, 1]}}
      "1.3.6.1.2.1.1.3.0" -> # sysUpTime.0
        {:ok, {oid_string, :timeticks, 12345}}
      "1.3.6.1.2.1.1.4.0" -> # sysContact.0
        {:ok, {oid_string, :octet_string, "admin@example.com"}}
      "1.3.6.1.2.1.1.5.0" -> # sysName.0
        {:ok, {oid_string, :octet_string, "cable-modem-sim"}}
      "1.3.6.1.2.1.1.6.0" -> # sysLocation.0
        {:ok, {oid_string, :octet_string, "Lab Environment"}}
      "1.3.6.1.2.1.1.7.0" -> # sysServices.0
        {:ok, {oid_string, :integer, 72}}
      
      # Interface group OIDs (1.3.6.1.2.1.2.x.0)
      "1.3.6.1.2.1.2.1.0" -> # ifNumber.0
        {:ok, {oid_string, :integer, 2}}
      
      # Interface table OIDs (1.3.6.1.2.1.2.2.1.x.y)
      "1.3.6.1.2.1.2.2.1.1.1" -> # ifIndex.1
        {:ok, {oid_string, :integer, 1}}
      "1.3.6.1.2.1.2.2.1.1.2" -> # ifIndex.2
        {:ok, {oid_string, :integer, 2}}
      "1.3.6.1.2.1.2.2.1.2.1" -> # ifDescr.1
        {:ok, {oid_string, :octet_string, "eth0"}}
      "1.3.6.1.2.1.2.2.1.2.2" -> # ifDescr.2
        {:ok, {oid_string, :octet_string, "eth1"}}
      "1.3.6.1.2.1.2.2.1.3.1" -> # ifType.1
        {:ok, {oid_string, :integer, 6}}
      "1.3.6.1.2.1.2.2.1.3.2" -> # ifType.2
        {:ok, {oid_string, :integer, 6}}
      oid when oid == "1.3.6.1.2.1.2.2.1.5.1" -> # Gauge32 (ifSpeed)
        {:ok, {oid_string, :gauge32, 100000000}}
      oid when oid == "1.3.6.1.2.1.2.2.1.10.1" -> # Counter32 (ifInOctets)
        {:ok, {oid_string, :counter32, 1234567}}
      oid when oid == "1.3.6.1.2.1.2.2.1.16.1" -> # Counter32 (ifOutOctets)
        {:ok, {oid_string, :counter32, 7654321}}
      _ ->
        case SharedProfiles.get_oid_value(device_type, oid_string, %{uptime: 0, device_type: device_type}) do
          {:ok, {type, value}} -> {:ok, {oid_string, type, value}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp get_hardcoded_oid_value(device_type, oid_list) do
    oid_string = Enum.join(oid_list, ".")
    case oid_string do
      # System group OIDs (1.3.6.1.2.1.1.x.0)
      "1.3.6.1.2.1.1.1.0" -> # sysDescr.0
        device_type_str =
          case device_type do
            :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
            :cmts -> "Cisco CMTS Cable Modem Termination System"
            :router -> "Cisco Router"
            :switch -> "SNMP Simulator Device"
            _ -> "SNMP Simulator Device"
          end
        {:ok, {oid_string, :octet_string, device_type_str}}
      "1.3.6.1.2.1.1.2.0" -> # sysObjectID.0
        {:ok, {oid_string, :object_identifier, [1, 3, 6, 1, 4, 1, 1, 1]}}
      "1.3.6.1.2.1.1.3.0" -> # sysUpTime.0
        {:ok, {oid_string, :timeticks, 12345}}
      "1.3.6.1.2.1.1.4.0" -> # sysContact.0
        {:ok, {oid_string, :octet_string, "admin@example.com"}}
      "1.3.6.1.2.1.1.5.0" -> # sysName.0
        {:ok, {oid_string, :octet_string, "cable-modem-sim"}}
      "1.3.6.1.2.1.1.6.0" -> # sysLocation.0
        {:ok, {oid_string, :octet_string, "Lab Environment"}}
      "1.3.6.1.2.1.1.7.0" -> # sysServices.0
        {:ok, {oid_string, :integer, 72}}
      
      # Interface group OIDs (1.3.6.1.2.1.2.x.0)
      "1.3.6.1.2.1.2.1.0" -> # ifNumber.0
        {:ok, {oid_string, :integer, 2}}
      
      # Interface table OIDs (1.3.6.1.2.1.2.2.1.x.y)
      "1.3.6.1.2.1.2.2.1.1.1" -> # ifIndex.1
        {:ok, {oid_string, :integer, 1}}
      "1.3.6.1.2.1.2.2.1.1.2" -> # ifIndex.2
        {:ok, {oid_string, :integer, 2}}
      "1.3.6.1.2.1.2.2.1.2.1" -> # ifDescr.1
        {:ok, {oid_string, :octet_string, "eth0"}}
      "1.3.6.1.2.1.2.2.1.2.2" -> # ifDescr.2
        {:ok, {oid_string, :octet_string, "eth1"}}
      "1.3.6.1.2.1.2.2.1.3.1" -> # ifType.1
        {:ok, {oid_string, :integer, 6}}
      "1.3.6.1.2.1.2.2.1.3.2" -> # ifType.2
        {:ok, {oid_string, :integer, 6}}
      oid when oid == "1.3.6.1.2.1.2.2.1.5.1" -> # Gauge32 (ifSpeed)
        {:ok, {oid_string, :gauge32, 100000000}}
      oid when oid == "1.3.6.1.2.1.2.2.1.10.1" -> # Counter32 (ifInOctets)
        {:ok, {oid_string, :counter32, 1234567}}
      oid when oid == "1.3.6.1.2.1.2.2.1.16.1" -> # Counter32 (ifOutOctets)
        {:ok, {oid_string, :counter32, 7654321}}
      _ ->
        {:error, :no_such_name}
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
    # Normalize OID to string format using SnmpLib.OID
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

    # Check if this is a device with walk data
    if Map.get(state, :has_walk_data, false) do
      Logger.debug("Device has walk data, checking SharedProfiles")
      case SharedProfiles.get_oid_value(state.device_type, oid_string, state.walk_data) do
        {:ok, {type, value}} ->
          Logger.debug("Found in SharedProfiles: type=#{inspect(type)}, value=#{inspect(value)}")
          {:ok, {oid_string, String.to_atom(String.downcase(type)), value}}
        _ ->
          Logger.debug("Not found in SharedProfiles, returning error")
          {:error, :no_such_name}
      end
    else
      Logger.debug("Device has no walk data, checking fallback OIDs")
      # Legacy device without walk data - use fallback values
      cond do
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
          uptime_ticks = calculate_uptime_ticks(state)
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

        # Interface table OIDs (1.3.6.1.2.1.2.2.1.x.y where x is column, y is interface index)
        String.starts_with?(oid_string, "1.3.6.1.2.1.2.2.1.") ->
          handle_interface_oid(oid_string, state)

        # High Capacity (HC) Interface Counters (1.3.6.1.2.1.31.1.1.1.x.y)
        String.starts_with?(oid_string, "1.3.6.1.2.1.31.1.1.1.") ->
          handle_hc_interface_oid(oid_string, state)

        # DOCSIS Cable Modem SNR (1.3.6.1.2.1.10.127.1.1.4.1.5.x)
        String.starts_with?(oid_string, "1.3.6.1.2.1.10.127.1.1.4.1.5.") ->
          handle_docsis_snr_oid(oid_string, state)

        # Host Resources MIB - Processor Load (1.3.6.1.2.1.25.3.3.1.2.x)
        String.starts_with?(oid_string, "1.3.6.1.2.1.25.3.3.1.2.") ->
          handle_host_processor_oid(oid_string, state)

        # Host Resources MIB - Storage Used (1.3.6.1.2.1.25.2.3.1.6.x)
        String.starts_with?(oid_string, "1.3.6.1.2.1.25.2.3.1.6.") ->
          handle_host_storage_oid(oid_string, state)

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
        # Convert device_type to atom since SharedProfiles uses atoms as keys
        device_type_atom = if is_binary(device_type), do: String.to_atom(device_type), else: device_type
        case SnmpSim.MIB.SharedProfiles.get_next_oid(device_type_atom, oid_string) do
          {:ok, next_oid_string} ->
            case SnmpSim.MIB.SharedProfiles.get_oid_value(device_type_atom, next_oid_string, state) do
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
        # Fallback to original implementation for compatibility
        with {:ok, oids} <- {:ok, get_known_oids(device_type)},
             {:ok, next_oid} <- find_next_oid(Enum.map(oids, &oid_to_string/1), oid_to_string(oid)) do
          oid_list = string_to_oid_list(next_oid)
          case get_oid_value(oid_list, state) do
            {:ok, %{type: type, value: value}} -> 
              result = {:ok, {string_to_oid_list(next_oid), String.to_atom(String.downcase(type)), value}}
              result
            {:ok, {_oid_string, type, value}} -> 
              result = {:ok, {string_to_oid_list(next_oid), type, value}}
              result
            {:ok, {type, value}} -> 
              result = {:ok, {string_to_oid_list(next_oid), type, value}}
              result
            _error_result -> 
              {:error, :end_of_mib_view}
          end
        else
          _error -> 
            {:error, :end_of_mib_view}
        end
    end
  end

  defp get_next_oid_value_from_map(oid, oid_map) do
    oid_string = oid_to_string(oid)
    oid_keys = Map.keys(oid_map) |> Enum.sort()
    
    case find_next_oid(oid_keys, oid_string) do
      {:ok, next_oid_string} ->
        case Map.get(oid_map, next_oid_string) do
          %{type: type, value: value} ->
            {:ok, {string_to_oid_list(next_oid_string), String.to_atom(String.downcase(type)), value}}
          nil ->
            {:error, :end_of_mib_view}
        end
      {:error, :not_found} ->
        {:error, :end_of_mib_view}
    end
  end

  defp find_next_oid(oids, oid) do
    # Validate input OID format first
    case validate_and_parse_oid(oid) do
      {:error, _} -> {:error, :invalid_oid}
      {:ok, oid_parts} ->
        # Sort OIDs numerically by converting to integer lists for comparison
        # Filter out any invalid OIDs during sorting
        sorted_oids = oids
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
            next_index = Enum.find_index(sorted_oids, fn candidate_oid ->
              {:ok, candidate_parts} = validate_and_parse_oid(candidate_oid)
              compare_oid_lists(candidate_parts, oid_parts) == :gt
            end)
            if next_index, do: {:ok, Enum.at(sorted_oids, next_index)}, else: {:error, :not_found}
          index ->
            # If exact match found, get the next one if it exists
            if index + 1 < length(sorted_oids), do: {:ok, Enum.at(sorted_oids, index + 1)}, else: {:error, :not_found}
        end
    end
  end

  # Helper function to validate and parse OID string
  defp validate_and_parse_oid(oid) when is_binary(oid) do
    case oid do
      "" -> {:error, :empty_oid}
      _ ->
        try do
          parts = oid
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
  Retrieves multiple OIDs for SNMP GetBulk operations.

  ## Parameters
  - `oid` - Starting OID
  - `count` - Maximum number of OIDs to retrieve
  - `state` - Device state

  ## Returns
  - List of `{oid, type, value}` tuples
  """
  def get_bulk_oid_values(oid, count, state) do
    try do
      case SharedProfiles.get_bulk_oids(state.device_type, oid, count) do
        {:ok, oid_values} -> {:ok, oid_values}
        {:error, _reason} -> {:ok, get_fallback_bulk_oids(oid, count, state)}
      end
    catch
      :exit, {:noproc, _} ->
        Logger.debug(
          "SharedProfiles unavailable, using fallback for OID #{oid}"
        )

        {:ok, get_fallback_bulk_oids(oid, count, state)}

      :exit, reason ->
        Logger.debug(
          "SharedProfiles unavailable (#{inspect(reason)}), using fallback for OID #{oid}"
        )

        {:ok, get_fallback_bulk_oids(oid, count, state)}
      :error, reason ->
        Logger.debug(
          "Error in SharedProfiles for OID #{oid}: #{inspect(reason)}"
        )

        {:ok, get_fallback_bulk_oids(oid, count, state)}
    end
  end

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
    sorted_results = acc
    |> Enum.reverse()
    |> Enum.sort_by(fn {oid, _value} -> 
      # Convert OID to list of integers for proper numerical sorting
      case oid do
        oid_list when is_list(oid_list) -> oid_list
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

  @doc """
  Gets fallback bulk OIDs for SNMP GetBulk operations.

  ## Parameters
  - `oid` - Starting OID
  - `count` - Maximum number of OIDs to retrieve
  - `state` - Device state

  ## Returns
  - List of `{oid, type, value}` tuples
  """
  def get_fallback_bulk_oids(start_oid, max_repetitions, state) do
    # Convert OID to string if it's a list
    start_oid_string = case start_oid do
      oid when is_list(oid) -> oid_to_string(oid)
      oid when is_binary(oid) -> oid
    end

    Logger.debug("Fallback bulk OIDs for #{start_oid_string}, max_repetitions: #{max_repetitions}")

    # Collect bulk OIDs iteratively
    get_bulk_oids_iteratively(start_oid, max_repetitions, state, [])
  end

  # Helper function to iteratively collect bulk OIDs
  defp get_bulk_oids_iteratively(_current_oid, 0, _state, acc) do
    # Reached max repetitions, return accumulated results
    Enum.reverse(acc)
  end

  defp get_bulk_oids_iteratively(current_oid, remaining_count, state, acc) do
    case get_fallback_next_oid(current_oid, state) do
      {next_oid, :end_of_mib_view, value} ->
        # Hit end of MIB, add this and stop
        Enum.reverse([{next_oid, :end_of_mib_view, value} | acc])
      {:error, :end_of_mib_view} ->
        # Hit end of MIB, add end_of_mib_view entry with the current OID and stop
        Enum.reverse([{current_oid, :end_of_mib_view, {:end_of_mib_view, nil}} | acc])
      {next_oid, type, value} ->
        # Got a valid OID, add it and continue
        new_acc = [{next_oid, type, value} | acc]
        get_bulk_oids_iteratively(next_oid, remaining_count - 1, state, new_acc)
    end
  end

  @doc """
  Gets fallback next OID for SNMP GetNext operations.

  ## Parameters
  - `oid_list` - Starting OID as list of integers
  - `state` - Device state

  ## Returns
  - `{next_oid, type, value}` - Next OID with its type and value
  """
  def get_fallback_next_oid(oid_list, state) do
    device_type = Map.get(state, :device_type, :cable_modem)
    known_oids = get_known_oids(device_type)
    # Ensure consistent format for comparison by converting all to strings
    current_oid_str = oid_to_string(oid_list)
    known_oids_str = Enum.map(known_oids, &oid_to_string/1)

    current_index = Enum.find_index(known_oids_str, &(&1 == current_oid_str))

    if current_index != nil and current_index + 1 < length(known_oids) do
      next_index = current_index + 1
      next_oid = Enum.at(known_oids, next_index)
      case get_hardcoded_oid_value(device_type, next_oid) do
        {:ok, {_oid, type, value}} when type == :object_identifier ->
          {next_oid, type, value}
        {:ok, {_oid, type, value}} ->
          {next_oid, type, value}
        {:ok, value} ->
          {next_oid, :unknown, value}
        {:error, _} ->
          # If we can't get a value for this OID, try the next one recursively
          get_fallback_next_oid(next_oid, state)
      end
    else
      # If no exact match or at the end, try to find the next logical OID
      sorted_oids = Enum.sort_by(known_oids, &oid_to_string/1)
      next_oid = Enum.find(sorted_oids, fn oid -> oid_to_string(oid) > current_oid_str end)
      if next_oid do
        case get_hardcoded_oid_value(device_type, next_oid) do
          {:ok, {_oid, type, value}} when type == :object_identifier ->
            {next_oid, type, value}
          {:ok, {_oid, type, value}} ->
            {next_oid, type, value}
          {:ok, value} ->
            {next_oid, :unknown, value}
          {:error, _} ->
            get_fallback_next_oid(next_oid, state)
        end
      else
        # Truly no more OIDs available
        {current_oid_str, :end_of_mib_view, {:end_of_mib_view, nil}}
      end
    end
  end

  @doc """
  Handles interface OID.

  ## Parameters
  - `oid` - Interface OID as string
  - `_state` - Device state (unused)

  ## Returns
  - `{:ok, value}` - Successfully retrieved OID value
  - `{:error, reason}` - Failed to retrieve OID value
  """
  def handle_interface_oid(oid, _state) do
    # Extract the last two components for column and index
    case Enum.take(String.split(oid, "."), -2) do
      [column, _index] ->
        case column do
          "1" -> {:ok, {oid, :integer, 1}} # ifIndex
          "2" -> {:ok, {oid, :octet_string, "Ethernet"}} # ifDescr
          "3" -> {:ok, {oid, :integer, 6}} # ifType (6 = ethernetCsmacd)
          "4" -> {:ok, {oid, :gauge32, 1500}} # ifMtu
          "5" -> {:ok, {oid, :gauge32, 10000000}} # ifSpeed (10Mbps)
          "6" -> {:ok, {oid, :octet_string, <<0, 1, 2, 3, 4, 5>>}} # ifPhysAddress
          "7" -> {:ok, {oid, :integer, 1}} # ifAdminStatus (1 = up)
          "8" -> {:ok, {oid, :integer, 1}} # ifOperStatus (1 = up)
          "10" -> {:ok, {oid, :counter32, 1000}} # ifInOctets
          "11" -> {:ok, {oid, :counter32, 100}} # ifInUcastPkts
          "16" -> {:ok, {oid, :counter32, 900}} # ifOutOctets
          "17" -> {:ok, {oid, :counter32, 90}} # ifOutUcastPkts
          _ -> {:error, :no_such_name}
        end
      _ -> {:error, :no_such_name}
    end
  end

  @doc """
  Handles high capacity interface OID.

  ## Parameters
  - `oid` - High capacity interface OID as string
  - `state` - Device state

  ## Returns
  - `{:ok, value}` - Successfully retrieved OID value
  - `{:error, reason}` - Failed to retrieve OID value
  """
  def handle_hc_interface_oid(oid, state) do
    # Parse HC interface OID: 1.3.6.1.2.1.31.1.1.1.column.interface_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "31", "1", "1", "1", column, interface_index] ->
        case {column, interface_index} do
          {"6", "1"} ->
            # ifHCInOctets.1 - high capacity input octets (Counter64)
            # 50GB base
            base_count = 50_000_000_000
            increment = calculate_traffic_increment(state, :hc_in_octets)
            {:ok, {oid, :counter64, base_count + increment}}

          {"10", "1"} ->
            # ifHCOutOctets.1 - high capacity output octets (Counter64)
            # 35GB base
            base_count = 35_000_000_000
            increment = calculate_traffic_increment(state, :hc_out_octets)
            {:ok, {oid, :counter64, base_count + increment}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  @doc """
  Handles DOCSIS SNR OID.

  ## Parameters
  - `oid` - DOCSIS SNR OID as string
  - `state` - Device state

  ## Returns
  - `{:ok, value}` - Successfully retrieved OID value
  - `{:error, reason}` - Failed to retrieve OID value
  """
  def handle_docsis_snr_oid(oid, state) do
    # Parse DOCSIS SNR OID: 1.3.6.1.2.1.10.127.1.1.4.1.5.channel_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "10", "127", "1", "1", "4", "1", "5", channel_index] ->
        case channel_index do
          "3" ->
            # docsIfSigQSignalNoise.3 - SNR for downstream channel 3
            snr_value = calculate_snr_gauge(state)
            {:ok, {oid, :gauge32, snr_value}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  @doc """
  Handles Host Resources processor OID.

  ## Parameters
  - `oid` - Host Resources processor OID as string
  - `state` - Device state

  ## Returns
  - `{:ok, value}` - Successfully retrieved OID value
  - `{:error, reason}` - Failed to retrieve OID value
  """
  def handle_host_processor_oid(oid, state) do
    # Parse Host Resources processor OID: 1.3.6.1.2.1.25.3.3.1.2.processor_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "25", "3", "3", "1", "2", processor_index] ->
        case processor_index do
          "1" ->
            # hrProcessorLoad.1 - CPU utilization percentage
            cpu_load = calculate_cpu_gauge(state)
            {:ok, {oid, :gauge32, cpu_load}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  @doc """
  Handles Host Resources storage OID.

  ## Parameters
  - `oid` - Host Resources storage OID as string
  - `state` - Device state

  ## Returns
  - `{:ok, value}` - Successfully retrieved OID value
  - `{:error, reason}` - Failed to retrieve OID value
  """
  def handle_host_storage_oid(oid, state) do
    # Parse Host Resources storage OID: 1.3.6.1.2.1.25.2.3.1.6.storage_index
    case String.split(oid, ".") do
      ["1", "3", "6", "1", "2", "1", "25", "2", "3", "1", "6", storage_index] ->
        case storage_index do
          "1" ->
            # hrStorageUsed.1 - Storage units used (typically memory)
            storage_used = calculate_storage_gauge(state)
            {:ok, {oid, :gauge32, storage_used}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  @doc """
  Calculates device uptime in milliseconds.

  ## Parameters
  - `state` - Device state containing uptime_start timestamp

  ## Returns
  - Integer representing uptime in milliseconds
  """
  def calculate_uptime(%{uptime_start: uptime_start}) when is_integer(uptime_start) do
    current_time = :erlang.monotonic_time()
    uptime_monotonic = current_time - uptime_start
    :erlang.convert_time_unit(uptime_monotonic, :native, :millisecond)
  end

  def calculate_uptime(_state) do
    0
  end

  @doc """
  Calculates device uptime in SNMP TimeTicks (centiseconds).

  ## Parameters
  - `state` - Device state

  ## Returns
  - Integer representing uptime in centiseconds (1/100th of a second)
  """
  def calculate_uptime_ticks(state) do
    # SNMP TimeTicks are in 1/100th of a second (centiseconds)
    uptime_milliseconds = calculate_uptime(state)
    # Convert milliseconds to centiseconds
    div(uptime_milliseconds, 10)
  end

  @doc """
  Builds comprehensive device state for monitoring and OID responses.

  ## Parameters
  - `state` - Current device state

  ## Returns
  - Map containing calculated device metrics and status information
  """
  def build_device_state(state) do
    %{
      device_id: state.device_id,
      device_type: state.device_type,
      uptime: calculate_uptime(state),
      mac_address: state.mac_address,
      port: state.port,
      interface_utilization: calculate_interface_utilization(state),
      signal_quality: calculate_signal_quality(state),
      cpu_utilization: calculate_cpu_utilization(state),
      temperature: calculate_temperature(state),
      error_rate: calculate_error_rate(state),
      health_score: calculate_health_score(state),
      correlation_factors: build_correlation_factors(state)
    }
  end

  @doc """
  Gets interface description based on device type.

  ## Parameters
  - `state` - Device state containing device_type

  ## Returns
  - String description of the interface
  """
  def get_interface_description(state) do
    case state.device_type do
      :cable_modem -> "Ethernet Interface"
      :cmts -> "Cable Interface 1/0/0"
      :router -> "GigabitEthernet0/0"
      _ -> "Interface 1"
    end
  end

  @doc """
  Calculates traffic increment for counters based on device type and time.

  ## Parameters
  - `state` - Device state
  - `counter_type` - Type of traffic counter (:in_octets, :out_octets, etc.)

  ## Returns
  - Integer representing traffic increment since device start
  """
  def calculate_traffic_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Base rate depends on device type and counter type
    base_rate =
      case {state.device_type, counter_type} do
        # ~1 Mbps
        {:cable_modem, :in_octets} -> 125_000
        # ~500 Kbps
        {:cable_modem, :out_octets} -> 62_500
        # ~10 Mbps
        {:cable_modem, :hc_in_octets} -> 1_250_000
        # ~5 Mbps
        {:cable_modem, :hc_out_octets} -> 625_000
        # ~100 Mbps
        {:cmts, :in_octets} -> 12_500_000
        # ~100 Mbps
        {:cmts, :out_octets} -> 12_500_000
        # ~1 Gbps
        {:cmts, :hc_in_octets} -> 125_000_000
        # ~1 Gbps
        {:cmts, :hc_out_octets} -> 125_000_000
        # Default ~80 Kbps
        _ -> 10_000
      end

    # Add time-of-day variation (peak evening hours)
    time_factor = get_time_factor()

    # Higher utilization = more errors (congestion)
    # 0.6x to 2.4x
    utilization_impact = 1.0 + (time_factor - 0.8) * 2.0

    # Signal quality impact (simulated via random factor)
    # 0.7 to 1.3
    signal_quality = 0.7 + :rand.uniform(6) / 10
    # Worse signal = more errors
    signal_impact = 2.0 - signal_quality

    # Calculate total increment
    rate_with_variation = base_rate * utilization_impact * signal_impact
    total_increment = trunc(rate_with_variation * uptime_seconds)

    # Add some accumulated variance
    # 5% base variance
    base_variance = div(total_increment, 20)
    variance = if base_variance > 0 do
      :rand.uniform(base_variance * 2) - base_variance
    else
      0
    end

    max(0, total_increment + variance)
  end

  @doc """
  Calculates packet increment for packet counters.

  ## Parameters
  - `state` - Device state
  - `counter_type` - Type of packet counter (:in_ucast_pkts, :out_ucast_pkts, etc.)

  ## Returns
  - Integer representing packet count increment since device start
  """
  def calculate_packet_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Packet rates are typically much lower than byte rates
    # Average packet size ~1000 bytes for mixed traffic
    base_pps =
      case {state.device_type, counter_type} do
        # ~125 pps
        {:cable_modem, :in_ucast_pkts} -> 125
        # ~63 pps
        {:cable_modem, :out_ucast_pkts} -> 63
        # ~12.5K pps
        {:cmts, :in_ucast_pkts} -> 12_500
        # ~12.5K pps
        {:cmts, :out_ucast_pkts} -> 12_500
        # Default ~10 pps
        _ -> 10
      end

    # Add time-of-day variation
    time_factor = get_time_factor()
    # -15% to +15%
    jitter = :rand.uniform(31) - 15
    jitter_factor = 1.0 + jitter / 100.0

    # Calculate total packets
    rate_with_variation = trunc(base_pps * time_factor * jitter_factor)
    total_packets = rate_with_variation * uptime_seconds

    # Add some accumulated variance
    # ~7% variance
    base_variance = div(total_packets, 15)
    variance = if base_variance > 0 do
      :rand.uniform(base_variance * 2) - base_variance
    else
      0
    end

    max(0, total_packets + variance)
  end

  @doc """
  Calculates error increment for error counters with environmental factors.

  ## Parameters
  - `state` - Device state
  - `counter_type` - Type of error counter (:in_errors, :out_errors, etc.)

  ## Returns
  - Integer representing error count increment since device start
  """
  def calculate_error_increment(state, counter_type) do
    uptime_seconds = div(calculate_uptime(state), 1000)

    # Error rates should be very low under normal conditions
    # Higher during poor signal quality or high utilization
    base_error_rate =
      case {state.device_type, counter_type} do
        # ~1 error per 100 seconds
        {:cable_modem, :in_errors} -> 0.01
        # ~1 error per 200 seconds
        {:cable_modem, :out_errors} -> 0.005
        # ~1 error per 10 seconds (more traffic)
        {:cmts, :in_errors} -> 0.1
        # ~1 error per 20 seconds
        {:cmts, :out_errors} -> 0.05
        # Very low default
        _ -> 0.001
      end

    # Environmental factors affect error rates
    time_factor = get_time_factor()

    # Higher utilization = more errors (congestion)
    # 0.6x to 2.4x
    utilization_impact = 1.0 + (time_factor - 0.8) * 2.0

    # Signal quality impact (simulated via random factor)
    # 0.7 to 1.3
    signal_quality = 0.7 + :rand.uniform(6) / 10
    # Worse signal = more errors
    signal_impact = 2.0 - signal_quality

    # Calculate error increment
    effective_rate = base_error_rate * utilization_impact * signal_impact
    total_errors = trunc(effective_rate * uptime_seconds)

    # Add burst errors occasionally
    # 5% chance
    burst_probability = 0.05

    if :rand.uniform() < burst_probability do
      # 5-15 extra errors
      burst_errors = :rand.uniform(10) + 5
      max(0, total_errors + burst_errors)
    else
      total_errors
    end
  end

  @doc """
  Calculates Signal-to-Noise Ratio (SNR) gauge value for cable modems.

  ## Parameters
  - `state` - Device state containing device_type

  ## Returns
  - Integer representing SNR in dB (15-45 range for cable modems)
  """
  def calculate_snr_gauge(state) do
    # Base SNR for cable modem (typically 25-40 dB, higher is better)
    base_snr =
      case state.device_type do
        # Good signal quality
        :cable_modem -> 32
        # Default
        _ -> 25
      end

    # Add environmental factors
    time_factor = get_time_factor()
    # -3 to +3 dB weather variation
    weather_impact = :rand.uniform(6) - 3

    # Traffic load affects SNR (higher utilization = slightly lower SNR)
    # Small impact
    utilization_factor = 1.0 - (time_factor - 0.7) * 0.1

    # Calculate final SNR with realistic bounds
    snr = trunc(base_snr * utilization_factor + weather_impact)

    # Clamp to realistic cable modem SNR range (15-45 dB)
    max(15, min(45, snr))
  end

  @doc """
  Calculates CPU utilization gauge with realistic load patterns.

  ## Parameters
  - `state` - Device state containing device_type

  ## Returns
  - Integer representing CPU utilization percentage (0-100)
  """
  def calculate_cpu_gauge(state) do
    # Base CPU load depends on device type
    base_cpu =
      case state.device_type do
        # Light load for residential device
        :cable_modem -> 15
        # Higher load for head-end equipment
        :cmts -> 45
        # Moderate load for network equipment
        :switch -> 25
        # Higher load for routing
        :router -> 35
        # Default
        _ -> 20
      end

    # Add time-of-day variation (more load during peak hours)
    time_factor = get_time_factor()
    # 0-14% additional load during peak
    time_cpu_impact = trunc((time_factor - 0.8) * 20)

    # Add traffic correlation (higher traffic = higher CPU)
    # Cap at 1.2x
    traffic_factor = min(time_factor, 1.2)
    # 0-3% additional load
    traffic_cpu_impact = trunc((traffic_factor - 1.0) * 15)

    # Add random variation for realistic simulation
    # -10% to +10%
    cpu_jitter = :rand.uniform(21) - 10
    jitter_impact = trunc(base_cpu * (cpu_jitter / 100.0))

    # Occasional CPU spikes (process startup, background tasks)
    # 2% chance
    spike_probability = 0.02

    spike_impact =
      if :rand.uniform() < spike_probability do
        # 10-40% spike
        :rand.uniform(30) + 10
      else
        0
      end

    # Calculate final CPU percentage
    final_cpu = base_cpu + time_cpu_impact + traffic_cpu_impact + jitter_impact + spike_impact

    # Clamp to realistic range (0-100%)
    max(0, min(100, final_cpu))
  end

  @doc """
  Calculates storage usage gauge in allocation units (typically KB).

  ## Parameters
  - `state` - Device state containing device_type

  ## Returns
  - Integer representing storage usage in allocation units
  """
  def calculate_storage_gauge(state) do
    # Base storage usage depends on device type (in allocation units)
    # Typical allocation unit is 1KB, so values represent KB used
    base_storage =
      case state.device_type do
        # ~64MB for embedded device
        :cable_modem -> 65_536
        # ~512MB for head-end equipment
        :cmts -> 524_288
        # ~128MB for network equipment
        :switch -> 131_072
        # ~256MB for routing equipment
        :router -> 262_144
        # ~32MB default
        _ -> 32_768
      end

    # Add uptime-based growth (memory leaks, log files, etc.)
    # Convert to hours
    uptime_hours = div(calculate_uptime(state), 3_600_000)
    # 0.1% growth per hour
    growth_factor = 1.0 + uptime_hours * 0.001

    # Add traffic-based memory usage (buffers, connection tables)
    time_factor = get_time_factor()
    # Up to 1% more during peak
    traffic_memory_factor = 1.0 + (time_factor - 0.8) * 0.05

    # Add random variation for cache usage, temporary files, etc.
    # -5% to +5%
    usage_jitter = :rand.uniform(11) - 5
    jitter_factor = 1.0 + usage_jitter / 100.0

    # Calculate final storage usage
    final_storage = trunc(base_storage * growth_factor * traffic_memory_factor * jitter_factor)

    # Ensure reasonable bounds
    # Never below 80% of base
    min_storage = trunc(base_storage * 0.8)
    # Never above 130% of base
    max_storage = trunc(base_storage * 1.3)

    max(min_storage, min(max_storage, final_storage))
  end

  @doc """
  Gets time-of-day factor for simulating traffic patterns.

  Peak traffic occurs during evening hours (8-10 PM) with lower
  utilization during overnight and early morning hours.

  ## Returns
  - Float representing traffic multiplier (0.6 to 1.5)
  """
  def get_time_factor do
    # Simple time-of-day factor (peak at 8-10 PM)
    hour = DateTime.utc_now().hour

    case hour do
      # Peak evening
      h when h >= 20 and h <= 22 -> 1.5
      # Early evening
      h when h >= 18 and h <= 19 -> 1.3
      # Business hours
      h when h >= 8 and h <= 17 -> 1.0
      # Overnight
      h when h >= 0 and h <= 6 -> 0.6
      # Other times
      _ -> 0.8
    end
  end

  @doc """
  Calculates interface utilization as a percentage.

  ## Parameters
  - `_state` - Device state (currently unused)

  ## Returns
  - Float representing interface utilization (0.1 to 0.8)
  """
  def calculate_interface_utilization(_state) do
    # Calculate based on current traffic levels
    # For now, return a random utilization between 0.1 and 0.8
    0.1 + :rand.uniform() * 0.7
  end

  @doc """
  Calculates signal quality metric.

  ## Parameters
  - `_state` - Device state (currently unused)

  ## Returns
  - Float representing signal quality (0.0 to 1.0)
  """
  def calculate_signal_quality(_state) do
    # Calculate signal quality (0.0 to 1.0)
    # Could be based on SNR, power levels, etc.
    base_quality = 0.8
    random_variation = (:rand.uniform() - 0.5) * 0.2
    max(0.0, min(1.0, base_quality + random_variation))
  end

  @doc """
  Calculates CPU utilization correlated with network activity.

  ## Parameters
  - `state` - Device state

  ## Returns
  - Float representing CPU utilization (0.0 to 1.0)
  """
  def calculate_cpu_utilization(state) do
    # CPU utilization often correlates with network activity
    interface_util = calculate_interface_utilization(state)
    base_cpu = 0.2 + interface_util * 0.4
    random_variation = (:rand.uniform() - 0.5) * 0.1
    max(0.0, min(1.0, base_cpu + random_variation))
  end

  @doc """
  Calculates device temperature in Celsius.

  Temperature is affected by CPU load and ambient conditions.

  ## Parameters
  - `state` - Device state

  ## Returns
  - Float representing temperature in Celsius
  """
  def calculate_temperature(state) do
    # Device temperature in Celsius
    # Could be affected by CPU load, ambient temperature, etc.
    base_temp = 35.0
    cpu_util = calculate_cpu_utilization(state)
    # Up to 15°C increase under load
    load_factor = cpu_util * 15.0
    ambient_variation = (:rand.uniform() - 0.5) * 10.0

    base_temp + load_factor + ambient_variation
  end

  @doc """
  Calculates error rate as a percentage based on signal quality.

  ## Parameters
  - `state` - Device state

  ## Returns
  - Float representing error rate percentage (0.0 to 0.05)
  """
  def calculate_error_rate(state) do
    # Error rate as a percentage
    signal_quality = calculate_signal_quality(state)
    # Up to 5% errors with poor signal
    base_error_rate = (1.0 - signal_quality) * 0.05
    max(0.0, base_error_rate)
  end

  @doc """
  Calculates overall device health score.

  Health score is based on signal quality, error rate, and uptime stability.

  ## Parameters
  - `state` - Device state

  ## Returns
  - Float representing health score (0.0 to 1.0)
  """
  def calculate_health_score(state) do
    # Overall device health score (0.0 to 1.0)
    signal_quality = calculate_signal_quality(state)
    error_rate = calculate_error_rate(state)
    uptime = calculate_uptime(state)

    # Health improves with good signal, low errors, and stable uptime
    # Normalize to days
    uptime_factor = min(1.0, uptime / 86400.0)
    health = (signal_quality + (1.0 - error_rate) + uptime_factor) / 3.0
    max(0.0, min(1.0, health))
  end

  @doc """
  Builds correlation factors for related OIDs.

  This can be expanded to track relationships between different metrics.

  ## Parameters
  - `_state` - Device state (currently unused)

  ## Returns
  - Map of correlation factors (currently empty)
  """
  def build_correlation_factors(_state) do
    # Build correlation factors for related OIDs
    # This could be expanded to track actual relationships
    %{}
  end

  defp get_known_oids(device_type) do
    # First try to get OIDs from SharedProfiles if available
    case SharedProfiles.get_all_oids(device_type) do
      {:ok, [_ | _] = oids} ->
        # Convert string OIDs to integer lists and sort numerically
        oids
        |> Enum.map(fn oid_string ->
          oid_string
          |> String.split(".")
          |> Enum.map(&String.to_integer/1)
        end)
        |> Enum.sort_by(&(&1))
        
      _ ->
        # Fallback to hardcoded OIDs when SharedProfiles is not available or empty
        case device_type do
          :cable_modem ->
            [
              [1, 3, 6, 1, 2, 1, 1, 1, 0],
              [1, 3, 6, 1, 2, 1, 1, 2, 0],
              [1, 3, 6, 1, 2, 1, 1, 3, 0],
              [1, 3, 6, 1, 2, 1, 1, 4, 0],
              [1, 3, 6, 1, 2, 1, 1, 5, 0],
              [1, 3, 6, 1, 2, 1, 1, 6, 0],
              [1, 3, 6, 1, 2, 1, 1, 7, 0],
              [1, 3, 6, 1, 2, 1, 2, 1, 0],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 2],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 2],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 1],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 2],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 1],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1],
              [1, 3, 6, 1, 2, 1, 2, 2, 1, 16, 1]
            ]
            # Sort the OIDs numerically to ensure proper lexicographical order
            |> Enum.sort_by(&(&1))

          _ ->
            [
              [1, 3, 6, 1, 2, 1, 1, 1, 0],
              [1, 3, 6, 1, 2, 1, 1, 2, 0],
              [1, 3, 6, 1, 2, 1, 1, 3, 0],
              [1, 3, 6, 1, 2, 1, 1, 4, 0],
              [1, 3, 6, 1, 2, 1, 1, 5, 0],
              [1, 3, 6, 1, 2, 1, 1, 6, 0],
              [1, 3, 6, 1, 2, 1, 1, 7, 0]
            ]
            # Sort the OIDs numerically to ensure proper lexicographical order
            |> Enum.sort_by(&(&1))
        end
    end
  end
end
