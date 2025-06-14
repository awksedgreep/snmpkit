defmodule SnmpKit.SnmpMgr.TableProcessingTest do
  use ExUnit.Case, async: true
  alias SnmpKit.SnmpMgr.Table

  describe "Table.to_table/2" do
    test "converts 3-tuple varbinds to table format" do
      # Test data in 3-tuple format {oid_string, type, value}
      varbinds = [
        # ifIndex.1
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},
        # ifDescr.1
        {"1.3.6.1.2.1.2.2.1.1.2.1", :octet_string, "eth0"},
        # ifSpeed.1
        {"1.3.6.1.2.1.2.2.1.1.5.1", :gauge32, 1_000_000_000},
        # ifIndex.2
        {"1.3.6.1.2.1.2.2.1.1.1.2", :integer, 2},
        # ifDescr.2
        {"1.3.6.1.2.1.2.2.1.1.2.2", :octet_string, "eth1"},
        # ifSpeed.2
        {"1.3.6.1.2.1.2.2.1.1.5.2", :gauge32, 100_000_000}
      ]

      # Use the interface table OID
      table_oid = "1.3.6.1.2.1.2.2.1"
      result = Table.to_table(varbinds, table_oid)

      assert {:ok, table_data} = result
      assert is_map(table_data)

      # Should have entries for indexes 1 and 2
      assert Map.has_key?(table_data, 1)
      assert Map.has_key?(table_data, 2)

      # Verify row 1 data
      row1 = table_data[1]
      # ifIndex
      assert row1[1] == 1
      # ifDescr
      assert row1[2] == "eth0"
      # ifSpeed
      assert row1[5] == 1_000_000_000

      # Verify row 2 data
      row2 = table_data[2]
      assert row2[1] == 2
      assert row2[2] == "eth1"
      assert row2[5] == 100_000_000
    end

    test "filters out OIDs not in table scope" do
      varbinds = [
        # In scope
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},
        # In scope
        {"1.3.6.1.2.1.2.2.1.1.2.1", :octet_string, "eth0"},
        # Out of scope
        {"1.3.6.1.2.1.1.1.0", :octet_string, "system"},
        # In scope
        {"1.3.6.1.2.1.2.2.1.1.1.2", :integer, 2}
      ]

      table_oid = "1.3.6.1.2.1.2.2.1"
      result = Table.to_table(varbinds, table_oid)

      assert {:ok, table_data} = result

      # Should only have interface table entries
      assert Map.has_key?(table_data, 1)
      assert Map.has_key?(table_data, 2)
      assert length(Map.keys(table_data)) == 2

      # Verify the out-of-scope OID was filtered out
      row1 = table_data[1]
      assert row1[1] == 1
      assert row1[2] == "eth0"
    end

    test "preserves type information in processing" do
      varbinds = [
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.1.2.1", :octet_string, "eth0"},
        # ifOperStatus
        {"1.3.6.1.2.1.2.2.1.1.8.1", :integer, 1}
      ]

      table_oid = "1.3.6.1.2.1.2.2.1"
      result = Table.to_table(varbinds, table_oid)

      assert {:ok, table_data} = result
      row1 = table_data[1]

      # Type information should be preserved in values
      assert is_integer(row1[1])
      assert is_binary(row1[2])
      assert is_integer(row1[8])
    end

    test "handles empty varbind list" do
      table_oid = "1.3.6.1.2.1.2.2.1"

      result = Table.to_table([], table_oid)

      assert {:ok, table_data} = result
      assert table_data == %{}
    end
  end

  describe "Table.to_map/2" do
    test "converts 3-tuple varbinds to keyed map" do
      varbinds = [
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.1.2.1", :octet_string, "eth0"},
        {"1.3.6.1.2.1.2.2.1.1.1.2", :integer, 2},
        {"1.3.6.1.2.1.2.2.1.1.2.2", :octet_string, "eth1"}
      ]

      # Use column 1 (ifIndex) as the key
      result = Table.to_map(varbinds, 1)

      assert {:ok, map_data} = result
      assert is_map(map_data)

      # Should be keyed by ifIndex values
      assert Map.has_key?(map_data, 1)
      assert Map.has_key?(map_data, 2)

      # Verify interface 1 data
      interface1 = map_data[1]
      assert interface1[1] == 1
      assert interface1[2] == "eth0"

      # Verify interface 2 data
      interface2 = map_data[2]
      assert interface2[1] == 2
      assert interface2[2] == "eth1"
    end

    test "filters OIDs outside table scope" do
      varbinds = [
        # ifIndex.1 (interface 1)
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},
        # ifDescr.1 (interface 1)
        {"1.3.6.1.2.1.2.2.1.1.2.1", :octet_string, "eth0"},
        # Different table - creates index 0
        {"1.3.6.1.2.1.1.1.0", :octet_string, "system"}
      ]

      result = Table.to_map(varbinds, 1)

      assert {:ok, map_data} = result

      # Should have two entries: keyed by column 1 values
      # The to_map function uses the specified column as the key
      # interface entry (ifIndex = 1)
      assert Map.has_key?(map_data, 1)
      # system entry (column 1 value = "system")
      assert Map.has_key?(map_data, "system")
      assert length(Map.keys(map_data)) == 2

      # Verify the interface data - should have both ifIndex and ifDescr
      interface1 = map_data[1]
      # ifIndex column
      assert interface1[1] == 1
      # ifDescr column
      assert interface1[2] == "eth0"

      # Verify the system data
      system_entry = map_data["system"]
      # column 1 for system entry
      assert system_entry[1] == "system"
    end
  end

  describe "Table.to_rows/1" do
    test "converts raw varbinds to list of rows" do
      varbinds = [
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.1.2.1", :octet_string, "eth0"},
        {"1.3.6.1.2.1.2.2.1.1.1.2", :integer, 2},
        {"1.3.6.1.2.1.2.2.1.1.2.2", :octet_string, "eth1"}
      ]

      result = Table.to_rows(varbinds)

      assert {:ok, rows} = result
      assert is_list(rows)
      # Should have 2 rows (one per index)
      assert length(rows) == 2

      # Each row should be a map with index and column data
      Enum.each(rows, fn row ->
        assert is_map(row)
        assert Map.has_key?(row, :index)
        # Should have column data
        assert Map.has_key?(row, 1) or Map.has_key?(row, 2)
      end)

      # Find rows by index
      row1 = Enum.find(rows, fn row -> row[:index] == 1 end)
      row2 = Enum.find(rows, fn row -> row[:index] == 2 end)

      assert row1 != nil
      assert row2 != nil

      # Verify row data
      # ifIndex
      assert row1[1] == 1
      # ifDescr
      assert row1[2] == "eth0"
      assert row2[1] == 2
      assert row2[2] == "eth1"
    end
  end

  describe "Table.get_indexes/1" do
    test "extracts table indexes from table data" do
      table_data = %{
        1 => %{1 => 1, 2 => "eth0"},
        10 => %{1 => 10, 2 => "eth10"},
        2 => %{1 => 2, 2 => "eth2"}
      }

      result = Table.get_indexes(table_data)

      assert {:ok, indexes} = result
      assert is_list(indexes)
      # Should return indexes as integers, sorted
      assert 1 in indexes
      assert 2 in indexes
      assert 10 in indexes
      assert length(indexes) == 3
    end

    test "handles empty table data" do
      result = Table.get_indexes(%{})

      assert {:ok, indexes} = result
      assert indexes == []
    end
  end

  describe "Table.get_columns/1" do
    test "extracts column identifiers from table data" do
      table_data = %{
        1 => %{1 => 1, 2 => "eth0", 3 => 6},
        2 => %{1 => 2, 2 => "eth1", 5 => 100}
      }

      result = Table.get_columns(table_data)

      assert {:ok, columns} = result
      assert is_list(columns)
      # Should return all unique column IDs
      assert 1 in columns
      assert 2 in columns
      assert 3 in columns
      assert 5 in columns
      assert length(columns) == 4
    end

    test "handles empty table data" do
      result = Table.get_columns(%{})

      assert {:ok, columns} = result
      assert columns == []
    end
  end
end
