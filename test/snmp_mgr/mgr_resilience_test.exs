defmodule SnmpKit.SnmpMgr.ResilienceTest do
  @moduledoc """
  Covers the manager-side fixes for head-of-line blocking in the circuit
  breaker, router isolation and atom safety, metrics subscriber cleanup, and
  supervised, race-free service start-up.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.{CircuitBreaker, Engine, Metrics, Router, SocketManager}

  @moduletag :unit

  defp unique(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  defp stop_quietly(pid) do
    try do
      GenServer.stop(pid)
    catch
      :exit, _ -> :ok
    end
  end

  describe "CircuitBreaker.call/4 runs the work in the caller" do
    setup do
      {:ok, cb} =
        CircuitBreaker.start_link(name: unique(:cb), failure_threshold: 2, recovery_timeout: 200)

      on_exit(fn -> stop_quietly(cb) end)
      {:ok, cb: cb}
    end

    test "a slow target does not block other targets", %{cb: cb} do
      slow =
        Task.async(fn ->
          CircuitBreaker.call(cb, "slow", fn -> Process.sleep(500) end, 2_000)
        end)

      # While the slow call is in flight the breaker must still serve others
      {elapsed_us, result} =
        :timer.tc(fn -> CircuitBreaker.call(cb, "fast", fn -> :fast_result end, 1_000) end)

      assert {:ok, :fast_result} = result
      assert elapsed_us < 200_000

      assert {:ok, :ok} = Task.await(slow)
    end

    @tag :capture_log
    test "timeouts and crashes are distinguished and isolated", %{cb: cb} do
      assert {:error, :timeout} = CircuitBreaker.call(cb, "t", fn -> Process.sleep(500) end, 50)
      assert {:error, {:crash, _}} = CircuitBreaker.call(cb, "c", fn -> raise "boom" end, 500)
      # The caller survived both
      assert Process.alive?(self())

      # Metrics keep them apart
      stats = CircuitBreaker.get_stats(cb)
      assert stats.metrics.timeouts >= 1
      assert stats.metrics.crashes >= 1
    end

    @tag :capture_log
    test "the breaker opens after the threshold and admits a trial call later", %{cb: cb} do
      for _ <- 1..2 do
        assert {:error, {:crash, _}} = CircuitBreaker.call(cb, "x", fn -> raise "x" end, 500)
      end

      # get_stats/record_* are casts; sync on the server before reading state
      assert {:ok, %{state: :open}} = CircuitBreaker.get_state(cb, "x")
      assert {:error, :circuit_breaker_open} = CircuitBreaker.call(cb, "x", fn -> :ok end, 500)

      Process.sleep(250)
      assert :ok = CircuitBreaker.allow?(cb, "x")
      assert {:ok, %{state: :half_open}} = CircuitBreaker.get_state(cb, "x")
    end
  end

  describe "Router" do
    setup do
      {:ok, engine} = Engine.start_link(name: unique(:router_engine), request_timeout: 100)
      engine_name = GenServer.call(engine, :get_stats) && :sys.get_state(engine).name

      {:ok, router} =
        Router.start_link(
          name: unique(:router),
          engines: [%{name: engine_name, weight: 1, max_load: 100}],
          health_check_interval: 0,
          max_retries: 1
        )

      on_exit(fn ->
        stop_quietly(router)
        stop_quietly(engine)
      end)

      {:ok, router: router, engine: engine, engine_name: engine_name}
    end

    test "string engine names must already exist as atoms", %{router: router} do
      bogus = "snmpkit_no_such_engine_#{System.unique_integer([:positive])}"

      assert {:error, {:unknown_engine, ^bogus}} =
               Router.configure_engines(router, engines: [bogus])

      # An existing atom is fine
      assert :ok = Router.configure_engines(router, engines: [Atom.to_string(:engine_1)])
    end

    test "a routed request that fails is reported to the caller, router stays up", %{
      router: router,
      engine: engine
    } do
      request = %{type: :get, target: "192.0.2.1", oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}
      assert {:error, _} = Router.route_request(router, request, timeout: 100)
      assert Process.alive?(router)

      # Kill the engine: routing to it must not take the router down
      Process.unlink(engine)
      Process.exit(engine, :kill)
      assert {:error, _} = Router.route_request(router, request, timeout: 100)
      assert Process.alive?(router)
    end

    test "load accounting is live", %{router: router, engine_name: engine_name} do
      request = %{type: :get, target: "192.0.2.1", oid: [1, 3, 6, 1, 2, 1, 1, 1, 0]}

      task = Task.async(fn -> Router.route_request(router, request, timeout: 300) end)
      Process.sleep(50)

      [%{name: ^engine_name} = during] = Router.get_stats(router).engine_health
      assert during.current_load == 1
      assert during.total_requests == 1

      Task.await(task, 2_000)
      Process.sleep(20)

      [after_] = Router.get_stats(router).engine_health
      assert after_.current_load == 0
      assert after_.error_count == 1
      assert :sys.get_state(router).workers == %{}
    end
  end

  describe "Metrics subscribers" do
    test "a subscriber that dies is removed" do
      {:ok, metrics} = Metrics.start_link(name: unique(:metrics), collection_interval: 0)
      on_exit(fn -> stop_quietly(metrics) end)

      subscriber = spawn(fn -> Process.sleep(:infinity) end)
      Metrics.subscribe(metrics, subscriber)
      Metrics.subscribe(metrics, self())
      _ = :sys.get_state(metrics)

      assert MapSet.member?(:sys.get_state(metrics).subscribers, subscriber)

      Process.exit(subscriber, :kill)
      Process.sleep(20)

      state = :sys.get_state(metrics)
      refute MapSet.member?(state.subscribers, subscriber)
      refute Map.has_key?(state.subscriber_monitors, subscriber)
      assert MapSet.member?(state.subscribers, self())

      Metrics.unsubscribe(metrics, self())
      state = :sys.get_state(metrics)
      refute Map.has_key?(state.subscriber_monitors, self())
    end
  end

  describe "manager service supervision" do
    test "ensure_started is race-free and does not link services to callers" do
      services = [
        SnmpKit.SnmpMgr.RequestIdGenerator,
        SnmpKit.SnmpMgr.SocketManager,
        SnmpKit.SnmpMgr.EngineV2
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
