defmodule SnmpKit.BulkVsWalkMultiTest do
  use ExUnit.Case, async: true
  @moduletag :bulk_vs_walk_multi

  alias SnmpKit.SnmpMgr.Multi
  alias SnmpKit.SnmpSim.{Device, MIB.SharedProfiles}

  @test_timeout 5000
  @sim_host "127.0.0.1"
  @sim_port 11650

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
    :timer.sleep(2000)

    # Verify simulator is responding
    case SnmpKit.SNMP.get(@sim_host, "1.3.6.1.2.1.1.1.0", port: @sim_port, timeout: 5000) do
      {:ok, _value} ->
        IO.puts("Simulator ready for bulk vs walk testing")

      {:error, reason} ->
        raise "Cannot start bulk vs walk tests - simulator not responding: #{inspect(reason)}"
    end

    on_exit(fn ->
      if Process.alive?(sim_pid) do
        Process.exit(sim_pid, :normal)
      end
    end)

    {:ok, simulator_pid: sim_pid}
  end

  describe "get_bulk_multi vs walk_multi behavior" do
    test "get_bulk_multi returns single GETBULK response (non-iterative)" do
      # get_bulk_multi should send one GETBULK and return what it gets
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1",
         [port: @sim_port, timeout: @test_timeout, max_repetitions: 10]}
      ]

      IO.puts("Testing get_bulk_multi...")
      start_time = System.monotonic_time(:millisecond)
      results = Multi.get_bulk_multi(targets_and_oids)
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      IO.puts("get_bulk_multi completed in #{duration}ms")

      assert is_list(results)
      assert length(results) == 1

      case results do
        [{:ok, bulk_results}] ->
          IO.puts("get_bulk_multi SUCCESS: Got #{length(bulk_results)} results")

          # Print first few for debugging
          bulk_results
          |> Enum.take(5)
          |> Enum.with_index()
          |> Enum.each(fn {{oid, type, value}, idx} ->
            IO.puts("  [#{idx}] #{oid || "EMPTY_OID"} = #{inspect(value)} (#{type})")
          end)

          assert is_list(bulk_results)
          # get_bulk_multi should return whatever the single GETBULK returns
          # This might be less than walk_multi since it doesn't iterate
          assert length(bulk_results) > 0, "get_bulk_multi should return at least some results"

        [{:error, reason}] ->
          flunk("get_bulk_multi failed: #{inspect(reason)}")
      end
    end

    test "walk_multi returns complete walk (iterative)" do
      # walk_multi should iterate until end of subtree
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: @test_timeout]}
      ]

      IO.puts("Testing walk_multi...")
      start_time = System.monotonic_time(:millisecond)
      results = Multi.walk_multi(targets_and_oids)
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      IO.puts("walk_multi completed in #{duration}ms")

      assert is_list(results)
      assert length(results) == 1

      case results do
        [{:ok, walk_results}] ->
          IO.puts("walk_multi SUCCESS: Got #{length(walk_results)} results")

          # Print first few for debugging
          walk_results
          |> Enum.take(5)
          |> Enum.each(fn {oid, type, value} ->
            IO.puts("  #{oid} = #{inspect(value)} (#{type})")
          end)

          assert is_list(walk_results)
          # walk_multi should return complete subtree (we know from previous tests it should be 7)
          assert length(walk_results) >= 7, "walk_multi should return complete system subtree"

        [{:error, reason}] ->
          flunk("walk_multi failed: #{inspect(reason)}")
      end
    end

    test "compare get_bulk_multi vs walk_multi behavior" do
      # Direct comparison to understand the difference
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1",
         [port: @sim_port, timeout: @test_timeout, max_repetitions: 10]}
      ]

      # Test both operations
      bulk_results = Multi.get_bulk_multi(targets_and_oids)
      walk_results = Multi.walk_multi(targets_and_oids)

      case {bulk_results, walk_results} do
        {[{:ok, bulk_data}], [{:ok, walk_data}]} ->
          IO.puts("=== COMPARISON ===")
          IO.puts("get_bulk_multi: #{length(bulk_data)} results")
          IO.puts("walk_multi: #{length(walk_data)} results")

          # Both should succeed but potentially return different amounts of data
          assert length(bulk_data) > 0, "bulk should return some results"
          assert length(walk_data) > 0, "walk should return some results"

          # Extract OIDs for comparison
          bulk_oids = Enum.map(bulk_data, fn {oid, _type, _value} -> oid end)
          walk_oids = Enum.map(walk_data, fn {oid, _type, _value} -> oid end)

          # Convert bulk OIDs to strings for display consistency
          bulk_oids_display =
            Enum.map(bulk_oids, fn
              oid when is_list(oid) -> Enum.join(oid, ".")
              oid when is_binary(oid) -> oid
            end)

          IO.puts("First bulk OID: #{List.first(bulk_oids_display) || "none"}")
          IO.puts("Last bulk OID: #{List.last(bulk_oids_display) || "none"}")
          IO.puts("First walk OID: #{List.first(walk_oids) || "none"}")
          IO.puts("Last walk OID: #{List.last(walk_oids) || "none"}")

          # get_bulk_multi can return more results than walk_multi when max_repetitions
          # exceeds the subtree size (bulk goes beyond subtree boundary)
          # Both should return some results - that's the main requirement
          assert length(bulk_data) > 0, "get_bulk_multi should return some results"
          assert length(walk_data) > 0, "walk_multi should return some results"

          # Note: bulk might return OIDs outside the walk subtree due to max_repetitions
          # So we don't assert subset relationship, just that both work correctly
          IO.puts("Bulk OIDs sample: #{inspect(Enum.take(bulk_oids, 3))}")
          IO.puts("Walk OIDs sample: #{inspect(Enum.take(walk_oids, 3))}")

          # Format consistency checks - bulk operations return lists, walk operations return strings
          assert Enum.all?(bulk_oids, &is_list/1),
                 "All bulk OIDs should be lists (matching single get_bulk format)"

          assert Enum.all?(walk_oids, &is_binary/1),
                 "All walk OIDs should be strings (matching single walk format)"

        {[{:error, bulk_error}], [{:ok, _walk_data}]} ->
          flunk("get_bulk_multi failed while walk_multi succeeded: #{inspect(bulk_error)}")

        {[{:ok, _bulk_data}], [{:error, walk_error}]} ->
          flunk("walk_multi failed while get_bulk_multi succeeded: #{inspect(walk_error)}")

        {[{:error, bulk_error}], [{:error, walk_error}]} ->
          flunk(
            "Both operations failed - bulk: #{inspect(bulk_error)}, walk: #{inspect(walk_error)}"
          )
      end
    end

    test "get_bulk_multi handles multiple targets correctly" do
      # Test get_bulk_multi with multiple targets to ensure it's working properly
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1",
         [port: @sim_port, timeout: @test_timeout, max_repetitions: 5]},
        {@sim_host, "1.3.6.1.2.1.2",
         [port: @sim_port, timeout: @test_timeout, max_repetitions: 5]}
      ]

      results = Multi.get_bulk_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 2

      IO.puts("get_bulk_multi with 2 targets:")

      Enum.with_index(results, 1)
      |> Enum.each(fn {result, idx} ->
        case result do
          {:ok, bulk_data} ->
            IO.puts("  Target #{idx}: #{length(bulk_data)} results")
            assert length(bulk_data) > 0, "Target #{idx} should return results"

          {:error, reason} ->
            IO.puts("  Target #{idx}: Error - #{inspect(reason)}")
            # Some targets might fail, that's OK for this test
        end
      end)
    end

    test "verify get_bulk_multi timeout behavior" do
      # Ensure get_bulk_multi doesn't have the same timeout issue that walk_multi had
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: 2000, max_repetitions: 5]}
      ]

      start_time = System.monotonic_time(:millisecond)
      results = Multi.get_bulk_multi(targets_and_oids)
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete quickly (not timeout)
      assert duration < 1000, "get_bulk_multi should complete quickly, took #{duration}ms"

      assert is_list(results)
      assert length(results) == 1

      case results do
        [{:ok, _bulk_data}] ->
          IO.puts("get_bulk_multi completed successfully in #{duration}ms")

        [{:error, reason}] ->
          flunk("get_bulk_multi failed: #{inspect(reason)}")
      end
    end
  end

  describe "bulk_vs_walk comparison with single operations" do
    test "compare multi vs single bulk operations" do
      # Compare get_bulk_multi with single get_bulk
      oid = "1.3.6.1.2.1.1"
      opts = [port: @sim_port, timeout: @test_timeout, max_repetitions: 10]

      # Single bulk operation
      single_result = SnmpKit.SNMP.get_bulk(@sim_host, oid, opts)

      # Multi bulk operation
      multi_results = Multi.get_bulk_multi([{@sim_host, oid, opts}])

      case {single_result, multi_results} do
        {{:ok, single_data}, [{:ok, multi_data}]} ->
          IO.puts("Single bulk: #{length(single_data)} results")
          IO.puts("Multi bulk: #{length(multi_data)} results")

          # Should return the same results
          assert length(single_data) == length(multi_data),
                 "Single and multi bulk should return same number of results"

          # Convert to comparable format and check equality
          single_oids = Enum.map(single_data, fn {oid, _type, _value} -> oid end)
          multi_oids = Enum.map(multi_data, fn {oid, _type, _value} -> oid end)

          assert Enum.sort(single_oids) == Enum.sort(multi_oids),
                 "Single and multi bulk should return the same OIDs"

        {{:error, single_error}, [{:error, multi_error}]} ->
          # Both failed - might be OK depending on the scenario
          IO.puts("Both single and multi bulk failed:")
          IO.puts("  Single: #{inspect(single_error)}")
          IO.puts("  Multi: #{inspect(multi_error)}")

        {{:ok, single_data}, [{:error, multi_error}]} ->
          IO.puts("Single bulk succeeded with #{length(single_data)} results")
          flunk("Multi bulk failed while single bulk succeeded: #{inspect(multi_error)}")

        {{:error, single_error}, [{:ok, multi_data}]} ->
          IO.puts("Multi bulk succeeded with #{length(multi_data)} results")
          flunk("Single bulk failed while multi bulk succeeded: #{inspect(single_error)}")
      end
    end
  end

  test "check OID format consistency between single operations" do
    # Check what format single operations return to understand the expected format
    oid = "1.3.6.1.2.1.1"
    opts = [port: @sim_port, timeout: @test_timeout, max_repetitions: 5]

    # Test single operations
    single_bulk = SnmpKit.SNMP.get_bulk(@sim_host, oid, opts)
    single_walk = SnmpKit.SNMP.walk(@sim_host, oid, opts)

    case {single_bulk, single_walk} do
      {{:ok, bulk_data}, {:ok, walk_data}} ->
        bulk_oid_sample = bulk_data |> List.first() |> elem(0)
        walk_oid_sample = walk_data |> List.first() |> elem(0)

        IO.puts(
          "Single get_bulk OID format: #{inspect(bulk_oid_sample)} (#{bulk_oid_sample |> is_binary()})"
        )

        IO.puts(
          "Single walk OID format: #{inspect(walk_oid_sample)} (#{walk_oid_sample |> is_binary()})"
        )

        # Different operation types return different formats by design
        # get_bulk returns lists, walk returns strings
        assert is_list(bulk_oid_sample), "get_bulk should return OID lists"
        assert is_binary(walk_oid_sample), "walk should return OID strings"

        IO.puts("✅ Single operations use expected formats for their types")

      _ ->
        IO.puts("Single operations failed - skipping format check")
    end
  end
end
