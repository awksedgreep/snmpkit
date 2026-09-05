defmodule SnmpKit.SnmpMgr.ResilienceTest do
  @moduledoc """
  Covers supervised, race-free start-up of the manager services and
  SocketManager health/drop reporting.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.SocketManager

  @moduletag :unit

  defp unique(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  defp stop_quietly(pid) do
    try do
      GenServer.stop(pid)
    catch
      :exit, _ -> :ok
    end
  end

  describe "manager service supervision" do
    test "ensure_started is race-free and does not link services to callers" do
      services = [
        SnmpKit.SnmpMgr.RequestIdGenerator,
        SnmpKit.SnmpMgr.SocketManager,
        SnmpKit.SnmpMgr.Engine
      ]

      for name <- services, pid = Process.whereis(name), do: stop_quietly(pid)
      Process.sleep(20)

      tasks =
        for _ <- 1..20 do
          Task.async(fn -> SnmpKit.SnmpMgr.ensure_started() end)
        end

      assert Enum.all?(Task.await_many(tasks, 5_000), &(&1 == :ok))
      assert SnmpKit.SnmpMgr.services_running?()

      pids = Enum.map(services, &Process.whereis/1)

      # The callers are gone; the services must not be linked to them
      Process.sleep(20)
      assert Enum.map(services, &Process.whereis/1) == pids

      for pid <- pids do
        {:links, links} = Process.info(pid, :links)
        assert Process.whereis(SnmpKit.SnmpMgr.ServiceSupervisor) in links
      end
    end

    test "SocketManager reports queue-based health and drop counters" do
      {:ok, manager} = SocketManager.start_link(name: unique(:sm), max_queue_depth: 100)
      on_exit(fn -> stop_quietly(manager) end)

      health = SocketManager.health_check(manager)
      assert health.status == :healthy
      assert health.queue_depth == 0
      assert health.max_queue_depth == 100

      stats = SocketManager.get_stats(manager)
      assert stats.custom_stats.dropped_overload == 0
      assert stats.custom_stats.dropped_no_engine == 0

      buffer = SocketManager.get_buffer_stats(manager)
      assert buffer.recv_utilization_percent >= 0
      assert Map.has_key?(buffer, :engine_queue_length)
    end
  end
end
