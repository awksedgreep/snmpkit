defmodule SnmpKit.SnmpSim.OIDTreeTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.OIDTree

  describe "OID Tree Creation and Basic Operations" do
    test "creates new empty tree" do
      tree = OIDTree.new()

      assert OIDTree.size(tree) == 0
      assert OIDTree.empty?(tree) == true
      assert OIDTree.list_oids(tree) == []
    end

    test "inserts single OID with value" do
      tree = OIDTree.new()
      tree = OIDTree.insert(tree, "1.3.6.1.2.1.1.1.0", "System Description")

      assert OIDTree.size(tree) == 1
      assert OIDTree.empty?(tree) == false
      assert {:ok, "System Description", nil} = OIDTree.get(tree, "1.3.6.1.2.1.1.1.0")
    end

    test "inserts multiple OIDs" do
      tree = OIDTree.new()

      tree =
        tree
        |> OIDTree.insert("1.3.6.1.2.1.1.1.0", "System Description")
        |> OIDTree.insert("1.3.6.1.2.1.1.3.0", {:timeticks, 123_456})
        |> OIDTree.insert("1.3.6.1.2.1.2.1.0", 2)

      assert OIDTree.size(tree) == 3
      assert {:ok, "System Description", nil} = OIDTree.get(tree, "1.3.6.1.2.1.1.1.0")
      assert {:ok, {:timeticks, 123_456}, nil} = OIDTree.get(tree, "1.3.6.1.2.1.1.3.0")
      assert {:ok, 2, nil} = OIDTree.get(tree, "1.3.6.1.2.1.2.1.0")
    end

    test "inserts OID with behavior information" do
      tree = OIDTree.new()
      behavior = {:traffic_counter, %{rate_range: {1000, 125_000_000}}}

      tree = OIDTree.insert(tree, "1.3.6.1.2.1.2.2.1.10.1", {:counter32, 1_234_567}, behavior)

      assert {:ok, {:counter32, 1_234_567}, behavior} =
               OIDTree.get(tree, "1.3.6.1.2.1.2.2.1.10.1")
    end

    test "handles non-existent OID lookup" do
      tree = OIDTree.new()
      tree = OIDTree.insert(tree, "1.3.6.1.2.1.1.1.0", "System Description")

      assert :not_found = OIDTree.get(tree, "1.3.6.1.2.1.1.2.0")
      assert :not_found = OIDTree.get(tree, "1.3.6.1.9.9.9.9.9")
    end

    test "overwrites existing OID value" do
      tree = OIDTree.new()

      tree = OIDTree.insert(tree, "1.3.6.1.2.1.1.1.0", "Original Value")
      assert OIDTree.size(tree) == 1
      assert {:ok, "Original Value", nil} = OIDTree.get(tree, "1.3.6.1.2.1.1.1.0")

      tree = OIDTree.insert(tree, "1.3.6.1.2.1.1.1.0", "Updated Value")
      # Size shouldn't change
      assert OIDTree.size(tree) == 1
      assert {:ok, "Updated Value", nil} = OIDTree.get(tree, "1.3.6.1.2.1.1.1.0")
    end
  end

  describe "Lexicographic Ordering and GETNEXT" do
    setup do
      tree =
        OIDTree.new()
        |> OIDTree.insert("1.3.6.1.2.1.1.1.0", "sysDescr")
        |> OIDTree.insert("1.3.6.1.2.1.1.3.0", "sysUpTime")
        |> OIDTree.insert("1.3.6.1.2.1.2.1.0", "ifNumber")
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.1.1", "ifIndex.1")
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.1.2", "ifIndex.2")
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.10.1", "ifInOctets.1")
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.10.2", "ifInOctets.2")

      {:ok, tree: tree}
    end

    test "maintains lexicographic order for OID list", %{tree: tree} do
      oids = OIDTree.list_oids(tree)

      expected_order = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.3.0",
        "1.3.6.1.2.1.2.1.0",
        "1.3.6.1.2.1.2.2.1.1.1",
        "1.3.6.1.2.1.2.2.1.1.2",
        "1.3.6.1.2.1.2.2.1.10.1",
        "1.3.6.1.2.1.2.2.1.10.2"
      ]

      assert oids == expected_order
    end

    test "get_next returns correct next OID", %{tree: tree} do
      # Test basic GETNEXT operation
      assert {:ok, "1.3.6.1.2.1.1.3.0", "sysUpTime", nil} =
               OIDTree.get_next(tree, "1.3.6.1.2.1.1.1.0")

      assert {:ok, "1.3.6.1.2.1.2.1.0", "ifNumber", nil} =
               OIDTree.get_next(tree, "1.3.6.1.2.1.1.3.0")

      assert {:ok, "1.3.6.1.2.1.2.2.1.1.1", "ifIndex.1", nil} =
               OIDTree.get_next(tree, "1.3.6.1.2.1.2.1.0")
    end

    test "get_next with partial OID matches correctly", %{tree: tree} do
      # Requesting next after non-existent OID should find next valid one
      assert {:ok, "1.3.6.1.2.1.1.3.0", "sysUpTime", nil} =
               OIDTree.get_next(tree, "1.3.6.1.2.1.1.2.0")

      assert {:ok, "1.3.6.1.2.1.2.2.1.1.2", "ifIndex.2", nil} =
               OIDTree.get_next(tree, "1.3.6.1.2.1.2.2.1.1.1")
    end

    test "get_next returns end_of_mib when no more OIDs", %{tree: tree} do
      assert :end_of_mib = OIDTree.get_next(tree, "1.3.6.1.2.1.2.2.1.10.2")
      assert :end_of_mib = OIDTree.get_next(tree, "1.3.6.1.9.9.9.9.9")
    end

    test "get_next with interface table traversal", %{tree: tree} do
      # Start with interface table base
      current_oid = "1.3.6.1.2.1.2.2.1.1"

      # Should get first ifIndex
      assert {:ok, next_oid, "ifIndex.1", nil} = OIDTree.get_next(tree, current_oid)
      assert next_oid == "1.3.6.1.2.1.2.2.1.1.1"

      # Should get second ifIndex
      assert {:ok, next_oid, "ifIndex.2", nil} = OIDTree.get_next(tree, next_oid)
      assert next_oid == "1.3.6.1.2.1.2.2.1.1.2"

      # Should move to next column (ifInOctets)
      assert {:ok, next_oid, "ifInOctets.1", nil} = OIDTree.get_next(tree, next_oid)
      assert next_oid == "1.3.6.1.2.1.2.2.1.10.1"
    end
  end

  describe "GETBULK Operations" do
    setup do
      # Create a larger tree for bulk testing
      tree = OIDTree.new()

      # Add system group
      tree =
        tree
        |> OIDTree.insert("1.3.6.1.2.1.1.1.0", "System Description")
        |> OIDTree.insert("1.3.6.1.2.1.1.3.0", {:timeticks, 123_456})

      # Add interface table with multiple interfaces and columns
      interface_oids = [
        {"1.3.6.1.2.1.2.2.1.1.1", "Interface 1 Index"},
        {"1.3.6.1.2.1.2.2.1.1.2", "Interface 2 Index"},
        {"1.3.6.1.2.1.2.2.1.1.3", "Interface 3 Index"},
        {"1.3.6.1.2.1.2.2.1.2.1", "Interface 1 Descr"},
        {"1.3.6.1.2.1.2.2.1.2.2", "Interface 2 Descr"},
        {"1.3.6.1.2.1.2.2.1.2.3", "Interface 3 Descr"},
        {"1.3.6.1.2.1.2.2.1.10.1", {:counter32, 1000}},
        {"1.3.6.1.2.1.2.2.1.10.2", {:counter32, 2000}},
        {"1.3.6.1.2.1.2.2.1.10.3", {:counter32, 3000}},
        {"1.3.6.1.2.1.2.2.1.16.1", {:counter32, 500}},
        {"1.3.6.1.2.1.2.2.1.16.2", {:counter32, 600}},
        {"1.3.6.1.2.1.2.2.1.16.3", {:counter32, 700}}
      ]

      tree =
        Enum.reduce(interface_oids, tree, fn {oid, value}, acc ->
          OIDTree.insert(acc, oid, value)
        end)

      {:ok, tree: tree}
    end

    test "bulk_walk returns correct number of results", %{tree: tree} do
      # Request 5 OIDs starting from interface table
      results = OIDTree.bulk_walk(tree, "1.3.6.1.2.1.2.2.1.1", 5)

      assert length(results) == 5

      # Check first few results are correct
      assert [
               {"1.3.6.1.2.1.2.2.1.1.1", "Interface 1 Index", nil},
               {"1.3.6.1.2.1.2.2.1.1.2", "Interface 2 Index", nil},
               {"1.3.6.1.2.1.2.2.1.1.3", "Interface 3 Index", nil},
               {"1.3.6.1.2.1.2.2.1.2.1", "Interface 1 Descr", nil},
               {"1.3.6.1.2.1.2.2.1.2.2", "Interface 2 Descr", nil}
             ] = results
    end

    test "bulk_walk with zero max_repetitions returns empty", %{tree: tree} do
      results = OIDTree.bulk_walk(tree, "1.3.6.1.2.1.2.2.1.1", 0)
      assert results == []
    end

    test "bulk_walk from middle of tree", %{tree: tree} do
      # Start from middle of interface table
      results = OIDTree.bulk_walk(tree, "1.3.6.1.2.1.2.2.1.2.2", 3)

      assert length(results) == 3

      assert [
               {"1.3.6.1.2.1.2.2.1.2.3", "Interface 3 Descr", nil},
               {"1.3.6.1.2.1.2.2.1.10.1", {:counter32, 1000}, nil},
               {"1.3.6.1.2.1.2.2.1.10.2", {:counter32, 2000}, nil}
             ] = results
    end

    test "bulk_walk near end of tree", %{tree: tree} do
      # Start near end and request more than available
      results = OIDTree.bulk_walk(tree, "1.3.6.1.2.1.2.2.1.16.2", 10)

      # Should only get available OIDs
      assert length(results) == 1
      assert [{"1.3.6.1.2.1.2.2.1.16.3", {:counter32, 700}, nil}] = results
    end

    test "bulk_walk beyond end of tree", %{tree: tree} do
      # Start beyond all OIDs
      results = OIDTree.bulk_walk(tree, "1.3.6.1.9.9.9", 5)

      assert results == []
    end
  end

  describe "Performance with Large OID Trees" do
    test "handles large OID trees efficiently" do
      # Create tree with 1000+ OIDs
      tree = OIDTree.new()

      # Add OIDs in interface table pattern (simulating real device)
      tree =
        Enum.reduce(1..100, tree, fn interface_index, acc ->
          # Add multiple columns for each interface
          # Common interface table columns
          columns = [1, 2, 10, 16, 14, 20]

          Enum.reduce(columns, acc, fn column, inner_acc ->
            oid = "1.3.6.1.2.1.2.2.1.#{column}.#{interface_index}"
            value = {:counter32, interface_index * column * 1000}
            OIDTree.insert(inner_acc, oid, value)
          end)
        end)

      # 100 interfaces * 6 columns
      assert OIDTree.size(tree) == 600

      # Test that lookups are still fast
      start_time = :erlang.monotonic_time(:microsecond)

      # Perform 100 random lookups
      for _ <- 1..100 do
        interface = :rand.uniform(100)
        column = Enum.random([1, 2, 10, 16, 14, 20])
        oid = "1.3.6.1.2.1.2.2.1.#{column}.#{interface}"
        assert {:ok, _value, nil} = OIDTree.get(tree, oid)
      end

      end_time = :erlang.monotonic_time(:microsecond)
      lookup_time = end_time - start_time

      # Should complete 100 lookups in under 10ms (100 microseconds per lookup average)
      assert lookup_time < 10_000, "Lookups took #{lookup_time} microseconds, expected < 10,000"
    end

    test "GETNEXT traversal is efficient on large trees" do
      # Create tree with interface table pattern
      tree = OIDTree.new()

      tree =
        Enum.reduce(1..50, tree, fn interface_index, acc ->
          # ifInOctets
          oid = "1.3.6.1.2.1.2.2.1.10.#{interface_index}"
          value = {:counter32, interface_index * 1000}
          OIDTree.insert(acc, oid, value)
        end)

      start_time = :erlang.monotonic_time(:microsecond)

      # Walk through entire table using GETNEXT
      current_oid = "1.3.6.1.2.1.2.2.1.10"
      count = 0

      loop_fn = fn loop_fn, oid, acc_count ->
        case OIDTree.get_next(tree, oid) do
          {:ok, next_oid, _value, _behavior} ->
            if String.starts_with?(next_oid, "1.3.6.1.2.1.2.2.1.10.") do
              loop_fn.(loop_fn, next_oid, acc_count + 1)
            else
              acc_count
            end

          :end_of_mib ->
            acc_count
        end
      end

      final_count = loop_fn.(loop_fn, current_oid, 0)

      end_time = :erlang.monotonic_time(:microsecond)
      traversal_time = end_time - start_time

      assert final_count == 50
      # Should complete traversal in under 10ms (200 microseconds per GETNEXT average)
      # Increased tolerance to account for system load variations
      assert traversal_time < 10_000,
             "Traversal took #{traversal_time} microseconds, expected < 10,000"
    end

    test "memory usage scales reasonably with tree size" do
      # This is more of a smoke test - actual memory usage would need profiling tools
      small_tree = create_test_tree(100)
      medium_tree = create_test_tree(1000)

      assert OIDTree.size(small_tree) == 100
      assert OIDTree.size(medium_tree) == 1000

      # Trees should be functional and responsive
      assert {:ok, _value, nil} = OIDTree.get(small_tree, "1.3.6.1.2.1.2.2.1.10.50")
      assert {:ok, _value, nil} = OIDTree.get(medium_tree, "1.3.6.1.2.1.2.2.1.10.500")
    end
  end

  # Helper function for performance tests
  defp create_test_tree(size) do
    tree = OIDTree.new()

    Enum.reduce(1..size, tree, fn i, acc ->
      oid = "1.3.6.1.2.1.2.2.1.10.#{i}"
      value = {:counter32, i * 1000}
      OIDTree.insert(acc, oid, value)
    end)
  end
end
