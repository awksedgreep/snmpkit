defmodule SnmpKit.WalkMultiRealDebugTest do
  use ExUnit.Case, async: false
  require Logger
  @moduletag :real_debug

  alias SnmpKit.SnmpMgr.Multi

  @test_device "192.168.89.206"
  @test_community "public"
  @test_oid "1.3.6.1.2.1.1"
  @test_timeout 10_000

  setup_all do
    case Process.whereis(SnmpKit.SnmpMgr.Engine) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.Engine.start_link(name: SnmpKit.SnmpMgr.Engine)

      _pid ->
        :ok
    end

    :ok
  end

  @tag :manual
  test "debug what happens in bulk_walk_subtree_iterative" do
    opts = [community: @test_community, timeout: @test_timeout, version: :v2c]

    Logger.debug("=== DEBUGGING BULK_WALK_SUBTREE_ITERATIVE ===")
    Logger.debug("Device: #{@test_device}")
    Logger.debug("OID: #{@test_oid}")

    # Enable debug logging to see what happens inside bulk_walk_subtree
    Logger.configure(level: :debug)

    # First test single walk to see expected behavior
    Logger.debug("\n1. Testing single walk for comparison...")
    single_result = SnmpKit.SNMP.walk(@test_device, @test_oid, opts)

    case single_result do
      {:ok, single_data} ->
        Logger.debug("✅ Single walk: #{length(single_data)} results")

        single_data
        |> Enum.take(3)
        |> Enum.each(fn {oid, type, value} ->
          Logger.debug("   #{oid} = #{inspect(String.slice(to_string(value), 0, 30))} (#{type})")
        end)

      {:error, reason} ->
        Logger.debug("❌ Single walk failed: #{inspect(reason)}")
        Logger.configure(level: :warning)
        flunk("Single walk failed - cannot proceed with debugging")
    end

    # Now test walk_multi with debug logging
    Logger.debug("\n2. Testing walk_multi with debug logging...")
    targets_and_oids = [{@test_device, @test_oid, opts}]

    multi_result = Multi.walk_multi(targets_and_oids, return_format: :map)

    case Map.get(multi_result, {@test_device, @test_oid}) do
      {:ok, multi_data} ->
        Logger.debug("walk_multi result: #{length(multi_data)} results")

        multi_data
        |> Enum.take(3)
        |> Enum.each(fn {oid, type, value} ->
          oid_str = if is_list(oid), do: Enum.join(oid, "."), else: oid
          Logger.debug("   #{oid_str} = #{inspect(String.slice(to_string(value), 0, 30))} (#{type})")
        end)

        if length(multi_data) == 1 do
          Logger.debug("\n🐛 BUG CONFIRMED: Only got 1 result from walk_multi")
          Logger.debug("Expected: Multiple results like single walk")
          Logger.debug("Check debug logs above to see where iteration stopped")
        end

      {:error, reason} ->
        Logger.debug("❌ walk_multi failed: #{inspect(reason)}")

      nil ->
        Logger.debug("❌ No result found in walk_multi response")
    end

    # Reset logging
    Logger.configure(level: :warn)
  end

  @tag :manual
  test "test Core.send_get_bulk_request directly" do
    opts = [
      community: @test_community,
      timeout: @test_timeout,
      version: :v2c,
      max_repetitions: 10
    ]

    Logger.debug("=== TESTING Core.send_get_bulk_request DIRECTLY ===")

    # Convert OID string to list
    {:ok, oid_list} = SnmpKit.SnmpLib.OID.string_to_list(@test_oid)
    Logger.debug("Root OID: #{inspect(oid_list)}")

    # Send direct GETBULK request
    Logger.debug("\nSending single GETBULK request...")

    case SnmpKit.SnmpMgr.Core.send_get_bulk_request(@test_device, oid_list, opts) do
      {:ok, results} ->
        Logger.debug("✅ GETBULK returned #{length(results)} results:")

        results
        |> Enum.with_index()
        |> Enum.each(fn {{oid, type, value}, idx} ->
          Logger.debug(
            "  [#{idx}] #{inspect(oid)} = #{inspect(String.slice(to_string(value), 0, 30))} (#{type})"
          )
        end)

        # Check which results are in scope for root_oid
        Logger.debug("\nFiltering results for subtree #{inspect(oid_list)}:")

        in_scope_results =
          Enum.filter(results, fn {result_oid, _type, _value} ->
            starts_with = List.starts_with?(result_oid, oid_list)
            Logger.debug("  #{inspect(result_oid)} starts_with #{inspect(oid_list)} = #{starts_with}")
            starts_with
          end)

        Logger.debug("In-scope results: #{length(in_scope_results)}")

        # Check what the next OID should be
        case List.last(in_scope_results) do
          {last_oid, _type, _value} ->
            Logger.debug("Next OID should be: #{inspect(last_oid)}")

          _ ->
            Logger.debug("No in-scope results - walk would stop here")
        end

      {:error, reason} ->
        Logger.debug("❌ GETBULK failed: #{inspect(reason)}")
    end
  end

  @tag :manual
  test "manually trace bulk_walk_subtree_iterative logic" do
    opts = [community: @test_community, timeout: @test_timeout, version: :v2c]

    Logger.debug("=== MANUALLY TRACING BULK_WALK_SUBTREE_ITERATIVE ===")

    {:ok, root_oid} = SnmpKit.SnmpLib.OID.string_to_list(@test_oid)
    Logger.debug("Root OID: #{inspect(root_oid)}")

    Logger.debug("\nStarting manual iteration...")

    {_final_oid, acc} =
      Enum.reduce_while(1..5, {root_oid, []}, fn iteration, {current_oid, acc} ->
        Logger.debug("\n--- ITERATION #{iteration} ---")
        Logger.debug("Current OID: #{inspect(current_oid)}")

        bulk_opts =
          opts
          |> Keyword.put(:max_repetitions, 10)
          |> Keyword.put(:version, :v2c)

        case SnmpKit.SnmpMgr.Core.send_get_bulk_request(@test_device, current_oid, bulk_opts) do
          {:ok, results} ->
            Logger.debug("Got #{length(results)} raw results")

            # Filter in-scope results
            in_scope =
              Enum.filter(results, fn {oid_list, _type, _value} ->
                List.starts_with?(oid_list, root_oid)
              end)

            Logger.debug("#{length(in_scope)} results in scope")

            if length(in_scope) > 0 do
              in_scope
              |> Enum.take(2)
              |> Enum.each(fn {oid, type, value} ->
                Logger.debug(
                  "  #{inspect(oid)} = #{inspect(String.slice(to_string(value), 0, 20))} (#{type})"
                )
              end)
            end

            # Determine next OID
            next_oid =
              case List.last(in_scope) do
                {oid_list, _type, _value} -> oid_list
                _ -> nil
              end

            Logger.debug("Next OID: #{inspect(next_oid)}")

            if Enum.empty?(in_scope) or next_oid == nil do
              Logger.debug(
                "❌ STOPPING: empty_in_scope=#{Enum.empty?(in_scope)}, next_oid_nil=#{next_oid == nil}"
              )

              {:halt, {current_oid, acc}}
            else
              acc = Enum.reverse(in_scope) ++ acc
              Logger.debug("✅ CONTINUING: #{length(acc)} total results so far")
              {:cont, {next_oid, acc}}
            end

          {:error, reason} ->
            Logger.debug("❌ Request failed: #{inspect(reason)}")
            {:halt, {current_oid, acc}}
        end
      end)

    Logger.debug("\nFinal result: #{length(acc)} total results")

    if length(acc) == 1 do
      Logger.debug("🐛 BUG CONFIRMED: Manual iteration also stops after 1 result")
      Logger.debug("This suggests the issue is in the filtering logic or next-OID calculation")
    else
      Logger.debug("✅ Manual iteration worked - bug must be elsewhere")
    end
  end
end
