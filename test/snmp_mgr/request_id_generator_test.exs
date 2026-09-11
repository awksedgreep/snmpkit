defmodule SnmpKit.SnmpMgr.RequestIdGeneratorTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.RequestIdGenerator

  @table :snmp_request_id_counter

  setup do
    # The application's generator owns the table; this second instance shares it.
    :ok = SnmpKit.SnmpMgr.ensure_started()
    {:ok, pid} = RequestIdGenerator.start_link(name: :test_generator)

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end

      :ok = SnmpKit.SnmpMgr.ensure_started()
    end)

    {:ok, generator: pid}
  end

  test "generates sequential IDs starting from 1" do
    RequestIdGenerator.reset()

    assert RequestIdGenerator.next_id() == 1
    assert RequestIdGenerator.next_id() == 2
    assert RequestIdGenerator.next_id() == 3
  end

  test "fetch_next_id is the tuple form of next_id" do
    RequestIdGenerator.reset()

    assert {:ok, 1} = RequestIdGenerator.fetch_next_id()
    assert RequestIdGenerator.next_id() == 2
  end

  test "current_value returns counter without incrementing" do
    RequestIdGenerator.reset()

    assert RequestIdGenerator.current_value() == 0
    RequestIdGenerator.next_id()
    assert RequestIdGenerator.current_value() == 1
    # Should not increment
    assert RequestIdGenerator.current_value() == 1
  end

  test "reset sets counter back to 0" do
    RequestIdGenerator.next_id()
    RequestIdGenerator.next_id()

    assert RequestIdGenerator.current_value() > 0

    RequestIdGenerator.reset()
    assert RequestIdGenerator.current_value() == 0
    assert RequestIdGenerator.next_id() == 1
  end

  test "counter wraps to 1 at the maximum" do
    # The Engine refuses to register an id that is still pending, so the wrap
    # itself is harmless (see EngineGuardTest).
    :ets.insert(@table, {:counter, 999_999})

    assert RequestIdGenerator.next_id() == 1_000_000
    assert RequestIdGenerator.next_id() == 1
  end

  test "thread safety with concurrent access" do
    RequestIdGenerator.reset()

    # Spawn multiple processes generating IDs concurrently
    parent = self()

    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          ids = for _ <- 1..100, do: RequestIdGenerator.next_id()
          send(parent, {:ids, i, ids})
        end)
      end

    # Collect all generated IDs
    all_ids =
      for _task <- tasks, reduce: [] do
        acc ->
          receive do
            {:ids, _i, ids} -> acc ++ ids
          end
      end

    # Wait for all tasks to complete
    Task.await_many(tasks)

    # Verify all IDs are unique
    assert length(all_ids) == length(Enum.uniq(all_ids))

    # Verify they're in reasonable range
    assert Enum.all?(all_ids, fn id -> id > 0 and id <= 1_000_000 end)
  end

  test "stopping a generator that shares the table leaves the table in place" do
    owner = Process.whereis(RequestIdGenerator)
    assert :ets.info(@table, :owner) == owner

    GenServer.stop(:test_generator)

    assert :ets.info(@table, :owner) == owner
    RequestIdGenerator.reset()
    assert RequestIdGenerator.next_id() == 1
  end

  test "there is no fallback id when the table is gone" do
    # Stop the owner: the table goes with it (the shared instance from setup
    # is still alive but has nothing to count on).
    GenServer.stop(RequestIdGenerator)
    assert :ets.whereis(@table) == :undefined

    assert {:error, :services_not_started} = RequestIdGenerator.fetch_next_id()

    assert_raise ArgumentError, ~r/not running/, fn ->
      RequestIdGenerator.next_id()
    end
  end
end
