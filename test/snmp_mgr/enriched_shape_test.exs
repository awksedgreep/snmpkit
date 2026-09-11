defmodule SnmpKit.SnmpMgr.EnrichedShapeTest do
  @moduledoc """
  The documented return shape of the bulk and *_pretty operations: enriched
  varbind maps, never tuples or bare strings. These pin the specs so they
  cannot drift from the code again.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr
  alias SnmpKit.TestSupport.SNMPSimulator

  @sys_descr "1.3.6.1.2.1.1.1.0"
  @system "1.3.6.1.2.1.1"

  setup do
    {:ok, device} = SNMPSimulator.create_test_device()
    :ok = SNMPSimulator.wait_for_device_ready(device)
    on_exit(fn -> SNMPSimulator.stop_device(device) end)

    %{
      target: "#{device.host}:#{device.port}",
      opts: [community: device.community, timeout: 1_000]
    }
  end

  defp assert_enriched(%{oid: oid, oid_list: oid_list, type: type, value: _} = map) do
    assert is_binary(oid)
    assert is_list(oid_list) and Enum.all?(oid_list, &is_integer/1)
    assert is_atom(type)
    map
  end

  defp assert_enriched(other),
    do: flunk("expected an enriched varbind map, got #{inspect(other)}")

  defp assert_pretty(map) do
    assert_enriched(map)
    assert is_binary(map.formatted)
    assert Map.has_key?(map, :name)
  end

  test "get_pretty returns one enriched map with :formatted", %{target: target, opts: opts} do
    assert {:ok, map} = SnmpMgr.get_pretty(target, @sys_descr, opts)
    assert_pretty(map)
    assert map.oid == @sys_descr

    # formatting cannot be switched off on the pretty variant
    assert {:ok, %{formatted: formatted}} =
             SnmpMgr.get_pretty(target, @sys_descr, Keyword.put(opts, :include_formatted, false))

    assert is_binary(formatted)
  end

  test "walk_pretty, bulk_pretty and bulk_walk_pretty return enriched maps with :formatted",
       %{target: target, opts: opts} do
    for pretty <- [&SnmpMgr.walk_pretty/3, &SnmpMgr.bulk_pretty/3, &SnmpMgr.bulk_walk_pretty/3] do
      assert {:ok, [_ | _] = rows} =
               pretty.(target, @system, Keyword.put(opts, :max_repetitions, 5))

      Enum.each(rows, &assert_pretty/1)

      assert {:ok, [row | _]} =
               pretty.(target, @system, Keyword.put(opts, :include_formatted, false))

      assert is_binary(row.formatted)
    end
  end

  test "get_bulk and bulk_walk return enriched maps; the bare form drops name and formatted",
       %{target: target, opts: opts} do
    for bulk <- [&SnmpMgr.get_bulk/3, &SnmpMgr.bulk_walk/3, &SnmpKit.SnmpMgr.Bulk.get_bulk/3] do
      assert {:ok, [_ | _] = rows} =
               bulk.(target, @system, Keyword.put(opts, :max_repetitions, 5))

      Enum.each(rows, &assert_pretty/1)

      bare_opts =
        Keyword.merge(opts, max_repetitions: 5, include_names: false, include_formatted: false)

      assert {:ok, [bare | _]} = bulk.(target, @system, bare_opts)
      assert_enriched(bare)
      refute Map.has_key?(bare, :name)
      refute Map.has_key?(bare, :formatted)
    end
  end
end
