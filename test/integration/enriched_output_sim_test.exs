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
end

