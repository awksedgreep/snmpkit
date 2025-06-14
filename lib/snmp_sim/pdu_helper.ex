defmodule SnmpSim.PduHelper do
  @moduledoc """
  Provides utility functions for PDU manipulation.
  """

  @doc """
  Converts a PDU version atom (e.g., :v1, :v2c) to its integer representation.
  Defaults to 2 (for SNMPv2c) if the atom is not :v1.
  """
  def pdu_version_to_int(:v1), do: 0
  def pdu_version_to_int(_version_atom), do: 1
end
