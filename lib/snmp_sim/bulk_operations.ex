defmodule SnmpSim.BulkOperations do
  @moduledoc """
  Efficient GETBULK implementation for SNMPv2c.
  Handles non-repeaters, max-repetitions, and response size management.

  GETBULK is a powerful SNMP operation that retrieves multiple variables in a single request.
  It's particularly useful for retrieving large tables like interface statistics.

  ## Algorithm

  1. Process first N variable bindings as non-repeaters (like GETNEXT)
  2. For remaining variable bindings, repeat up to max-repetitions times
  3. Respect UDP packet size limits (typically 1472 bytes for Ethernet)
  4. Return tooBig error if response would exceed limits
  """

  alias SnmpSim.OIDTree

  # Conservative UDP payload size
  @max_udp_size 1400

  @doc """
  Handle a GETBULK request with proper non-repeaters and max-repetitions processing.

  ## Parameters

  - `oid_tree`: The OID tree to query
  - `non_repeaters`: Number of variables to treat as non-repeating (GETNEXT only)
  - `max_repetitions`: Maximum number of repetitions for repeating variables
  - `varbinds`: List of starting OIDs for the bulk operation

  ## Returns

  - `{:ok, result_varbinds}`: Successful bulk operation results
  - `{:error, :too_big}`: Response would exceed UDP size limits
  - `{:error, reason}`: Other error conditions

  ## Examples

      varbinds = [{"1.3.6.1.2.1.2.2.1.1", nil}, {"1.3.6.1.2.1.2.2.1.2", nil}]
      {:ok, results} = SnmpSim.BulkOperations.handle_bulk_request(
        tree, 0, 10, varbinds
      )
      
  """
  def handle_bulk_request(%OIDTree{} = oid_tree, non_repeaters, max_repetitions, varbinds)
      when is_integer(non_repeaters) and is_integer(max_repetitions) and is_list(varbinds) do
    # Validate parameters
    cond do
      non_repeaters < 0 -> {:error, :invalid_non_repeaters}
      max_repetitions < 0 -> {:error, :invalid_max_repetitions}
      non_repeaters > length(varbinds) -> {:error, :non_repeaters_exceeds_varbinds}
      true -> process_bulk_request(oid_tree, non_repeaters, max_repetitions, varbinds)
    end
  end

  @doc """
  Optimize bulk response to fit within UDP packet size limits.
  Estimates response size and truncates if necessary.

  ## Parameters

  - `results`: List of {oid, value, behavior} tuples
  - `max_size`: Maximum response size in bytes (default: 1400)

  ## Returns

  - `{:ok, optimized_results}`: Results that fit within size limit
  - `{:error, :too_big}`: Even minimal response exceeds size limit

  ## Examples

      {:ok, optimized} = SnmpSim.BulkOperations.optimize_bulk_response(results, 1400)
      
  """
  def optimize_bulk_response(results, max_size \\ @max_udp_size) when is_list(results) do
    estimate_and_truncate(results, max_size, [], 0)
  end

  @doc """
  Calculate estimated response size for a list of variable bindings.
  Used for response size management.

  ## Examples

      size = SnmpSim.BulkOperations.estimate_response_size(varbinds)
      
  """
  def estimate_response_size(varbinds) when is_list(varbinds) do
    # SNMP message overhead
    base_overhead = 50

    varbind_size =
      varbinds
      |> Enum.reduce(0, fn {oid, value, _behavior}, acc ->
        # OID encoding overhead
        oid_size = byte_size(oid) + 10
        value_size = estimate_value_size(value)
        # Variable binding overhead
        acc + oid_size + value_size + 8
      end)

    base_overhead + varbind_size
  end

  @doc """
  Process an interface table bulk request efficiently.
  Optimized for common SNMP table walking operations.

  ## Examples

      {:ok, results} = SnmpSim.BulkOperations.process_interface_table(
        tree, "1.3.6.1.2.1.2.2.1", 10
      )
      
  """
  def process_interface_table(%OIDTree{} = oid_tree, table_oid, max_repetitions) do
    # Find all OIDs under the table
    all_oids = OIDTree.list_oids(oid_tree)

    table_oids =
      all_oids
      |> Enum.filter(&String.starts_with?(&1, table_oid))
      |> Enum.take(max_repetitions)

    # Fetch values for table OIDs
    results =
      table_oids
      |> Enum.map(fn oid ->
        case OIDTree.get(oid_tree, oid) do
          {:ok, value, behavior} -> {oid, value, behavior}
          :not_found -> {oid, nil, nil}
        end
      end)

    {:ok, results}
  end

  # Private implementation functions

  defp process_bulk_request(oid_tree, non_repeaters, max_repetitions, varbinds) do
    {non_repeating_vbs, repeating_vbs} = Enum.split(varbinds, non_repeaters)

    # Process non-repeating variables (like GETNEXT)
    non_repeating_results = process_non_repeaters(oid_tree, non_repeating_vbs)

    # Process repeating variables up to max_repetitions
    repeating_results = process_repeaters(oid_tree, repeating_vbs, max_repetitions)

    all_results = non_repeating_results ++ repeating_results

    # Check if response fits in UDP packet
    case optimize_bulk_response(all_results) do
      {:ok, optimized_results} -> {:ok, optimized_results}
      {:error, :too_big} -> {:error, :too_big}
    end
  end

  defp process_non_repeaters(oid_tree, varbinds) do
    Enum.map(varbinds, fn {oid, _value} ->
      case OIDTree.get_next(oid_tree, oid) do
        {:ok, next_oid, value, behavior} -> {next_oid, value, behavior}
        :end_of_mib -> {oid, :end_of_mib_view, nil}
      end
    end)
  end

  defp process_repeaters(oid_tree, varbinds, max_repetitions) do
    # For each repeating variable, collect up to max_repetitions values
    varbinds
    |> Enum.flat_map(fn {start_oid, _value} ->
      collect_repetitions(oid_tree, start_oid, max_repetitions, [])
    end)
  end

  defp collect_repetitions(_oid_tree, _current_oid, 0, acc), do: Enum.reverse(acc)

  defp collect_repetitions(oid_tree, current_oid, remaining, acc) do
    # Use efficient bulk walk instead of individual get_next calls
    results = OIDTree.bulk_walk(oid_tree, current_oid, remaining, 0)

    case results do
      [] ->
        # No more OIDs in this branch
        Enum.reverse(acc)

      results when is_list(results) ->
        # Convert to the expected format and append to accumulator
        formatted_results =
          Enum.map(results, fn {oid, value, behavior} -> {oid, value, behavior} end)

        Enum.reverse(acc) ++ formatted_results
    end
  end

  defp estimate_and_truncate([], _max_size, acc, _current_size) do
    {:ok, Enum.reverse(acc)}
  end

  defp estimate_and_truncate([result | rest], max_size, acc, current_size) do
    result_size = estimate_result_size(result)
    new_size = current_size + result_size

    cond do
      new_size <= max_size ->
        # This result fits, continue
        estimate_and_truncate(rest, max_size, [result | acc], new_size)

      current_size == 0 ->
        # Even the first result is too big
        {:error, :too_big}

      true ->
        # This result would exceed limit, stop here
        {:ok, Enum.reverse(acc)}
    end
  end

  defp estimate_result_size({oid, value, _behavior}) do
    # OID encoding overhead
    oid_size = byte_size(oid) + 10
    value_size = estimate_value_size(value)
    # Variable binding overhead
    oid_size + value_size + 8
  end

  defp estimate_value_size(value) when is_binary(value), do: byte_size(value) + 4
  defp estimate_value_size(value) when is_integer(value), do: 8
  defp estimate_value_size({:counter32, _}), do: 8
  defp estimate_value_size({:counter64, _}), do: 12
  defp estimate_value_size({:gauge32, _}), do: 8
  defp estimate_value_size({:timeticks, _}), do: 8
  defp estimate_value_size({:ipaddress, _}), do: 8
  defp estimate_value_size({:objectid, oid}), do: byte_size(oid) + 4
  defp estimate_value_size(:end_of_mib_view), do: 4
  defp estimate_value_size(:no_such_object), do: 4
  defp estimate_value_size(:no_such_instance), do: 4
  defp estimate_value_size(nil), do: 4
  # Default estimate
  defp estimate_value_size(_), do: 8
end
