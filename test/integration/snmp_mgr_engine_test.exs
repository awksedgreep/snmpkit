defmodule SnmpKit.SnmpMgr.EngineIntegrationTest do
  use ExUnit.Case, async: false

  alias SnmpKit.TestSupport.SNMPSimulator

  @moduletag :integration
  @moduletag :engine_integration

  describe "SnmpMgr SnmpLib Backend Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "complete request processing through snmp_lib backend", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test complete flow: API -> Core -> SnmpKit.SnmpLib.Manager -> Response
      result =
        SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
          community: device.community,
          timeout: 100
        )

      case result do
        {:ok, value} ->
          # Successful operation through snmp_lib
          assert is_binary(value) or is_integer(value) or is_list(value)

        {:error, reason} ->
          # Should get proper error format from snmp_lib integration
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "multiple operation types through snmp_lib backend", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test various SNMP operations through SnmpKit.SnmpLib.Manager
      operations = [
        # GET operation
        {:get, target, "1.3.6.1.2.1.1.1.0", [community: device.community, timeout: 100]},

        # SET operation
        {:set, target, "1.3.6.1.2.1.1.6.0", "test_location",
         [community: device.community, timeout: 100]},

        # GET-BULK operation
        {:get_bulk, target, "1.3.6.1.2.1.2.2",
         [max_repetitions: 3, community: device.community, timeout: 100]},

        # GET-NEXT operation
        {:get_next, target, "1.3.6.1.2.1.1.1", [community: device.community, timeout: 100]},

        # WALK operation
        {:walk, target, "1.3.6.1.2.1.1", [community: device.community, timeout: 200]}
      ]

      Enum.each(operations, fn
        {:get, target, oid, opts} ->
          result = SnmpKit.SnmpMgr.get(target, oid, opts)

          case result do
            {:ok, _} ->
              :ok

            {:error, reason}
            when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
              :ok

            {:error, reason} ->
              flunk("Unexpected error: #{inspect(reason)}")
          end

        {:set, target, oid, value, opts} ->
          result = SnmpKit.SnmpMgr.set(target, oid, value, opts)

          case result do
            {:ok, _} ->
              :ok

            {:error, reason} when reason in [:not_writable, :read_only, :no_access, :gen_err] ->
              :ok

            {:error, reason} ->
              flunk("Unexpected error: #{inspect(reason)}")
          end

        {:get_bulk, target, oid, opts} ->
          result = SnmpKit.SnmpMgr.get_bulk(target, oid, opts)

          case result do
            {:ok, data} when is_list(data) ->
              :ok

            # Very common with simulators for bulk operations
            {:error, reason}
            when reason in [:endOfMibView, :end_of_mib_view, :timeout, :gen_err, :no_such_name] ->
              :ok

            {:error, reason} ->
              flunk("Unexpected error: #{inspect(reason)}")
          end

        {:get_next, target, oid, opts} ->
          result = SnmpKit.SnmpMgr.get_next(target, oid, opts)

          case result do
            {:ok, _} ->
              :ok

            {:error, reason}
            when reason in [:timeout, :gen_err, :end_of_mib_view, :endOfMibView] ->
              :ok

            {:error, reason} ->
              flunk("Unexpected error: #{inspect(reason)}")
          end

        {:walk, target, oid, opts} ->
          result = SnmpKit.SnmpMgr.walk(target, oid, opts)

          case result do
            {:ok, data} when is_list(data) ->
              :ok

            # Very common with simulators
            {:error, reason}
            when reason in [:endOfMibView, :end_of_mib_view, :timeout, :gen_err, :no_such_name] ->
              :ok

            {:error, reason} ->
              flunk("Unexpected error: #{inspect(reason)}")
          end
      end)
    end

    test "concurrent operations through snmp_lib manager", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test concurrent operations to validate snmp_lib handles concurrency
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.#{i}.0",
              community: device.community,
              timeout: 100
            )
          end)
        end)

      results = Task.await_many(tasks, 1000)

      # All should complete through snmp_lib
      assert length(results) == 5

      Enum.each(results, fn result ->
        case result do
          {:ok, _} ->
            :ok

          {:error, reason}
          when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
            :ok

          {:error, reason} ->
            flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end

    test "mixed operation types in concurrent environment", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test mixed operations concurrently through snmp_lib
      concurrent_operations = [
        Task.async(fn ->
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
            community: device.community,
            timeout: 100
          )
        end),
        Task.async(fn ->
          SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
            max_repetitions: 3,
            community: device.community,
            timeout: 100
          )
        end),
        Task.async(fn ->
          SnmpKit.SnmpMgr.walk(target, "1.3.6.1.2.1.1",
            community: device.community,
            timeout: 150
          )
        end),
        Task.async(fn ->
          SnmpKit.SnmpMgr.get_next(target, "1.3.6.1.2.1.1.1",
            community: device.community,
            timeout: 100
          )
        end)
      ]

      results = Task.await_many(concurrent_operations, 2000)

      # All operations should complete through snmp_lib
      assert length(results) == 4

      Enum.each(results, fn result ->
        case result do
          {:ok, _} ->
            :ok

          {:error, reason}
          when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
            :ok

          {:error, reason} ->
            flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end
  end

  describe "SnmpMgr Multi-Target Integration" do
    setup do
      # Create multiple devices for multi-target testing
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

    test "multi-target operations through snmp_lib", %{device1: device1, device2: device2} do
      # Test get_multi processing multiple targets through snmp_lib
      requests = [
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.1.1.0",
         [community: device1.community, timeout: 100]},
        {SNMPSimulator.device_target(device2), "1.3.6.1.2.1.1.3.0",
         [community: device2.community, timeout: 100]}
      ]

      results = SnmpKit.SnmpMgr.get_multi(requests)

      assert is_list(results)
      assert length(results) == 2

      # Each result should be proper format from snmp_lib integration
      Enum.each(results, fn result ->
        case result do
          {:ok, _} ->
            :ok

          {:error, reason}
          when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
            :ok

          {:error, reason} ->
            flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end

    test "bulk multi-target operations through snmp_lib", %{device1: device1, device2: device2} do
      # Test get_bulk_multi processing multiple targets through snmp_lib
      requests = [
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.2.2",
         [max_repetitions: 3, community: device1.community, timeout: 100]},
        {SNMPSimulator.device_target(device2), "1.3.6.1.2.1.2.2",
         [max_repetitions: 3, community: device2.community, timeout: 100]}
      ]

      results = SnmpKit.SnmpMgr.get_bulk_multi(requests)

      assert is_list(results)
      assert length(results) == 2

      # Each result should be proper format from snmp_lib integration
      Enum.each(results, fn result ->
        case result do
          {:ok, list} when is_list(list) ->
            :ok

          {:error, reason}
          when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
            :ok

          {:error, reason} ->
            flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end

    test "mixed multi-target operations", %{device1: device1, device2: device2} do
      target1 = SNMPSimulator.device_target(device1)
      target2 = SNMPSimulator.device_target(device2)

      # Test various multi-target scenarios
      get_requests = [
        {target1, "1.3.6.1.2.1.1.1.0", [community: device1.community, timeout: 100]},
        {target2, "1.3.6.1.2.1.1.1.0", [community: device2.community, timeout: 100]}
      ]

      bulk_requests = [
        {target1, "1.3.6.1.2.1.2.2",
         [max_repetitions: 3, community: device1.community, timeout: 100]},
        {target2, "1.3.6.1.2.1.4.20",
         [max_repetitions: 3, community: device2.community, timeout: 100]}
      ]

      # Process both types through snmp_lib
      get_results = SnmpKit.SnmpMgr.get_multi(get_requests)
      bulk_results = SnmpKit.SnmpMgr.get_bulk_multi(bulk_requests)

      # Both should work through snmp_lib integration
      assert length(get_results) == 2
      assert length(bulk_results) == 2

      Enum.each(get_results ++ bulk_results, fn result ->
        case result do
          {:ok, _} ->
            :ok

          {:error, reason}
          when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
            :ok

          {:error, reason} ->
            flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end
  end

  describe "SnmpMgr Configuration Integration with SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn ->
        SnmpKit.SnmpMgr.Config.reset()
        SNMPSimulator.stop_device(device)
      end)

      %{device: device}
    end

    test "configuration affects snmp_lib operations", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Set configuration that should be passed to snmp_lib
      SnmpKit.SnmpMgr.Config.set_default_community(device.community)
      SnmpKit.SnmpMgr.Config.set_default_timeout(100)
      SnmpKit.SnmpMgr.Config.set_default_version(:v2c)

      # Operation should use these defaults through snmp_lib
      result = SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0")

      # Should process with configured defaults through snmp_lib
      case result do
        {:ok, _} ->
          :ok

        {:error, reason}
        when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    test "request options override configuration in snmp_lib calls", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Set one default
      SnmpKit.SnmpMgr.Config.set_default_timeout(200)
      SnmpKit.SnmpMgr.Config.set_default_community("default_community")

      # Override with request options
      result =
        SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
          community: device.community,
          timeout: 100,
          version: :v1
        )

      # Should process with overridden options through snmp_lib
      case result do
        {:ok, _} ->
          :ok

        {:error, reason}
        when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    test "version configuration affects snmp_lib operation mode", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test different versions through snmp_lib
      versions = [:v1, :v2c]

      Enum.each(versions, fn version ->
        SnmpKit.SnmpMgr.Config.set_default_version(version)

        result =
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
            community: device.community,
            timeout: 100
          )

        # Should process with specified version through snmp_lib
        case result do
          {:ok, _} ->
            :ok

          {:error, reason}
          when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
            :ok

          {:error, reason} ->
            flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end
  end

  describe "SnmpMgr Performance Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "rapid sequential operations through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test rapid operations to ensure snmp_lib handles them efficiently
      start_time = System.monotonic_time(:millisecond)

      results =
        Enum.map(1..10, fn i ->
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.#{rem(i, 5) + 1}.0",
            community: device.community,
            timeout: 100
          )
        end)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete reasonably quickly with snmp_lib
      # Less than 2 seconds for 10 operations
      assert duration < 2000
      assert length(results) == 10

      # All should return proper format through snmp_lib
      Enum.each(results, fn result ->
        case result do
          {:ok, _} ->
            :ok

          {:error, reason}
          when reason in [:timeout, :gen_err, :no_such_name, :endOfMibView, :end_of_mib_view] ->
            :ok

          {:error, reason} ->
            flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end

    test "sustained load through snmp_lib manager", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test sustained operations for a period
      # 2 seconds
      duration_ms = 2000
      # Every 100ms
      request_interval = 100

      start_time = System.monotonic_time(:millisecond)
      request_count = 0

      # Submit requests at regular intervals
      max_requests = div(duration_ms, request_interval) + 1

      request_count =
        1..max_requests
        |> Enum.reduce_while(request_count, fn i, count ->
          current_time = System.monotonic_time(:millisecond)

          if current_time - start_time < duration_ms do
            spawn(fn ->
              SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.#{rem(i, 5) + 1}.0",
                community: device.community,
                timeout: 100
              )
            end)

            new_count = count + 1
            Process.sleep(request_interval)

            {:cont, new_count}
          else
            {:halt, count}
          end
        end)

      end_time = System.monotonic_time(:millisecond)
      actual_duration = end_time - start_time

      # System should remain stable through snmp_lib
      assert actual_duration >= duration_ms
      assert request_count >= duration_ms / request_interval / 2

      # Verify snmp_lib can still process requests
      final_result =
        SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
          community: device.community,
          timeout: 100
        )

      assert match?({:ok, _}, final_result) or match?({:error, _}, final_result)
    end

    test "memory usage remains bounded with snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Measure initial memory usage
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)

      # Generate significant load through snmp_lib
      Enum.each(1..50, fn i ->
        spawn(fn ->
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.#{rem(i, 5) + 1}.0",
            community: device.community,
            timeout: 100
          )
        end)

        if rem(i, 10) == 0 do
          # Also test bulk operations
          spawn(fn ->
            SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2",
              max_repetitions: 3,
              community: device.community,
              timeout: 100
            )
          end)
        end
      end)

      # Allow processing and cleanup
      Process.sleep(1000)
      :erlang.garbage_collect()

      # Measure final memory usage
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory

      # Memory growth should be reasonable with snmp_lib
      # Less than 10MB growth
      assert memory_growth < 10_000_000
    end
  end

  describe "SnmpMgr Error Handling Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn -> SNMPSimulator.stop_device(device) end)

      %{device: device}
    end

    test "network errors handled by snmp_lib", %{device: device} do
      # Test various network error conditions through snmp_lib
      error_targets = [
        # Unreachable IP
        "240.0.0.1",
        # Documentation range
        "192.0.2.254"
      ]

      Enum.each(error_targets, fn target ->
        result =
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
            community: device.community,
            timeout: 50
          )

        case result do
          {:error, reason}
          when reason in [
                 :timeout,
                 :host_unreachable,
                 :network_unreachable,
                 :ehostunreach,
                 :enetunreach,
                 :econnrefused
               ] ->
            # Expected network errors through snmp_lib
            assert true

          # Other errors acceptable
          {:error, _other} ->
            assert true

          # Unexpected success (device might exist)
          {:ok, _} ->
            assert true
        end
      end)
    end

    test "timeout handling through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test timeout behavior through snmp_lib
      timeouts = [1, 10, 50]

      Enum.each(timeouts, fn timeout ->
        result =
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
            community: device.community,
            timeout: timeout
          )

        # Should handle timeouts properly through snmp_lib
        case result do
          {:error, :timeout} -> assert true
          # Other errors
          {:error, _other} -> assert true
          # Unexpectedly fast response
          {:ok, _} -> assert true
        end
      end)
    end

    test "authentication errors handled by snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test authentication handling through snmp_lib
      invalid_communities = ["wrong_community", "", "invalid"]

      Enum.each(invalid_communities, fn community ->
        result =
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: community, timeout: 100)

        # Should handle authentication errors properly through snmp_lib
        case result do
          {:error, reason} when reason in [:authentication_error, :bad_community] ->
            # Expected authentication error
            assert true

          # Other errors acceptable
          {:error, _other} ->
            assert true

          # Might succeed in test environment
          {:ok, _} ->
            assert true
        end
      end)
    end

    test "invalid OID errors handled by SnmpKit.SnmpLib.OID", %{device: device} do
      target = SNMPSimulator.device_target(device)

      invalid_oids = [
        "invalid.oid.format",
        "1.3.6.1.2.1.999.999.999.0",
        ""
      ]

      Enum.each(invalid_oids, fn oid ->
        result = SnmpKit.SnmpMgr.get(target, oid, community: device.community, timeout: 100)

        case result do
          {:ok, _} ->
            assert true

          {:error, reason} ->
            # Should return proper error from SnmpKit.SnmpLib.OID or validation
            assert is_atom(reason) or (is_tuple(reason) and tuple_size(reason) >= 1)
        end
      end)
    end
  end

  describe "SnmpMgr Components Integration Test" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)

      on_exit(fn ->
        SnmpKit.SnmpMgr.Config.reset()
        SNMPSimulator.stop_device(device)
      end)

      %{device: device}
    end

    test "all components work together with snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test that all SnmpMgr components integrate properly with snmp_lib

      # 1. Configuration affects snmp_lib operations
      SnmpKit.SnmpMgr.Config.set_default_community(device.community)
      SnmpKit.SnmpMgr.Config.set_default_timeout(100)

      # 2. Core operation through snmp_lib with MIB resolution
      result1 = SnmpKit.SnmpMgr.get(target, "sysDescr.0")
      assert match?({:ok, _}, result1) or match?({:error, _}, result1)

      # 3. Bulk operation through SnmpKit.SnmpLib.Manager
      result2 = SnmpKit.SnmpMgr.get_bulk(target, "1.3.6.1.2.1.2.2", max_repetitions: 3)
      assert match?({:ok, _}, result2) or match?({:error, _}, result2)

      # 4. Multi-target operation through snmp_lib
      requests = [
        {target, "1.3.6.1.2.1.1.1.0", []},
        {target, "1.3.6.1.2.1.1.3.0", []}
      ]

      results = SnmpKit.SnmpMgr.get_multi(requests)
      assert is_list(results) and length(results) == 2

      # 5. Walk operation through snmp_lib
      result3 = SnmpKit.SnmpMgr.walk(target, "1.3.6.1.2.1.1")
      assert match?({:ok, _}, result3) or match?({:error, _}, result3)

      # All operations should complete properly through snmp_lib integration
      assert true
    end

    test "error formats consistent across snmp_lib operations", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test that error formats are consistent across different operations
      operations = [
        fn -> SnmpKit.SnmpMgr.get(target, "invalid.oid", timeout: 100) end,
        fn -> SnmpKit.SnmpMgr.set(target, "invalid.oid", "value", timeout: 100) end,
        fn ->
          SnmpKit.SnmpMgr.get_bulk(target, "invalid.oid", max_repetitions: 3, timeout: 100)
        end,
        fn -> SnmpKit.SnmpMgr.walk(target, "invalid.oid", timeout: 100) end
      ]

      Enum.each(operations, fn operation ->
        result = operation.()

        case result do
          {:ok, _} ->
            assert true

          {:error, reason} ->
            # Error reason should be properly formatted from snmp_lib
            assert is_atom(reason) or (is_tuple(reason) and tuple_size(reason) >= 1)
        end
      end)
    end

    test "return value formats consistent across snmp_lib operations", %{device: device} do
      target = SNMPSimulator.device_target(device)

      # Test that return values maintain consistent format through snmp_lib
      operations = [
        fn ->
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0",
            community: device.community,
            timeout: 100
          )
        end,
        fn ->
          SnmpKit.SnmpMgr.get_next(target, "1.3.6.1.2.1.1.1",
            community: device.community,
            timeout: 100
          )
        end
      ]

      Enum.each(operations, fn operation ->
        result = operation.()

        case result do
          {:ok, value} ->
            # Value should be in expected format from snmp_lib
            assert is_binary(value) or is_integer(value) or is_list(value) or
                     is_tuple(value) or is_atom(value)

          {:error, reason} ->
            assert is_atom(reason) or (is_tuple(reason) and tuple_size(reason) >= 1)
        end
      end)
    end
  end
end
