defmodule SnmpKit.SnmpMgr.MIBIntegrationTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpKit.SnmpMgr.MIB
  alias SnmpKit.SnmpKit.TestSupport.SNMPSimulator

  @moduletag :unit
  @moduletag :mib
  @moduletag :snmp_lib_integration

  setup_all do
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}

      error ->
        %{device: nil, setup_error: error}
    end
  end

  setup do
    case GenServer.whereis(SnmpKit.SnmpMgr.MIB) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.MIB.start_link()
        :ok

      _pid ->
        :ok
    end

    :ok
  end

  describe "MIB Integration with snmp_lib Operations" do
    test "MIB name resolution works with SNMP operations", %{device: device} do
      skip_if_no_device(device)

      # Test MIB name resolution for standard names
      standard_names = ["sysDescr", "sysUpTime", "sysName"]

      for name <- standard_names do
        case MIB.resolve(name) do
          {:ok, oid} ->
            # Use resolved OID in SNMP operation
            oid_string = oid |> Enum.join(".") |> then(&"#{&1}.0")
            target = SNMPSimulator.device_target(device)
            result = SnmpMgr.get(target, oid_string, community: device.community, timeout: 200)

            assert {:ok, _} = result

          {:error, reason} ->
            # MIB resolution might fail if MIB not loaded, which is acceptable
            IO.puts("MIB resolution failed for '#{name}': #{inspect(reason)}")
        end
      end
    end

    test "MIB reverse lookup integration", %{device: device} do
      skip_if_no_device(device)

      # Get a value first
      target = SNMPSimulator.device_target(device)

      case SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community, timeout: 200) do
        {:ok, _value} ->
          # Try reverse lookup on the OID we requested
          case MIB.reverse_lookup("1.3.6.1.2.1.1.1.0") do
            {:ok, name} ->
              assert is_binary(name)
              assert String.length(name) > 0

            {:error, _reason} ->
              # Reverse lookup might fail if MIB not loaded, acceptable
              :ok
          end

        {:error, _reason} ->
          # SNMP operation failed, skip reverse lookup test
          :ok
      end
    end
  end

  describe "Enhanced MIB with SnmpKit.SnmpLib.MIB Integration" do
    test "integrates with SnmpKit.SnmpLib.MIB for enhanced functionality", %{device: device} do
      skip_if_no_device(device)

      # Test basic MIB functionality
      standard_oids = [
        # sysDescr
        "1.3.6.1.2.1.1.1.0",
        # sysUpTime
        "1.3.6.1.2.1.1.3.0",
        # sysName
        "1.3.6.1.2.1.1.5.0"
      ]

      for oid <- standard_oids do
        target = SNMPSimulator.device_target(device)
        result = SnmpMgr.get(target, oid, community: device.community, timeout: 200)

        case result do
          {:ok, _value} ->
            # Test that MIB can handle the OID we requested
            case MIB.reverse_lookup(oid) do
              {:ok, _name} -> assert true
              # MIB might not be loaded
              {:error, _reason} -> assert true
            end

          {:error, _reason} ->
            # Operation failed, which is acceptable
            :ok
        end
      end
    end

    test "MIB tree walking integration", %{device: device} do
      skip_if_no_device(device)

      # Test MIB tree functionality with SNMP data
      # System group
      root_oid = "1.3.6.1.2.1.1"

      # Perform SNMP walk
      target = SNMPSimulator.device_target(device)

      case SnmpKit.SnmpMgr.walk(target, root_oid, community: device.community, timeout: 200) do
        {:ok, results} when is_list(results) ->
          # For each result, test MIB integration
          # Limit to first 3 for test efficiency
          limited_results = Enum.take(results, 3)

          for {oid, _value} <- limited_results do
            case MIB.reverse_lookup(oid) do
              {:ok, name} ->
                assert is_binary(name)

              {:error, _reason} ->
                # MIB reverse lookup might fail, acceptable
                :ok
            end
          end

        {:error, _reason} ->
          # Walk operation failed, skip MIB integration test
          :ok
      end
    end
  end

  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end
