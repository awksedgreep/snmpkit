defmodule SnmpKit.SnmpLib.MIB.RegistryTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpLib.MIB.Registry

  describe "resolve_name/1" do
    test "resolves standard MIB names" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1]} = Registry.resolve_name("sysDescr")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 5]} = Registry.resolve_name("sysName")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 1]} = Registry.resolve_name("ifNumber")
    end

    test "resolves names with instances" do
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = Registry.resolve_name("sysDescr.0")
      assert {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1]} = Registry.resolve_name("ifIndex.1")
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 123, 456]} = Registry.resolve_name("sysDescr.123.456")
    end

    test "returns error for unknown names" do
      assert {:error, :not_found} = Registry.resolve_name("unknownName")
      assert {:error, :not_found} = Registry.resolve_name("nonExistent")
    end

    test "handles invalid inputs" do
      assert {:error, :invalid_name} = Registry.resolve_name(nil)
      assert {:error, :invalid_name} = Registry.resolve_name(123)
    end

    test "handles invalid instance notation" do
      assert {:error, :invalid_instance} = Registry.resolve_name("sysDescr.abc")
      assert {:error, :invalid_instance} = Registry.resolve_name("sysDescr.1.abc")
    end
  end

  describe "reverse_lookup/1" do
    test "performs exact reverse lookups" do
      assert {:ok, "sysDescr"} = Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1])
      assert {:ok, "sysName"} = Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 5])
      assert {:ok, "enterprises"} = Registry.reverse_lookup([1, 3, 6, 1, 4, 1])
    end

    test "performs partial reverse lookups with instances" do
      assert {:ok, "sysDescr.0"} = Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
      assert {:ok, "ifIndex.1"} = Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1])

      assert {:ok, "sysDescr.123.456"} =
               Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 123, 456])
    end

    test "returns error for unknown OIDs" do
      assert {:error, :not_found} = Registry.reverse_lookup([1, 2, 3, 4, 5])
      assert {:error, :not_found} = Registry.reverse_lookup([99, 99, 99])
    end

    test "handles invalid inputs" do
      assert {:error, :invalid_oid_format} = Registry.reverse_lookup("1.3.6.1")
      assert {:error, :empty_oid} = Registry.reverse_lookup([])
    end
  end

  describe "reverse_lookup/1 instance suffix handling" do
    test "appends .0 for scalar leaves" do
      assert {:ok, "sysUpTime.0"} = Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 3, 0])
      assert {:ok, "snmpInPkts.0"} = Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 11, 1, 0])
    end

    test "appends single index for table columns" do
      assert {:ok, "ifDescr.42"} = Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 42])
      assert {:ok, "ifType.7"} = Registry.reverse_lookup([1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 7])
    end

    test "does not append suffix for exact symbol OIDs" do
      assert {:ok, "enterprises"} = Registry.reverse_lookup([1, 3, 6, 1, 4, 1])
    end
  end

  describe "children/1" do
    test "finds direct children of system group" do
      {:ok, children} = Registry.children([1, 3, 6, 1, 2, 1, 1])
      assert "sysDescr" in children
      assert "sysName" in children
      assert "sysLocation" in children
      assert length(children) == 7
    end

    test "finds children of interface group" do
      {:ok, children} = Registry.children([1, 3, 6, 1, 2, 1, 2])
      assert "ifNumber" in children
      assert "ifTable" in children
    end

    test "returns empty list for leaf nodes" do
      {:ok, children} = Registry.children([1, 3, 6, 1, 2, 1, 1, 1])
      assert children == []
    end

    test "handles string OID input" do
      # This would require SnmpKit.SnmpLib.OID.string_to_list to work
      # For now, test the error case
      assert {:error, :invalid_parent_oid} = Registry.children("invalid")
    end
  end

  describe "walk_tree/1" do
    test "walks system subtree" do
      {:ok, descendants} = Registry.walk_tree([1, 3, 6, 1, 2, 1, 1])

      names = Enum.map(descendants, fn {name, _oid} -> name end)
      assert "sysDescr" in names
      assert "sysName" in names
      assert "sysLocation" in names
      assert length(descendants) == 7
    end

    test "walks interface subtree" do
      {:ok, descendants} = Registry.walk_tree([1, 3, 6, 1, 2, 1, 2])

      names = Enum.map(descendants, fn {name, _oid} -> name end)
      assert "ifNumber" in names
      assert "ifTable" in names
      assert "ifEntry" in names
      assert "ifIndex" in names
    end

    test "returns sorted results" do
      {:ok, descendants} = Registry.walk_tree([1, 3, 6, 1, 2, 1, 1])

      oids = Enum.map(descendants, fn {_name, oid} -> oid end)
      assert oids == Enum.sort(oids)
    end
  end

  describe "standard_mibs/0" do
    test "returns the standard MIB map" do
      mibs = Registry.standard_mibs()
      assert is_map(mibs)
      assert Map.has_key?(mibs, "sysDescr")
      assert Map.has_key?(mibs, "enterprises")
      assert Map.get(mibs, "sysDescr") == [1, 3, 6, 1, 2, 1, 1, 1]
    end
  end

  describe "standard_mibs_reverse/0" do
    test "returns the reverse lookup map" do
      reverse_map = Registry.standard_mibs_reverse()
      assert is_map(reverse_map)
      assert Map.has_key?(reverse_map, [1, 3, 6, 1, 2, 1, 1, 1])
      assert Map.get(reverse_map, [1, 3, 6, 1, 2, 1, 1, 1]) == "sysDescr"
    end
  end
end
