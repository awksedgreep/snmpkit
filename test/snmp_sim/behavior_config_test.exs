defmodule SnmpKit.SnmpSim.BehaviorConfigTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpSim.BehaviorConfig

  @profile %{
    name: :test,
    oid_map: %{
      "1.3.6.1.2.1.1.1.0" => %{type: "STRING", value: "router"},
      "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 1_000},
      "1.3.6.1.2.1.2.2.1.14.1" => %{type: "Counter32", value: 3},
      "1.3.6.1.2.1.31.1.1.1.6.1" => %{type: "Counter64", value: 10_000},
      "1.3.6.1.2.1.2.2.1.5.1" => %{type: "Gauge32", value: 1_000_000_000}
    }
  }

  @presets [
    :cable_modem_realistic,
    :cmts_realistic,
    :switch_realistic,
    :high_traffic_simulation,
    :low_signal_quality,
    :network_congestion,
    :maintenance_mode,
    :development_testing
  ]

  describe "apply_behaviors/2" do
    test "realistic_counters attaches a behavior to counters only" do
      %{oid_map: oid_map} = BehaviorConfig.apply_behaviors(@profile, [:realistic_counters])

      assert Map.has_key?(oid_map["1.3.6.1.2.1.2.2.1.10.1"], :behavior)
      assert Map.has_key?(oid_map["1.3.6.1.2.1.31.1.1.1.6.1"], :behavior)
      refute Map.has_key?(oid_map["1.3.6.1.2.1.1.1.0"], :behavior)
      refute Map.has_key?(oid_map["1.3.6.1.2.1.2.2.1.5.1"], :behavior)
    end

    test "error counters get a different behavior from traffic counters" do
      %{oid_map: oid_map} = BehaviorConfig.apply_behaviors(@profile, [:realistic_counters])
      traffic = oid_map["1.3.6.1.2.1.2.2.1.10.1"].behavior
      errors = oid_map["1.3.6.1.2.1.2.2.1.14.1"].behavior
      assert traffic != errors
    end

    test "daily_patterns applies to counters and gauges, not strings" do
      %{oid_map: oid_map} = BehaviorConfig.apply_behaviors(@profile, [:daily_patterns])

      assert Map.has_key?(oid_map["1.3.6.1.2.1.2.2.1.10.1"], :behavior)
      assert Map.has_key?(oid_map["1.3.6.1.2.1.2.2.1.5.1"], :behavior)
      refute Map.has_key?(oid_map["1.3.6.1.2.1.1.1.0"], :behavior)
    end

    test "behaviors compose in order and keep every object" do
      result =
        BehaviorConfig.apply_behaviors(@profile, [
          :realistic_counters,
          :daily_patterns,
          :weekly_patterns
        ])

      assert Map.keys(result.oid_map) == Map.keys(@profile.oid_map)

      assert Enum.all?(result.oid_map, fn {_oid, info} ->
               Map.has_key?(info, :type) and Map.has_key?(info, :value)
             end)
    end

    test "tuple, keyword and atom specs are accepted" do
      for spec <- [:realistic_counters, {:realistic_counters, %{}}, {:realistic_counters, []}] do
        %{oid_map: oid_map} = BehaviorConfig.apply_behaviors(@profile, [spec])
        assert Map.has_key?(oid_map["1.3.6.1.2.1.2.2.1.10.1"], :behavior)
      end
    end

    test "an unknown behavior leaves the profile unchanged" do
      assert BehaviorConfig.apply_behaviors(@profile, [:no_such_behavior, {:also_unknown, %{}}]) ==
               @profile
    end

    test "every preset applies to a profile without raising" do
      for preset <- @presets do
        behaviors = BehaviorConfig.get_preset(preset)
        result = BehaviorConfig.apply_behaviors(@profile, behaviors)
        assert map_size(result.oid_map) == map_size(@profile.oid_map), "preset #{preset}"
      end
    end
  end

  describe "get_preset/1" do
    test "known presets are lists of {behavior, config} pairs" do
      for preset <- @presets do
        behaviors = BehaviorConfig.get_preset(preset)
        assert match?([_ | _], behaviors), "preset #{preset}"

        assert Enum.all?(behaviors, &match?({type, %{}} when is_atom(type), &1)),
               "preset #{preset}"
      end
    end

    test "an unknown preset is an error" do
      assert {:error, :unknown_preset} = BehaviorConfig.get_preset(:nope)
    end
  end

  describe "create_custom/1" do
    test "normalises keyword configs and atoms into {behavior, map} pairs" do
      assert {:ok, [{:increment_counters, %{rate_multiplier: 2.0}}, {:daily_patterns, %{}}]} =
               BehaviorConfig.create_custom([
                 {:increment_counters, rate_multiplier: 2.0},
                 :daily_patterns
               ])
    end

    test "rejects behaviors it does not know" do
      assert {:error, {:invalid_behavior_spec, {:teleport, %{}}}} =
               BehaviorConfig.create_custom([:daily_patterns, {:teleport, %{}}])

      assert {:error, {:invalid_behavior_spec, "increment_counters"}} =
               BehaviorConfig.create_custom(["increment_counters"])
    end
  end

  test "list_available_behaviors/0 names every family" do
    families = BehaviorConfig.list_available_behaviors()

    assert Map.keys(families) |> Enum.sort() ==
             [
               :counter_behaviors,
               :error_simulation,
               :gauge_behaviors,
               :signal_quality,
               :time_patterns
             ]

    assert :realistic_counters in families.counter_behaviors
    assert :daily_patterns in families.time_patterns
  end
end
