defmodule SnmpKit.SnmpMgr.AdaptiveWalkTest do
  @moduledoc """
  AdaptiveWalk terminates on the shared rule in `SnmpKit.SnmpLib.Types`:
  the first exception varbind or OID outside the base OID ends the walk, and
  the varbinds before it are kept with their type information intact.
  """
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpLib.Types
  alias SnmpKit.SnmpMgr.AdaptiveWalk
  alias SnmpKit.TestSupport.FakeAgent

  @if_entry [1, 3, 6, 1, 2, 1, 2, 2, 1]

  describe "scope filtering through SnmpKit.SnmpLib.Types.take_in_scope/2" do
    test "keeps the leading in-scope varbinds and stops at the first one outside" do
      results = [
        {@if_entry ++ [1, 1], :integer, 1},
        {@if_entry ++ [2, 1], :octet_string, "eth0"},
        {@if_entry ++ [3, 1], :integer, 6},
        {[1, 3, 6, 1, 2, 1, 3, 1, 1, 1], :integer, 100},
        {@if_entry ++ [5, 1], :gauge32, 1_000_000_000}
      ]

      assert {kept, true} = Types.take_in_scope(results, @if_entry)

      assert Enum.map(kept, &elem(&1, 0)) == [
               @if_entry ++ [1, 1],
               @if_entry ++ [2, 1],
               @if_entry ++ [3, 1]
             ]

      assert Enum.map(kept, &elem(&1, 1)) == [:integer, :octet_string, :integer]
    end

    test "accepts dotted-string OIDs" do
      results = [
        {"1.3.6.1.2.1.2.2.1.1.1", :integer, 1},
        {"1.3.6.1.2.1.1.1.0", :octet_string, "system"}
      ]

      assert {[{"1.3.6.1.2.1.2.2.1.1.1", :integer, 1}], true} =
               Types.take_in_scope(results, @if_entry)
    end

    for exception <- [:end_of_mib_view, :no_such_object, :no_such_instance] do
      test "a #{exception} varbind ends the walk even when its OID is under the base OID" do
        results = [
          {@if_entry ++ [1, 1], :integer, 1},
          {@if_entry ++ [1, 2], unquote(exception), nil},
          {@if_entry ++ [1, 3], :integer, 3}
        ]

        assert {[{_, :integer, 1}], true} = Types.take_in_scope(results, @if_entry)
      end
    end

    test "a clean page is kept whole and the walk continues" do
      results = [{@if_entry ++ [1, 1], :integer, 1}, {@if_entry ++ [1, 2], :integer, 2}]
      assert {^results, false} = Types.take_in_scope(results, @if_entry)
      assert {[], false} = Types.take_in_scope([], @if_entry)
    end

    test "varbinds without type information are rejected" do
      assert {[], true} = Types.take_in_scope([{@if_entry ++ [2, 1], "eth0"}], @if_entry)
      assert {[], true} = Types.take_in_scope([{@if_entry ++ [3, 1]}], @if_entry)
    end
  end

  describe "AdaptiveWalk.bulk_walk/3" do
    @root [1, 3, 6, 1, 4, 1, 9999, 2]
    @opts [timeout: 1_000, retries: 0, max_repetitions: 10]

    test "returns typed varbinds up to the end-of-MIB marker and drops the marker" do
      {agent, port} =
        FakeAgent.start(fn _n, _pdu ->
          [
            {@root ++ [1], :octet_string, "FastEthernet0/1"},
            {@root ++ [2], :gauge32, 1_000_000_000},
            {@root ++ [2], :end_of_mib_view, nil}
          ]
        end)

      assert {:ok, rows} = AdaptiveWalk.bulk_walk("127.0.0.1:#{port}", @root, @opts)

      assert rows == [
               {@root ++ [1], :octet_string, "FastEthernet0/1"},
               {@root ++ [2], :gauge32, 1_000_000_000}
             ]

      assert FakeAgent.requests(agent) == 1
    end

    test "stops at noSuchObject / noSuchInstance the same way" do
      for exception <- [:no_such_object, :no_such_instance] do
        {agent, port} =
          FakeAgent.start(fn _n, _pdu ->
            [{@root ++ [1], :integer, 1}, {@root ++ [7], exception, nil}]
          end)

        assert {:ok, [{_, :integer, 1}]} =
                 AdaptiveWalk.bulk_walk("127.0.0.1:#{port}", @root, @opts)

        assert FakeAgent.requests(agent) == 1
      end
    end

    test "honours max_entries" do
      {agent, port} =
        FakeAgent.start(fn n, pdu ->
          base = (n - 1) * 3
          rows = for i <- 1..3, do: {@root ++ [base + i], :integer, base + i}
          Enum.take(rows, pdu.max_repetitions)
        end)

      assert {:ok, rows} =
               AdaptiveWalk.bulk_walk(
                 "127.0.0.1:#{port}",
                 @root,
                 Keyword.put(@opts, :max_entries, 5)
               )

      assert Enum.map(rows, &elem(&1, 2)) == [1, 2, 3, 4, 5]
      assert FakeAgent.requests(agent) == 2
    end
  end
end
