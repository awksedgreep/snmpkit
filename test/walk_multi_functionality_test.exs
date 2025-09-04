defmodule SnmpKit.WalkMultiFunctionalityTest do
  use ExUnit.Case, async: true
  @moduletag :walk_multi

  alias SnmpKit.SnmpMgr.Multi
  alias SnmpKit.SnmpSim.{Device, ProfileLoader, MIB.SharedProfiles}

  @test_timeout 5000
  @sim_host "127.0.0.1"
  @sim_port 11620

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
        :ok

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

  describe "walk_multi basic functionality" do
    test "walk_multi returns multiple OIDs for single target" do
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 1

      # Extract the single result
      [{:ok, walk_results}] = results

      assert is_list(walk_results)

      assert length(walk_results) > 1,
             "walk_multi should return multiple OIDs, but got only #{length(walk_results)}: #{inspect(walk_results)}"

      # Verify all results are properly formatted 3-tuples
      Enum.each(walk_results, fn result ->
        assert match?({_oid, _type, _value}, result),
               "Each result should be {oid, type, value}, got: #{inspect(result)}"
      end)

      # Extract OIDs to verify we have multiple different ones
      oids = Enum.map(walk_results, fn {oid, _type, _value} -> oid end)
      unique_oids = Enum.uniq(oids)

      assert length(unique_oids) > 1,
             "Should have multiple unique OIDs, but got: #{inspect(unique_oids)}"

      # Verify OIDs are within the system subtree
      Enum.each(oids, fn oid ->
        assert String.starts_with?(oid, "1.3.6.1.2.1.1."),
               "OID should be within system subtree: #{oid}"
      end)
    end

    test "walk_multi returns multiple OIDs for multiple targets" do
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: @test_timeout]},
        {@sim_host, "1.3.6.1.2.1.2", [port: @sim_port, timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 2

      # Check both results
      Enum.each(results, fn result ->
        case result do
          {:ok, walk_results} ->
            assert is_list(walk_results)

            assert length(walk_results) > 1,
                   "Each walk should return multiple OIDs, but got: #{inspect(walk_results)}"

            # Verify proper formatting
            Enum.each(walk_results, fn entry ->
              assert match?({_oid, _type, _value}, entry),
                     "Each entry should be {oid, type, value}, got: #{inspect(entry)}"
            end)

          {:error, _reason} ->
            # Some walks might fail due to simulator limitations, that's OK for this test
            :ok
        end
      end)
    end

    test "walk_multi with :with_targets format preserves multiple OIDs" do
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids, return_format: :with_targets)

      assert is_list(results)
      assert length(results) == 1

      # Extract the single result
      [{target, oid, result}] = results

      assert target == @sim_host
      assert oid == "1.3.6.1.2.1.1"

      case result do
        {:ok, walk_results} ->
          assert is_list(walk_results)

          assert length(walk_results) > 1,
                 "walk_multi with :with_targets should return multiple OIDs, but got: #{inspect(walk_results)}"

        {:error, reason} ->
          flunk("Expected successful walk but got error: #{inspect(reason)}")
      end
    end

    test "walk_multi with :map format preserves multiple OIDs" do
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids, return_format: :map)

      assert is_map(results)
      assert map_size(results) == 1

      key = {@sim_host, "1.3.6.1.2.1.1"}
      assert Map.has_key?(results, key)

      case results[key] do
        {:ok, walk_results} ->
          assert is_list(walk_results)

          assert length(walk_results) > 1,
                 "walk_multi with :map should return multiple OIDs, but got: #{inspect(walk_results)}"

        {:error, reason} ->
          flunk("Expected successful walk but got error: #{inspect(reason)}")
      end
    end
  end

  describe "walk_multi vs single walk comparison" do
    test "walk_multi returns same results as individual walk" do
      oid = "1.3.6.1.2.1.1"
      opts = [port: @sim_port, timeout: @test_timeout]

      # Single walk
      {:ok, single_walk_results} = SnmpKit.SNMP.walk(@sim_host, oid, opts)

      # Multi walk
      targets_and_oids = [{@sim_host, oid, opts}]
      multi_results = Multi.walk_multi(targets_and_oids)

      assert length(multi_results) == 1

      case multi_results do
        [{:ok, multi_walk_results}] ->
          # Both should return multiple OIDs
          assert length(single_walk_results) > 1,
                 "Single walk should return multiple OIDs: #{inspect(single_walk_results)}"

          assert length(multi_walk_results) > 1,
                 "Multi walk should return multiple OIDs: #{inspect(multi_walk_results)}"

          # Results should be equivalent (allowing for minor ordering differences)
          single_oids = Enum.map(single_walk_results, fn {oid, _type, _value} -> oid end)
          multi_oids = Enum.map(multi_walk_results, fn {oid, _type, _value} -> oid end)

          assert Enum.sort(single_oids) == Enum.sort(multi_oids),
                 "Single walk and multi walk should return the same OIDs"

        [{:error, reason}] ->
          flunk("Multi walk failed: #{inspect(reason)}")
      end
    end
  end

  describe "walk_multi edge cases" do
    test "walk_multi handles non-existent subtree" do
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.999", [port: @sim_port, timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 1

      case List.first(results) do
        {:ok, walk_results} ->
          # If successful, should still follow the multiple OID rule
          assert is_list(walk_results)

        {:error, _reason} ->
          # Expected for non-existent subtree
          :ok
      end
    end

    test "walk_multi handles empty target list" do
      results = Multi.walk_multi([])

      assert results == []
    end
  end

  describe "walk_multi regression tests" do
    test "walk_multi does not return only first OID" do
      # This is the main regression test for the reported issue
      targets_and_oids = [
        {@sim_host, "1.3.6.1.2.1.1", [port: @sim_port, timeout: @test_timeout]}
      ]

      results = Multi.walk_multi(targets_and_oids)

      assert is_list(results)
      assert length(results) == 1

      case List.first(results) do
        {:ok, walk_results} ->
          assert is_list(walk_results)

          # The critical check: we should NOT get only one result
          refute length(walk_results) == 1,
                 "BUG CONFIRMED: walk_multi returned only first OID: #{inspect(walk_results)}"

          # We should get multiple results
          assert length(walk_results) > 1,
                 "walk_multi should return multiple OIDs from system subtree, got #{length(walk_results)}"

          # Verify the results span multiple OIDs within the subtree
          oids = Enum.map(walk_results, fn {oid, _type, _value} -> oid end)

          unique_base_oids =
            oids
            |> Enum.map(fn oid ->
              # Extract the base OID (e.g., "1.3.6.1.2.1.1.1" from "1.3.6.1.2.1.1.1.0")
              oid
              |> String.split(".")
              # Take first 8 components
              |> Enum.take(8)
              |> Enum.join(".")
            end)
            |> Enum.uniq()

          assert length(unique_base_oids) > 1,
                 "Should have multiple different base OIDs, got: #{inspect(unique_base_oids)}"

        {:error, reason} ->
          flunk("Walk failed unexpectedly: #{inspect(reason)}")
      end
    end
  end
end
