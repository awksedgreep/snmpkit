defmodule SnmpKit.WalkMultiDebugTest do
  use ExUnit.Case, async: false
  @moduletag :walk_multi_debug

  alias SnmpKit.SnmpMgr.Multi

  # Use one of the user's real devices for testing
  @test_device "192.168.89.206"
  @test_community "public"
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

  @tag :manual
  test "debug walk_multi first OID only bug" do
    opts = [community: @test_community, timeout: @test_timeout, version: :v2c]

    IO.puts("=== DEBUGGING WALK_MULTI FIRST-OID BUG ===")
    IO.puts("Device: #{@test_device}")
    IO.puts("OID: #{@test_oid}")

    # Test single walk first
    IO.puts("\n1. Testing single walk...")
    single_result = SnmpKit.SNMP.walk(@test_device, @test_oid, opts)

    case single_result do
      {:ok, single_data} ->
        IO.puts("✅ Single walk: #{length(single_data)} results")
        single_data
        |> Enum.take(3)
        |> Enum.each(fn {oid, type, value} ->
          IO.puts("   #{oid} = #{inspect(String.slice(to_string(value), 0, 20))}... (#{type})")
        end)

      {:error, reason} ->
        IO.puts("❌ Single walk failed: #{inspect(reason)}")
        assert false, "Single walk failed: #{inspect(reason)}"
    end

    # Test walk_multi
    IO.puts("\n2. Testing walk_multi...")
    targets_and_oids = [{@test_device, @test_oid, opts}]

    multi_result = Multi.walk_multi(targets_and_oids)

    case multi_result do
      [{:ok, multi_data}] ->
        IO.puts("✅ walk_multi: #{length(multi_data)} results")
        multi_data
        |> Enum.take(3)
        |> Enum.each(fn {oid, type, value} ->
          # Handle both string and list OID formats
          oid_str = if is_list(oid), do: Enum.join(oid, "."), else: oid
          value_str = String.slice(to_string(value), 0, 20)
          IO.puts("   #{oid_str} = #{inspect(value_str)}... (#{type})")
        end)

      [{:error, reason}] ->
        IO.puts("❌ walk_multi failed: #{inspect(reason)}")
        assert false, "walk_multi failed: #{inspect(reason)}"

      other ->
        IO.puts("❌ walk_multi unexpected result: #{inspect(other)}")
        assert false, "walk_multi unexpected result: #{inspect(other)}"
    end

    # Compare results
    case {single_result, multi_result} do
      {{:ok, single_data}, [{:ok, multi_data}]} ->
        IO.puts("\n3. COMPARISON:")
        IO.puts("Single walk: #{length(single_data)} results")
        IO.puts("Multi walk:  #{length(multi_data)} results")

        if length(single_data) > 1 and length(multi_data) == 1 do
          IO.puts("\n🐛 BUG CONFIRMED!")
          IO.puts("walk_multi only returned the first OID while single walk returned the full subtree")
          IO.puts("Expected: walk_multi should return same results as single walk")

          # Show what we got vs what we expected
          {first_oid, first_type, first_value} = List.first(multi_data)
          oid_str = if is_list(first_oid), do: Enum.join(first_oid, "."), else: first_oid
          IO.puts("Got only: #{oid_str} = #{inspect(first_value)} (#{first_type})")

        elsif length(single_data) == length(multi_data) do
          IO.puts("✅ Both returned same number of results")
        else
          IO.puts("⚠️  Different counts but not the classic first-OID bug pattern")
        end

      _ ->
        IO.puts("Cannot compare - one or both operations failed")
    end
  end

  @tag :manual
  test "test direct Walk.walk vs Multi.walk_multi" do
    opts = [community: @test_community, timeout: @test_timeout, version: :v2c]

    IO.puts("=== TESTING DIRECT CALL CHAIN ===")

    # Test Walk.walk directly
    IO.puts("1. Direct Walk.walk...")
    direct_result = SnmpKit.SnmpMgr.Walk.walk(@test_device, @test_oid, opts)

    case direct_result do
      {:ok, data} ->
        IO.puts("   Direct Walk.walk: #{length(data)} results")
      {:error, reason} ->
        IO.puts("   Direct Walk.walk failed: #{inspect(reason)}")
    end

    # Test through Multi wrapper
    IO.puts("2. Through Multi.walk_multi...")
    targets_and_oids = [{@test_device, @test_oid, opts}]
    multi_result = Multi.walk_multi(targets_and_oids)

    case multi_result do
      [{:ok, data}] ->
        IO.puts("   Multi.walk_multi: #{length(data)} results")
      [{:error, reason}] ->
        IO.puts("   Multi.walk_multi failed: #{inspect(reason)}")
      other ->
        IO.puts("   Multi.walk_multi unexpected: #{inspect(other)}")
    end

    # The critical comparison
    case {direct_result, multi_result} do
      {{:ok, direct_data}, [{:ok, multi_data}]} ->
        IO.puts("\n3. DIRECT COMPARISON:")
        IO.puts("Direct call: #{length(direct_data)} results")
        IO.puts("Multi call:  #{length(multi_data)} results")

        if length(direct_data) != length(multi_data) do
          IO.puts("🐛 The Multi wrapper is corrupting the results!")
          IO.puts("This proves the bug is in the Multi implementation, not the underlying Walk logic")
        else
          IO.puts("✅ Multi wrapper preserves results correctly")
        end

      _ ->
        IO.puts("Cannot compare - errors occurred")
    end
  end
end
