defmodule SnmpKit.SnmpLib.OIDTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpKit.SnmpLib.OID

  @moduletag :unit
  @moduletag :protocol
  @moduletag :phase_2

  describe "String/List conversions" do
    test "converts valid OID string to list" do
      {:ok, oid_list} = OID.string_to_list("1.3.6.1.2.1.1.1.0")
      assert oid_list == [1, 3, 6, 1, 2, 1, 1, 1, 0]
    end

    test "converts valid OID list to string" do
      {:ok, oid_string} = OID.list_to_string([1, 3, 6, 1, 2, 1, 1, 1, 0])
      assert oid_string == "1.3.6.1.2.1.1.1.0"
    end

    test "handles single component OID" do
      {:ok, oid_list} = OID.string_to_list("42")
      assert oid_list == [42]

      {:ok, oid_string} = OID.list_to_string([42])
      assert oid_string == "42"
    end

    test "rejects empty OID string" do
      assert {:error, :empty_oid} = OID.string_to_list("")
      assert {:error, :empty_oid} = OID.string_to_list("   ")
    end

    test "rejects empty OID list" do
      assert {:error, :empty_oid} = OID.list_to_string([])
    end

    test "rejects invalid OID string formats" do
      assert {:error, :invalid_oid_string} = OID.string_to_list("1.3.6.1.a.2")
      assert {:error, :invalid_oid_string} = OID.string_to_list("1..3.6.1")
      assert {:error, :invalid_oid_string} = OID.string_to_list("1.3.6.1.")
    end

    test "rejects negative components" do
      assert {:error, :invalid_component} = OID.list_to_string([1, 3, -1, 4])
      assert {:error, :invalid_component} = OID.list_to_string([-1])
    end

    test "rejects non-integer components" do
      assert {:error, :invalid_component} = OID.list_to_string([1, 3, "6", 1])
      assert {:error, :invalid_component} = OID.list_to_string([1.5, 3, 6])
    end

    test "handles large OID components" do
      large_oid = [1, 3, 6, 1, 4, 1, 999_999, 1, 2, 3]
      {:ok, oid_string} = OID.list_to_string(large_oid)
      {:ok, parsed_oid} = OID.string_to_list(oid_string)
      assert parsed_oid == large_oid
    end
  end

  describe "Tree operations" do
    test "correctly identifies child relationships" do
      parent = [1, 3, 6, 1, 2, 1]
      child = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      assert OID.is_child_of?(child, parent) == true
      assert OID.is_child_of?(parent, child) == false
    end

    test "correctly identifies parent relationships" do
      parent = [1, 3, 6, 1, 2, 1]
      child = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      assert OID.is_parent_of?(parent, child) == true
      assert OID.is_parent_of?(child, parent) == false
    end

    test "rejects equal OIDs as child/parent" do
      oid = [1, 3, 6, 1, 2, 1]

      assert OID.is_child_of?(oid, oid) == false
      assert OID.is_parent_of?(oid, oid) == false
    end

    test "rejects sibling OIDs as child/parent" do
      oid1 = [1, 3, 6, 1, 2, 1]
      oid2 = [1, 3, 6, 1, 2, 2]

      assert OID.is_child_of?(oid1, oid2) == false
      assert OID.is_child_of?(oid2, oid1) == false
    end

    test "gets parent OID correctly" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      {:ok, parent} = OID.get_parent(oid)
      assert parent == [1, 3, 6, 1, 2, 1, 1, 1]
    end

    test "handles root OIDs in get_parent" do
      assert {:error, :root_oid} = OID.get_parent([])
      assert {:error, :root_oid} = OID.get_parent([1])
    end

    test "gets immediate children from OID set" do
      parent = [1, 3, 6, 1]

      oid_set = [
        [1, 3, 6, 1, 2],
        [1, 3, 6, 1, 4],
        [1, 3, 6, 1, 2, 1],
        [1, 3, 6, 1, 4, 1, 9],
        [1, 3, 6, 2]
      ]

      children = OID.get_children(parent, oid_set)
      assert length(children) == 2
      assert [1, 3, 6, 1, 2] in children
      assert [1, 3, 6, 1, 4] in children
    end

    test "finds next OID in sorted set" do
      current = [1, 3, 6, 1, 2, 1, 1, 1, 0]

      oid_set = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 2, 1, 1, 2, 0],
        [1, 3, 6, 1, 2, 1, 1, 3, 0]
      ]

      {:ok, next_oid} = OID.get_next_oid(current, oid_set)
      assert next_oid == [1, 3, 6, 1, 2, 1, 1, 2, 0]
    end

    test "handles end of MIB in get_next_oid" do
      current = [1, 3, 6, 1, 2, 1, 1, 3, 0]

      oid_set = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 2, 1, 1, 2, 0],
        [1, 3, 6, 1, 2, 1, 1, 3, 0]
      ]

      assert {:error, :end_of_mib} = OID.get_next_oid(current, oid_set)
    end
  end

  describe "Comparison operations" do
    test "compares OIDs lexicographically" do
      oid1 = [1, 3, 6, 1]
      oid2 = [1, 3, 6, 2]
      oid3 = [1, 3, 6, 1]
      oid4 = [1, 3, 6, 1, 2]

      assert OID.compare(oid1, oid2) == :lt
      assert OID.compare(oid2, oid1) == :gt
      assert OID.compare(oid1, oid3) == :eq
      assert OID.compare(oid1, oid4) == :lt
      assert OID.compare(oid4, oid1) == :gt
    end

    test "sorts OID list correctly" do
      oids = [
        [1, 3, 6, 2],
        [1, 3, 6, 1, 2],
        [1, 3, 6, 1],
        [1, 3, 6, 1, 4, 1],
        [1, 3, 6, 1, 1]
      ]

      sorted = OID.sort(oids)

      expected = [
        [1, 3, 6, 1],
        [1, 3, 6, 1, 1],
        [1, 3, 6, 1, 2],
        [1, 3, 6, 1, 4, 1],
        [1, 3, 6, 2]
      ]

      assert sorted == expected
    end

    test "handles empty list in sort" do
      assert OID.sort([]) == []
      assert OID.sort(:not_a_list) == []
    end
  end

  describe "Table operations" do
    test "extracts table index correctly" do
      table_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 1]
      instance_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1]

      {:ok, index} = OID.extract_table_index(table_oid, instance_oid)
      assert index == [1]
    end

    test "extracts complex table index" do
      table_oid = [1, 3, 6, 1, 2, 1, 4, 20, 1, 1]
      instance_oid = [1, 3, 6, 1, 2, 1, 4, 20, 1, 1, 192, 168, 1, 1]

      {:ok, index} = OID.extract_table_index(table_oid, instance_oid)
      assert index == [192, 168, 1, 1]
    end

    test "rejects invalid table instances" do
      table_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 1]
      # Wrong table column
      invalid_instance = [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1]

      assert {:error, :invalid_table_instance} =
               OID.extract_table_index(table_oid, invalid_instance)
    end

    test "builds table instance from OID and index" do
      table_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 1]
      index = [1]

      {:ok, instance_oid} = OID.build_table_instance(table_oid, index)
      assert instance_oid == [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1]
    end

    test "builds complex table instance" do
      table_oid = [1, 3, 6, 1, 2, 1, 4, 20, 1, 1]
      index = [192, 168, 1, 1]

      {:ok, instance_oid} = OID.build_table_instance(table_oid, index)
      assert instance_oid == [1, 3, 6, 1, 2, 1, 4, 20, 1, 1, 192, 168, 1, 1]
    end

    test "parses integer table index" do
      {:ok, value} = OID.parse_table_index([42], :integer)
      assert value == 42
    end

    test "parses fixed-length string table index" do
      # "test" in ASCII
      index = [116, 101, 115, 116]
      {:ok, value} = OID.parse_table_index(index, {:string, 4})
      assert value == "test"
    end

    test "parses variable-length string table index" do
      # Length-prefixed "test"
      index = [4, 116, 101, 115, 116]
      {:ok, value} = OID.parse_table_index(index, {:variable_string})
      assert value == "test"
    end

    test "builds integer table index" do
      {:ok, index} = OID.build_table_index(42, :integer)
      assert index == [42]
    end

    test "builds fixed-length string table index" do
      {:ok, index} = OID.build_table_index("test", {:string, 4})
      assert index == [116, 101, 115, 116]
    end

    test "builds variable-length string table index" do
      {:ok, index} = OID.build_table_index("test", {:variable_string})
      assert index == [4, 116, 101, 115, 116]
    end

    test "rejects invalid string length for fixed-length index" do
      assert {:error, :invalid_string_length} = OID.build_table_index("test", {:string, 5})
    end
  end

  describe "Validation" do
    test "validates correct OIDs" do
      assert :ok = OID.valid_oid?([1, 3, 6, 1, 2, 1, 1, 1, 0])
      assert :ok = OID.valid_oid?([0])
      assert :ok = OID.valid_oid?([1, 2, 3, 4, 5])
    end

    test "rejects invalid OIDs" do
      assert {:error, :empty_oid} = OID.valid_oid?([])
      assert {:error, :invalid_component} = OID.valid_oid?([1, 3, -1, 4])
      assert {:error, :invalid_component} = OID.valid_oid?([1, 3, "6", 1])
      assert {:error, :invalid_input} = OID.valid_oid?(:not_a_list)
    end

    test "normalizes different OID formats" do
      {:ok, normalized1} = OID.normalize([1, 3, 6, 1])
      assert normalized1 == [1, 3, 6, 1]

      {:ok, normalized2} = OID.normalize("1.3.6.1")
      assert normalized2 == [1, 3, 6, 1]

      assert {:error, :invalid_input} = OID.normalize(:invalid)
    end
  end

  describe "Standard OID utilities" do
    test "returns standard OID prefixes" do
      assert OID.mib_2() == [1, 3, 6, 1, 2, 1]
      assert OID.enterprises() == [1, 3, 6, 1, 4, 1]
      assert OID.experimental() == [1, 3, 6, 1, 3]
      assert OID.private() == [1, 3, 6, 1, 4]
    end

    test "identifies MIB-2 OIDs" do
      assert OID.is_mib_2?([1, 3, 6, 1, 2, 1]) == true
      assert OID.is_mib_2?([1, 3, 6, 1, 2, 1, 1, 1, 0]) == true
      assert OID.is_mib_2?([1, 3, 6, 1, 4, 1, 9]) == false
    end

    test "identifies enterprise OIDs" do
      assert OID.is_enterprise?([1, 3, 6, 1, 4, 1, 9, 1, 1]) == true
      assert OID.is_enterprise?([1, 3, 6, 1, 2, 1, 1, 1, 0]) == false
    end

    test "identifies experimental OIDs" do
      assert OID.is_experimental?([1, 3, 6, 1, 3, 1]) == true
      assert OID.is_experimental?([1, 3, 6, 1, 2, 1]) == false
    end

    test "identifies private OIDs" do
      assert OID.is_private?([1, 3, 6, 1, 4, 2]) == true
      assert OID.is_private?([1, 3, 6, 1, 2, 1]) == false
    end

    test "extracts enterprise numbers" do
      {:ok, enterprise_num} = OID.get_enterprise_number([1, 3, 6, 1, 4, 1, 9, 1, 1])
      assert enterprise_num == 9

      {:ok, enterprise_num2} = OID.get_enterprise_number([1, 3, 6, 1, 4, 1, 12345])
      assert enterprise_num2 == 12345
    end

    test "rejects non-enterprise OIDs for enterprise number extraction" do
      assert {:error, :not_enterprise_oid} = OID.get_enterprise_number([1, 3, 6, 1, 2, 1])
      # Too short
      assert {:error, :not_enterprise_oid} = OID.get_enterprise_number([1, 3, 6, 1, 4, 1])
    end
  end

  describe "Error handling and edge cases" do
    test "handles invalid inputs gracefully" do
      assert {:error, :invalid_input} = OID.string_to_list(:not_binary)
      assert {:error, :invalid_input} = OID.list_to_string(:not_list)
      assert OID.is_child_of?(:not_list, [1, 2, 3]) == false
      assert OID.is_child_of?([1, 2, 3], :not_list) == false
      assert {:error, :invalid_input} = OID.get_parent(:not_list)
    end

    test "handles whitespace in OID strings" do
      {:ok, oid} = OID.string_to_list("  1.3.6.1.2.1  ")
      assert oid == [1, 3, 6, 1, 2, 1]
    end

    test "handles very long OIDs" do
      long_oid = [1, 3, 6, 1] ++ Enum.to_list(1..100)
      {:ok, oid_string} = OID.list_to_string(long_oid)
      {:ok, parsed_oid} = OID.string_to_list(oid_string)
      assert parsed_oid == long_oid
    end

    test "handles zero components in OID" do
      oid_with_zeros = [1, 3, 0, 1, 0, 0, 1]
      {:ok, oid_string} = OID.list_to_string(oid_with_zeros)
      {:ok, parsed_oid} = OID.string_to_list(oid_string)
      assert parsed_oid == oid_with_zeros
    end
  end

  describe "Performance and stress testing" do
    test "handles many OID operations efficiently" do
      # Generate 1000 OIDs
      oids =
        for i <- 1..1000 do
          [1, 3, 6, 1, 4, 1, 9999, i]
        end

      # Test sorting performance
      start_time = System.monotonic_time(:microsecond)
      sorted_oids = OID.sort(oids)
      end_time = System.monotonic_time(:microsecond)

      # Should complete in reasonable time (< 10ms)
      assert end_time - start_time < 10000
      assert length(sorted_oids) == 1000
    end

    test "handles concurrent OID operations" do
      # Test thread safety
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            oid = [1, 3, 6, 1, 4, 1, 9999, i]
            {:ok, oid_string} = OID.list_to_string(oid)
            {:ok, parsed_oid} = OID.string_to_list(oid_string)
            {i, oid, parsed_oid}
          end)
        end

      results = Task.await_many(tasks, 1000)

      # Verify all operations completed successfully
      assert length(results) == 50

      for {i, original_oid, parsed_oid} <- results do
        assert original_oid == parsed_oid
        assert List.last(original_oid) == i
      end
    end
  end
end
