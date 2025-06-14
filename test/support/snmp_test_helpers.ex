defmodule SnmpKit.TestHelpers.SNMPTestHelpers do
  @moduledoc """
  Shared SNMP test utilities that handle the new SnmpKit.SnmpLib.PDU API
  while maintaining compatibility with existing test expectations.
  """

  # Suppress Dialyzer warnings for test helper functions
  @dialyzer [
    {:nowarn_function, send_snmp_get: 2},
    {:nowarn_function, send_snmp_get: 3},
    {:nowarn_function, send_snmp_getbulk: 4},
    {:nowarn_function, send_snmp_getbulk: 5},
    {:nowarn_function, send_snmp_getnext: 2},
    {:nowarn_function, send_snmp_getnext: 3},
    {:nowarn_function, send_snmp_request: 2},
    {:nowarn_function, convert_to_legacy_format: 1},
    {:nowarn_function, pdu_type_to_hex: 1},
    {:nowarn_function, convert_varbinds_to_legacy: 1}
  ]

  alias SnmpKit.SnmpLib.PDU

  @doc """
  Sends an SNMP GET request to a device and returns a legacy-compatible response.
  """
  def send_snmp_get(port, oid, community \\ "public") do
    oid_list = convert_oid_to_list(oid)
    request_id = :rand.uniform(65535)

    request_pdu = PDU.build_get_request(oid_list, request_id)
    message = PDU.build_message(request_pdu, community, :v2c)

    send_snmp_request(port, message)
  end

  @doc """
  Sends an SNMP GETBULK request to a device and returns a legacy-compatible response.
  """
  def send_snmp_getbulk(port, oid, non_repeaters, max_repetitions, community \\ "public") do
    oid_list = convert_oid_to_list(oid)
    request_id = :rand.uniform(65535)

    request_pdu = PDU.build_get_bulk_request(oid_list, request_id, non_repeaters, max_repetitions)
    message = PDU.build_message(request_pdu, community, :v2c)

    send_snmp_request(port, message)
  end

  @doc """
  Sends an SNMP GETNEXT request to a device and returns a legacy-compatible response.
  """
  def send_snmp_getnext(port, oid, community \\ "public") do
    oid_list = convert_oid_to_list(oid)
    request_id = :rand.uniform(65535)

    request_pdu = PDU.build_get_next_request(oid_list, request_id)
    message = PDU.build_message(request_pdu, community, :v2c)

    send_snmp_request(port, message)
  end

  # Private helper functions

  defp send_snmp_request(port, message) do
    case PDU.encode_message(message) do
      {:ok, packet} ->
        {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

        :gen_udp.send(socket, {127, 0, 0, 1}, port, packet)

        result =
          case :gen_udp.recv(socket, 0, 2000) do
            {:ok, {_ip, _port, response_data}} ->
              case PDU.decode_message(response_data) do
                {:ok, response_message} ->
                  # Convert to legacy format for test compatibility
                  legacy_pdu = convert_to_legacy_format(response_message)
                  {:ok, legacy_pdu}

                error ->
                  error
              end

            {:error, :timeout} ->
              :timeout

            {:error, reason} ->
              {:error, reason}
          end

        :gen_udp.close(socket)
        result

      {:error, reason} ->
        {:error, {:encode_failed, reason}}
    end
  end

  defp convert_oid_to_list(oid) when is_binary(oid) do
    String.split(oid, ".") |> Enum.map(&String.to_integer/1)
  end

  defp convert_oid_to_list(oid) when is_list(oid), do: oid

  defp convert_to_legacy_format(response_message) do
    %{
      version: response_message.version,
      community: response_message.community,
      pdu_type: pdu_type_to_hex(response_message.pdu.type),
      request_id: response_message.pdu.request_id,
      error_status: Map.get(response_message.pdu, :error_status, 0),
      error_index: Map.get(response_message.pdu, :error_index, 0),
      non_repeaters: Map.get(response_message.pdu, :non_repeaters),
      max_repetitions: Map.get(response_message.pdu, :max_repetitions),
      variable_bindings: convert_varbinds_to_legacy(response_message.pdu.varbinds)
    }
  end

  defp pdu_type_to_hex(:get_request), do: 0xA0
  defp pdu_type_to_hex(:get_next_request), do: 0xA1
  defp pdu_type_to_hex(:get_response), do: 0xA2
  defp pdu_type_to_hex(:set_request), do: 0xA3
  defp pdu_type_to_hex(:get_bulk_request), do: 0xA5
  defp pdu_type_to_hex(_), do: 0xA2

  defp convert_varbinds_to_legacy(varbinds) do
    Enum.map(varbinds, fn
      {oid_list, _type, value} when is_list(oid_list) ->
        oid_string = Enum.join(oid_list, ".")
        {oid_string, value}

      {oid_string, value} when is_binary(oid_string) ->
        {oid_string, value}

      other ->
        other
    end)
  end
end
