defmodule SnmpKit.Agent.Types do
  @moduledoc false
  # The type spellings the built-in handlers treat as equal when a SET's type
  # is compared with the declared one. Each family is one wire type:
  # BITS is an OCTET STRING, Unsigned32 and Gauge32 share a tag, and
  # `:oid` is a short spelling of `:object_identifier`.

  @families [
    [:octet_string, :string, :bits],
    [:gauge32, :unsigned32],
    [:object_identifier, :oid]
  ]

  @doc "Every spelling that is compatible with `type`, `type` itself included."
  @spec family(atom()) :: [atom()]
  def family(type), do: Enum.find(@families, [type], &(type in &1))

  @doc "Whether a value of type `b` may be written to an object declared as `a`."
  @spec same_type?(atom(), atom()) :: boolean()
  def same_type?(a, b), do: a == b or b in family(a)
end
