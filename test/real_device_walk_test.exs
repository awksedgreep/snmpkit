defmodule SnmpKit.RealDeviceWalkTest do
  use ExUnit.Case, async: false
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

      IO.puts("=== TESTING DEVICE #{device_ip} ===")

      # Test single walk
      IO.puts("Testing single walk...")
      single_result = SnmpKit.SNMP.walk(device_ip, @test_oid, opts)

      case single_result do
        {:ok, single_walk_data} ->
          IO.puts("✅ Single walk SUCCESS: #{length(single_walk_data)} results")

          # Show first few results
          single_walk_data
          |> Enum.take(5)
          |> Enum.with_index()
          |> Enum.each(fn {{oid, type, value}, idx} ->
            IO.puts("  [#{idx}] #{oid} = #{inspect(value)} (#{type})")
          end)

          if length(single_walk_data) > 5 do
            IO.puts("  ... and #{length(single_walk_data) - 5} more results")
          end

        {:error, reason} ->
          IO.puts("❌ Single walk FAILED: #{inspect(reason)}")
      end

      # Test walk_multi
      IO.puts("\nTesting walk_multi...")
      targets_and_oids = [{device_ip, @test_oid, opts}]
      multi_results = Multi.walk_multi(targets_and_oids, return_format: :map)

      case Map.get(multi_results, {device_ip, @test_oid}) do
        {:ok, multi_walk_data} ->
          IO.puts("✅ walk_multi SUCCESS: #{length(multi_walk_data)} results")

          # Show first few results
          multi_walk_data
          |> Enum.take(5)
          |> Enum.with_index()
          |> Enum.each(fn {{oid, type, value}, idx} ->
            # Convert OID to string if it's a list for display
            oid_str = if is_list(oid), do: Enum.join(oid, "."), else: oid
            IO.puts("  [#{idx}] #{oid_str} = #{inspect(value)} (#{type})")
          end)

          if length(multi_walk_data) > 5 do
            IO.puts("  ... and #{length(multi_walk_data) - 5} more results")
          end

        {:error, reason} ->
          IO.puts("❌ walk_multi FAILED: #{inspect(reason)}")

        nil ->
          IO.puts("❌ walk_multi FAILED: No result found in map")
      end

      # Compare results if both succeeded
      case {single_result, Map.get(multi_results, {device_ip, @test_oid})} do
        {{:ok, single_data}, {:ok, multi_data}} ->
          IO.puts("\n=== COMPARISON ===")
          IO.puts("Single walk results: #{length(single_data)}")
          IO.puts("Multi walk results: #{length(multi_data)}")

          if length(single_data) > 1 and length(multi_data) == 1 do
            IO.puts("🐛 BUG CONFIRMED: walk_multi only returned 1 result while single walk returned #{length(single_data)}")
            IO.puts("This is the 'first OID only' bug!")
          elsif length(single_data) == length(multi_data) do
            IO.puts("✅ Both operations returned the same number of results")
          else
            IO.puts("⚠️  Different result counts - needs investigation")
          end

        _ ->
          IO.puts("Cannot compare - one or both operations failed")
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

      IO.puts("=== TESTING MULTIPLE DEVICES ===")
      IO.puts("Devices: #{inspect(@test_devices)}")
      IO.puts("OID: #{@test_oid}")

      start_time = System.monotonic_time(:millisecond)
      results = Multi.walk_multi(targets_and_oids, return_format: :map)
      end_time = System.monotonic_time(:millisecond)

      IO.puts("Completed in #{end_time - start_time} milliseconds")
      IO.puts("Results:")

      results
      |> Enum.each(fn {{ip, oid}, result} ->
        case result do
          {:ok, walk_data} ->
            IO.puts("  #{ip} (#{oid}): #{length(walk_data)} results")

            if length(walk_data) == 1 do
              {first_oid, type, value} = List.first(walk_data)
              oid_str = if is_list(first_oid), do: Enum.join(first_oid, "."), else: first_oid
              IO.puts("    🐛 ONLY ONE RESULT: #{oid_str} = #{inspect(value)} (#{type})")
            else
              IO.puts("    ✅ Multiple results returned")
            end

          {:error, reason} ->
            IO.puts("  #{ip} (#{oid}): ERROR - #{inspect(reason)}")
        end
      end)

      # Check for the bug pattern
      successful_results =
        results
        |> Enum.filter(fn {_key, result} -> match?({:ok, _}, result) end)
        |> Enum.map(fn {_key, {:ok, data}} -> length(data) end)

      if Enum.all?(successful_results, &(&1 == 1)) and length(successful_results) > 0 do
        IO.puts("\n🐛 BUG PATTERN DETECTED!")
        IO.puts("All successful walks returned exactly 1 result.")
        IO.puts("This strongly indicates the 'first OID only' bug in walk_multi.")
        IO.puts("Expected: Each device should return multiple OIDs from system subtree (sysDescr, sysObjectID, sysUpTime, etc.)")
        IO.puts("Actual: Each device only returns sysDescr (first OID)")
      end
    end

    @tag :manual
    test "debug walk_multi call chain" do
      # Test to debug what's actually happening in the call chain
      {device_ip, community} = List.first(@test_devices)
      opts = [community: community, timeout: @test_timeout, version: :v2c]

      IO.puts("=== DEBUGGING WALK_MULTI CALL CHAIN ===")

      # Test the underlying Walk.walk call directly
      IO.puts("1. Testing Walk.walk directly...")
      direct_walk_result = SnmpKit.SnmpMgr.Walk.walk(device_ip, @test_oid, opts)

      case direct_walk_result do
        {:ok, data} ->
          IO.puts("   Walk.walk returned #{length(data)} results")
        {:error, reason} ->
          IO.puts("   Walk.walk failed: #{inspect(reason)}")
      end

      # Test through Multi.walk_multi
      IO.puts("2. Testing through Multi.walk_multi...")
      targets_and_oids = [{device_ip, @test_oid, opts}]
      multi_result = Multi.walk_multi(targets_and_oids)

      case multi_result do
        [{:ok, data}] ->
          IO.puts("   Multi.walk_multi returned #{length(data)} results")
        [{:error, reason}] ->
          IO.puts("   Multi.walk_multi failed: #{inspect(reason)}")
        other ->
          IO.puts("   Multi.walk_multi unexpected result: #{inspect(other)}")
      end

      # Compare the two
      case {direct_walk_result, multi_result} do
        {{:ok, direct_data}, [{:ok, multi_data}]} ->
          IO.puts("\n3. COMPARISON:")
          IO.puts("   Direct Walk.walk: #{length(direct_data)} results")
          IO.puts("   Through Multi: #{length(multi_data)} results")

          if length(direct_data) != length(multi_data) do
            IO.puts("   🐛 MISMATCH DETECTED!")
            IO.puts("   The Multi wrapper is changing the results!")
          else
            IO.puts("   ✅ Both return same count")
          end

        _ ->
          IO.puts("   Cannot compare due to errors")
      end
    end
  end

  describe "bulk operations comparison" do
    @tag :manual
    test "single get_bulk vs get_bulk_multi comparison" do
      # Also test bulk operations to see if they have similar issues
      {device_ip, community} = List.first(@test_devices)
      opts = [community: community, timeout: @test_timeout, version: :v2c, max_repetitions: 10]

      IO.puts("=== BULK OPERATIONS COMPARISON ===")

      # Single get_bulk
      single_bulk = SnmpKit.SNMP.get_bulk(device_ip, @test_oid, opts)

      case single_bulk do
        {:ok, data} ->
          IO.puts("Single get_bulk: #{length(data)} results")
        {:error, reason} ->
          IO.puts("Single get_bulk failed: #{inspect(reason)}")
      end

      # Multi get_bulk
      targets_and_oids = [{device_ip, @test_oid, opts}]
      multi_bulk = Multi.get_bulk_multi(targets_and_oids)

      case multi_bulk do
        [{:ok, data}] ->
          IO.puts("Multi get_bulk: #{length(data)} results")
        [{:error, reason}] ->
          IO.puts("Multi get_bulk failed: #{inspect(reason)}")
        other ->
          IO.puts("Multi get_bulk unexpected: #{inspect(other)}")
      end
    end
  end
end
