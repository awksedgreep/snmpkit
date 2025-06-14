defmodule SnmpKit.SnmpSim.BulkOperationsTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.{BulkOperations, OIDTree}

  describe "GETBULK Request Handling" do
    setup do
      # Create test OID tree with interface table data
      tree =
        OIDTree.new()
        |> OIDTree.insert("1.3.6.1.2.1.1.1.0", "System Description")
        |> OIDTree.insert("1.3.6.1.2.1.1.3.0", {:timeticks, 123_456})
        # ifNumber
        |> OIDTree.insert("1.3.6.1.2.1.2.1.0", 3)
        # ifIndex.1
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.1.1", 1)
        # ifIndex.2
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.1.2", 2)
        # ifIndex.3
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.1.3", 3)
        # ifDescr.1
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.2.1", "eth0")
        # ifDescr.2
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.2.2", "eth1")
        # ifDescr.3
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.2.3", "lo0")
        # ifInOctets.1
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.10.1", {:counter32, 1000})
        # ifInOctets.2
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.10.2", {:counter32, 2000})
        # ifInOctets.3
        |> OIDTree.insert("1.3.6.1.2.1.2.2.1.10.3", {:counter32, 3000})

      {:ok, tree: tree}
    end

    test "handles basic GETBULK with no non-repeaters", %{tree: tree} do
      varbinds = [{"1.3.6.1.2.1.2.2.1.1", nil}]

      {:ok, results} = BulkOperations.handle_bulk_request(tree, 0, 5, varbinds)

      assert length(results) == 5

      # Should get interface indexes
      assert [
               {"1.3.6.1.2.1.2.2.1.1.1", 1, nil},
               {"1.3.6.1.2.1.2.2.1.1.2", 2, nil},
               {"1.3.6.1.2.1.2.2.1.1.3", 3, nil},
               {"1.3.6.1.2.1.2.2.1.2.1", "eth0", nil},
               {"1.3.6.1.2.1.2.2.1.2.2", "eth1", nil}
             ] = results
    end

    test "handles GETBULK with non-repeaters", %{tree: tree} do
      varbinds = [
        # Non-repeater: sysDescr
        {"1.3.6.1.2.1.1.1.0", nil},
        # Repeater: ifIndex
        {"1.3.6.1.2.1.2.2.1.1", nil}
      ]

      {:ok, results} = BulkOperations.handle_bulk_request(tree, 1, 3, varbinds)

      # Should get sysUpTime (next after sysDescr) plus 3 interface indexes
      assert length(results) == 4

      assert [
               # Non-repeater result
               {"1.3.6.1.2.1.1.3.0", {:timeticks, 123_456}, nil},
               # First repeater
               {"1.3.6.1.2.1.2.2.1.1.1", 1, nil},
               # Second repeater
               {"1.3.6.1.2.1.2.2.1.1.2", 2, nil},
               # Third repeater
               {"1.3.6.1.2.1.2.2.1.1.3", 3, nil}
             ] = results
    end

    test "handles GETBULK with multiple repeating variables", %{tree: tree} do
      varbinds = [
        # ifIndex
        {"1.3.6.1.2.1.2.2.1.1", nil},
        # ifDescr
        {"1.3.6.1.2.1.2.2.1.2", nil}
      ]

      {:ok, results} = BulkOperations.handle_bulk_request(tree, 0, 2, varbinds)

      # Should get 2 repetitions of each variable (4 total)
      assert length(results) == 4

      # Results should be interleaved: ifIndex.1, ifIndex.2, ifDescr.1, ifDescr.2
      assert [
               # ifIndex.1
               {"1.3.6.1.2.1.2.2.1.1.1", 1, nil},
               # ifIndex.2
               {"1.3.6.1.2.1.2.2.1.1.2", 2, nil},
               # ifDescr.1
               {"1.3.6.1.2.1.2.2.1.2.1", "eth0", nil},
               # ifDescr.2
               {"1.3.6.1.2.1.2.2.1.2.2", "eth1", nil}
             ] = results
    end

    test "handles GETBULK at end of tree", %{tree: tree} do
      # Near end of tree
      varbinds = [{"1.3.6.1.2.1.2.2.1.10.2", nil}]

      {:ok, results} = BulkOperations.handle_bulk_request(tree, 0, 5, varbinds)

      # Should only get remaining OID(s)
      assert length(results) == 1
      assert [{"1.3.6.1.2.1.2.2.1.10.3", {:counter32, 3000}, nil}] = results
    end

    test "handles GETBULK beyond end of tree", %{tree: tree} do
      # Beyond all OIDs
      varbinds = [{"1.3.6.1.9.9.9", nil}]

      {:ok, results} = BulkOperations.handle_bulk_request(tree, 0, 5, varbinds)

      assert results == []
    end

    test "validates non-repeaters parameter" do
      tree = OIDTree.new()
      varbinds = [{"1.3.6.1.2.1.1.1.0", nil}]

      # Negative non-repeaters
      assert {:error, :invalid_non_repeaters} =
               BulkOperations.handle_bulk_request(tree, -1, 5, varbinds)

      # Non-repeaters exceeds varbinds length
      assert {:error, :non_repeaters_exceeds_varbinds} =
               BulkOperations.handle_bulk_request(tree, 2, 5, varbinds)
    end

    test "validates max-repetitions parameter" do
      tree = OIDTree.new()
      varbinds = [{"1.3.6.1.2.1.1.1.0", nil}]

      # Negative max-repetitions
      assert {:error, :invalid_max_repetitions} =
               BulkOperations.handle_bulk_request(tree, 0, -1, varbinds)
    end
  end

  describe "Response Size Management" do
    test "estimates response size for various data types" do
      varbinds = [
        {"1.3.6.1.2.1.1.1.0", "Short string", nil},
        {"1.3.6.1.2.1.1.3.0", {:timeticks, 123_456}, nil},
        {"1.3.6.1.2.1.2.2.1.10.1", {:counter32, 1_234_567_890}, nil},
        {"1.3.6.1.2.1.2.2.1.11.1", {:counter64, 1_234_567_890_123_456}, nil}
      ]

      size = BulkOperations.estimate_response_size(varbinds)

      # Should be reasonable estimate (not exact, but in right ballpark)
      # Minimum overhead
      assert size > 100
      # Not excessive for small response
      assert size < 500
    end

    test "optimize_bulk_response fits results within size limit" do
      # Create large results that exceed size limit
      large_results =
        for i <- 1..100 do
          oid = "1.3.6.1.2.1.2.2.1.10.#{i}"

          value =
            "Very long interface description string for interface #{i} that makes the response large"

          {oid, value, nil}
        end

      # Optimize for small size limit
      {:ok, optimized} = BulkOperations.optimize_bulk_response(large_results, 500)

      # Should have fewer results to fit in size limit
      assert length(optimized) < length(large_results)
      # But should have at least some results
      assert length(optimized) > 0

      # Verify optimized results fit in size limit
      optimized_size = BulkOperations.estimate_response_size(optimized)
      assert optimized_size <= 500
    end

    test "optimize_bulk_response handles oversized single result" do
      # Single result that's too big
      huge_result = [
        {"1.3.6.1.2.1.1.1.0", String.duplicate("X", 2000), nil}
      ]

      # Should return error if even first result is too big
      assert {:error, :too_big} = BulkOperations.optimize_bulk_response(huge_result, 100)
    end

    test "optimize_bulk_response with reasonable size limit" do
      results = [
        {"1.3.6.1.2.1.1.1.0", "System Description", nil},
        {"1.3.6.1.2.1.1.3.0", {:timeticks, 123_456}, nil},
        {"1.3.6.1.2.1.2.1.0", 3, nil}
      ]

      # Should fit comfortably in reasonable size limit
      {:ok, optimized} = BulkOperations.optimize_bulk_response(results, 1400)

      assert length(optimized) == length(results)
      assert optimized == results
    end
  end

  describe "Interface Table Processing" do
    setup do
      # Create interface table with multiple interfaces and columns
      tree = OIDTree.new()

      interfaces = 1..5

      columns = [
        {1, "Index"},
        {2, "Description"},
        {3, "Type"},
        {5, "Speed"},
        {10, "InOctets"},
        {16, "OutOctets"}
      ]

      tree =
        for interface <- interfaces, {col_id, col_name} <- columns, reduce: tree do
          acc ->
            oid = "1.3.6.1.2.1.2.2.1.#{col_id}.#{interface}"

            value =
              case col_name do
                "Index" -> interface
                "Description" -> "Interface #{interface}"
                # ethernetCsmacd
                "Type" -> 6
                # 1 Gbps
                "Speed" -> 1_000_000_000
                "InOctets" -> {:counter32, interface * 1000}
                "OutOctets" -> {:counter32, interface * 800}
              end

            OIDTree.insert(acc, oid, value)
        end

      {:ok, tree: tree}
    end

    test "processes interface table efficiently", %{tree: tree} do
      {:ok, results} = BulkOperations.process_interface_table(tree, "1.3.6.1.2.1.2.2.1", 10)

      assert length(results) == 10

      # Should get first 10 OIDs in the interface table
      first_oid = List.first(results) |> elem(0)
      assert String.starts_with?(first_oid, "1.3.6.1.2.1.2.2.1")
    end

    test "handles table requests with more repetitions than available", %{tree: tree} do
      {:ok, results} = BulkOperations.process_interface_table(tree, "1.3.6.1.2.1.2.2.1", 100)

      # Should get all available OIDs (5 interfaces * 6 columns = 30)
      assert length(results) == 30

      # Verify all results are from interface table
      assert Enum.all?(results, fn {oid, _value, _behavior} ->
               String.starts_with?(oid, "1.3.6.1.2.1.2.2.1")
             end)
    end

    test "handles table requests for non-existent table", %{tree: tree} do
      {:ok, results} = BulkOperations.process_interface_table(tree, "1.3.6.1.2.1.99.99", 10)

      assert results == []
    end
  end

  describe "Edge Cases and Error Handling" do
    test "handles empty OID tree" do
      tree = OIDTree.new()
      varbinds = [{"1.3.6.1.2.1.1.1.0", nil}]

      {:ok, results} = BulkOperations.handle_bulk_request(tree, 0, 5, varbinds)

      assert results == []
    end

    test "handles empty variable bindings list" do
      tree = OIDTree.new() |> OIDTree.insert("1.3.6.1.2.1.1.1.0", "Test")

      {:ok, results} = BulkOperations.handle_bulk_request(tree, 0, 5, [])

      assert results == []
    end

    test "handles zero max-repetitions" do
      tree = OIDTree.new() |> OIDTree.insert("1.3.6.1.2.1.1.1.0", "Test")
      varbinds = [{"1.3.6.1.2.1.1.1.0", nil}]

      {:ok, results} = BulkOperations.handle_bulk_request(tree, 0, 0, varbinds)

      assert results == []
    end

    test "handles max non-repeaters equal to varbinds length" do
      tree =
        OIDTree.new()
        |> OIDTree.insert("1.3.6.1.2.1.1.1.0", "sysDescr")
        |> OIDTree.insert("1.3.6.1.2.1.1.3.0", "sysUpTime")

      varbinds = [
        {"1.3.6.1.2.1.1.1.0", nil},
        {"1.3.6.1.2.1.1.2.0", nil}
      ]

      # All variables are non-repeaters, none are repeating
      {:ok, results} = BulkOperations.handle_bulk_request(tree, 2, 5, varbinds)

      # Should get GETNEXT for both non-repeaters
      assert length(results) == 2

      assert [
               # Next after sysDescr
               {"1.3.6.1.2.1.1.3.0", "sysUpTime", nil},
               # Next after non-existent OID
               {"1.3.6.1.2.1.1.3.0", "sysUpTime", nil}
             ] = results
    end

    test "estimates size for various SNMP data types" do
      # Test all supported SNMP data types
      test_cases = [
        "Simple string",
        42,
        {:counter32, 1_234_567_890},
        {:counter64, 1_234_567_890_123_456_789},
        {:gauge32, 50},
        {:timeticks, 123_456},
        {:ipaddress, "192.168.1.1"},
        {:objectid, "1.3.6.1.2.1.1.1.0"},
        :end_of_mib_view,
        :no_such_object,
        :no_such_instance,
        nil
      ]

      for test_value <- test_cases do
        varbinds = [{"1.3.6.1.2.1.1.1.0", test_value, nil}]
        size = BulkOperations.estimate_response_size(varbinds)

        # All estimates should be reasonable (not zero, not huge)
        assert size > 10
        assert size < 1000
      end
    end
  end
end
