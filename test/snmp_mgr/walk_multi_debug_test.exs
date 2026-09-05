defmodule SnmpKit.WalkMultiDebugTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :walk_multi_debug

  alias SnmpKit.SnmpMgr.Multi

  @test_device "192.168.89.206"
  @test_community "public"
  @test_oid "1.3.6.1.2.1.1"
  @test_timeout 10_000

  setup_all do
    case Process.whereis(SnmpKit.SnmpMgr.Engine) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.Engine.start_link(name: SnmpKit.SnmpMgr.Engine)
        :ok

      _pid ->
        :ok
    end
  end

  @tag :manual
  test "debug walk_multi first oid only bug" do
    opts = [community: @test_community, timeout: @test_timeout, version: :v2c]

    Logger.debug("=== DEBUGGING WALK_MULTI FIRST-OID BUG ===")
    Logger.debug("Device: #{@test_device}")
    Logger.debug("OID: #{@test_oid}")

    Logger.debug("\n1. Testing single walk...")
    single_result = SnmpKit.SNMP.walk(@test_device, @test_oid, opts)

    case single_result do
      {:ok, single_data} ->
        Logger.debug("Single walk results: #{length(single_data)}")
        print_results(single_data)

      {:error, reason} ->
        flunk("single walk failed: #{inspect(reason)}")
    end

    Logger.debug("\n2. Testing walk_multi...")
    multi_result = Multi.walk_multi([{@test_device, @test_oid, opts}])

    case multi_result do
      [{:ok, multi_data}] ->
        Logger.debug("walk_multi results: #{length(multi_data)}")
        print_results(multi_data)

      [{:error, reason}] ->
        flunk("walk_multi failed: #{inspect(reason)}")

      other ->
        flunk("walk_multi unexpected result: #{inspect(other)}")
    end

    compare_results(single_result, multi_result)
  end

  @tag :manual
  test "test direct walk vs multi walk" do
    opts = [community: @test_community, timeout: @test_timeout, version: :v2c]

    Logger.debug("=== TESTING DIRECT CALL CHAIN ===")
    Logger.debug("1. Direct Walk.walk...")
    direct_result = SnmpKit.SnmpMgr.Walk.walk(@test_device, @test_oid, opts)

    case direct_result do
      {:ok, data} ->
        Logger.debug("Direct Walk.walk results: #{length(data)}")

      {:error, reason} ->
        Logger.debug("Direct Walk.walk failed: #{inspect(reason)}")
    end

    Logger.debug("2. Through Multi.walk_multi...")
    multi_result = Multi.walk_multi([{@test_device, @test_oid, opts}])

    case multi_result do
      [{:ok, data}] ->
        Logger.debug("Multi.walk_multi results: #{length(data)}")

      [{:error, reason}] ->
        Logger.debug("Multi.walk_multi failed: #{inspect(reason)}")

      other ->
        Logger.debug("Multi.walk_multi unexpected: #{inspect(other)}")
    end

    case {direct_result, multi_result} do
      {{:ok, direct_data}, [{:ok, multi_data}]} when length(direct_data) != length(multi_data) ->
        flunk("multi wrapper changed result count")

      _ ->
        :ok
    end
  end

  defp compare_results({:ok, single_data}, [{:ok, multi_data}]) do
    Logger.debug("\n3. COMPARISON:")
    Logger.debug("Single walk: #{length(single_data)} results")
    Logger.debug("Multi walk:  #{length(multi_data)} results")

    cond do
      length(single_data) > 1 and length(multi_data) == 1 ->
        flunk("walk_multi only returned the first OID")

      length(single_data) == length(multi_data) ->
        Logger.debug("Counts match")

      true ->
        Logger.debug("Counts differ but not in the classic first-OID pattern")
    end
  end

  defp compare_results(_single_result, _multi_result), do: :ok

  defp print_results(results) do
    results
    |> Enum.take(3)
    |> Enum.each(fn {oid, type, value} ->
      oid_str = if is_list(oid), do: Enum.join(oid, "."), else: oid
      value_str = String.slice(to_string(value), 0, 20)
      Logger.debug("  #{oid_str} = #{inspect(value_str)} (#{type})")
    end)
  end
end
