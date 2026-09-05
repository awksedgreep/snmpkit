defmodule SnmpKit.RealDeviceWalkTest do
  use ExUnit.Case, async: false
  require Logger
  @moduletag :real_device

  alias SnmpKit.SnmpMgr.Multi

  # Test with actual devices from the user's example
  @test_devices [
    {"192.168.89.206", "public"},
    {"192.168.89.207", "public"},
    {"192.168.89.228", "public"}
  ]

  @test_oid "1.3.6.1.2.1.1"
  @test_timeout 10_000

  setup_all do
    # Ensure the SnmpMgr Engine is running
    case Process.whereis(SnmpKit.SnmpMgr.Engine) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.Engine.start_link(name: SnmpKit.SnmpMgr.Engine)
        :ok

      _pid ->
        :ok
    end

    :ok
  end

  describe "real device walk comparison" do
    @tag :manual
    test "single walk vs walk_multi comparison on real device" do
      # Test with first device from the list
      {device_ip, community} = List.first(@test_devices)
      opts = [community: community, timeout: @test_timeout, version: :v2c]

      Logger.info("=== TESTING DEVICE #{device_ip} ===")

      # Test single walk
      Logger.info("Testing single walk...")
      single_result = SnmpKit.SNMP.walk(device_ip, @test_oid, opts)

      case single_result do
        {:ok, single_walk_data} ->
          Logger.info("✅ Single walk SUCCESS: #{length(single_walk_data)} results")

          # Show first few results
          single_walk_data
          |> Enum.take(5)
          |> Enum.with_index()
          |> Enum.each(fn {{oid, type, value}, idx} ->
            Logger.info("  [#{idx}] #{oid} = #{inspect(value)} (#{type})")
          end)

          if length(single_walk_data) > 5 do
            Logger.info("  ... and #{length(single_walk_data) - 5} more results")
          end

        {:error, reason} ->
          Logger.info("❌ Single walk FAILED: #{inspect(reason)}")
      end

      # Test walk_multi
      Logger.info("\nTesting walk_multi...")
      targets_and_oids = [{device_ip, @test_oid, opts}]
      multi_results = Multi.walk_multi(targets_and_oids, return_format: :map)

      case Map.get(multi_results, {device_ip, @test_oid}) do
        {:ok, multi_walk_data} ->
          Logger.info("✅ walk_multi SUCCESS: #{length(multi_walk_data)} results")

          # Show first few results
          multi_walk_data
          |> Enum.take(5)
          |> Enum.with_index()
          |> Enum.each(fn {{oid, type, value}, idx} ->
            # Convert OID to string if it's a list for display
            oid_str = if is_list(oid), do: Enum.join(oid, "."), else: oid
            Logger.info("  [#{idx}] #{oid_str} = #{inspect(value)} (#{type})")
          end)

          if length(multi_walk_data) > 5 do
            Logger.info("  ... and #{length(multi_walk_data) - 5} more results")
          end

        {:error, reason} ->
          Logger.info("❌ walk_multi FAILED: #{inspect(reason)}")

        nil ->
          Logger.info("❌ walk_multi FAILED: No result found in map")
      end

      # Compare results if both succeeded
      case {single_result, Map.get(multi_results, {device_ip, @test_oid})} do
        {{:ok, single_data}, {:ok, multi_data}} ->
          Logger.info("\n=== COMPARISON ===")
          Logger.info("Single walk results: #{length(single_data)}")
          Logger.info("Multi walk results: #{length(multi_data)}")

          cond do
            length(single_data) > 1 and length(multi_data) == 1 ->
              Logger.info(
                "🐛 BUG CONFIRMED: walk_multi only returned 1 result while single walk returned #{length(single_data)}"
              )

              Logger.info("This is the 'first OID only' bug!")

            length(single_data) == length(multi_data) ->
              Logger.info("✅ Both operations returned the same number of results")

            true ->
              Logger.info("⚠️  Different result counts - needs investigation")
          end

        _ ->
          Logger.info("Cannot compare - one or both operations failed")
      end
    end

    @tag :manual
    test "walk_multi multiple devices shows first-OID bug pattern" do
      # Test multiple devices to show the pattern
      targets_and_oids =
        @test_devices
        |> Enum.map(fn {ip, community} ->
          {ip, @test_oid, [community: community, timeout: @test_timeout, version: :v2c]}
        end)

      Logger.info("=== TESTING MULTIPLE DEVICES ===")
      Logger.info("Devices: #{inspect(@test_devices)}")
      Logger.info("OID: #{@test_oid}")

      start_time = System.monotonic_time(:millisecond)
      results = Multi.walk_multi(targets_and_oids, return_format: :map)
      end_time = System.monotonic_time(:millisecond)

      Logger.info("Completed in #{end_time - start_time} milliseconds")
      Logger.info("Results:")

      results
      |> Enum.each(fn {{ip, oid}, result} ->
        case result do
          {:ok, walk_data} ->
            Logger.info("  #{ip} (#{oid}): #{length(walk_data)} results")

            if length(walk_data) == 1 do
              {first_oid, type, value} = List.first(walk_data)
              oid_str = if is_list(first_oid), do: Enum.join(first_oid, "."), else: first_oid
              Logger.info("    🐛 ONLY ONE RESULT: #{oid_str} = #{inspect(value)} (#{type})")
            else
              Logger.info("    ✅ Multiple results returned")
            end

          {:error, reason} ->
            Logger.info("  #{ip} (#{oid}): ERROR - #{inspect(reason)}")
        end
      end)

      # Check for the bug pattern
      successful_results =
        results
        |> Enum.filter(fn {_key, result} -> match?({:ok, _}, result) end)
        |> Enum.map(fn {_key, {:ok, data}} -> length(data) end)

      if Enum.all?(successful_results, &(&1 == 1)) and length(successful_results) > 0 do
        Logger.info("\n🐛 BUG PATTERN DETECTED!")
        Logger.info("All successful walks returned exactly 1 result.")
        Logger.info("This strongly indicates the 'first OID only' bug in walk_multi.")

        Logger.info(
          "Expected: Each device should return multiple OIDs from system subtree (sysDescr, sysObjectID, sysUpTime, etc.)"
        )

        Logger.info("Actual: Each device only returns sysDescr (first OID)")
      end
    end

    @tag :manual
    test "debug walk_multi call chain" do
      # Test to debug what's actually happening in the call chain
      {device_ip, community} = List.first(@test_devices)
      opts = [community: community, timeout: @test_timeout, version: :v2c]

      Logger.info("=== DEBUGGING WALK_MULTI CALL CHAIN ===")

      # Test the underlying Walk.walk call directly
      Logger.info("1. Testing Walk.walk directly...")
      direct_walk_result = SnmpKit.SnmpMgr.Walk.walk(device_ip, @test_oid, opts)

      case direct_walk_result do
        {:ok, data} ->
          Logger.info("   Walk.walk returned #{length(data)} results")

        {:error, reason} ->
          Logger.info("   Walk.walk failed: #{inspect(reason)}")
      end

      # Test through Multi.walk_multi
      Logger.info("2. Testing through Multi.walk_multi...")
      targets_and_oids = [{device_ip, @test_oid, opts}]
      multi_result = Multi.walk_multi(targets_and_oids)

      case multi_result do
        [{:ok, data}] ->
          Logger.info("   Multi.walk_multi returned #{length(data)} results")

        [{:error, reason}] ->
          Logger.info("   Multi.walk_multi failed: #{inspect(reason)}")

        other ->
          Logger.info("   Multi.walk_multi unexpected result: #{inspect(other)}")
      end

      # Compare the two
      case {direct_walk_result, multi_result} do
        {{:ok, direct_data}, [{:ok, multi_data}]} ->
          Logger.info("\n3. COMPARISON:")
          Logger.info("   Direct Walk.walk: #{length(direct_data)} results")
          Logger.info("   Through Multi: #{length(multi_data)} results")

          if length(direct_data) != length(multi_data) do
            Logger.info("   🐛 MISMATCH DETECTED!")
            Logger.info("   The Multi wrapper is changing the results!")
          else
            Logger.info("   ✅ Both return same count")
          end

        _ ->
          Logger.info("   Cannot compare due to errors")
      end
    end
  end

  describe "bulk operations comparison" do
    @tag :manual
    test "single get_bulk vs get_bulk_multi comparison" do
      # Also test bulk operations to see if they have similar issues
      {device_ip, community} = List.first(@test_devices)
      opts = [community: community, timeout: @test_timeout, version: :v2c, max_repetitions: 10]

      Logger.info("=== BULK OPERATIONS COMPARISON ===")

      # Single get_bulk
      single_bulk = SnmpKit.SNMP.get_bulk(device_ip, @test_oid, opts)

      case single_bulk do
        {:ok, data} ->
          Logger.info("Single get_bulk: #{length(data)} results")

        {:error, reason} ->
          Logger.info("Single get_bulk failed: #{inspect(reason)}")
      end

      # Multi get_bulk
      targets_and_oids = [{device_ip, @test_oid, opts}]
      multi_bulk = Multi.get_bulk_multi(targets_and_oids)

      case multi_bulk do
        [{:ok, data}] ->
          Logger.info("Multi get_bulk: #{length(data)} results")

        [{:error, reason}] ->
          Logger.info("Multi get_bulk failed: #{inspect(reason)}")

        other ->
          Logger.info("Multi get_bulk unexpected: #{inspect(other)}")
      end
    end
  end
end
