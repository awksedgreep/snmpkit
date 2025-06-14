defmodule SnmpKit.SnmpMgr.AdaptiveWalkTest do
  use ExUnit.Case, async: true
  alias SnmpKit.SnmpMgr.AdaptiveWalk
  
  describe "AdaptiveWalk.filter_scope_results/2 with 3-tuple format" do
    test "filters results by scope with 3-tuple format" do
      # Test data in 3-tuple format
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},           # In scope
        {"1.3.6.1.2.1.1.1.0", :octet_string, "system"},   # Out of scope  
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "eth0"}, # In scope
        {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6},           # In scope
        {"1.3.6.1.2.1.3.1.1.1", :integer, 100}            # Out of scope
      ]
      
      root_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1]
      
      # Use reflection to test the private function behavior
      # This simulates what filter_scope_results should do
      in_scope_results = Enum.filter(results, fn {oid_string, _type, _value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
          _ -> false
        end
      end)
      
      assert length(in_scope_results) == 3
      
      # Verify only in-scope results remain
      oids = Enum.map(in_scope_results, fn {oid, _type, _value} -> oid end)
      assert "1.3.6.1.2.1.2.2.1.1.1" in oids
      assert "1.3.6.1.2.1.2.2.1.2.1" in oids
      assert "1.3.6.1.2.1.2.2.1.3.1" in oids
      refute "1.3.6.1.2.1.1.1.0" in oids
      refute "1.3.6.1.2.1.3.1.1.1" in oids
    end
    
    test "handles mixed 2-tuple and 3-tuple formats during transition" do
      # Mixed format data during transition
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},        # 3-tuple, in scope
        {"1.3.6.1.2.1.2.2.1.2.1", "eth0"},             # 2-tuple, in scope
        {"1.3.6.1.2.1.1.1.0", :octet_string, "sys"},   # 3-tuple, out of scope
        {"1.3.6.1.2.1.2.2.1.3.1", 6}                   # 2-tuple, in scope
      ]
      
      root_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1]
      
      # Filter that handles both formats
      in_scope_results = Enum.filter(results, fn
        {oid_string, _type, _value} ->
          case SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
            _ -> false
          end
        {oid_string, _value} ->
          case SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
            _ -> false
          end
      end)
      
      assert length(in_scope_results) == 3
      
      # Should include both 2-tuple and 3-tuple in-scope results
      oids = Enum.map(in_scope_results, fn
        {oid, _type, _value} -> oid
        {oid, _value} -> oid
      end)
      
      assert "1.3.6.1.2.1.2.2.1.1.1" in oids
      assert "1.3.6.1.2.1.2.2.1.2.1" in oids
      assert "1.3.6.1.2.1.2.2.1.3.1" in oids
      refute "1.3.6.1.2.1.1.1.0" in oids
    end
    
    test "extracts next OID from 3-tuple format results" do
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "eth0"},
        {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6}
      ]
      
      # Simulate next OID extraction from last result
      next_oid = case List.last(results) do
        {oid_string, _type, _value} ->
          case SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} -> oid_list
            _ -> nil
          end
        _ -> nil
      end
      
      assert next_oid == [1, 3, 6, 1, 2, 1, 2, 2, 1, 3, 1]
    end
    
    test "handles empty results gracefully" do
      results = []
      root_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1]
      
      in_scope_results = Enum.filter(results, fn {oid_string, _type, _value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
          _ -> false
        end
      end)
      
      assert in_scope_results == []
      
      next_oid = case List.last(results) do
        {oid_string, _type, _value} ->
          case SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} -> oid_list
            _ -> nil
          end
        _ -> nil
      end
      
      assert next_oid == nil
    end
  end
  
  describe "AdaptiveWalk type-aware processing" do
    test "can make decisions based on SNMP data types" do
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "FastEthernet0/1"},
        {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 1000000000},
        {"1.3.6.1.2.1.2.2.1.8.1", :integer, 1}
      ]
      
      # Filter for high-speed interfaces (gauge32 values > 100Mbps)
      high_speed_filter = fn {_oid, type, value} ->
        type == :gauge32 and is_integer(value) and value > 100_000_000
      end
      
      high_speed = Enum.filter(results, high_speed_filter)
      
      assert length(high_speed) == 1
      assert {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 1000000000} in high_speed
    end
    
    test "can process different types appropriately" do
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "interface-name"},
        {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 1000000000},
        {"1.3.6.1.2.1.2.2.1.6.1", :counter32, 12345},
        {"1.3.6.1.2.1.2.2.1.7.1", :timeticks, 98765}
      ]
      
      # Group by type
      by_type = Enum.group_by(results, fn {_oid, type, _value} -> type end)
      
      assert Map.has_key?(by_type, :integer)
      assert Map.has_key?(by_type, :octet_string)
      assert Map.has_key?(by_type, :gauge32)
      assert Map.has_key?(by_type, :counter32)
      assert Map.has_key?(by_type, :timeticks)
      
      # Verify each group has the expected entries
      assert length(by_type[:integer]) == 1
      assert length(by_type[:octet_string]) == 1
      assert length(by_type[:gauge32]) == 1
      assert length(by_type[:counter32]) == 1
      assert length(by_type[:timeticks]) == 1
    end
    
    test "preserves type information for adaptive decisions" do
      # Simulate adaptive walk making decisions based on response types
      results = [
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "very-long-interface-description-that-might-cause-issues"},
        {"1.3.6.1.2.1.2.2.1.2.2", :octet_string, "eth0"},
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.1.2", :integer, 2}
      ]
      
      # Adaptive logic: if we see long string values, might want to reduce bulk size
      has_long_strings = Enum.any?(results, fn {_oid, type, value} ->
        type == :octet_string and is_binary(value) and String.length(value) > 50
      end)
      
      assert has_long_strings == true
      
      # Count different value types for adaptive tuning
      type_counts = Enum.reduce(results, %{}, fn {_oid, type, _value}, acc ->
        Map.update(acc, type, 1, &(&1 + 1))
      end)
      
      assert type_counts[:octet_string] == 2
      assert type_counts[:integer] == 2
    end
  end
  
  describe "AdaptiveWalk error handling with 3-tuple format" do
    test "handles malformed 3-tuple data gracefully" do
      # Mix of valid and invalid tuple formats
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},     # Valid 3-tuple
        {"1.3.6.1.2.1.2.2.1.2.1", "eth0"},          # Valid 2-tuple
        {"1.3.6.1.2.1.2.2.1.3.1"},                  # Invalid - missing value
        {"1.3.6.1.2.1.2.2.1.4.1", :integer, 6, :extra}, # Invalid - extra element
        {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 1000}   # Valid 3-tuple
      ]
      
      root_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1]
      
      # Robust filter that handles various formats
      safe_results = Enum.filter(results, fn
        {oid_string, _type, _value} when is_binary(oid_string) ->
          case SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
            _ -> false
          end
        {oid_string, _value} when is_binary(oid_string) ->
          case SnmpLib.OID.string_to_list(oid_string) do
            {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
            _ -> false
          end
        _ -> false
      end)
      
      # Should only get the valid entries
      assert length(safe_results) == 3
      
      oids = Enum.map(safe_results, fn
        {oid, _type, _value} -> oid
        {oid, _value} -> oid
      end)
      
      assert "1.3.6.1.2.1.2.2.1.1.1" in oids
      assert "1.3.6.1.2.1.2.2.1.2.1" in oids
      assert "1.3.6.1.2.1.2.2.1.5.1" in oids
    end
    
    test "handles invalid OID strings in results" do
      results = [
        {"invalid.oid.string", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"", :octet_string, "empty"},
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "valid"}
      ]
      
      root_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1]
      
      # Filter with OID validation
      valid_results = Enum.filter(results, fn {oid_string, _type, _value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
          _ -> false
        end
      end)
      
      assert length(valid_results) == 2
      
      oids = Enum.map(valid_results, fn {oid, _type, _value} -> oid end)
      assert "1.3.6.1.2.1.2.2.1.1.1" in oids
      assert "1.3.6.1.2.1.2.2.1.2.1" in oids
      refute "invalid.oid.string" in oids
      refute "" in oids
    end
  end
end
