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

    # SNMPv2c: exceptions (noSuchObject/noSuchInstance) travel in the varbinds
    # with error-status 0. SNMPv1: noSuchName error with the request echoed.
    %{pdu | type: :get_response, varbinds: varbinds, error_status: 0, error_index: 0}
    |> PduHelper.apply_v1_error_semantics(PduHelper.snmp_version(pdu), pdu.varbinds)
  end

  @doc """
  Process a GETNEXT request for walk-based devices.
  """
  def process_getnext_request(pdu, state) do
    varbinds =
      Enum.map(pdu.varbinds, fn
        {oid, _, _} ->
          get_next_varbind_value(oid, state)

        {oid, _} ->
          get_next_varbind_value(oid, state)

        oid when is_list(oid) ->
          get_next_varbind_value(oid, state)

        other ->
          Logger.debug("WalkPduProcessor: Unexpected varbind format: #{inspect(other)}")
          get_next_varbind_value(other, state)
      end)

    # End of MIB is an endOfMibView exception for SNMPv2c (RFC 3416 4.2.2) and
    # a noSuchName error for SNMPv1 (RFC 1157 4.1.3); the branches used to be
    # inverted, and the version check compared an integer with an atom.
    %{pdu | type: :get_response, varbinds: varbinds, error_status: 0, error_index: 0}
    |> PduHelper.apply_v1_error_semantics(PduHelper.snmp_version(pdu), pdu.varbinds)
  end

  @doc """
  Process a GETBULK request for walk-based devices.
  """
  def process_getbulk_request(pdu, state) do
    %{non_repeaters: _non_repeaters, max_repetitions: _max_repetitions, varbinds: _varbinds} = pdu

    Logger.debug("WalkPduProcessor: Processing GETBULK with PDU: #{inspect(pdu)}")
    Logger.debug("WalkPduProcessor: PDU version: #{inspect(pdu.version)}")

    # GETBULK does not exist in SNMPv1; treat it as GETNEXT with v1 semantics
    case PduHelper.snmp_version(pdu) do
      :v1 -> process_getbulk_as_getnext_v1(pdu, state)
      :v2c -> process_getbulk_v2(pdu, state)
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
          get_next_varbind_value(oid, state)

        {oid, _} ->
          get_next_varbind_value(oid, state)

        oid when is_list(oid) ->
          get_next_varbind_value(oid, state)

        other ->
          Logger.debug("WalkPduProcessor: Unexpected varbind format: #{inspect(other)}")
          get_next_varbind_value(other, state)
      end)

    # Process repeaters (bulk operation)
    repeater_varbinds = process_bulk_oids(repeater_oids, max_repetitions, state)

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
      |> Enum.reduce_while({[], 0, 0}, fn {varbind, index}, {acc_varbinds, _, _} ->
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
            # RFC 1157: noSuchName, request varbinds echoed
            {:halt, {pdu.varbinds |> normalize_request_varbinds() |> Enum.reverse(), 2, index}}
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

  defp normalize_request_varbinds(varbinds) do
    Enum.map(varbinds, fn
      {oid, type, value} -> {normalize_oid_to_list(oid), type, value}
      {oid, value} -> {normalize_oid_to_list(oid), :null, value}
      oid -> {normalize_oid_to_list(oid), :null, :null}
    end)
  end

  @doc """
  Process a SET request for walk-based devices.
  Supports special-case writable OIDs for DOCSIS modem upgrade flow.
  Other OIDs remain read-only.
  """
  def process_set_request(pdu, state) do
    Logger.debug("WalkPduProcessor: Processing SET request (with writable OIDs for :cable_modem)")

    {all_ok?, err_index, err_status, _new_state} =
      pdu.varbinds
      |> Enum.with_index(1)
      |> Enum.reduce({true, 0, 0, state}, fn {vb, idx}, {ok?, _ei, _es, st} ->
        case handle_set_varbind(vb, st) do
          {:ok, st2} -> {ok? and true, 0, 0, st2}
          {:error, code_atom} -> {false, idx, error_code(code_atom), st}
        end
      end)

    if all_ok? do
      # No error; when admin trigger is set, send trigger message
      maybe_trigger = Enum.any?(pdu.varbinds, &admin_trigger?/1)

      if maybe_trigger do
        send(self(), {:modem_upgrade, :trigger})
      end

      %{
        pdu
        | type: :get_response,
          error_status: 0,
          error_index: 0
      }
    else
      %{
        pdu
        | type: :get_response,
          error_status: err_status,
          error_index: err_index
      }
    end
  end

  defp admin_trigger?({oid, _type, value}), do: admin_trigger?({oid, value})

  defp admin_trigger?({oid, value}) do
    oid_str = oid_to_string(oid)
    oid_str == "1.3.6.1.2.1.69.1.3.1.0" and is_integer(value) and value == 1
  end

  # Handle a single SET varbind for DOCSIS upgrade OIDs; others are read-only
  defp handle_set_varbind({oid, _type, value}, state), do: handle_set_varbind({oid, value}, state)

  defp handle_set_varbind({oid, value}, state) do
    oid_str = oid_to_string(oid)

    case {state.device_type, oid_str} do
      {:cable_modem, "1.3.6.1.2.1.69.1.3.3.0"} ->
        # docsDevSwServer (IpAddress; read-write)
        case value do
          v when is_binary(v) ->
            if ip_string_valid?(v) do
              send(self(), {:modem_upgrade, {:set, :server, v}})
              {:ok, state}
            else
              {:error, :wrongValue}
            end

          _ ->
            {:error, :wrongType}
        end

      {:cable_modem, "1.3.6.1.2.1.69.1.3.4.0"} ->
        # docsDevSwFilename (SnmpAdminString SIZE(0..64); read-write)
        case value do
          v when is_binary(v) and byte_size(v) <= 64 ->
            send(self(), {:modem_upgrade, {:set, :filename, v}})
            {:ok, state}

          v when is_binary(v) ->
            {:error, :wrongLength}

          _ ->
            {:error, :wrongType}
        end

      {:cable_modem, "1.3.6.1.2.1.69.1.3.1.0"} ->
        # docsDevSwAdminStatus (INTEGER; read-write)
        case value do
          v when is_integer(v) and v in [1, 2, 3] ->
            cond do
              state.upgrade_enabled == false ->
                {:error, :notWritable}

              # Already in-progress and trying to trigger again
              v == 1 and Map.get(state.upgrade, :oper_status) == 1 ->
                {:error, :inconsistentValue}

              # Trigger requires valid server/filename
              v == 1 and
                  (state.upgrade.server == "0.0.0.0" or
                     state.upgrade.filename in ["", "(unknown)"]) ->
                {:error, :wrongValue}

              true ->
                send(self(), {:modem_upgrade, {:set, :admin_status, v}})
                {:ok, state}
            end

          v when is_integer(v) ->
            {:error, :wrongValue}

          _ ->
            {:error, :wrongType}
        end

      # All other OIDs are read-only
      _ ->
        {:error, :notWritable}
    end
  end

  # SNMPv2c error-status codes for the errors the SET handlers above produce
  defp error_code(:wrongType), do: 7
  defp error_code(:wrongLength), do: 8
  defp error_code(:wrongValue), do: 10
  defp error_code(:inconsistentValue), do: 12
  defp error_code(:notWritable), do: 17

  defp ip_string_valid?(str) when is_binary(str) do
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
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp get_next_varbind_value_v1(oid, state) do
    oid_string = oid_to_string(oid)

    Logger.debug(
      "WalkPduProcessor: Getting next OID for #{oid_string}, device_type: #{inspect(state.device_type)}"
    )

    # First get the next OID - check manual oid_map first
    next_oid_result =
      cond do
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

    # DOCSIS modem upgrade scalar overrides
    case {state.device_type, oid_string} do
      # These return bare varbind tuples like every other clause; wrapping them
      # in {:ok, _} made the response unencodable so GETs of the upgrade OIDs on
      # walk-data devices never got an answer.
      {:cable_modem, "1.3.6.1.2.1.69.1.3.2.0"} ->
        # docsDevSwOperStatus (INTEGER; read-only)
        {oid_list, :integer, Map.get(state.upgrade, :oper_status, 5)}

      {:cable_modem, "1.3.6.1.2.1.69.1.3.3.0"} ->
        # docsDevSwServer (IpAddress; read-write)
        {oid_list, :ip_address, Map.get(state.upgrade, :server, "0.0.0.0")}

      {:cable_modem, "1.3.6.1.2.1.69.1.3.4.0"} ->
        # docsDevSwFilename (SnmpAdminString; read-write)
        {oid_list, :octet_string, Map.get(state.upgrade, :filename, "(unknown)")}

      {:cable_modem, "1.3.6.1.2.1.69.1.3.1.0"} ->
        # docsDevSwAdminStatus (INTEGER; read-write)
        {oid_list, :integer, Map.get(state.upgrade, :admin_status, 2)}

      _ ->
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

              {:error, :no_such_name} ->
                {oid_list, :no_such_object, {:no_such_object, nil}}

              {:error, :device_type_not_found} ->
                {oid_list, :no_such_object, {:no_such_object, nil}}
            end
        end
    end
  end

  defp get_next_varbind_value(oid, state) do
    oid_string = oid_to_string(oid)

    Logger.debug(
      "WalkPduProcessor: Getting next OID for #{oid_string}, device_type: #{inspect(state.device_type)}"
    )

    # First get the next OID - check manual oid_map first
    next_oid_result =
      cond do
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

              {:error, reason} ->
                Logger.debug(
                  "WalkPduProcessor: Failed to get value for #{next_oid_string}: #{inspect(reason)}"
                )

                {next_oid, :no_such_object, {:no_such_object, nil}}
            end
        end

      :end_of_mib ->
        Logger.debug("WalkPduProcessor: End of MIB reached for #{oid_string}")
        {normalize_oid_to_list(oid), :end_of_mib_view, {:end_of_mib_view, nil}}

      {:error, reason} ->
        Logger.debug(
          "WalkPduProcessor: Failed to get next OID for #{oid_string}: #{inspect(reason)}"
        )

        oid_list = normalize_oid_to_list(oid)
        {oid_list, :no_such_object, {:no_such_object, nil}}
    end
  end

  defp process_bulk_oids(oids, max_repetitions, state) do
    Enum.flat_map(oids, fn
      {oid, _, _} -> get_bulk_varbinds(oid, max_repetitions, state)
      {oid, _} -> get_bulk_varbinds(oid, max_repetitions, state)
      oid when is_list(oid) -> get_bulk_varbinds(oid, max_repetitions, state)
    end)
  end

  defp get_bulk_varbinds(start_oid, max_repetitions, state) do
    start_oid_string = oid_to_string(start_oid)
    # Honour the manager's max-repetitions as-is: operators tune it to their
    # network (jumbo frames included) and real agents do not cap it.
    limited_max_repetitions = max(0, max_repetitions)

    # Collect successors; the list ends with a single :end_of_mib_marker when
    # the MIB view is exhausted (RFC 3416 4.2.3 allows the response to stop
    # there instead of padding every remaining repetition).
    bulk_oids = collect_bulk_oids(start_oid_string, limited_max_repetitions, state, [])

    if Enum.empty?(bulk_oids) do
      []
    else
      # Map each OID to its value
      Enum.map(bulk_oids, fn
        :end_of_mib_marker ->
          {normalize_oid_to_list(start_oid), :end_of_mib_view, {:end_of_mib_view, nil}}

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

                _not_found_or_error ->
                  {next_oid, :end_of_mib_view, {:end_of_mib_view, nil}}
              end
          end
      end)
    end
  end

  defp collect_bulk_oids(_current_oid, 0, _state, acc), do: Enum.reverse(acc)

  defp collect_bulk_oids(current_oid, remaining, state, acc) do
    # Use manual oid_map if available, otherwise use SharedProfiles
    next_oid_result =
      cond do
        Map.has_key?(state, :oid_map) and map_size(state.oid_map) > 0 ->
          get_next_oid_from_manual_map(current_oid, state.oid_map)

        true ->
          SharedProfiles.get_next_oid(state.device_type, current_oid)
      end

    case next_oid_result do
      {:ok, next_oid} ->
        collect_bulk_oids(next_oid, remaining - 1, state, [next_oid | acc])

      _end_of_mib_or_error ->
        # End of the MIB view: one endOfMibView marker, no padding
        Enum.reverse([:end_of_mib_marker | acc])
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

  # Helper function to get next OID from manual OID map
  defp get_next_oid_from_manual_map(oid_string, oid_map) do
    # Use the public OID library functions for validation and sorting
    alias SnmpKit.SnmpLib.OID

    # Convert string OID to list format for validation
    current_oid_parts =
      try do
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
          oid_parts =
            oid_key
            |> String.split(".")
            |> Enum.map(&String.to_integer/1)

          {oid_key, oid_parts}
        end)
        |> Enum.sort_by(
          fn {_oid_string, oid_parts} -> oid_parts end,
          &(OID.compare(&1, &2) != :gt)
        )

      # Find the next OID lexicographically
      next_oid =
        Enum.find(valid_oids, fn {_oid_string, candidate_parts} ->
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
      other -> existing_type_atom(other)
    end
  end

  defp convert_snmp_type(_), do: :octet_string

  defp existing_type_atom(type) do
    String.to_existing_atom(String.downcase(type))
  rescue
    ArgumentError -> :octet_string
  end
end
