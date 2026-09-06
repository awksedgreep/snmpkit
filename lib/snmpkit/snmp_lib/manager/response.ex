defmodule SnmpKit.SnmpLib.Manager.Response do
  @moduledoc """
  Turns decoded SNMP response messages into the manager's result tuples:
  GET / GETNEXT / GETBULK / SET result extraction and error-status decoding
  (RFC 1157 and RFC 3416 error codes).
  """

  require Logger

  # Result extraction
  def extract_get_result(%{pdu: %{error_status: error_status}} = response)
      when error_status != 0 do
    Logger.debug("Extracting error result - error_status: #{error_status}")
    Logger.debug("Full response PDU: #{inspect(response.pdu)}")
    {:error, decode_error_status(error_status)}
  end

  def extract_get_result(%{pdu: %{varbinds: [{oid, type, value}]}} = response) do
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

  def extract_get_result(response) do
    Logger.error("Invalid response format: #{inspect(response)}")
    {:error, :invalid_response}
  end

  def extract_get_result_with_oid(%{pdu: %{error_status: error_status}} = response)
      when error_status != 0 do
    Logger.debug("Extracting error result - error_status: #{error_status}")
    Logger.debug("Full response PDU: #{inspect(response.pdu)}")
    {:error, decode_error_status(error_status)}
  end

  def extract_get_result_with_oid(%{pdu: %{varbinds: [{oid, type, value}]}} = response) do
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

  def extract_get_result_with_oid(response) do
    Logger.error("Invalid response format: #{inspect(response)}")
    {:error, :invalid_response}
  end

  def extract_bulk_result(%{pdu: %{varbinds: varbinds}}) do
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

  def extract_bulk_result(%{pdu: %{error_status: error_status}}) when error_status != 0 do
    {:error, decode_error_status(error_status)}
  end

  def extract_bulk_result(_), do: {:error, :invalid_response}

  @doc """
  Returns every varbind of a response as `{oid, type, value}`, with SNMPv2c
  exceptions normalised into the type field (`:no_such_object`,
  `:no_such_instance`, `:end_of_mib_view`, value `nil`). A non-zero
  error-status (SNMPv1 `noSuchName`, `tooBig`, ...) is `{:error, reason}`.
  """
  def extract_varbinds(%{pdu: %{error_status: error_status}}) when error_status != 0 do
    {:error, decode_error_status(error_status)}
  end

  def extract_varbinds(%{pdu: %{varbinds: varbinds}}) when is_list(varbinds) do
    {:ok,
     Enum.map(varbinds, fn
       {oid, exception, _}
       when exception in [:no_such_object, :no_such_instance, :end_of_mib_view] ->
         {oid, exception, nil}

       {oid, _type, {exception, _}}
       when exception in [:no_such_object, :no_such_instance, :end_of_mib_view] ->
         {oid, exception, nil}

       {oid, type, value} ->
         {oid, type, value}
     end)}
  end

  def extract_varbinds(_), do: {:error, :invalid_response}

  def extract_set_result(%{pdu: %{error_status: 0}}) do
    {:ok, :success}
  end

  def extract_set_result(%{pdu: %{error_status: error_status}}) when error_status != 0 do
    {:error, decode_error_status(error_status)}
  end

  def extract_set_result(_), do: {:error, :invalid_response}

  def extract_get_next_result(%{pdu: %{error_status: error_status}}) when error_status != 0 do
    # SNMPv1 agents answer a GETNEXT past the end of the MIB with noSuchName
    {:error, decode_error_status(error_status)}
  end

  def extract_get_next_result(%{pdu: %{varbinds: [{next_oid, type, value}]}} = response) do
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

  def extract_get_next_result(response) do
    Logger.error("Invalid GETNEXT response format: #{inspect(response)}")
    {:error, :invalid_response}
  end

  def decode_error_status(0), do: :no_error
  def decode_error_status(1), do: :too_big
  def decode_error_status(2), do: :no_such_name
  def decode_error_status(3), do: :bad_value
  def decode_error_status(4), do: :read_only
  def decode_error_status(5), do: :gen_err
  # SNMPv2c additional error codes (RFC 3416)
  def decode_error_status(6), do: :no_access
  def decode_error_status(7), do: :wrong_type
  def decode_error_status(8), do: :wrong_length
  def decode_error_status(9), do: :wrong_encoding
  def decode_error_status(10), do: :wrong_value
  def decode_error_status(11), do: :no_creation
  def decode_error_status(12), do: :inconsistent_value
  def decode_error_status(13), do: :resource_unavailable
  def decode_error_status(14), do: :commit_failed
  def decode_error_status(15), do: :undo_failed
  def decode_error_status(16), do: :authorization_error
  def decode_error_status(17), do: :not_writable
  def decode_error_status(18), do: :inconsistent_name
  def decode_error_status(error), do: {:unknown_error, error}
end
