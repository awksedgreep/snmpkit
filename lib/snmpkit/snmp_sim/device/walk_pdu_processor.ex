defmodule SnmpKit.SnmpSim.Device.WalkPduProcessor do
  @moduledoc """
  Simplified PDU processor for devices with walk data.
  Handles GET, GETNEXT, and GETBULK requests using walk file data
  with support for dynamic counters and gauges.
  """

  require Logger
  alias SnmpKit.SnmpSim.MIB.SharedProfiles
  alias SnmpKit.SnmpSim.PDUHelper, as: PduHelper

  @doc """
  Process a GET request for walk-based devices.
  """
  def process_get_request(pdu, state) do
    varbinds =
      Enum.map(pdu.varbinds, fn
        {oid, _, _} -> get_varbind_value(oid, state)
        {oid, _} -> get_varbind_value(oid, state)
      end)

    error_status = if Enum.any?(varbinds, &is_error_varbind?/1), do: 2, else: 0
    error_index = find_error_index(varbinds)

    %{
      pdu
      | type: :get_response,
        varbinds: varbinds,
        error_status: error_status,
        error_index: error_index
    }
  end

  @doc """
  Process a GETNEXT request for walk-based devices.
  """
  def process_getnext_request(pdu, state) do
    pdu_version_int = PduHelper.pdu_version_to_int(pdu.version)

    varbinds =
      Enum.map(pdu.varbinds, fn
        {oid, _, _} ->
          get_next_varbind_value(oid, state, pdu_version_int)

        {oid, _} ->
          get_next_varbind_value(oid, state, pdu_version_int)

        oid when is_list(oid) ->
          get_next_varbind_value(oid, state, pdu_version_int)

        other ->
          Logger.debug("WalkPduProcessor: Unexpected varbind format: #{inspect(other)}")
          get_next_varbind_value(other, state, pdu_version_int)
      end)

    %{
      pdu
      | type: :get_response,
        varbinds: varbinds,
        error_status: 0,
        error_index: 0
    }
  end

  @doc """
  Process a GETBULK request for walk-based devices.
  """
  def process_getbulk_request(pdu, state) do
    %{non_repeaters: _non_repeaters, max_repetitions: _max_repetitions, varbinds: _varbinds} = pdu

    Logger.debug("WalkPduProcessor: Processing GETBULK with PDU: #{inspect(pdu)}")
    Logger.debug("WalkPduProcessor: PDU version: #{inspect(pdu.version)}")

    # For SNMPv1, GETBULK is not officially supported, but we'll process it as GETNEXT
    if pdu.version == 1 do
      # Process as individual GETNEXT operations for SNMPv1
      process_getbulk_as_getnext_v1(pdu, state)
    else
      # Normal SNMPv2c GETBULK processing
      process_getbulk_v2(pdu, state)
    end
  end

  defp process_getbulk_v2(pdu, state) do
    %{non_repeaters: non_repeaters, max_repetitions: max_repetitions, varbinds: varbinds} = pdu

    # Split varbinds into non-repeaters and repeaters
    {non_repeater_oids, repeater_oids} = Enum.split(varbinds, non_repeaters)

    # Process non-repeaters (like GETNEXT)
    non_repeater_varbinds =
      Enum.map(non_repeater_oids, fn
        {oid, _, _} ->
          get_next_varbind_value(oid, state, 2)

        {oid, _} ->
          get_next_varbind_value(oid, state, 2)

        oid when is_list(oid) ->
          get_next_varbind_value(oid, state, 2)

        other ->
          Logger.debug("WalkPduProcessor: Unexpected varbind format: #{inspect(other)}")
          get_next_varbind_value(other, state, 2)
      end)

    # Process repeaters (bulk operation)
    repeater_varbinds = process_bulk_oids(repeater_oids, max_repetitions, state, 2)

    # Combine all varbinds
    all_varbinds = non_repeater_varbinds ++ repeater_varbinds

    # Create response PDU without GETBULK-specific fields
    %{
      type: :get_response,
      version: pdu.version,
      request_id: pdu.request_id,
      community: pdu.community,
      varbinds: all_varbinds,
      error_status: 0,
      error_index: 0
    }
  end

  defp process_getbulk_as_getnext_v1(pdu, state) do
    %{varbinds: varbinds} = pdu

    # Process each varbind as GETNEXT and check for errors
    {result_varbinds, error_status, error_index} =
      varbinds
      |> Enum.with_index(1)
      |> Enum.reduce_while({[], 0, 0}, fn {varbind, _index}, {acc_varbinds, _, _} ->
        oid =
          case varbind do
            {oid, _, _} -> oid
            {oid, _} -> oid
            oid when is_list(oid) -> oid
          end

        case get_next_varbind_value_v1(oid, state) do
          {:ok, varbind} ->
            {:cont, {[varbind | acc_varbinds], 0, 0}}

          {:error, :no_such_name} ->
            # Return end_of_mib_view instead of original OID for GETBULK
            end_of_mib_varbind = {oid, :end_of_mib_view, {:end_of_mib_view, nil}}
            {:cont, {[end_of_mib_varbind | acc_varbinds], 0, 0}}
        end
      end)

    final_varbinds = Enum.reverse(result_varbinds)

    %{
      type: :get_response,
      version: pdu.version,
      request_id: pdu.request_id,
      community: pdu.community,
      varbinds: final_varbinds,
      error_status: error_status,
      error_index: error_index
    }
  end

  @doc """
  Process a SET request for walk-based devices.
  Since walk files contain read-only data, all SET requests return readOnly error.
  """
  def process_set_request(pdu, _state) do
    Logger.debug("WalkPduProcessor: Processing SET request - returning readOnly error")

    %{
      pdu
      | type: :get_response,
        # readOnly error
        error_status: 4,
        # First varbind caused the error
        error_index: 1
    }
  end

  defp get_next_varbind_value_v1(oid, state) do
    oid_string = oid_to_string(oid)

    Logger.debug(
      "WalkPduProcessor: Getting next OID for #{oid_string}, device_type: #{inspect(state.device_type)}"
    )

    # First get the next OID - check manual oid_map first
    next_oid_result = cond do
      Map.has_key?(state, :oid_map) and map_size(state.oid_map) > 0 ->
        get_next_oid_from_manual_map(oid_string, state.oid_map)

      true ->
        SharedProfiles.get_next_oid(state.device_type, oid_string)
    end

    case next_oid_result do
      {:ok, next_oid_string} ->
        Logger.debug("WalkPduProcessor: Next OID is #{next_oid_string}")
        # Then get its value - check manual oid_map first
        case get_oid_value_with_fallback(next_oid_string, state) do
          {:ok, {type, value}} ->
            next_oid = string_to_oid_list(next_oid_string)
            {:ok, {next_oid, type, value}}

          {:error, _reason} ->
            {:error, :no_such_name}
        end

      :end_of_mib ->
        Logger.debug("WalkPduProcessor: End of MIB reached for #{oid_string}")
        {:error, :no_such_name}

      {:error, reason} ->
        Logger.debug(
          "WalkPduProcessor: Error getting next OID for #{oid_string}: #{inspect(reason)}"
        )

        {:error, :no_such_name}

      :not_found ->
        Logger.debug("WalkPduProcessor: No next OID found for #{oid_string}")
        {:error, :no_such_name}
    end
  end

  # Helper function to get OID value with manual map fallback
  defp get_oid_value_with_fallback(oid_string, state) do
    cond do
      # Check dynamic counters
      Map.has_key?(state.counters, oid_string) ->
        {:ok, {:counter32, Map.get(state.counters, oid_string)}}

      # Check dynamic gauges
      Map.has_key?(state.gauges, oid_string) ->
        {:ok, {:gauge32, Map.get(state.gauges, oid_string)}}

      # Special case for uptime
      oid_string == "1.3.6.1.2.1.1.3.0" ->
        {:ok, {:timeticks, calculate_uptime_ticks(state)}}

      # Check manual OID map
      Map.has_key?(state, :oid_map) and Map.has_key?(state.oid_map, oid_string) ->
        case Map.get(state.oid_map, oid_string) do
          %{type: type_str, value: value} ->
            atom_type = convert_snmp_type(type_str)
            {:ok, {atom_type, value}}
          value when is_binary(value) ->
            {:ok, {:octet_string, value}}
          value when is_integer(value) ->
            {:ok, {:integer, value}}
          value ->
            {:ok, {:octet_string, to_string(value)}}
        end

      # Default: get from SharedProfiles
      true ->
        SharedProfiles.get_oid_value(state.device_type, oid_string, state)
    end
  end

  # Private functions

  defp get_varbind_value(oid, state) do
    oid_string = oid_to_string(oid)
    oid_list = normalize_oid_to_list(oid)

    # Check for dynamic values first
    cond do
      # Dynamic counters
      Map.has_key?(state.counters, oid_string) ->
        {oid_list, :counter32, Map.get(state.counters, oid_string)}

      # Dynamic gauges
      Map.has_key?(state.gauges, oid_string) ->
        {oid_list, :gauge32, Map.get(state.gauges, oid_string)}

      # Special case for uptime
      oid_string == "1.3.6.1.2.1.1.3.0" ->
        uptime_ticks = calculate_uptime_ticks(state)
        {oid_list, :timeticks, uptime_ticks}

      # Check manual OID map
      Map.has_key?(state, :oid_map) and Map.has_key?(state.oid_map, oid_string) ->
        case Map.get(state.oid_map, oid_string) do
          %{type: type, value: value} ->
            atom_type = convert_snmp_type(type)
            {oid_list, atom_type, value}

          # Handle simple string values
          value when is_binary(value) ->
            {oid_list, :octet_string, value}

          # Handle simple integer values
          value when is_integer(value) ->
            {oid_list, :integer, value}

          # Handle other simple values
          value ->
            {oid_list, :octet_string, to_string(value)}
        end

      # Default: get from walk file
      true ->
        case SharedProfiles.get_oid_value(state.device_type, oid_string, state) do
          {:ok, {type, value}} ->
            {oid_list, type, value}

          :not_found ->
            {oid_list, :no_such_object, {:no_such_object, nil}}

          {:error, :no_such_name} ->
            {oid_list, :no_such_object, {:no_such_object, nil}}

          {:error, :device_type_not_found} ->
            {oid_list, :no_such_object, {:no_such_object, nil}}
        end
    end
  end

  defp get_next_varbind_value(oid, state, pdu_version) do
    oid_string = oid_to_string(oid)

    Logger.debug(
      "WalkPduProcessor: Getting next OID for #{oid_string}, device_type: #{inspect(state.device_type)}"
    )

    # First get the next OID - check manual oid_map first
    next_oid_result = cond do
      Map.has_key?(state, :oid_map) and map_size(state.oid_map) > 0 ->
        get_next_oid_from_manual_map(oid_string, state.oid_map)

      true ->
        SharedProfiles.get_next_oid(state.device_type, oid_string)
    end

    case next_oid_result do
      {:ok, next_oid_string} ->
        Logger.debug("WalkPduProcessor: Next OID is #{next_oid_string}")
        next_oid = string_to_oid_list(next_oid_string)

        # Then get its value - check manual oid_map and dynamic values first
        cond do
          # Check dynamic counters
          Map.has_key?(state.counters, next_oid_string) ->
            {next_oid, :counter32, Map.get(state.counters, next_oid_string)}

          # Check dynamic gauges
          Map.has_key?(state.gauges, next_oid_string) ->
            {next_oid, :gauge32, Map.get(state.gauges, next_oid_string)}

          # Special case for uptime
          next_oid_string == "1.3.6.1.2.1.1.3.0" ->
            {next_oid, :timeticks, calculate_uptime_ticks(state)}

          # Check manual oid_map for the next OID value
          Map.has_key?(state, :oid_map) and Map.has_key?(state.oid_map, next_oid_string) ->
            case Map.get(state.oid_map, next_oid_string) do
              %{type: type_str, value: value} ->
                atom_type = convert_snmp_type(type_str)
                {next_oid, atom_type, value}
              value when is_binary(value) ->
                {next_oid, :octet_string, value}
              value when is_integer(value) ->
                {next_oid, :integer, value}
              value ->
                {next_oid, :octet_string, to_string(value)}
            end

          # Fallback to SharedProfiles
          true ->
            case SharedProfiles.get_oid_value(state.device_type, next_oid_string, state) do
              {:ok, {type, value}} ->
                {next_oid, type, value}

              :not_found ->
                # SNMPv1 vs SNMPv2c+
                if pdu_version == 1 do
                  {next_oid, :no_such_instance, {:no_such_instance, nil}}
                else
                  {next_oid, :no_such_object, {:no_such_object, nil}}
                end

              {:error, reason} ->
                Logger.debug(
                  "WalkPduProcessor: Failed to get value for #{next_oid_string}: #{inspect(reason)}"
                )
                {next_oid, :no_such_object, {:no_such_object, nil}}
            end
        end

      :end_of_mib ->
        Logger.debug("WalkPduProcessor: End of MIB reached for #{oid_string}")
        oid_list = normalize_oid_to_list(oid)
        # SNMPv2c+
        # SNMPv1
        if pdu_version == 1 do
          {oid_list, :end_of_mib_view, {:end_of_mib_view, nil}}
        else
          {oid_list, :no_such_object, {:no_such_object, nil}}
        end

      {:error, reason} ->
        Logger.debug(
          "WalkPduProcessor: Failed to get next OID for #{oid_string}: #{inspect(reason)}"
        )

        oid_list = normalize_oid_to_list(oid)
        {oid_list, :no_such_object, {:no_such_object, nil}}

      :not_found ->
        oid_list = normalize_oid_to_list(oid)

        if pdu_version == 1 do
          {oid_list, :no_such_name, {:no_such_name, nil}}
        else
          {oid_list, :no_such_object, {:no_such_object, nil}}
        end
    end
  end

  defp process_bulk_oids(oids, max_repetitions, state, pdu_version) do
    Enum.flat_map(oids, fn
      {oid, _, _} -> get_bulk_varbinds(oid, max_repetitions, state, pdu_version)
      {oid, _} -> get_bulk_varbinds(oid, max_repetitions, state, pdu_version)
      oid when is_list(oid) -> get_bulk_varbinds(oid, max_repetitions, state, pdu_version)
    end)
  end

  defp get_bulk_varbinds(start_oid, max_repetitions, state, pdu_version) do
    start_oid_string = oid_to_string(start_oid)

    # Limit max_repetitions to prevent huge responses that can cause UDP packet size issues
    limited_max_repetitions = min(max_repetitions, 50)

    # Collect OIDs for bulk operation
    bulk_oids =
      collect_bulk_oids(start_oid_string, limited_max_repetitions, state, [])

    # If no OIDs were collected (e.g., invalid start OID), return end_of_mib_view varbinds
    if Enum.empty?(bulk_oids) do
      # Return the requested number of end_of_mib_view varbinds
      List.duplicate(
        if pdu_version == 1 do
          {start_oid, :no_such_name, {:no_such_name, nil}}
        else
          {start_oid, :end_of_mib_view, {:end_of_mib_view, nil}}
        end,
        limited_max_repetitions
      )
    else
      # Map each OID to its value
      Enum.map(bulk_oids, fn
        :end_of_mib_marker ->
          # Handle end of MIB markers
          start_oid_list = normalize_oid_to_list(start_oid)

          if pdu_version == 1 do
            {start_oid_list, :no_such_name, {:no_such_name, nil}}
          else
            {start_oid_list, :end_of_mib_view, {:end_of_mib_view, nil}}
          end

        next_oid_string ->
          next_oid = string_to_oid_list(next_oid_string)

          # Check for dynamic values first
          cond do
            Map.has_key?(state.counters, next_oid_string) ->
              {next_oid, :counter32, Map.get(state.counters, next_oid_string)}

            Map.has_key?(state.gauges, next_oid_string) ->
              {next_oid, :gauge32, Map.get(state.gauges, next_oid_string)}

            next_oid_string == "1.3.6.1.2.1.1.3.0" ->
              {next_oid, :timeticks, calculate_uptime_ticks(state)}

            # Check manual oid_map
            Map.has_key?(state, :oid_map) and Map.has_key?(state.oid_map, next_oid_string) ->
              case Map.get(state.oid_map, next_oid_string) do
                %{type: type_str, value: value} ->
                  atom_type = convert_snmp_type(type_str)
                  {next_oid, atom_type, value}
                value when is_binary(value) ->
                  {next_oid, :octet_string, value}
                value when is_integer(value) ->
                  {next_oid, :integer, value}
                value ->
                  {next_oid, :octet_string, to_string(value)}
              end

            # Try SharedProfiles as fallback
            true ->
              case SharedProfiles.get_oid_value(state.device_type, next_oid_string, state) do
                {:ok, {type, value}} ->
                  {next_oid, type, value}

                :not_found ->
                  if pdu_version == 1 do
                    {next_oid, :no_such_name, {:no_such_name, nil}}
                  else
                    {next_oid, :end_of_mib_view, {:end_of_mib_view, nil}}
                  end

                {:error, :no_such_name} ->
                  if pdu_version == 1 do
                    {next_oid, :no_such_name, {:no_such_name, nil}}
                  else
                    {next_oid, :end_of_mib_view, {:end_of_mib_view, nil}}
                  end

                {:error, :device_type_not_found} ->
                  if pdu_version == 1 do
                    {next_oid, :no_such_name, {:no_such_name, nil}}
                  else
                    {next_oid, :end_of_mib_view, {:end_of_mib_view, nil}}
                  end

                {:error, _reason} ->
                  if pdu_version == 1 do
                    {next_oid, :no_such_name, {:no_such_name, nil}}
                  else
                    {next_oid, :end_of_mib_view, {:end_of_mib_view, nil}}
                  end
              end
          end
      end)
    end
  end

  defp collect_bulk_oids(_current_oid, 0, _state, acc), do: Enum.reverse(acc)

  defp collect_bulk_oids(current_oid, remaining, state, acc) do
    # Use manual oid_map if available, otherwise use SharedProfiles
    next_oid_result = cond do
      Map.has_key?(state, :oid_map) and map_size(state.oid_map) > 0 ->
        get_next_oid_from_manual_map(current_oid, state.oid_map)

      true ->
        SharedProfiles.get_next_oid(state.device_type, current_oid)
    end

    case next_oid_result do
      {:ok, next_oid} ->
        collect_bulk_oids(next_oid, remaining - 1, state, [next_oid | acc])

      :end_of_mib ->
        # End of MIB reached, fill remaining slots with end_of_mib markers
        end_of_mib_markers = List.duplicate(:end_of_mib_marker, remaining)
        Enum.reverse(acc) ++ end_of_mib_markers

      :not_found ->
        # No next OID found, fill remaining slots with end_of_mib markers
        end_of_mib_markers = List.duplicate(:end_of_mib_marker, remaining)
        Enum.reverse(acc) ++ end_of_mib_markers

      {:error, :device_type_not_found} ->
        # Device type not found in SharedProfiles, fill remaining slots with end_of_mib markers
        end_of_mib_markers = List.duplicate(:end_of_mib_marker, remaining)
        Enum.reverse(acc) ++ end_of_mib_markers

      {:error, _reason} ->
        # Other errors, fill remaining slots with end_of_mib markers
        end_of_mib_markers = List.duplicate(:end_of_mib_marker, remaining)
        Enum.reverse(acc) ++ end_of_mib_markers
    end
  end

  defp oid_to_string(oid) when is_list(oid), do: Enum.join(oid, ".")
  defp oid_to_string(oid) when is_binary(oid), do: oid
  defp oid_to_string(oid), do: to_string(oid)

  defp string_to_oid_list(oid_string) when is_binary(oid_string) do
    oid_string
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end

  # Helper function to normalize OID to list format for SNMP encoding
  defp normalize_oid_to_list(oid) when is_list(oid), do: oid
  defp normalize_oid_to_list(oid) when is_binary(oid), do: string_to_oid_list(oid)
  defp normalize_oid_to_list(oid), do: string_to_oid_list(to_string(oid))

  defp calculate_uptime_ticks(state) do
    current_time = :erlang.monotonic_time()
    elapsed_native = current_time - state.uptime_start
    elapsed_ms = :erlang.convert_time_unit(elapsed_native, :native, :millisecond)
    div(elapsed_ms, 10)
  end

  defp is_error_varbind?({_, :no_such_object, _}), do: true
  defp is_error_varbind?({_, :no_such_instance, _}), do: true
  defp is_error_varbind?(_), do: false

  defp find_error_index(varbinds) do
    varbinds
    |> Enum.with_index(1)
    |> Enum.find_value(fn
      {{_, :no_such_object, _}, idx} -> idx
      {{_, :no_such_instance, _}, idx} -> idx
      _ -> nil
    end) || 0
  end

  # Helper function to get next OID from manual OID map
  defp get_next_oid_from_manual_map(oid_string, oid_map) do
    # Use the public OID library functions for validation and sorting
    alias SnmpKit.SnmpLib.OID

    # Convert string OID to list format for validation
    current_oid_parts = try do
      oid_string
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)
    rescue
      _ -> nil
    end

    if current_oid_parts == nil do
      {:error, :invalid_oid}
    else
      # Get all valid OID keys and convert to list format
      valid_oids =
        Map.keys(oid_map)
        |> Enum.filter(fn oid_key ->
          try do
            oid_key
            |> String.split(".")
            |> Enum.map(&String.to_integer/1)
            true
          rescue
            _ -> false
          end
        end)
        |> Enum.map(fn oid_key ->
          oid_parts = oid_key
                     |> String.split(".")
                     |> Enum.map(&String.to_integer/1)
          {oid_key, oid_parts}
        end)
        |> Enum.sort_by(fn {_oid_string, oid_parts} -> oid_parts end, &(OID.compare(&1, &2) != :gt))

      # Find the next OID lexicographically
      next_oid = Enum.find(valid_oids, fn {_oid_string, candidate_parts} ->
        OID.compare(candidate_parts, current_oid_parts) == :gt
      end)

      case next_oid do
        {oid_string, _parts} -> {:ok, oid_string}
        nil -> :end_of_mib
      end
    end
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
      _ -> String.to_atom(String.downcase(type))
    end
  end
  defp convert_snmp_type(_), do: :octet_string
end
