defmodule SnmpKit.SnmpSim.Device.BuiltinValues do
  @moduledoc """
  Values for devices that have no walk file or manual OID map: the hard-coded
  system group, interface, DOCSIS, host-resources objects per device type, the
  list of OIDs such a device "knows", and GETNEXT/GETBULK over that list.

  Dynamic numbers come from `SnmpKit.SnmpSim.Device.Metrics`; lookup and
  formatting helpers from `SnmpKit.SnmpSim.Device.OidHandler`.
  """

  alias SnmpKit.SnmpSim.Device.{Metrics, OidHandler}
  alias SnmpKit.SnmpSim.MIB.SharedProfiles
  require Logger

  def get_device_specific_value(device_type, oid_list, state \\ %{}) do
    oid_string = Enum.join(oid_list, ".")

    case oid_string do
      # System group OIDs (1.3.6.1.2.1.1.x.0)
      # sysDescr.0
      "1.3.6.1.2.1.1.1.0" ->
        device_type_str =
          case device_type do
            :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
            :cmts -> "Cisco CMTS Cable Modem Termination System"
            :router -> "Cisco Router"
            :switch -> "SNMP Simulator Device"
            _ -> "SNMP Simulator Device"
          end

        {:ok, {oid_string, :octet_string, device_type_str}}

      # sysObjectID.0
      "1.3.6.1.2.1.1.2.0" ->
        {:ok, {oid_string, :object_identifier, [1, 3, 6, 1, 4, 1, 1, 1]}}

      # sysUpTime.0
      "1.3.6.1.2.1.1.3.0" ->
        {:ok, {oid_string, :timeticks, Metrics.calculate_uptime_ticks(state)}}

      # sysContact.0
      "1.3.6.1.2.1.1.4.0" ->
        {:ok, {oid_string, :octet_string, "admin@example.com"}}

      # sysName.0
      "1.3.6.1.2.1.1.5.0" ->
        {:ok, {oid_string, :octet_string, "cable-modem-sim"}}

      # sysLocation.0
      "1.3.6.1.2.1.1.6.0" ->
        {:ok, {oid_string, :octet_string, "Lab Environment"}}

      # sysServices.0
      "1.3.6.1.2.1.1.7.0" ->
        {:ok, {oid_string, :integer, 72}}

      # Interface group OIDs (1.3.6.1.2.1.2.x.0)
      # ifNumber.0
      "1.3.6.1.2.1.2.1.0" ->
        {:ok, {oid_string, :integer, 2}}

      # Interface table OIDs (1.3.6.1.2.1.2.2.1.x.y)
      # ifIndex.1
      "1.3.6.1.2.1.2.2.1.1.1" ->
        {:ok, {oid_string, :integer, 1}}

      # ifIndex.2
      "1.3.6.1.2.1.2.2.1.1.2" ->
        {:ok, {oid_string, :integer, 2}}

      # ifDescr.1
      "1.3.6.1.2.1.2.2.1.2.1" ->
        {:ok, {oid_string, :octet_string, "eth0"}}

      # ifDescr.2
      "1.3.6.1.2.1.2.2.1.2.2" ->
        {:ok, {oid_string, :octet_string, "eth1"}}

      # ifType.1
      "1.3.6.1.2.1.2.2.1.3.1" ->
        {:ok, {oid_string, :integer, 6}}

      # ifType.2
      "1.3.6.1.2.1.2.2.1.3.2" ->
        {:ok, {oid_string, :integer, 6}}

      # Gauge32 (ifSpeed)
      oid when oid == "1.3.6.1.2.1.2.2.1.5.1" ->
        {:ok, {oid_string, :gauge32, 100_000_000}}

      # Counter32 (ifInOctets)
      oid when oid == "1.3.6.1.2.1.2.2.1.10.1" ->
        {:ok, {oid_string, :counter32, 1_234_567}}

      # Counter32 (ifOutOctets)
      oid when oid == "1.3.6.1.2.1.2.2.1.16.1" ->
        {:ok, {oid_string, :counter32, 7_654_321}}

      _ ->
        case SharedProfiles.get_oid_value(device_type, oid_string, %{
               uptime: 0,
               device_type: device_type
             }) do
          {:ok, {type, value}} -> {:ok, {oid_string, type, value}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def get_hardcoded_oid_value(device_type, oid_list, state) do
    oid_string = Enum.join(oid_list, ".")

    case oid_string do
      # System group OIDs (1.3.6.1.2.1.1.x.0)
      # sysDescr.0
      "1.3.6.1.2.1.1.1.0" ->
        device_type_str =
          case device_type do
            :cable_modem -> "Motorola SB6141 DOCSIS 3.0 Cable Modem"
            :cmts -> "Cisco CMTS Cable Modem Termination System"
            :router -> "Cisco Router"
            :switch -> "SNMP Simulator Device"
            _ -> "SNMP Simulator Device"
          end

        {:ok, {oid_string, :octet_string, device_type_str}}

      # sysObjectID.0
      "1.3.6.1.2.1.1.2.0" ->
        {:ok, {oid_string, :object_identifier, [1, 3, 6, 1, 4, 1, 1, 1]}}

      # sysUpTime.0
      "1.3.6.1.2.1.1.3.0" ->
        {:ok, {oid_string, :timeticks, Metrics.calculate_uptime_ticks(state)}}

      # sysContact.0
      "1.3.6.1.2.1.1.4.0" ->
        {:ok, {oid_string, :octet_string, "admin@example.com"}}

      # sysName.0
      "1.3.6.1.2.1.1.5.0" ->
        {:ok, {oid_string, :octet_string, "cable-modem-sim"}}

      # sysLocation.0
      "1.3.6.1.2.1.1.6.0" ->
        {:ok, {oid_string, :octet_string, "Lab Environment"}}

      # sysServices.0
      "1.3.6.1.2.1.1.7.0" ->
        {:ok, {oid_string, :integer, 72}}

      # Interface group OIDs (1.3.6.1.2.1.2.x.0)
      # ifNumber.0
      "1.3.6.1.2.1.2.1.0" ->
        {:ok, {oid_string, :integer, 2}}

      # Interface table OIDs (1.3.6.1.2.1.2.2.1.x.y)
      # ifIndex.1
      "1.3.6.1.2.1.2.2.1.1.1" ->
        {:ok, {oid_string, :integer, 1}}

      # ifIndex.2
      "1.3.6.1.2.1.2.2.1.1.2" ->
        {:ok, {oid_string, :integer, 2}}

      # ifDescr.1
      "1.3.6.1.2.1.2.2.1.2.1" ->
        {:ok, {oid_string, :octet_string, "eth0"}}

      # ifDescr.2
      "1.3.6.1.2.1.2.2.1.2.2" ->
        {:ok, {oid_string, :octet_string, "eth1"}}

      # ifType.1
      "1.3.6.1.2.1.2.2.1.3.1" ->
        {:ok, {oid_string, :integer, 6}}

      # ifType.2
      "1.3.6.1.2.1.2.2.1.3.2" ->
        {:ok, {oid_string, :integer, 6}}

      # Gauge32 (ifSpeed)
      oid when oid == "1.3.6.1.2.1.2.2.1.5.1" ->
        {:ok, {oid_string, :gauge32, 100_000_000}}

      # Counter32 (ifInOctets)
      oid when oid == "1.3.6.1.2.1.2.2.1.10.1" ->
        {:ok, {oid_string, :counter32, 1_234_567}}

      # Counter32 (ifOutOctets)
      oid when oid == "1.3.6.1.2.1.2.2.1.16.1" ->
        {:ok, {oid_string, :counter32, 7_654_321}}

      _ ->
        {:error, :no_such_name}
    end
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
    start_oid_string =
      case start_oid do
        oid when is_list(oid) -> OidHandler.oid_to_string(oid)
        oid when is_binary(oid) -> oid
      end

    Logger.debug(
      "Fallback bulk OIDs for #{start_oid_string}, max_repetitions: #{max_repetitions}"
    )

    # Collect bulk OIDs iteratively
    get_bulk_oids_iteratively(start_oid, max_repetitions, state, [])
  end

  # Helper function to iteratively collect bulk OIDs
  def get_bulk_oids_iteratively(_current_oid, 0, _state, acc) do
    # Reached max repetitions, return accumulated results
    Enum.reverse(acc)
  end

  def get_bulk_oids_iteratively(current_oid, remaining_count, state, acc) do
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
    current_oid_str = OidHandler.oid_to_string(oid_list)
    known_oids_str = Enum.map(known_oids, &OidHandler.oid_to_string/1)

    current_index = Enum.find_index(known_oids_str, &(&1 == current_oid_str))

    if current_index != nil and current_index + 1 < length(known_oids) do
      next_index = current_index + 1
      next_oid = Enum.at(known_oids, next_index)

      case get_hardcoded_oid_value(device_type, next_oid, state) do
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
      sorted_oids = Enum.sort_by(known_oids, &OidHandler.oid_to_string/1)

      next_oid =
        Enum.find(sorted_oids, fn oid -> OidHandler.oid_to_string(oid) > current_oid_str end)

      if next_oid do
        case get_hardcoded_oid_value(device_type, next_oid, state) do
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
          # ifIndex
          "1" -> {:ok, {oid, :integer, 1}}
          # ifDescr
          "2" -> {:ok, {oid, :octet_string, "Ethernet"}}
          # ifType (6 = ethernetCsmacd)
          "3" -> {:ok, {oid, :integer, 6}}
          # ifMtu
          "4" -> {:ok, {oid, :gauge32, 1500}}
          # ifSpeed (10Mbps)
          "5" -> {:ok, {oid, :gauge32, 10_000_000}}
          # ifPhysAddress
          "6" -> {:ok, {oid, :octet_string, <<0, 1, 2, 3, 4, 5>>}}
          # ifAdminStatus (1 = up)
          "7" -> {:ok, {oid, :integer, 1}}
          # ifOperStatus (1 = up)
          "8" -> {:ok, {oid, :integer, 1}}
          # ifInOctets
          "10" -> {:ok, {oid, :counter32, 1000}}
          # ifInUcastPkts
          "11" -> {:ok, {oid, :counter32, 100}}
          # ifOutOctets
          "16" -> {:ok, {oid, :counter32, 900}}
          # ifOutUcastPkts
          "17" -> {:ok, {oid, :counter32, 90}}
          _ -> {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
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
            increment = Metrics.calculate_traffic_increment(state, :hc_in_octets)
            {:ok, {oid, :counter64, base_count + increment}}

          {"10", "1"} ->
            # ifHCOutOctets.1 - high capacity output octets (Counter64)
            # 35GB base
            base_count = 35_000_000_000
            increment = Metrics.calculate_traffic_increment(state, :hc_out_octets)
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
            snr_value = Metrics.calculate_snr_gauge(state)
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
            cpu_load = Metrics.calculate_cpu_gauge(state)
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
            storage_used = Metrics.calculate_storage_gauge(state)
            {:ok, {oid, :gauge32, storage_used}}

          _ ->
            {:error, :no_such_name}
        end

      _ ->
        {:error, :no_such_name}
    end
  end

  def get_known_oids(device_type) do
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
        |> Enum.sort_by(& &1)

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
            |> Enum.sort_by(& &1)

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
            |> Enum.sort_by(& &1)
        end
    end
  end
end
