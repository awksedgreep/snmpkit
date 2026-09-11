defmodule SnmpKit.MIB.Registry do
  @moduledoc """
  Static name/OID resolution over the built-in MIB table.

  A process-free view of `SnmpKit.MIB.Builtin.name_to_oid/0` — the same table
  that seeds `SnmpKit.SnmpMgr.MIB` — for callers that run without the
  registry process (SnmpLib on its own, compile-time tooling). It never sees
  MIBs loaded at runtime; use `SnmpKit.SnmpMgr.MIB` for those.
  """

  alias SnmpKit.MIB.{Builtin, Resolver}

  @doc """
  The built-in name -> OID map (`SnmpKit.MIB.Builtin.name_to_oid/0`).
  """
  def standard_mibs, do: Builtin.name_to_oid()

  @doc """
  The reverse lookup map (OID -> name).
  """
  def standard_mibs_reverse, do: Resolver.build_reverse_map(Builtin.name_to_oid())

  @doc """
  Resolve a MIB name to an OID list.
  Handles instance notation like "sysDescr.0".

  ## Examples

      iex> SnmpKit.MIB.Registry.resolve_name("sysDescr.0")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}

      iex> SnmpKit.MIB.Registry.resolve_name("sysDescr")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1]}

      iex> SnmpKit.MIB.Registry.resolve_name("unknownName")
      {:error, :not_found}
  """
  def resolve_name(name), do: Resolver.resolve_name(name, Builtin.name_to_oid())

  @doc """
  Reverse lookup an OID to get the MIB name.
  Handles partial matches and instances.

  ## Examples

      iex> SnmpKit.MIB.Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
      {:ok, "sysDescr.0"}

      iex> SnmpKit.MIB.Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1])
      {:ok, "sysDescr"}
  """
  def reverse_lookup(oid), do: Resolver.reverse_lookup_oid(oid, standard_mibs_reverse())

  @doc """
  Find direct children of a parent OID.

  ## Examples

      iex> SnmpKit.MIB.Registry.children([1, 3, 6, 1, 2, 1, 1])
      {:ok, ["sysContact", "sysDescr", "sysLocation", "sysName", "sysObjectID", "sysServices", "sysUpTime"]}
  """
  def children(parent_oid), do: Resolver.find_children(parent_oid, Builtin.name_to_oid())

  @doc """
  Walk the MIB tree from a root OID. The root itself is included when it is a
  named node.

  ## Examples

      iex> {:ok, [{"system", [1, 3, 6, 1, 2, 1, 1]}, {"sysDescr", [1, 3, 6, 1, 2, 1, 1, 1]} | _]} =
      ...>   SnmpKit.MIB.Registry.walk_tree([1, 3, 6, 1, 2, 1, 1])
  """
  def walk_tree(root_oid), do: Resolver.walk_tree_from_root(root_oid, Builtin.name_to_oid())
end
