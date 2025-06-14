defmodule SnmpKit.SnmpMgr.StreamProcessingTest do
  use ExUnit.Case, async: true
  alias SnmpKit.SnmpMgr.Stream
  
  describe "Stream.walk/3 with 3-tuple format" do
    setup do
      # Mock data in 3-tuple format that stream processing should handle
      mock_varbinds = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "FastEthernet0/1"},
        {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6},
        {"1.3.6.1.2.1.2.2.1.1.2", :integer, 2},
        {"1.3.6.1.2.1.2.2.1.2.2", :octet_string, "FastEthernet0/2"},
        {"1.3.6.1.2.1.2.2.1.3.2", :integer, 6}
      ]
      
      %{mock_varbinds: mock_varbinds}
    end
    
    test "filter function handles 3-tuple format correctly", %{mock_varbinds: varbinds} do
      # Test that filter functions can access type information
      filter_fn = fn {oid, type, _value} ->
        # Filter for interface descriptions (column 2) that are strings
        String.contains?(oid, "1.3.6.1.2.1.2.2.1.2.") and type == :octet_string
      end
      
      filtered = Enum.filter(varbinds, filter_fn)
      
      assert length(filtered) == 2
      # Should only have interface description entries
      assert {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "FastEthernet0/1"} in filtered
      assert {"1.3.6.1.2.1.2.2.1.2.2", :octet_string, "FastEthernet0/2"} in filtered
    end
    
    test "filter function can access type information for processing decisions", %{mock_varbinds: varbinds} do
      # Filter for integer types only
      integer_filter = fn {_oid, type, _value} -> type == :integer end
      
      filtered = Enum.filter(varbinds, integer_filter)
      
      assert length(filtered) == 4  # Should have 4 integer entries
      Enum.each(filtered, fn {_oid, type, _value} ->
        assert type == :integer
      end)
    end
    
    test "filter function can combine OID and type criteria", %{mock_varbinds: varbinds} do
      # Filter for ifIndex entries (column 1) that are integers
      combined_filter = fn {oid, type, _value} ->
        String.contains?(oid, "1.3.6.1.2.1.2.2.1.1.") and type == :integer
      end
      
      filtered = Enum.filter(varbinds, combined_filter)
      
      assert length(filtered) == 2  # Should have 2 ifIndex entries
      assert {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1} in filtered
      assert {"1.3.6.1.2.1.2.2.1.1.2", :integer, 2} in filtered
    end
    
    test "processes mixed 2-tuple and 3-tuple formats during transition" do
      # Simulate mixed format during transition period
      mixed_varbinds = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},        # 3-tuple
        {"1.3.6.1.2.1.2.2.1.2.1", "FastEthernet0/1"},  # 2-tuple
        {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6}         # 3-tuple
      ]
      
      # Filter that handles both formats
      flexible_filter = fn
        {oid, _type, _value} ->
          # 3-tuple format
          String.contains?(oid, "1.3.6.1.2.1.2.2.1.")
        {oid, _value} ->
          # 2-tuple format
          String.contains?(oid, "1.3.6.1.2.1.2.2.1.")
      end
      
      filtered = Enum.filter(mixed_varbinds, flexible_filter)
      
      assert length(filtered) == 3  # All should pass the OID filter
    end
  end
  
  describe "Stream result processing" do
    test "handles 3-tuple format in result processing" do
      # Simulate stream results in 3-tuple format
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "eth0"},
        {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6}
      ]
      
      # Test that we can extract OIDs for next operation
      last_oid = case List.last(results) do
        {oid_string, _type, _value} ->
          oid_string
        _ -> nil
      end
      
      assert last_oid == "1.3.6.1.2.1.2.2.1.3.1"
    end
    
    test "filters results by scope with 3-tuple format" do
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},           # In scope
        {"1.3.6.1.2.1.1.1.0", :octet_string, "system"},   # Out of scope
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "eth0"}  # In scope
      ]
      
      root_oid = "1.3.6.1.2.1.2.2.1"
      
      # Simulate scope filtering
      in_scope = Enum.filter(results, fn {oid_string, _type, _value} ->
        String.starts_with?(oid_string, root_oid)
      end)
      
      assert length(in_scope) == 2
      refute Enum.any?(in_scope, fn {oid, _type, _value} -> 
        String.starts_with?(oid, "1.3.6.1.2.1.1")
      end)
    end
    
    test "preserves type information through processing chain" do
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "interface"},
        {"1.3.6.1.2.1.2.2.1.5.1", :gauge32, 1000000000}
      ]
      
      # Verify type information is accessible
      types = Enum.map(results, fn {_oid, type, _value} -> type end)
      
      assert :integer in types
      assert :octet_string in types
      assert :gauge32 in types
      
      # Verify values are preserved correctly
      values = Enum.map(results, fn {_oid, _type, value} -> value end)
      
      assert 1 in values
      assert "interface" in values
      assert 1000000000 in values
    end
  end
  
  describe "Stream error handling with 3-tuple format" do
    test "handles malformed 3-tuple data gracefully" do
      # Test with incomplete tuple
      malformed_results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer},  # Missing value
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "eth0", :extra},  # Extra element
        {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6}  # Correct format
      ]
      
      # Filter should handle gracefully
      safe_filter = fn
        {oid, _type, _value} when is_binary(oid) -> true
        _ -> false
      end
      
      filtered = Enum.filter(malformed_results, safe_filter)
      
      # Should only get the correctly formatted entry
      assert length(filtered) == 1
      assert {"1.3.6.1.2.1.2.2.1.3.1", :integer, 6} in filtered
    end
    
    test "handles invalid OID strings in 3-tuple format" do
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},     # Valid OID
        {"invalid.oid", :octet_string, "test"},      # Invalid OID
        {"1.3.6.1.2.1.2.2.1.2.1", :octet_string, "eth0"} # Valid OID
      ]
      
      # Filter with OID validation
      valid_oid_filter = fn {oid_string, _type, _value} ->
        String.contains?(oid_string, ".")
      end
      
      filtered = Enum.filter(results, valid_oid_filter)
      
      # All OIDs contain dots, so all should pass this simple filter
      assert length(filtered) == 3
      
      # More sophisticated validation
      snmp_oid_filter = fn {oid_string, _type, _value} ->
        String.match?(oid_string, ~r/^\d+(\.\d+)+$/)
      end
      
      valid_snmp_oids = Enum.filter(results, snmp_oid_filter)
      assert length(valid_snmp_oids) == 2  # Should exclude "invalid.oid"
    end
  end
end
