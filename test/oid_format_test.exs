defmodule SnmpKit.OidFormatTest do
  use ExUnit.Case, async: true
  @moduletag :oid_format

  alias SnmpKit.SnmpMgr.Multi
  alias SnmpKit.SnmpSim.{Device, MIB.SharedProfiles}

  @test_timeout 5000
  @sim_host "127.0.0.1"
  @sim_port 11660

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

    on_exit(fn ->
      if Process.alive?(sim_pid) do
        Process.exit(sim_pid, :normal)
      end
    end)

    {:ok, simulator_pid: sim_pid}
  end

  describe "OID format consistency" do
    test "check single operation OID formats" do
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

          IO.puts("=== SINGLE OPERATIONS OID FORMATS ===")
          IO.puts("Single get_bulk OID format: #{inspect(bulk_oid_sample)}")
          IO.puts("Single get_bulk OID is_binary: #{is_binary(bulk_oid_sample)}")
          IO.puts("Single walk OID format: #{inspect(walk_oid_sample)}")
          IO.puts("Single walk OID is_binary: #{is_binary(walk_oid_sample)}")

          # Both should use the same format - let's see what it is
          bulk_is_string = is_binary(bulk_oid_sample)
          walk_is_string = is_binary(walk_oid_sample)

          if bulk_is_string == walk_is_string do
            IO.puts("✅ Single operations use consistent formats")
          else
            IO.puts("❌ Single operations use different formats")
          end

        _ ->
          flunk("Single operations failed - cannot check format consistency")
      end
    end

    test "check multi operation OID formats" do
      # Check what format multi operations return
      oid = "1.3.6.1.2.1.1"

      targets_and_oids = [
        {@sim_host, oid, [port: @sim_port, timeout: @test_timeout, max_repetitions: 5]}
      ]

      # Test multi operations
      multi_bulk = Multi.get_bulk_multi(targets_and_oids)
      multi_walk = Multi.walk_multi(targets_and_oids)

      case {multi_bulk, multi_walk} do
        {[{:ok, bulk_data}], [{:ok, walk_data}]} ->
          bulk_oid_sample = bulk_data |> List.first() |> elem(0)
          walk_oid_sample = walk_data |> List.first() |> elem(0)

          IO.puts("=== MULTI OPERATIONS OID FORMATS ===")
          IO.puts("Multi get_bulk OID format: #{inspect(bulk_oid_sample)}")
          IO.puts("Multi get_bulk OID is_binary: #{is_binary(bulk_oid_sample)}")
          IO.puts("Multi walk OID format: #{inspect(walk_oid_sample)}")
          IO.puts("Multi walk OID is_binary: #{is_binary(walk_oid_sample)}")

          # Both should use the same format
          bulk_is_string = is_binary(bulk_oid_sample)
          walk_is_string = is_binary(walk_oid_sample)

          if bulk_is_string == walk_is_string do
            IO.puts("✅ Multi operations use consistent formats")
          else
            IO.puts("❌ Multi operations use different formats - this needs fixing!")
          end

        _ ->
          flunk("Multi operations failed - cannot check format consistency")
      end
    end

    test "compare single vs multi format consistency" do
      # Compare single vs multi operations to ensure they all use the same format
      oid = "1.3.6.1.2.1.1"
      opts = [port: @sim_port, timeout: @test_timeout, max_repetitions: 5]
      targets_and_oids = [{@sim_host, oid, opts}]

      # Get all operation results
      single_bulk = SnmpKit.SNMP.get_bulk(@sim_host, oid, opts)
      single_walk = SnmpKit.SNMP.walk(@sim_host, oid, opts)
      multi_bulk = Multi.get_bulk_multi(targets_and_oids)
      multi_walk = Multi.walk_multi(targets_and_oids)

      case {single_bulk, single_walk, multi_bulk, multi_walk} do
        {{:ok, sb_data}, {:ok, sw_data}, [{:ok, mb_data}], [{:ok, mw_data}]} ->
          # Extract first OID from each
          sb_oid = sb_data |> List.first() |> elem(0)
          sw_oid = sw_data |> List.first() |> elem(0)
          mb_oid = mb_data |> List.first() |> elem(0)
          mw_oid = mw_data |> List.first() |> elem(0)

          IO.puts("=== ALL OPERATIONS FORMAT COMPARISON ===")
          IO.puts("Single bulk: #{inspect(sb_oid)} (binary: #{is_binary(sb_oid)})")
          IO.puts("Single walk: #{inspect(sw_oid)} (binary: #{is_binary(sw_oid)})")
          IO.puts("Multi bulk: #{inspect(mb_oid)} (binary: #{is_binary(mb_oid)})")
          IO.puts("Multi walk: #{inspect(mw_oid)} (binary: #{is_binary(mw_oid)})")

          # Check if all operations use the same format
          formats = [
            is_binary(sb_oid),
            is_binary(sw_oid),
            is_binary(mb_oid),
            is_binary(mw_oid)
          ]

          all_same_format = formats |> Enum.uniq() |> length() == 1

          if all_same_format do
            IO.puts("✅ All operations use consistent OID format")
          else
            IO.puts("❌ Operations use inconsistent OID formats - this needs fixing!")
            IO.puts("Format consistency: #{inspect(formats)}")

            # This should pass once we fix the format issue
            assert all_same_format, "All SNMP operations should return OIDs in the same format"
          end

        _ ->
          flunk("Some operations failed - cannot perform full format comparison")
      end
    end
  end
end
