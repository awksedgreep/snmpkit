defmodule SnmpKit.SnmpLib.PDU.Builder do
  @moduledoc """
  High-level PDU and message building functions for SNMP operations.

  This module provides functions to build various types of SNMP PDUs and messages,
  including GET, GETNEXT, SET, GETBULK requests, and responses.
  """

  alias SnmpKit.SnmpLib.PDU.Constants

  @type snmp_version :: Constants.snmp_version()
  @type pdu_type :: Constants.pdu_type()
  @type error_status :: Constants.error_status()
  @type oid :: Constants.oid()
  @type snmp_value :: Constants.snmp_value()
  @type varbind :: Constants.varbind()
  @type pdu :: Constants.pdu()
  @type message :: Constants.message()

  @doc """
  Builds a GET request PDU.
  """
  @spec build_get_request(oid(), non_neg_integer()) :: pdu()
  def build_get_request(oid_list, request_id) do
    validate_request_id!(request_id)
    normalized_oid = Constants.normalize_oid(oid_list)

    %{
      type: :get_request,
      request_id: request_id,
      error_status: Constants.no_error(),
      error_index: 0,
      varbinds: [{normalized_oid, :null, :null}]
    }
  end

  @doc """
  Builds a GET request PDU with multiple varbinds.
  """
  @spec build_get_request_multi([varbind()], non_neg_integer()) :: pdu()
  def build_get_request_multi(varbinds, request_id) do
    validate_request_id!(request_id)

    case validate_varbinds_format(varbinds) do
      :ok ->
        %{
          type: :get_request,
          request_id: request_id,
          error_status: Constants.no_error(),
          error_index: 0,
          varbinds: varbinds
        }

      error ->
        error
    end
  end

  @doc """
  Builds a GETNEXT request PDU.
  """
  @spec build_get_next_request(oid(), non_neg_integer()) :: pdu()
  def build_get_next_request(oid_list, request_id) do
    validate_request_id!(request_id)
    normalized_oid = Constants.normalize_oid(oid_list)

    %{
      type: :get_next_request,
      request_id: request_id,
      error_status: Constants.no_error(),
      error_index: 0,
      varbinds: [{normalized_oid, :null, :null}]
    }
  end

  @doc """
  Builds a SET request PDU.
  """
  @spec build_set_request(oid(), {atom(), any()}, non_neg_integer()) :: pdu()
  def build_set_request(oid_list, {type, value}, request_id) do
    validate_request_id!(request_id)
    normalized_oid = Constants.normalize_oid(oid_list)

    %{
      type: :set_request,
      request_id: request_id,
      error_status: Constants.no_error(),
      error_index: 0,
      varbinds: [{normalized_oid, type, value}]
    }
  end

  @doc """
  Builds a SET request PDU carrying several varbinds (`{oid, type, value}`).
  """
  @spec build_set_request_multi([varbind()], non_neg_integer()) :: pdu()
  def build_set_request_multi(varbinds, request_id) when is_list(varbinds) do
    validate_request_id!(request_id)

    %{
      type: :set_request,
      request_id: request_id,
      error_status: Constants.no_error(),
      error_index: 0,
      varbinds:
        Enum.map(varbinds, fn {oid, type, value} ->
          {Constants.normalize_oid(oid), type, value}
        end)
    }
  end

  @doc """
  Builds a GETBULK request PDU for SNMPv2c.

  ## Parameters

  - `oid_list`: Starting OID
  - `request_id`: Request identifier
  - `non_repeaters`: Number of non-repeating variables (default: 0)
  - `max_repetitions`: Maximum repetitions (default: 10)
  """
  @spec build_get_bulk_request(oid(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          pdu()
  def build_get_bulk_request(oid_list, request_id, non_repeaters \\ 0, max_repetitions \\ 10) do
    validate_request_id!(request_id)
    validate_bulk_params!(non_repeaters, max_repetitions)
    normalized_oid = Constants.normalize_oid(oid_list)

    %{
      type: :get_bulk_request,
      request_id: request_id,
      error_status: Constants.no_error(),
      error_index: 0,
      non_repeaters: non_repeaters,
      max_repetitions: max_repetitions,
      varbinds: [{normalized_oid, :null, :null}]
    }
  end

  @doc """
  Builds a response PDU.
  """
  @spec build_response(non_neg_integer(), error_status(), non_neg_integer(), [varbind()]) :: pdu()
  def build_response(request_id, error_status, error_index, varbinds \\ []) do
    validate_request_id!(request_id)

    %{
      type: :get_response,
      request_id: request_id,
      error_status: error_status,
      error_index: error_index,
      varbinds: varbinds
    }
  end

  @sys_uptime_oid [1, 3, 6, 1, 2, 1, 1, 3, 0]
  @snmp_trap_oid [1, 3, 6, 1, 6, 3, 1, 1, 4, 1, 0]

  @doc """
  Builds an SNMPv1 Trap-PDU (RFC 1157).

  `agent_addr` is an IPv4 tuple or 4-byte binary; `generic_trap` is 0..6
  (6 = enterpriseSpecific); `time_stamp` is sysUpTime in centiseconds.
  """
  @spec build_trap_v1(
          oid(),
          :inet.ip4_address() | binary(),
          0..6,
          non_neg_integer(),
          non_neg_integer(),
          [varbind()]
        ) :: pdu()
  def build_trap_v1(
        enterprise,
        agent_addr,
        generic_trap,
        specific_trap,
        time_stamp,
        varbinds \\ []
      ) do
    unless is_integer(generic_trap) and generic_trap in 0..6 do
      raise ArgumentError, "generic_trap must be 0..6, got: #{inspect(generic_trap)}"
    end

    %{
      type: :trap,
      enterprise: Constants.normalize_oid(enterprise),
      agent_addr: agent_addr,
      generic_trap: generic_trap,
      specific_trap: specific_trap,
      time_stamp: time_stamp,
      varbinds: varbinds
    }
  end

  @doc """
  Builds an SNMPv2c trap PDU. The mandatory `sysUpTime.0` and
  `snmpTrapOID.0` varbinds are prepended to `varbinds`.
  """
  @spec build_trap_v2(non_neg_integer(), oid(), [varbind()], non_neg_integer()) :: pdu()
  def build_trap_v2(sys_uptime, trap_oid, varbinds \\ [], request_id \\ 0) do
    validate_request_id!(request_id)

    %{
      type: :snmpv2_trap,
      request_id: request_id,
      error_status: 0,
      error_index: 0,
      varbinds: notification_varbinds(sys_uptime, trap_oid, varbinds)
    }
  end

  @doc """
  Builds an SNMPv2c inform PDU (an acknowledged notification); see
  `build_trap_v2/4` for the varbinds.
  """
  @spec build_inform(non_neg_integer(), oid(), [varbind()], non_neg_integer()) :: pdu()
  def build_inform(sys_uptime, trap_oid, varbinds, request_id) do
    validate_request_id!(request_id)

    %{
      type: :inform_request,
      request_id: request_id,
      error_status: 0,
      error_index: 0,
      varbinds: notification_varbinds(sys_uptime, trap_oid, varbinds)
    }
  end

  defp notification_varbinds(sys_uptime, trap_oid, varbinds) do
    [
      {@sys_uptime_oid, :timeticks, sys_uptime},
      {@snmp_trap_oid, :object_identifier, Constants.normalize_oid(trap_oid)}
      | varbinds
    ]
  end

  @doc """
  Builds an SNMP message structure.

  ## Parameters

  - `pdu`: The PDU to include in the message
  - `community`: Community string
  - `version`: SNMP version (:v1, :v2c, etc.)
  """
  @spec build_message(pdu(), binary(), snmp_version()) :: message()
  def build_message(pdu, community, version \\ :v1) do
    validate_community!(community)
    validate_bulk_version!(pdu, version)

    version_number = Constants.normalize_version(version)

    %{
      version: version_number,
      community: community,
      pdu: pdu
    }
  end

  @doc """
  Creates an error response PDU from a request PDU.

  ## Examples

      error_pdu = SnmpKit.SnmpLib.PDU.Builder.create_error_response(request_pdu, 2, 1)
  """
  @spec create_error_response(pdu(), error_status(), non_neg_integer()) :: pdu()
  def create_error_response(request_pdu, error_status, error_index \\ 0) do
    # Handle PDU map format - all PDUs are maps with :type field
    case request_pdu do
      %{type: _type, request_id: request_id, varbinds: varbinds} ->
        %{
          type: :get_response,
          request_id: request_id,
          error_status: error_status,
          error_index: error_index,
          varbinds: varbinds
        }

      _ ->
        # Legacy map format for backward compatibility
        %{
          type: :get_response,
          request_id: Map.get(request_pdu, :request_id, 1),
          error_status: error_status,
          error_index: error_index,
          varbinds: Map.get(request_pdu, :varbinds, [])
        }
    end
  end

  @doc """
  Validates a PDU structure.
  """
  @spec validate(pdu()) :: {:ok, pdu()} | {:error, atom()}
  def validate(pdu) when is_map(pdu) do
    # First check if we have a type field
    case Map.get(pdu, :type) do
      nil ->
        {:error, :missing_required_fields}

      type ->
        # Validate the type first
        case validate_pdu_type_only(type) do
          :ok ->
            # Now check required fields based on type
            basic_fields = [:request_id, :varbinds]

            case Enum.all?(basic_fields, &Map.has_key?(pdu, &1)) do
              false ->
                {:error, :missing_required_fields}

              true ->
                case type do
                  :get_bulk_request ->
                    bulk_fields = [:non_repeaters, :max_repetitions]

                    case Enum.all?(bulk_fields, &Map.has_key?(pdu, &1)) do
                      true -> {:ok, pdu}
                      false -> {:error, :missing_bulk_fields}
                    end

                  _ ->
                    # Standard PDUs need error_status and error_index
                    standard_fields = [:error_status, :error_index]

                    case Enum.all?(standard_fields, &Map.has_key?(pdu, &1)) do
                      true -> {:ok, pdu}
                      false -> {:error, :missing_required_fields}
                    end
                end
            end

          :error ->
            {:error, :invalid_pdu_type}
        end
    end
  end

  def validate(_), do: {:error, :invalid_pdu_format}

  @doc """
  Validates a community string against an encoded SNMP message.
  """
  @spec validate_community(binary(), binary()) :: :ok | {:error, atom()}
  def validate_community(encoded_message, expected_community)
      when is_binary(encoded_message) and is_binary(expected_community) do
    case SnmpKit.SnmpLib.PDU.Decoder.decode_message(encoded_message) do
      {:ok, %{community: community}} when community == expected_community -> :ok
      {:ok, %{community: _other}} -> {:error, :invalid_community}
      {:error, _reason} -> {:error, :decode_failed}
    end
  end

  def validate_community(_encoded, _community), do: {:error, :invalid_parameters}

  ## Private Implementation

  # Validation helpers
  defp validate_request_id!(request_id) do
    unless is_integer(request_id) and request_id >= 0 and request_id <= 2_147_483_647 do
      raise ArgumentError,
            "Request ID must be a valid integer (0-2147483647), got: #{inspect(request_id)}"
    end
  end

  defp validate_bulk_params!(non_repeaters, max_repetitions) do
    unless is_integer(non_repeaters) and non_repeaters >= 0 do
      raise ArgumentError,
            "non_repeaters must be a non-negative integer, got: #{inspect(non_repeaters)}"
    end

    unless is_integer(max_repetitions) and max_repetitions >= 0 do
      raise ArgumentError,
            "max_repetitions must be a non-negative integer, got: #{inspect(max_repetitions)}"
    end
  end

  defp validate_community!(community) do
    unless is_binary(community) do
      raise ArgumentError, "Community must be a binary string, got: #{inspect(community)}"
    end
  end

  defp validate_bulk_version!(pdu, version) do
    v1? = Constants.normalize_version(version) == 0

    case Map.get(pdu, :type) do
      :get_bulk_request when v1? ->
        raise ArgumentError, "GETBULK requests require SNMPv2c or higher, cannot use v1"

      type when type in [:snmpv2_trap, :inform_request, :report] and v1? ->
        raise ArgumentError, "#{type} PDUs require SNMPv2c or higher, cannot use v1"

      :trap when not v1? ->
        raise ArgumentError, "SNMPv1 Trap-PDUs can only be sent in SNMPv1 messages"

      _ ->
        :ok
    end
  end

  defp validate_varbinds_format(varbinds) do
    valid =
      Enum.all?(varbinds, fn
        {oid, _type, _value} when is_list(oid) -> Enum.all?(oid, &is_integer/1)
        _ -> false
      end)

    if valid, do: :ok, else: {:error, :invalid_varbind_format}
  end

  # Helper function to validate PDU type
  defp validate_pdu_type_only(type) do
    case type do
      :get_request -> :ok
      :get_next_request -> :ok
      :get_response -> :ok
      :set_request -> :ok
      :get_bulk_request -> :ok
      :inform_request -> :ok
      :snmpv2_trap -> :ok
      :report -> :ok
      _ -> :error
    end
  end
end
