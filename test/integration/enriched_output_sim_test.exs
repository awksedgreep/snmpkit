defmodule SnmpKit.EnrichedOutputSimTest do
  use ExUnit.Case
  @moduletag :needs_simulator

  require Logger

  test "get/3 returns enriched map with type and formatted by default" do
    # Simple simulated device profile for sysDescr and sysUpTime
    profile = %{
      name: "Test Device",
      objects: %{
        [1, 3, 6, 1, 2, 1, 1, 1, 0] => "Simulated Device",         # sysDescr.0
        [1, 3, 6, 1, 2, 1, 1, 3, 0] => 12_345_600                   # sysUpTime.0 (hundredths)
      }
    }

    {:ok, _device} = SnmpKit.Sim.start_device(profile, port: 31161)
    target = "127.0.0.1:31161"

    # GET sysDescr.0
    assert {:ok, result} = SnmpKit.SNMP.get(target, "sysDescr.0")
    assert %{oid: oid, type: :octet_string, value: value} = result
    assert is_binary(oid) and is_binary(value)
    # include_names and include_formatted default true
    assert Map.has_key?(result, :name)
    assert Map.has_key?(result, :formatted)

    # GET pretty uptime
    assert {:ok, up} = SnmpKit.SNMP.get_pretty(target, "sysUpTime.0")
    assert %{oid: ^oid_uptime?, type: :timeticks, value: _, formatted: fmt} = up
    assert is_binary(fmt)
  end

  test "pretty walk and pretty bulk return formatted for all items" do
    profile = %{
      name: "Pretty Device",
      objects: %{
        [1, 3, 6, 1, 2, 1, 1, 1, 0] => "Device",
        [1, 3, 6, 1, 2, 1, 1, 3, 0] => 5000
      }
    }

    {:ok, _d} = SnmpKit.Sim.start_device(profile, port: 31162)
    target = "127.0.0.1:31162"

    # Pretty walk system
    assert {:ok, items} = SnmpKit.SNMP.walk_pretty(target, "system")
    assert is_list(items)
    assert Enum.all?(items, fn m -> is_map(m) and Map.has_key?(m, :formatted) and Map.has_key?(m, :type) end)

    # Pretty bulk on interfaces/system
    assert {:ok, bulk_items} = SnmpKit.SNMP.bulk_pretty(target, "system")
    assert is_list(bulk_items)
    assert Enum.all?(bulk_items, fn m -> is_map(m) and Map.has_key?(m, :formatted) and Map.has_key?(m, :type) end)
  end

  test "multi-target :with_targets returns enriched inner results" do
    profile = %{
      name: "Test Device",
      objects: %{
        [1, 3, 6, 1, 2, 1, 1, 1, 0] => "Simulated Device"
      }
    }

    {:ok, _d1} = SnmpKit.Sim.start_device(profile, port: 31162)
    {:ok, _d2} = SnmpKit.Sim.start_device(profile, port: 31163)

    reqs = [
      {"127.0.0.1:31162", "sysDescr.0"},
      {"127.0.0.1:31163", "sysDescr.0"}
    ]

    results = SnmpKit.SNMP.get_multi(reqs, return_format: :with_targets)

    assert is_list(results)
    for {target, oid, {:ok, inner}} <- results do
      assert is_binary(target)
      assert is_binary(oid)
      assert %{oid: _, type: :octet_string, value: _} = inner
    end
  end

  test "multi-target :list and :map enrich results and preserve shape" do
    profile = %{
      name: "ListMap Device",
      objects: %{
        [1, 3, 6, 1, 2, 1, 1, 1, 0] => "Device"
      }
    }

    {:ok, _d1} = SnmpKit.Sim.start_device(profile, port: 31164)
    {:ok, _d2} = SnmpKit.Sim.start_device(profile, port: 31165)

    reqs = [
      {"127.0.0.1:31164", "sysDescr.0"},
      {"127.0.0.1:31165", "sysDescr.0"}
    ]

    # :list format
    list_results = SnmpKit.SNMP.get_multi(reqs, return_format: :list)
    assert is_list(list_results)
    assert Enum.all?(list_results, fn {:ok, %{oid: _, type: _, value: _}} -> true; _ -> false end)

    # :map format
    map_results = SnmpKit.SNMP.get_multi(reqs, return_format: :map)
    assert is_map(map_results)
    assert map_size(map_results) == 2
    for {{t, o}, {:ok, inner}} <- map_results do
      assert is_binary(t) and is_binary(o)
      assert %{oid: _, type: _, value: _} = inner
    end
  end

  test "toggles include_names and include_formatted work via public API" do
    profile = %{
      name: "Toggles Device",
      objects: %{
        [1, 3, 6, 1, 2, 1, 1, 1, 0] => "Device",
        [1, 3, 6, 1, 2, 1, 1, 3, 0] => 10000
      }
    }

    {:ok, _d} = SnmpKit.Sim.start_device(profile, port: 31166)
    target = "127.0.0.1:31166"

    # Both off
    assert {:ok, res} = SnmpKit.SNMP.get(target, "sysUpTime.0", include_names: false, include_formatted: false)
    refute Map.has_key?(res, :name)
    refute Map.has_key?(res, :formatted)
    assert Map.has_key?(res, :oid) and Map.has_key?(res, :type) and Map.has_key?(res, :value)
  end
end

