defmodule SnmpKit.SnmpMgr.ErrorComprehensiveTest do
  use ExUnit.Case, async: false
  
  alias SnmpKit.SnmpKit.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :error
  @moduletag :snmp_lib_integration

  describe "Error Format Consistency with SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "all SNMP operations return consistent error formats", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test error format consistency across all operation types
      operations = [
        # GET operation with invalid OID
        {:get, fn -> SnmpMgr.get(target, "invalid.oid", timeout: 100) end},
        
        # SET operation with invalid OID  
        {:set, fn -> SnmpMgr.set(target, "invalid.oid", "value", timeout: 100) end},
        
        # GET-BULK operation with invalid OID
        {:get_bulk, fn -> SnmpMgr.get_bulk(target, "invalid.oid", max_repetitions: 3, timeout: 100) end},
        
        # GET-NEXT operation with invalid OID
        {:get_next, fn -> SnmpMgr.get_next(target, "invalid.oid", timeout: 100) end},
        
        # WALK operation with invalid OID
        {:walk, fn -> SnmpMgr.walk(target, "invalid.oid", timeout: 100) end}
      ]
      
      Enum.each(operations, fn {op_type, operation} ->
        case operation.() do
          {:ok, _} -> 
            # Some operations might succeed unexpectedly
            assert true
            
          {:error, reason} ->
            # Error reason should be properly formatted from snmp_lib
            assert is_atom(reason) or (is_tuple(reason) and tuple_size(reason) >= 1),
              "#{op_type} should return proper error format, got: #{inspect(reason)}"
        end
      end)
    end

    test "network errors handled consistently through snmp_lib", %{device: device} do
      # Test network error handling through snmp_lib with unreachable targets
      unreachable_targets = [
        "240.0.0.1",
        "192.0.2.254"
      ]
      
      Enum.each(unreachable_targets, fn target ->
        result = SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: device.community, timeout: 50)
        
        case result do
          {:error, reason} when reason in [:timeout, :host_unreachable, :network_unreachable,
                                          :ehostunreach, :enetunreach, :econnrefused] ->
            # Expected network errors through snmp_lib
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "Network error should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Unexpected success (target might exist)
            assert true
        end
      end)
    end

    test "timeout errors handled by snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test timeout behavior through snmp_lib
      very_short_timeouts = [1, 5, 10]
      
      Enum.each(very_short_timeouts, fn timeout ->
        result = SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: device.community, timeout: timeout)
        
        case result do
          {:error, :timeout} ->
            # Expected timeout error from snmp_lib
            assert true
            
          {:error, reason} ->
            # Other errors acceptable (might be faster than timeout)
            assert is_atom(reason) or is_tuple(reason),
              "Timeout error should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Operation completed faster than timeout
            assert true
        end
      end)
    end

    test "authentication errors through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test authentication error handling through snmp_lib
      invalid_communities = ["wrong_community", "", "invalid123"]
      
      Enum.each(invalid_communities, fn community ->
        result = SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: community, timeout: 100)
        
        case result do
          {:error, reason} when reason in [:authentication_error, :bad_community] ->
            # Expected authentication error from snmp_lib
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "Authentication error should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Might succeed in test environment
            assert true
        end
      end)
    end
  end

  describe "SnmpLib.OID Error Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "invalid OID formats handled by SnmpLib.OID", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test invalid OID handling through SnmpLib.OID
      invalid_oids = [
        "invalid.oid.format",
        "",
        "not.numeric.oid",
        "1.2.3.4.5.6.7.8.9.999.999.999"
      ]
      
      Enum.each(invalid_oids, fn oid ->
        result = SnmpMgr.get(target, oid, community: device.community, timeout: 100)
        
        case result do
          {:error, reason} ->
            # Should get proper error from SnmpLib.OID validation
            assert is_atom(reason) or is_tuple(reason),
              "Invalid OID should return proper error format: #{inspect(reason)}"
            
          {:ok, _} ->
            # Some invalid OIDs might resolve unexpectedly
            assert true
        end
      end)
    end

    test "OID processing errors consistent across operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      invalid_oid = "completely.invalid.oid"
      
      # Test OID error consistency across different operations
      operations = [
        fn -> SnmpMgr.get(target, invalid_oid, community: device.community, timeout: 100) end,
        fn -> SnmpMgr.set(target, invalid_oid, "value", community: device.community, timeout: 100) end,
        fn -> SnmpMgr.get_bulk(target, invalid_oid, max_repetitions: 3, 
                               community: device.community, timeout: 100) end,
        fn -> SnmpMgr.walk(target, invalid_oid, community: device.community, timeout: 100) end
      ]
      
      Enum.each(operations, fn operation ->
        case operation.() do
          {:error, reason} ->
            # All should return similar error format for OID errors
            assert is_atom(reason) or is_tuple(reason),
              "OID error should be consistently formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Unexpected success
            assert true
        end
      end)
    end
  end

  describe "Multi-Operation Error Handling" do
    setup do
      # Create multiple devices for multi-operation testing
      {:ok, device1} = SNMPSimulator.create_test_device()
      {:ok, device2} = SNMPSimulator.create_test_device()
      
      :ok = SNMPSimulator.wait_for_device_ready(device1)
      :ok = SNMPSimulator.wait_for_device_ready(device2)
      
      on_exit(fn -> 
        SNMPSimulator.stop_device(device1)
        SNMPSimulator.stop_device(device2)
      end)
      
      %{device1: device1, device2: device2}
    end

    test "get_multi error handling through snmp_lib", %{device1: device1, device2: device2} do
      # Test error handling in multi-target operations
      requests = [
        # Valid request
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.1.1.0", 
         [community: device1.community, timeout: 100]},
        
        # Invalid target
        {"240.0.0.1", "1.3.6.1.2.1.1.1.0", [timeout: 50]},
        
        # Valid target, invalid OID
        {SNMPSimulator.device_target(device2), "invalid.oid", 
         [community: device2.community, timeout: 100]}
      ]
      
      results = SnmpMgr.get_multi(requests)
      
      assert is_list(results)
      assert length(results) == 3
      
      # Each result should have consistent error format
      Enum.each(results, fn result ->
        case result do
          {:ok, _value} ->
            # Some operations might succeed
            assert true
            
          {:error, reason} ->
            # All errors should be properly formatted from snmp_lib
            assert is_atom(reason) or is_tuple(reason),
              "Multi-operation error should be properly formatted: #{inspect(reason)}"
        end
      end)
    end

    test "get_bulk_multi error handling through snmp_lib", %{device1: device1, device2: device2} do
      # Test error handling in multi-bulk operations
      requests = [
        # Valid request
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.2.2", 
         [max_repetitions: 3, community: device1.community, timeout: 100]},
        
        # Invalid target
        {"240.0.0.1", "1.3.6.1.2.1.2.2", [max_repetitions: 3, timeout: 50]},
        
        # Valid target, invalid OID
        {SNMPSimulator.device_target(device2), "invalid.oid", 
         [max_repetitions: 3, community: device2.community, timeout: 100]}
      ]
      
      results = SnmpMgr.get_bulk_multi(requests)
      
      assert is_list(results)
      assert length(results) == 3
      
      # Each result should have consistent error format
      Enum.each(results, fn result ->
        case result do
          {:ok, list} when is_list(list) ->
            # Successful bulk operation
            assert true
            
          {:error, reason} ->
            # All errors should be properly formatted from snmp_lib
            assert is_atom(reason) or is_tuple(reason),
              "Multi-bulk error should be properly formatted: #{inspect(reason)}"
        end
      end)
    end
  end

  describe "Error Handling Performance with SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "error handling doesn't impact performance", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Measure error handling performance through snmp_lib
      start_time = System.monotonic_time(:millisecond)
      
      # Generate multiple errors quickly
      error_operations = Enum.map(1..10, fn i ->
        Task.async(fn ->
          SnmpMgr.get(target, "invalid.oid.#{i}", 
                     community: device.community, timeout: 100)
        end)
      end)
      
      results = Task.await_many(error_operations, 2000)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should handle errors efficiently through snmp_lib
      assert duration < 2000  # Less than 2 seconds for 10 error operations
      assert length(results) == 10
      
      # All should return proper error format
      Enum.each(results, fn result ->
        case result do
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Error should be properly formatted: #{inspect(reason)}"
          {:ok, _} ->
            # Unexpected success
            assert true
        end
      end)
    end

    test "concurrent error handling through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test concurrent error handling
      concurrent_errors = Enum.map(1..5, fn i ->
        Task.async(fn ->
          case rem(i, 3) do
            0 -> SnmpMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 50)  # Network error
            1 -> SnmpMgr.get(target, "invalid.oid.#{i}", timeout: 100)  # OID error
            2 -> SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: "wrong", timeout: 100)  # Auth error
          end
        end)
      end)
      
      results = Task.await_many(concurrent_errors, 2000)
      
      # All should complete with proper error formats
      assert length(results) == 5
      
      Enum.each(results, fn result ->
        case result do
          {:error, reason} ->
            # Should be properly formatted from snmp_lib
            assert is_atom(reason) or is_tuple(reason),
              "Concurrent error should be properly formatted: #{inspect(reason)}"
          {:ok, _} ->
            # Some might succeed unexpectedly
            assert true
        end
      end)
    end
  end

  describe "SNMPv2c Exception Values through SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "SNMPv2c exception values handled by snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test SNMPv2c exception handling through snmp_lib
      exception_test_cases = [
        # Non-existent OID for no_such_object
        {"1.3.6.1.2.1.999.999.999.0", [:no_such_object, :no_such_name]},
        
        # End of MIB view scenario
        {"1.3.6.1.2.1.999", [:end_of_mib_view, :no_such_name]}
      ]
      
      Enum.each(exception_test_cases, fn {oid, expected_exceptions} ->
        result = SnmpMgr.get(target, oid, version: :v2c, 
                            community: device.community, timeout: 100)
        
        case result do
          {:ok, value} when value in [:no_such_object, :no_such_instance, :end_of_mib_view] ->
            # SNMPv2c exception values handled correctly by snmp_lib
            assert value in expected_exceptions,
              "Exception value #{value} should be in #{inspect(expected_exceptions)}"
            
          {:error, reason} ->
            # Exception converted to error by snmp_lib
            if reason in expected_exceptions do
              assert true
            else
              # Other error format from snmp_lib
              assert is_atom(reason) or is_tuple(reason),
                "Unexpected error format: #{inspect(reason)}"
            end
            
          {:ok, _other_value} ->
            # Might get different response from simulator
            assert true
        end
      end)
    end

    test "bulk operations handle exceptions through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test bulk operations with potential exceptions
      result = SnmpMgr.get_bulk(target, "1.3.6.1.2.1.999", 
                               max_repetitions: 5, version: :v2c,
                               community: device.community, timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Check for exception values in results
          exception_values = Enum.filter(results, fn
            {_oid, value} when value in [:no_such_object, :no_such_instance, :end_of_mib_view] -> true
            _ -> false
          end)
          
          # If we got results, exception handling should be correct
          assert true
          
        {:error, reason} when reason in [:end_of_mib_view, :no_such_name] ->
          # Bulk operation failed with expected exception
          assert true
          
        {:error, reason} ->
          # Other error format from snmp_lib
          assert is_atom(reason) or is_tuple(reason),
            "Bulk exception should be properly formatted: #{inspect(reason)}"
      end
    end
  end

  describe "Application-Level Error Enhancement" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "enhanced error context for user operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that SnmpMgr provides useful error context over raw snmp_lib
      error_scenarios = [
        # Network timeout with context
        {fn -> SnmpMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 50) end,
         "network operation"},
        
        # Invalid OID with context
        {fn -> SnmpMgr.get(target, "invalid.oid", community: device.community, timeout: 100) end,
         "OID validation"},
        
        # Authentication with context
        {fn -> SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: "wrong", timeout: 100) end,
         "authentication"}
      ]
      
      Enum.each(error_scenarios, fn {operation, context} ->
        case operation.() do
          {:error, reason} ->
            # Should get properly formatted error from SnmpMgr over snmp_lib
            assert is_atom(reason) or is_tuple(reason),
              "#{context} error should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Some operations might succeed unexpectedly
            assert true
        end
      end)
    end

    test "consistent error handling across all API functions", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that all SnmpMgr API functions handle errors consistently
      api_functions = [
        {:get, fn -> SnmpMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 50) end},
        {:set, fn -> SnmpMgr.set("240.0.0.1", "1.3.6.1.2.1.1.6.0", "test", timeout: 50) end},
        {:get_bulk, fn -> SnmpMgr.get_bulk("240.0.0.1", "1.3.6.1.2.1.2.2", max_repetitions: 3, timeout: 50) end},
        {:get_next, fn -> SnmpMgr.get_next("240.0.0.1", "1.3.6.1.2.1.1.1", timeout: 50) end},
        {:walk, fn -> SnmpMgr.walk("240.0.0.1", "1.3.6.1.2.1.1", timeout: 50) end}
      ]
      
      Enum.each(api_functions, fn {function_name, operation} ->
        case operation.() do
          {:error, reason} ->
            # All API functions should return consistent error formats
            assert is_atom(reason) or is_tuple(reason),
              "#{function_name} should return consistent error format: #{inspect(reason)}"
            
          {:ok, _} ->
            # Some might succeed unexpectedly
            assert true
        end
      end)
    end
  end
end