defmodule SnmpKit.SnmpSim.PDUHelper do
  @moduledoc """
  Provides utility functions for PDU manipulation.
  """

  @doc """
  Converts a PDU version atom (e.g., :v1, :v2c) to its integer representation.
  Defaults to 2 (for SNMPv2c) if the atom is not :v1.
  """
  def pdu_version_to_int(:v1), do: 0
  def pdu_version_to_int(_version_atom), do: 1

  @doc """
  Normalizes the version carried in a simulator PDU to `:v1` or `:v2c`.

  The UDP server sets `version` to the message version plus one (1 = SNMPv1,
  2 = SNMPv2c); other callers pass `:v1` / `:v2c` / `:v2` atoms or the raw
  wire value (0 = SNMPv1, 1 = SNMPv2c) with `:wire` tagging. Anything
  unrecognised is treated as SNMPv2c.
  """
  @spec snmp_version(map() | term()) :: :v1 | :v2c
  def snmp_version(%{version: version}), do: snmp_version(version)
  def snmp_version(:v1), do: :v1
  def snmp_version(1), do: :v1
  def snmp_version(_), do: :v2c

  @doc """
  RFC 1157 4.1.3: an SNMPv1 agent answers a GET/GETNEXT that runs off the
  end of the MIB (or names an unknown object) with error-status noSuchName(2),
  error-index set to the offending varbind, and the request's varbinds
  echoed unchanged. SNMPv2c instead reports per-varbind exceptions with
  error-status 0 (RFC 3416 4.2.2 / 4.2.3).

  Given a response built with v2c semantics, this converts it to the v1 form
  when needed. `request_varbinds` are the varbinds of the original request.
  """
  @spec apply_v1_error_semantics(map(), :v1 | :v2c, list()) :: map()
  def apply_v1_error_semantics(response, :v2c, _request_varbinds), do: response

  def apply_v1_error_semantics(%{varbinds: varbinds} = response, :v1, request_varbinds) do
    case first_exception_index(varbinds) do
      nil ->
        response

      index ->
        %{response | varbinds: request_varbinds, error_status: 2, error_index: index}
    end
  end

  @exception_types [:end_of_mib_view, :no_such_object, :no_such_instance, :no_such_name]

  defp first_exception_index(varbinds) do
    varbinds
    |> Enum.with_index(1)
    |> Enum.find_value(fn
      {{_oid, type, _value}, idx} when type in @exception_types -> idx
      {{_oid, {type, _}}, idx} when type in @exception_types -> idx
      _ -> nil
    end)
  end
end
