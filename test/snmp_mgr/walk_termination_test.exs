defmodule SnmpKit.SnmpMgr.WalkTerminationTest do
  @moduledoc """
  Every GETBULK walk stack (Bulk, AdaptiveWalk, V2Walk) must stop on the same
  rule: the first endOfMibView / noSuchObject / noSuchInstance marker, the
  first OID outside the root, or an agent that stops making progress; the
  markers never reach the caller and no extra round trip is spent.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.{AdaptiveWalk, Bulk, V2Walk}
  alias SnmpKit.TestSupport.FakeAgent

  @root [1, 3, 6, 1, 4, 1, 9999, 1]
  @row1 {@root ++ [1], :integer, 1}
  @row2 {@root ++ [2], :integer, 2}
  @row3 {@root ++ [3], :integer, 3}
  @opts [timeout: 1_000, retries: 0, max_repetitions: 10]

  setup_all do
    :ok = SnmpKit.SnmpMgr.ensure_started()
    :ok
  end

  # The three stacks, each as (port, opts) -> the OIDs the walk returned
  @stacks [
    bulk: &__MODULE__.bulk/2,
    adaptive: &__MODULE__.adaptive/2,
    v2walk: &__MODULE__.v2walk/2
  ]

  def bulk(port, opts), do: oids(Bulk.walk_bulk("127.0.0.1:#{port}", @root, opts))
  def adaptive(port, opts), do: oids(AdaptiveWalk.bulk_walk("127.0.0.1:#{port}", @root, opts))

  def v2walk(port, opts) do
    request = %{target: "127.0.0.1:#{port}", oid: @root, opts: opts}
    oids(V2Walk.walk(request, 2_000))
  end

  defp oids({:ok, rows}), do: Enum.map(rows, &row_oid/1)
  defp oids(other), do: other
  defp row_oid(%{oid_list: oid}), do: oid
  defp row_oid({oid, _type, _value}), do: oid

  for exception <- [:end_of_mib_view, :no_such_object, :no_such_instance] do
    test "a #{exception} marker inside the root ends the walk and is dropped, no extra request" do
      marker = {@root ++ [2], unquote(exception), nil}

      for {name, walk} <- @stacks do
        {agent, port} =
          FakeAgent.start(fn
            1, _pdu -> [@row1, marker, @row3]
            _n, _pdu -> [{@root ++ [3], :end_of_mib_view, nil}]
          end)

        assert walk.(port, @opts) == [@root ++ [1]], "#{name} kept rows past the marker"
        assert FakeAgent.requests(agent) == 1, "#{name} sent an extra request"
      end
    end
  end

  test "an OID outside the root ends the walk without another request" do
    outside = {[1, 3, 6, 1, 4, 1, 9999, 2, 1], :integer, 99}

    for {name, walk} <- @stacks do
      {agent, port} =
        FakeAgent.start(fn
          1, _pdu -> [@row1, @row2, outside]
          _n, _pdu -> [outside]
        end)

      assert walk.(port, @opts) == [@root ++ [1], @root ++ [2]], "#{name} kept an outside OID"
      assert FakeAgent.requests(agent) == 1, "#{name} sent an extra request"
    end
  end

  test "an agent that keeps answering with the same OID never loops the walk" do
    for {name, walk} <- @stacks do
      {agent, port} = FakeAgent.start(fn _n, _pdu -> [@row1] end)

      # one page of data, then the same OID back for the OID just asked from
      assert walk.(port, @opts) == [@root ++ [1]], "#{name} did not stop on a repeated OID"
      assert FakeAgent.requests(agent) == 2, "#{name} kept asking"
    end
  end

  test "a full page with no marker asks once more, then stops on the marker" do
    for {name, walk} <- @stacks do
      {agent, port} =
        FakeAgent.start(fn
          1, _pdu -> [@row1, @row2]
          _n, _pdu -> [{@root ++ [2], :end_of_mib_view, nil}]
        end)

      assert walk.(port, Keyword.put(@opts, :max_repetitions, 2)) == [@root ++ [1], @root ++ [2]],
             "#{name} lost rows"

      assert FakeAgent.requests(agent) == 2, "#{name} request count"
    end
  end

  describe "against a simulated device" do
    setup do
      test_pid = self()
      id = "walk-termination-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        id,
        [:snmpkit, :sim, :request],
        fn _event, _measurements, metadata, _ -> send(test_pid, {:sim_request, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)

      # system is the last (and only) subtree of this device
      profile = %{
        name: "Tail Device",
        objects: %{
          [1, 3, 6, 1, 2, 1, 1, 1, 0] => "Simulated Device",
          [1, 3, 6, 1, 2, 1, 1, 5, 0] => "tail",
          [1, 3, 6, 1, 2, 1, 1, 6, 0] => "rack 1"
        }
      }

      port = SnmpKit.SnmpSim.TestHelpers.PortHelper.get_port()
      {:ok, _device} = SnmpKit.Sim.start_device(profile, port: port)
      %{target: "127.0.0.1:#{port}"}
    end

    defp sim_requests do
      Stream.repeatedly(fn ->
        receive do
          {:sim_request, _} -> 1
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(&(&1 != nil))
      |> length()
    end

    test "walking the last subtree of the device needs exactly one GETBULK", %{target: target} do
      # a single page covers the whole subtree; the endOfMibView marker that
      # follows the last object ends the walk without a second request
      for walk <- [
            &Bulk.walk_bulk(&1, "1.3.6.1.2.1.1", max_repetitions: 10),
            &SnmpKit.SnmpMgr.walk(&1, "1.3.6.1.2.1.1", max_repetitions: 10),
            &SnmpKit.SnmpMgr.bulk_walk(&1, "1.3.6.1.2.1.1", max_repetitions: 10),
            &SnmpKit.SnmpMgr.walk_table(&1, "1.3.6.1.2.1.1", max_repetitions: 10)
          ] do
        assert {:ok, rows} = walk.(target)
        assert length(rows) == 3
        assert Enum.all?(rows, &is_map/1)

        refute Enum.any?(
                 rows,
                 &(&1.type in [:end_of_mib_view, :no_such_object, :no_such_instance])
               )

        assert sim_requests() == 1
      end
    end
  end
end
