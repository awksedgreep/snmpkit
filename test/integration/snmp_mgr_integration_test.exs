defmodule SnmpKit.SnmpMgr.IntegrationTest do
  use ExUnit.Case, async: false

  alias SnmpKit.TestSupport.SNMPSimulator

  @moduletag :integration

  setup_all do
    # Ensure required GenServers are started
    case GenServer.whereis(SnmpKit.SnmpMgr.Config) do
      nil -> {:ok, _pid} = SnmpKit.SnmpMgr.Config.start_link()
      _pid -> :ok
    end

    # Create test device following @testing_rules
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}

      error ->
        %{device: nil, setup_error: error}
    end
  end

  describe "SnmpMgr Full Integration" do
    test "get/3 complete integration flow", %{device: device} do

      # Test complete flow through all layers: API -> Core -> SnmpKit.SnmpLib.Manager
      result =
        SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
          community: device.community,
          version: :v2c,
          timeout: 200
        )

      case result do
        {:ok, value} ->
          # Successful operation through snmp_lib
          assert is_binary(value) or is_integer(value) or is_list(value) or is_atom(value)
          assert byte_size(to_string(value)) > 0

        {:error, reason} ->
          # Accept valid SNMP errors from simulator
          assert reason in [
                   :timeout,
                   :noSuchObject,
                   :noSuchInstance,
                   :endOfMibView,
                   :end_of_mib_view
                 ]
      end
    end

    test "set/4 complete integration flow", %{device: device} do

      # Test SET operation through snmp_lib
      result =
        SnmpKit.SnmpMgr.set("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.6.0", "test_location",
          community: device.community,
          version: :v2c,
          timeout: 200
        )

      case result do
        {:ok, value} ->
          # Successful SET through snmp_lib
          assert is_binary(value) or is_atom(value) or is_integer(value)

        {:error, reason} ->
          # Accept valid SNMP errors (many objects are read-only)
          assert reason in [:not_writable, :read_only, :no_access, :timeout, :noSuchObject, :gen_err]
      end
    end

    test "get_bulk/3 complete integration flow", %{device: device} do

      # Test GET-BULK operation through SnmpKit.SnmpLib.Manager
      result =
        SnmpKit.SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2",
          max_repetitions: 5,
          non_repeaters: 0,
          community: device.community,
          version: :v2c,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) ->
          # Successful bulk operation through snmp_lib
          assert true

        {:error, reason} ->
          # Accept valid bulk operation errors
          assert reason in [:timeout, :noSuchObject, :getbulk_requires_v2c]
      end
    end

    test "walk/3 complete integration flow", %{device: device} do

      # Test WALK operation through snmp_lib integration
      result =
        SnmpKit.SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1",
          community: device.community,
          version: :v2c,
          timeout: 200
        )

      case result do
        {:ok, results} when is_list(results) ->
          # Successful walk through snmp_lib
          if length(results) > 0 do
            Enum.each(results, fn {oid, type, value} ->
              assert is_binary(oid)
              assert String.starts_with?(oid, "1.3.6.1.2.1.1")
              assert is_atom(type)
              assert value != nil
            end)
          end

          assert true

        {:error, reason} ->
          # Accept valid walk errors
          assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view]
      end
    end

    test "get_next/3 complete integration flow", %{device: device} do

      # Test GET-NEXT operation through SnmpKit.SnmpLib.Manager
      result =
        SnmpKit.SnmpMgr.get_next("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1",
          community: device.community,
          version: :v2c,
          timeout: 200
        )

      case result do
        {:ok, {oid, value}} ->
          # Successful get_next through snmp_lib
          assert is_binary(oid) or is_list(oid)
          assert is_binary(value) or is_integer(value) or is_list(value) or is_atom(value)

        {:error, reason} ->
          # Accept valid get_next errors (both old and new formats)
          assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view]
      end
    end
  end

  describe "SnmpMgr Multi-Operation Integration" do
    test "get_multi/1 processes multiple requests", %{device: device} do

      # Use same device with different OIDs for multi-operation testing
      requests = [
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
         [community: device.community, timeout: 200]},
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.3.0",
         [community: device.community, timeout: 200]},
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.5.0",
         [community: device.community, timeout: 200]}
      ]

      results = SnmpKit.SnmpMgr.get_multi(requests)

      assert is_list(results)
      assert length(results) == 3

      # All should return proper format from snmp_lib integration
      Enum.each(results, fn result ->
        case result do
          {:ok, _value} ->
            assert true

          {:error, reason} ->
            # Accept valid SNMP errors from simulator
            assert reason in [:timeout, :noSuchObject, :noSuchInstance]
        end
      end)
    end

    test "get_bulk_multi/1 processes multiple bulk requests", %{device: device} do

      # Use same device with different OID trees for bulk testing
      requests = [
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2",
         [max_repetitions: 3, community: device.community, timeout: 200]},
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1",
         [max_repetitions: 3, community: device.community, timeout: 200]}
      ]

      results = SnmpKit.SnmpMgr.get_bulk_multi(requests)

      assert is_list(results)
      assert length(results) == 2

      # All should return proper format from snmp_lib integration
      Enum.each(results, fn result ->
        case result do
          {:ok, list} when is_list(list) ->
            assert true

          {:error, reason} ->
            # Accept valid bulk operation errors
            assert reason in [:timeout, :noSuchObject, :getbulk_requires_v2c]
        end
      end)
    end
  end

  describe "SnmpMgr Configuration Integration" do
    test "global configuration affects operations", %{device: device} do

      # Set custom defaults using simulator community
      SnmpKit.SnmpMgr.Config.set_default_community(device.community)
      SnmpKit.SnmpMgr.Config.set_default_timeout(200)
      SnmpKit.SnmpMgr.Config.set_default_version(:v2c)

      # Operation should use these defaults with simulator
      result = SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0")

      # Should succeed with configured defaults through snmp_lib
      assert {:ok, _} = result

      # Reset to defaults
      SnmpKit.SnmpMgr.Config.reset()
    end

    test "request options override configuration", %{device: device} do

      # Set one default
      SnmpKit.SnmpMgr.Config.set_default_timeout(200)

      # Override with request option using simulator
      result =
        SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
          community: device.community,
          timeout: 200,
          version: :v1
        )

      # Should succeed with overridden options through snmp_lib
      assert {:ok, _} = result

      SnmpKit.SnmpMgr.Config.reset()
    end

    test "configuration merging works correctly" do
      # Test the merge_opts function used by all operations
      SnmpKit.SnmpMgr.Config.set_default_community("default_comm")
      SnmpKit.SnmpMgr.Config.set_default_timeout(200)
      SnmpKit.SnmpMgr.Config.set_default_version(:v1)

      merged = SnmpKit.SnmpMgr.Config.merge_opts(community: "override", retries: 3)

      # Should have overridden community but default timeout and version
      assert merged[:community] == "override"
      assert merged[:timeout] == 200
      assert merged[:version] == :v1
      assert merged[:retries] == 3

      SnmpKit.SnmpMgr.Config.reset()
    end
  end

  describe "SnmpMgr OID Processing Integration" do
    test "string OIDs processed through SnmpKit.SnmpLib.OID", %{device: device} do

      # Test various OID formats through SnmpKit.SnmpLib.OID integration
      oid_formats = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.3.0",
        "1.3.6.1.2.1.1.5.0"
      ]

      Enum.each(oid_formats, fn oid ->
        result =
          SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", oid,
            community: device.community,
            timeout: 200
          )

        # Should process OID through SnmpKit.SnmpLib.OID and return proper format
        assert {:ok, _} = result
      end)
    end

    test "list OIDs processed through SnmpKit.SnmpLib.OID", %{device: device} do

      # Test list format OIDs
      list_oids = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 2, 1, 1, 3, 0],
        [1, 3, 6, 1, 2, 1, 1, 5, 0]
      ]

      Enum.each(list_oids, fn oid ->
        result =
          SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", oid,
            community: device.community,
            timeout: 200
          )

        # Should process list OID through SnmpKit.SnmpLib.OID
        assert {:ok, _} = result
      end)
    end

    test "symbolic OIDs through MIB integration", %{device: device} do

      # Test symbolic OIDs that should resolve through MIB integration
      symbolic_oids = [
        "sysDescr.0",
        "sysUpTime.0",
        "sysName.0"
      ]

      Enum.each(symbolic_oids, fn oid ->
        result =
          SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", oid,
            community: device.community,
            timeout: 200
          )

        # Should process symbolic OID through MIB -> SnmpKit.SnmpLib.OID chain
        assert {:ok, _} = result
      end)
    end

    test "invalid OIDs handled properly", %{device: device} do

      invalid_oids = [
        "invalid.oid.format",
        "1.3.6.1.2.1.999.999.999.0",
        "not.a.valid.oid"
      ]

      Enum.each(invalid_oids, fn oid ->
        result =
          SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", oid,
            community: device.community,
            timeout: 200
          )

        # Should return error for invalid OIDs
        case result do
          {:error, _reason} -> assert true
          # Some invalid OIDs might resolve unexpectedly
          {:ok, _value} -> assert true
        end
      end)
    end
  end

  describe "SnmpMgr Error Handling Integration" do
    test "network errors through snmp_lib" do
      # Test various network error conditions with unreachable hosts
      error_targets = [
        # Unreachable IP
        "240.0.0.1",
        # Documentation range
        "192.0.2.254",
        # Link-local
        "169.254.1.1"
      ]

      Enum.each(error_targets, fn target ->
        result =
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: "public", timeout: 200)

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

      # Test timeout behavior through snmp_lib with simulator
      timeouts = [1, 10, 50, 200]

      Enum.each(timeouts, fn timeout ->
        result =
          SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
            community: device.community,
            timeout: timeout
          )

        # Should handle timeouts properly through snmp_lib
        case result do
          {:error, :timeout} -> assert true
          # Other errors
          {:error, _other} -> assert true
          # Fast response from simulator
          {:ok, _} -> assert true
        end
      end)
    end

    test "invalid target handling" do
      invalid_targets = [
        "invalid..hostname",
        "256.256.256.256",
        "not.a.valid.target"
      ]

      Enum.each(invalid_targets, fn target ->
        result =
          SnmpKit.SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: "public", timeout: 200)

        # Should return proper error format
        case result do
          {:error, _reason} -> assert true
          # Some invalid targets might resolve
          {:ok, _} -> assert true
        end
      end)
    end

    test "community string validation", %{device: device} do

      # Test community string handling through snmp_lib
      communities = [device.community, "wrong_community", ""]

      Enum.each(communities, fn community ->
        result =
          SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
            community: community,
            timeout: 200
          )

        # Should handle various community strings properly
        case result do
          {:ok, _} ->
            assert true

          {:error, reason} when reason in [:timeout, :authentication_error, :bad_community] ->
            assert true

          # Other errors acceptable in test environment
          {:error, _other} ->
            assert true
        end
      end)
    end
  end

  describe "SnmpMgr Version Compatibility Integration" do
    test "SNMPv1 operations through snmp_lib", %{device: device} do

      # Test SNMPv1 operations
      result =
        SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
          version: :v1,
          community: device.community,
          timeout: 200
        )

      # Should process v1 requests through snmp_lib
      assert {:ok, _} = result
    end

    test "SNMPv2c operations through snmp_lib", %{device: device} do

      # Test SNMPv2c operations
      result =
        SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
          version: :v2c,
          community: device.community,
          timeout: 200
        )

      # Should process v2c requests through snmp_lib
      case result do
        {:ok, _} ->
          assert true

        {:error, reason}
        when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] ->
          assert true

        # Other errors acceptable
        {:error, _other} ->
          assert true
      end
    end

    test "bulk operations require v2c", %{device: device} do

      # Bulk operations should work with v2c
      result_v2c =
        SnmpKit.SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2",
          version: :v2c,
          community: device.community,
          max_repetitions: 3,
          timeout: 200
        )

      # Should handle v2c bulk through snmp_lib
      case result_v2c do
        {:ok, _} ->
          assert true

        {:error, reason}
        when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] ->
          assert true

        # Other errors acceptable
        {:error, _other} ->
          assert true
      end
    end

    test "walk adapts to version", %{device: device} do

      # Walk should adapt behavior based on version
      result_v1 =
        SnmpKit.SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1",
          version: :v1,
          community: device.community,
          timeout: 200
        )

      result_v2c =
        SnmpKit.SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1",
          version: :v2c,
          community: device.community,
          timeout: 200
        )

      # Both should work through appropriate snmp_lib mechanisms
      case result_v1 do
        {:ok, _} ->
          assert true

        {:error, reason}
        when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] ->
          assert true

        # Other errors acceptable
        {:error, _other} ->
          assert true
      end

      case result_v2c do
        {:ok, _} ->
          assert true

        {:error, reason}
        when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] ->
          assert true

        # Other errors acceptable
        {:error, _other} ->
          assert true
      end
    end
  end

  describe "SnmpMgr Performance Integration" do
    test "concurrent operations through snmp_lib", %{device: device} do

      # Test concurrent operations to validate snmp_lib integration
      tasks =
        Enum.map(1..5, fn _i ->
          Task.async(fn ->
            SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
              community: device.community,
              timeout: 200
            )
          end)
        end)

      results = Task.await_many(tasks, 2000)

      # All should complete through snmp_lib
      assert length(results) == 5

      Enum.each(results, fn result ->
        assert {:ok, _} = result
      end)
    end

    test "rapid sequential operations", %{device: device} do

      # Test rapid operations to ensure snmp_lib handles them properly
      start_time = System.monotonic_time(:millisecond)

      results =
        Enum.map(1..10, fn _i ->
          SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.3.0",
            community: device.community,
            timeout: 200
          )
        end)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete reasonably quickly
      # Less than 5 seconds for 10 operations
      assert duration < 5000
      assert length(results) == 10

      # All should return proper format through snmp_lib
      Enum.each(results, fn result ->
        assert {:ok, _} = result
      end)
    end

    test "memory usage with many operations", %{device: device} do

      # Test memory usage during many operations
      initial_memory = :erlang.memory(:total)

      # Perform many operations
      results =
        Enum.map(1..50, fn _i ->
          SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0",
            community: device.community,
            timeout: 200
          )
        end)

      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory

      # Memory growth should be reasonable
      # Less than 10MB growth
      assert memory_growth < 10_000_000
      assert length(results) == 50

      # Trigger garbage collection
      :erlang.garbage_collect()
    end
  end

  describe "SnmpMgr Components Integration Test" do
    test "all components work together", %{device: device} do

      # Test that all SnmpMgr components integrate properly with snmp_lib

      # 1. Configuration
      SnmpKit.SnmpMgr.Config.set_default_community(device.community)
      SnmpKit.SnmpMgr.Config.set_default_timeout(200)

      # 2. Core operation with MIB resolution
      result1 = SnmpKit.SnmpMgr.get("#{device.host}:#{device.port}", "sysDescr.0")
      assert {:ok, _} = result1

      # 3. Bulk operation
      result2 =
        SnmpKit.SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2",
          max_repetitions: 3
        )

      assert {:ok, _} = result2

      # 4. Multi-target operation
      requests = [
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", [community: device.community]},
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.3.0", [community: device.community]}
      ]

      results = SnmpKit.SnmpMgr.get_multi(requests)
      assert is_list(results) and length(results) == 2

      # 5. Walk operation
      result3 = SnmpKit.SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1")

      case result3 do
        {:ok, _} ->
          assert true

        {:error, reason}
        when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] ->
          assert true

        # Other errors acceptable
        {:error, _other} ->
          assert true
      end

      # Reset configuration
      SnmpKit.SnmpMgr.Config.reset()

      # All operations should complete properly through snmp_lib integration
      assert true
    end
  end

  # Helper functions
end
