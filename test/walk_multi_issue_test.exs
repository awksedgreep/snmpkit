defmodule SnmpKit.WalkMultiIssueTest do
  use ExUnit.Case, async: true
  @moduletag :walk_multi_issue

  alias SnmpKit.SnmpMgr.Multi
  alias SnmpKit.SnmpSim.{Device, MIB.SharedProfiles}

  @test_timeout 10_000
  @sim_host "127.0.0.1"
  @sim_port 11640

  setup_all do
    # Ensure SharedProfiles is available
    case GenServer.whereis(SharedProfiles) do
      nil ->
        {:ok, _} = SharedProfiles.start_link([])

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          :ok
        else
          {:ok, _} = SharedProfiles.start_link([])
        end
    end

    # Load cable_modem profile into SharedProfiles
    :ok =
      SharedProfiles.load_walk_profile(
        :cable_modem,
        "priv/walks/cable_modem.walk",
        []
      )

    # Start the simulator device
    device_config = %{
      port: @sim_port,
      device_type: :cable_modem,
      device_id: "cable_modem_#{@sim_port}",
      community: "public"
    }

    {:ok, sim_pid} = Device.start_link(device_config)

    # Ensure the SnmpMgr Engine is running
    case Process.whereis(SnmpKit.SnmpMgr.Engine) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.Engine.start_link(name: SnmpKit.SnmpMgr.Engine)
        :ok

      _pid ->
        :ok
    end

    # Wait for simulator to be ready
    :timer.sleep(3000)

    # Verify simulator is responding with basic GET
    case SnmpKit.SNMP.get(@sim_host, "1.3.6.1.2.1.1.1.0", port: @sim_port, timeout: 5000) do
      {:ok, _value} ->
        IO.puts("Simulator is ready and responding")

      {:error, reason} ->
        raise "Cannot start walk_multi tests - simulator not responding: #{inspect(reason)}"
    end

    on_exit(fn ->
      if Process.alive?(sim_pid) do
        Process.exit(sim_pid, :normal)
      end
    end)

    {:ok, simulator_pid: sim_pid}
  end

  describe "walk_multi timeout investigation" do
    test "single walk works correctly" do
      # First verify that regular walk works
      case SnmpKit.SNMP.walk(@sim_host, "1.3.6.1.2.1.1", port: @sim_port, timeout: @test_timeout) do
        {:ok, walk_results} ->
          IO.puts("SINGLE WALK SUCCESS: Got #{length(walk_results)} results")

          # Print first few for debugging
          walk_results
          |> Enum.take(3)
          |> Enum.each(fn {oid, type, value} ->
            IO.puts("  #{oid} = #{inspect(value)} (#{type})")
          end)

          assert is_list(walk_results)
          assert length(walk_results) > 1, "Should get multiple results from system subtree"

        {:error, reason} ->
          flunk("Single walk failed: #{inspect(reason)}")
      end
    end

    test "walk_multi with same parameters as working single walk" do
      # Use exact same parameters as the working single walk
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: @test_timeout]}
      ]

      IO.puts("Starting walk_multi with timeout: #{@test_timeout}ms")
      start_time = System.monotonic_time(:millisecond)

      results = Multi.walk_multi(targets_and_oids)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      IO.puts("walk_multi completed in #{duration}ms")

      assert is_list(results)
      assert length(results) == 1

      case results do
        [{:ok, walk_results}] ->
          IO.puts("WALK_MULTI SUCCESS: Got #{length(walk_results)} results")

          # Print first few for debugging
          walk_results
          |> Enum.take(3)
          |> Enum.each(fn {oid, type, value} ->
            IO.puts("  #{oid} = #{inspect(value)} (#{type})")
          end)

          assert is_list(walk_results)
          assert length(walk_results) > 1, "walk_multi should return multiple results"

          # THIS IS THE KEY TEST: If walk_multi only returned the first OID,
          # we would get length(walk_results) == 1
          refute length(walk_results) == 1,
                 "BUG CONFIRMED: walk_multi returned only first OID: #{inspect(walk_results)}"

        [{:error, reason}] ->
          IO.puts("WALK_MULTI FAILED: #{inspect(reason)} after #{duration}ms")
          flunk("walk_multi failed while single walk works: #{inspect(reason)}")
      end
    end

    test "walk_multi vs single walk direct comparison" do
      # Test both with identical parameters and compare results
      oid = "1.3.6.1.2.1.1"
      opts = [port: @sim_port, timeout: @test_timeout]

      IO.puts("=== SINGLE WALK TEST ===")
      single_start = System.monotonic_time(:millisecond)
      single_result = SnmpKit.SNMP.walk(@sim_host, oid, opts)
      single_end = System.monotonic_time(:millisecond)
      single_duration = single_end - single_start

      IO.puts("=== WALK_MULTI TEST ===")
      multi_start = System.monotonic_time(:millisecond)
      multi_results = Multi.walk_multi([{@sim_host, oid, opts}])
      multi_end = System.monotonic_time(:millisecond)
      multi_duration = multi_end - multi_start

      IO.puts("Single walk: #{single_duration}ms")
      IO.puts("Multi walk: #{multi_duration}ms")

      case {single_result, multi_results} do
        {{:ok, single_walk_results}, [{:ok, multi_walk_results}]} ->
          IO.puts("Both succeeded!")
          IO.puts("Single walk: #{length(single_walk_results)} results")
          IO.puts("Multi walk: #{length(multi_walk_results)} results")

          # Compare the results
          assert length(single_walk_results) == length(multi_walk_results),
                 "Both walks should return the same number of results"

          # Both should return multiple results (detecting the first-OID bug)
          assert length(single_walk_results) > 1, "Single walk should return multiple OIDs"
          assert length(multi_walk_results) > 1, "Multi walk should return multiple OIDs"

          # Verify OIDs match
          single_oids = Enum.map(single_walk_results, fn {oid, _type, _value} -> oid end)
          multi_oids = Enum.map(multi_walk_results, fn {oid, _type, _value} -> oid end)

          assert Enum.sort(single_oids) == Enum.sort(multi_oids),
                 "Both walks should return the same OIDs"

        {{:ok, single_walk_results}, [{:error, multi_error}]} ->
          IO.puts("Single walk succeeded with #{length(single_walk_results)} results")
          IO.puts("Multi walk failed: #{inspect(multi_error)}")

          flunk("walk_multi failed while single walk succeeded: #{inspect(multi_error)}")

        {{:error, single_error}, [{:ok, multi_walk_results}]} ->
          IO.puts("Single walk failed: #{inspect(single_error)}")
          IO.puts("Multi walk succeeded with #{length(multi_walk_results)} results")

          flunk("Single walk failed while walk_multi succeeded: #{inspect(single_error)}")

        {{:error, single_error}, [{:error, multi_error}]} ->
          IO.puts("Both failed:")
          IO.puts("Single walk: #{inspect(single_error)}")
          IO.puts("Multi walk: #{inspect(multi_error)}")

          flunk("Both walks failed - simulator issue?")
      end
    end

    test "walk_multi with very long timeout to rule out timing issues" do
      # Test with an extremely long timeout to see if it's really a timeout issue
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: 30_000]}
      ]

      IO.puts("Testing walk_multi with 30 second timeout...")
      start_time = System.monotonic_time(:millisecond)

      results = Multi.walk_multi(targets_and_oids)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      IO.puts("walk_multi with long timeout completed in #{duration}ms")

      assert is_list(results)
      assert length(results) == 1

      case results do
        [{:ok, walk_results}] ->
          IO.puts("SUCCESS with long timeout: Got #{length(walk_results)} results")
          assert length(walk_results) > 1, "Should get multiple results"

        [{:error, reason}] ->
          IO.puts("FAILED even with 30s timeout: #{inspect(reason)}")

          # This would indicate a real bug, not just a timeout issue
          flunk("walk_multi failed even with 30 second timeout: #{inspect(reason)}")
      end
    end

    test "walk_multi result structure analysis" do
      # If walk_multi does work, let's analyze if it returns complete results
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: 15_000]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      case results do
        [{:ok, walk_results}] ->
          IO.puts("Analyzing walk_multi results...")
          IO.puts("Total results: #{length(walk_results)}")

          # Group by base OID to see distribution
          base_oid_counts =
            walk_results
            |> Enum.map(fn {oid, _type, _value} ->
              # Extract base like "1.3.6.1.2.1.1.1" from "1.3.6.1.2.1.1.1.0"
              oid
              |> String.split(".")
              |> Enum.take(8)
              |> Enum.join(".")
            end)
            |> Enum.frequencies()

          IO.puts("Results by base OID:")

          Enum.each(base_oid_counts, fn {base, count} ->
            IO.puts("  #{base}: #{count} result(s)")
          end)

          # The bug would be if we only got results for one base OID
          unique_base_oids = Map.keys(base_oid_counts)

          if length(unique_base_oids) == 1 do
            IO.puts("WARNING: Only got results for one base OID - possible first-OID bug!")
            IO.puts("Single base OID: #{List.first(unique_base_oids)}")

            # Show all results to understand the pattern
            IO.puts("All results:")

            Enum.each(walk_results, fn {oid, type, value} ->
              IO.puts("  #{oid} = #{inspect(value)} (#{type})")
            end)
          end

          assert length(unique_base_oids) > 1,
                 "Should have results for multiple base OIDs, but only got: #{inspect(unique_base_oids)}"

        [{:error, reason}] ->
          flunk("walk_multi failed: #{inspect(reason)}")
      end
    end
  end
end
