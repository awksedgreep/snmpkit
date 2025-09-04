defmodule SnmpKit.SimulatorDebugTest do
  use ExUnit.Case, async: true
  @moduletag :simulator_debug

  alias SnmpKit.SnmpSim.{Device, MIB.SharedProfiles}

  @test_timeout 5000
  @sim_host "127.0.0.1"
  @sim_port 11630

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

    on_exit(fn ->
      if Process.alive?(sim_pid) do
        Process.exit(sim_pid, :normal)
      end
    end)

    {:ok, simulator_pid: sim_pid}
  end

  describe "simulator basic functionality" do
    test "simulator responds to basic GET request" do
      # Test basic GET first
      case SnmpKit.SNMP.get(@sim_host, "1.3.6.1.2.1.1.1.0",
             port: @sim_port,
             timeout: @test_timeout
           ) do
        {:ok, {oid, type, value}} ->
          IO.puts("GET SUCCESS: #{oid} = #{inspect(value)} (#{type})")
          assert oid == "1.3.6.1.2.1.1.1.0"
          assert is_binary(value)

        {:error, reason} ->
          flunk("Basic GET failed: #{inspect(reason)}")
      end
    end

    test "simulator responds to multiple GET requests" do
      # Test several system OIDs
      system_oids = [
        # sysDescr
        "1.3.6.1.2.1.1.1.0",
        # sysObjectID
        "1.3.6.1.2.1.1.2.0",
        # sysUpTime
        "1.3.6.1.2.1.1.3.0",
        # sysContact
        "1.3.6.1.2.1.1.4.0",
        # sysName
        "1.3.6.1.2.1.1.5.0"
      ]

      successful_gets =
        Enum.map(system_oids, fn oid ->
          case SnmpKit.SNMP.get(@sim_host, oid, port: @sim_port, timeout: @test_timeout) do
            {:ok, {returned_oid, type, value}} ->
              IO.puts("GET #{oid}: #{returned_oid} = #{inspect(value)} (#{type})")
              {oid, :ok, returned_oid, type, value}

            {:error, reason} ->
              IO.puts("GET #{oid}: ERROR = #{inspect(reason)}")
              {oid, :error, reason}
          end
        end)

      successful_count = successful_gets |> Enum.count(&match?({_, :ok, _, _, _}, &1))

      assert successful_count > 0, "At least some system OIDs should be accessible"
      IO.puts("Successfully got #{successful_count}/#{length(system_oids)} system OIDs")
    end

    test "simulator responds to single OID walk" do
      # Test basic walk functionality
      case SnmpKit.SNMP.walk(@sim_host, "1.3.6.1.2.1.1", port: @sim_port, timeout: @test_timeout) do
        {:ok, walk_results} ->
          IO.puts("WALK SUCCESS: Got #{length(walk_results)} results")

          # Print first few results for debugging
          walk_results
          |> Enum.take(5)
          |> Enum.with_index()
          |> Enum.each(fn {{oid, type, value}, idx} ->
            IO.puts("  [#{idx}] #{oid} = #{inspect(value)} (#{type})")
          end)

          assert is_list(walk_results)
          assert length(walk_results) > 0, "Walk should return at least some results"

          # Verify each result is properly formatted
          Enum.each(walk_results, fn result ->
            assert match?({_oid, _type, _value}, result),
                   "Each result should be {oid, type, value}, got: #{inspect(result)}"
          end)

          # Check if we got multiple unique OIDs (this would detect the bug)
          oids = Enum.map(walk_results, fn {oid, _type, _value} -> oid end)
          unique_oids = Enum.uniq(oids)

          IO.puts(
            "Walk returned #{length(walk_results)} total results with #{length(unique_oids)} unique OIDs"
          )

          if length(walk_results) == 1 do
            IO.puts("WARNING: Walk returned only 1 result - this could indicate a bug")
            IO.puts("Single result: #{inspect(List.first(walk_results))}")
          end

        {:error, reason} ->
          flunk("Walk failed: #{inspect(reason)}")
      end
    end

    test "simulator walk vs get_bulk comparison" do
      # Compare walk with get_bulk to see if there's a difference
      walk_result =
        SnmpKit.SNMP.walk(@sim_host, "1.3.6.1.2.1.1", port: @sim_port, timeout: @test_timeout)

      bulk_result =
        SnmpKit.SNMP.get_bulk(@sim_host, "1.3.6.1.2.1.1",
          port: @sim_port,
          timeout: @test_timeout,
          max_repetitions: 10
        )

      case {walk_result, bulk_result} do
        {{:ok, walk_results}, {:ok, bulk_results}} ->
          IO.puts("WALK: #{length(walk_results)} results")
          IO.puts("BULK: #{length(bulk_results)} results")

          walk_oids = Enum.map(walk_results, fn {oid, _type, _value} -> oid end)
          bulk_oids = Enum.map(bulk_results, fn {oid, _type, _value} -> oid end)

          IO.puts("Walk OIDs: #{inspect(Enum.take(walk_oids, 3))}...")
          IO.puts("Bulk OIDs: #{inspect(Enum.take(bulk_oids, 3))}...")

          # Both should return multiple results
          assert length(walk_results) > 1, "Walk should return multiple results"
          assert length(bulk_results) > 1, "Bulk should return multiple results"

        {{:error, walk_error}, {:error, bulk_error}} ->
          flunk(
            "Both walk and bulk failed: walk=#{inspect(walk_error)}, bulk=#{inspect(bulk_error)}"
          )

        {{:ok, walk_results}, {:error, bulk_error}} ->
          IO.puts(
            "Walk succeeded with #{length(walk_results)} results, bulk failed: #{inspect(bulk_error)}"
          )

          assert length(walk_results) > 1, "Walk should return multiple results"

        {{:error, walk_error}, {:ok, bulk_results}} ->
          IO.puts(
            "Bulk succeeded with #{length(bulk_results)} results, walk failed: #{inspect(walk_error)}"
          )

          assert length(bulk_results) > 1, "Bulk should return multiple results"
      end
    end

    test "debug walk file content" do
      # Let's see what's actually in the walk file
      walk_file_path = "priv/walks/cable_modem.walk"

      if File.exists?(walk_file_path) do
        content = File.read!(walk_file_path)
        lines = String.split(content, "\n")

        IO.puts("Walk file has #{length(lines)} lines")

        # Show first few lines
        lines
        |> Enum.take(10)
        |> Enum.with_index()
        |> Enum.each(fn {line, idx} ->
          IO.puts("  [#{idx}] #{line}")
        end)

        # Count system OIDs
        system_lines = Enum.filter(lines, &String.contains?(&1, "1.3.6.1.2.1.1."))
        IO.puts("System OIDs in walk file: #{length(system_lines)}")

        assert length(system_lines) > 1, "Walk file should contain multiple system OIDs"
      else
        flunk("Walk file not found: #{walk_file_path}")
      end
    end
  end
end
