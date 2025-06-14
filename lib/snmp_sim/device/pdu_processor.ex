defmodule SnmpSim.Device.PduProcessor do
  @moduledoc """
  Handles SNMP PDU processing for devices.
  """
  require Logger
  alias SnmpSim.Device.WalkPduProcessor
  alias SnmpSim.MIB.SharedProfiles
  import SnmpSim.Device.OidHandler, only: [
    get_dynamic_oid_value: 2,
    string_to_oid_list: 1
  ]

  # SNMP Error Status constants
  @no_error 0
  @no_such_name 2
  @read_only 4
  @gen_err 5

  def process_pdu(pdu, state) do
    Logger.debug("process_pdu called with PDU type: #{inspect(pdu.type)}")
    Logger.debug("Device has_walk_data: #{inspect(state.has_walk_data)}")
    
    # Route to walk-based processor if device has walk data
    if state.has_walk_data do
      Logger.debug("Processing PDU with walk-based processor for device #{state.device_type}")
      case pdu.type do
        :get_request -> WalkPduProcessor.process_get_request(pdu, state)
        :get_next_request -> WalkPduProcessor.process_getnext_request(pdu, state)
        :get_bulk_request -> WalkPduProcessor.process_getbulk_request(pdu, state)
        :set_request -> WalkPduProcessor.process_set_request(pdu, state)
        _ -> process_unsupported_pdu(pdu)
      end
    else
      Logger.debug("Processing PDU with legacy processor for device #{state.device_type}")
      Logger.debug("PDU varbinds: #{inspect(pdu.variable_bindings)}")
      # Original complex processing for non-walk devices
      case pdu.type do
        :get_request -> 
          varbinds = Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, []))
          processed = process_get_request(varbinds, state)
          response = create_get_response_with_fields(pdu, processed)
          response
          
        :get_next_request -> 
          varbinds = Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, []))
          processed = process_getnext_request(varbinds, state)
          response = create_get_response_with_fields(pdu, processed)
          response
          
        :get_bulk_request -> 
          varbinds = Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, []))
          non_repeaters = Map.get(pdu, :non_repeaters, 0)
          max_repetitions = Map.get(pdu, :max_repetitions, 0)
          processed = process_getbulk_request(varbinds, state, non_repeaters, max_repetitions)
          response = create_getbulk_response(pdu, processed)
          response
          
        :set_request ->
          # For legacy devices, return readOnly error for all SET attempts
          varbinds = Map.get(pdu, :varbinds, Map.get(pdu, :variable_bindings, []))
          create_set_error_response(pdu, varbinds)
          
        _ -> 
          process_unsupported_pdu(pdu)
      end
    end
  end

  def process_snmp_pdu(pdu, state) do
    # Delegate to the new routing function
    process_pdu(pdu, state)
  end

  defp process_get_request(variable_bindings, state) do
    Logger.debug("PDU Processor: variable_bindings = #{inspect(variable_bindings)}")
    normalized_bindings =
      Enum.map(variable_bindings, fn
        # Extract OID from 3-tuple
        {oid, _type, _value} -> 
          Logger.debug("PDU Processor: Extracted OID from 3-tuple: #{inspect(oid)}")
          oid
        # Extract OID from 2-tuple (common in SNMP GET requests)
        {oid, _type} -> 
          Logger.debug("PDU Processor: Extracted OID from 2-tuple: #{inspect(oid)}")
          oid
        # Use OID as-is if it's just an OID
        oid -> 
          Logger.debug("PDU Processor: Using OID as-is: #{inspect(oid)}")
          oid
      end)

    Enum.map(normalized_bindings, fn oid ->
      Logger.debug("PDU Processor: Processing OID #{inspect(oid)}")
      result = get_dynamic_oid_value(oid, state)
      Logger.debug("PDU Processor: get_dynamic_oid_value returned #{inspect(result)}")
      
      case result do
        {:ok, {_oid_str, type, value}} ->
          Logger.debug("DEBUG: get_dynamic_oid_value returned type=#{inspect(type)}, value=#{inspect(value)}")
          {oid, type, value}

        {:error, :no_such_name} ->
          Logger.debug("DEBUG: OID #{inspect(oid)} not found, returning no_such_object")
          {oid, :no_such_object, {:no_such_object, nil}}
          
        other ->
          Logger.debug("PDU Processor: Unexpected result for OID #{inspect(oid)}: #{inspect(other)}. Defaulting to null.")
          {oid, :null, :null}
      end
    end)
  end

  def process_getnext_request(variable_bindings, state) do
    Enum.map(variable_bindings, fn varbind ->
      oid = extract_varbind_oid(varbind)

      oid_string =
        case oid do
          list when is_list(list) -> Enum.join(list, ".")
          str when is_binary(str) -> str
          _ -> raise "Invalid OID format"
        end

      try do
        case SharedProfiles.get_next_oid(state.device_type, oid_string) do
          {:ok, next_oid} ->
            # Use get_dynamic_oid_value for legacy devices
            case get_dynamic_oid_value(next_oid, state) do
              {:ok, {_oid_str, type, value}} ->
                next_oid_list = string_to_oid_list(next_oid)
                {next_oid_list, type, value}
                
              {:error, _} ->
                # If we can't get the value, use fallback
                SnmpSim.Device.OidHandler.get_fallback_next_oid(oid, state)
            end
            
          :end_of_mib ->
            {oid, :end_of_mib_view, {:end_of_mib_view, nil}}

          _ ->
            # For GETNEXT, if we can't find a next OID, it's end of MIB
            {oid, :end_of_mib_view, {:end_of_mib_view, nil}}
        end
      catch
        :error, reason ->
          Logger.warning("Error processing GETNEXT for OID #{oid_string}: #{inspect(reason)}")
          {oid, :no_such_object, {:no_such_object, nil}}
      end
    end)
  end

  defp extract_varbind_oid(varbind) do
    case varbind do
      {oid, _type, _value} -> oid
      {oid, _value} -> oid
      _ -> []
    end
  end

  defp process_getbulk_request(varbinds, state, non_repeaters, max_repetitions) do
    # Split varbinds into non-repeaters and repeaters
    {non_repeater_varbinds, repeater_varbinds} = Enum.split(varbinds, non_repeaters)
    
    # Process non-repeaters as GETNEXT
    non_repeater_results = process_getnext_request(non_repeater_varbinds, state)
    
    # Process repeaters - get multiple next OIDs for each
    repeater_results = if max_repetitions > 0 do
      Enum.flat_map(repeater_varbinds, fn varbind ->
        oid = extract_varbind_oid(varbind)
        get_bulk_repetitions(oid, state, max_repetitions)
      end)
    else
      []
    end
    
    # Combine results
    non_repeater_results ++ repeater_results
  end
  
  defp get_bulk_repetitions(start_oid, state, max_repetitions) do
    # Get max_repetitions number of next OIDs starting from start_oid
    {_final_oid, results} = Enum.reduce_while(1..max_repetitions, {start_oid, []}, fn _, {current_oid, acc} ->
      case get_next_oid_and_value(current_oid, state) do
        {_next_oid, :end_of_mib_view, _} = result ->
          # End of MIB, stop here
          {:halt, {current_oid, Enum.reverse([result | acc])}}
          
        {next_oid, type, _value} = result when type != :null ->
          # Continue with next OID
          {:cont, {next_oid, [result | acc]}}
          
        _ ->
          # Error or unexpected format
          {:halt, {current_oid, Enum.reverse(acc)}}
      end
    end)
    
    results
  end
  
  defp get_next_oid_and_value(oid, state) do
    oid_string = 
      case oid do
        list when is_list(list) -> Enum.join(list, ".")
        str when is_binary(str) -> str
        _ -> raise "Invalid OID format"
      end

    case get_dynamic_oid_value(oid_string, state) do
      {:ok, _} ->
        # For GETBULK, we need to get the NEXT OID after this one
        case SharedProfiles.get_next_oid(state.device_type, oid_string) do
          {:ok, next_oid_str} ->
            next_oid_list = string_to_oid_list(next_oid_str)
            case get_dynamic_oid_value(next_oid_str, state) do
              {:ok, {_, next_type, next_value}} ->
                {next_oid_list, next_type, next_value}
              _ ->
                {next_oid_list, :no_such_object, {:no_such_object, nil}}
            end
            
          :end_of_mib ->
            {oid, :end_of_mib_view, {:end_of_mib_view, nil}}
            
          _ ->
            # For GETBULK, if we can't find a next OID, it's end of MIB
            {oid, :end_of_mib_view, {:end_of_mib_view, nil}}
        end
        
      _ ->
        # OID not found, try to get next
        case SharedProfiles.get_next_oid(state.device_type, oid_string) do
          {:ok, next_oid_str} ->
            next_oid_list = string_to_oid_list(next_oid_str)
            case get_dynamic_oid_value(next_oid_str, state) do
              {:ok, {_, next_type, next_value}} ->
                {next_oid_list, next_type, next_value}
              _ ->
                {next_oid_list, :no_such_object, {:no_such_object, nil}}
            end
          :end_of_mib ->
            {oid, :end_of_mib_view, {:end_of_mib_view, nil}}
            
          _ ->
            # For GETBULK, if we can't find a next OID, it's end of MIB
            {oid, :end_of_mib_view, {:end_of_mib_view, nil}}
        end
    end
  end

  defp create_getbulk_response(request_pdu, variable_bindings) do
    # GETBULK responses always have error_status = 0 in SNMPv2c
    %{
      type: :get_response,
      version: Map.get(request_pdu, :version, 1),  # Preserve version from request
      request_id: request_pdu.request_id,
      error_status: 0,
      error_index: 0,
      varbinds: Enum.reverse(variable_bindings)
    }
  end
  
  defp create_get_response_with_fields(request_pdu, variable_bindings) do
    # Initialize error status and index
    {error_status, error_index, converted_bindings} =
      Enum.reduce(Enum.with_index(variable_bindings), {@no_error, 0, []}, fn
        {{oid, :end_of_mib_view, _}, index}, {_, _, acc} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end
          # Set error status and index for end_of_mib_view, use a special atom for encoding
          {@no_error, index + 1, [{oid_list, :end_of_mib_view, {:end_of_mib_view, nil}} | acc]}

        {{oid, :no_such_object, _}, index}, {_, _, acc} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end
          # Set error status and index for no_such_object, use a special atom for encoding
          {@no_such_name, index + 1, [{oid_list, :no_such_object, {:no_such_object, nil}} | acc]}

        {{oid, :no_such_instance, _}, index}, {_, _, acc} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end
          # Set error status and index for no_such_instance, use a special atom for encoding
          {@no_such_name, index + 1, [{oid_list, :no_such_instance, {:no_such_instance, nil}} | acc]}

        {{oid, type, value}, _index}, {status, err_index, acc} ->
          oid_list =
            case oid do
              oid when is_list(oid) -> oid
              oid when is_binary(oid) -> string_to_oid_list(oid)
              _ -> oid
            end
          # Keep track of error status if already set, otherwise no error
          {status, err_index, [{oid_list, type, value} | acc]}

        {varbind, _index}, {status, err_index, acc} ->
          # Keep track of error status if already set
          {status, err_index, [varbind | acc]}
      end)

    converted_bindings = Enum.reverse(converted_bindings)

    # Create response format expected by tests (with :type and :varbinds fields)
    response_pdu = %{
      type: :get_response,
      version: Map.get(request_pdu, :version, 1),
      community: Map.get(request_pdu, :community, "public"),
      request_id: Map.get(request_pdu, :request_id, 0),
      varbinds: converted_bindings,
      error_status: error_status,
      error_index: error_index
    }

    response_pdu
  end

  defp create_set_error_response(request_pdu, variable_bindings) do
    # SET responses always have error_status = 0 in SNMPv2c
    %{
      type: :get_response,
      version: Map.get(request_pdu, :version, 1),  # Preserve version from request
      request_id: request_pdu.request_id,
      error_status: @read_only,
      error_index: 0,
      varbinds: Enum.reverse(variable_bindings)
    }
  end
  
  defp process_unsupported_pdu(pdu) do
    # Return error response for unsupported PDU types
    %{
      type: :get_response,
      version: Map.get(pdu, :version, 1),
      community: Map.get(pdu, :community, "public"),
      request_id: Map.get(pdu, :request_id, 0),
      varbinds: [],
      error_status: @gen_err,
      error_index: 0
    }
  end
end
