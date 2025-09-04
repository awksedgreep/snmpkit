defmodule SnmpKit.WalkMultiSimpleFixTest do
  use ExUnit.Case, async: false
  @moduletag :walk_multi_fix

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
  test "verify walk_multi fix returns multiple OIDs" do
    opts = [community: @test_community, timeout: @test_timeout, version: :v2c]

    IO.puts("Testing walk_multi fix...")
    targets_and_oids = [{@test_device, @test_oid, opts}]

    start_time = System.monotonic_time(:millisecond)
    results = Multi.walk_multi(targets_and_oids, return_format: :map)
    end_time = System.monotonic_time(:millisecond)

    IO.puts("Completed in #{end_time - start_time} milliseconds")

    case Map.get(results, {@test_device, @test_oid}) do
      {:ok, walk_data} ->
        IO.puts("SUCCESS: Got #{length(walk_data)} results")

        walk_data
        |> Enum.take(5)
        |> Enum.with_index()
        |> Enum.each(fn {{oid, type, value}, idx} ->
          IO.puts("  [#{idx}] #{oid} = #{inspect(value)} (#{type})")
        end)

        if length(walk_data) > 1 do
          IO.puts(
            "✅ FIX CONFIRMED: walk_multi returned #{length(walk_data)} OIDs instead of just 1"
          )
        else
          IO.puts("🐛 BUG STILL EXISTS: Only got 1 OID: #{inspect(List.first(walk_data))}")
          flunk("walk_multi still only returns first OID")
        end

      {:error, reason} ->
        IO.puts("❌ walk_multi failed: #{inspect(reason)}")
        flunk("walk_multi failed: #{inspect(reason)}")

      nil ->
        IO.puts("❌ No result found")
        flunk("No result found in walk_multi response")
    end
  end
end
