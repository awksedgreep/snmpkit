defmodule SnmpKit.AgentStoreTest do
  use ExUnit.Case, async: true

  alias SnmpKit.Agent.Store

  @oid [1, 3, 6, 1, 4, 1, 99_999, 60, 0]

  setup do
    table = Store.new_table()
    %{table: table, ctx: %{table: table}}
  end

  describe "set" do
    test "replaces a writable object and keeps the stored type spelling", %{
      table: table,
      ctx: ctx
    } do
      Store.put(table, @oid, :string, "a", writable: true)
      assert :ok = Store.set(@oid, {:octet_string, "b"}, ctx)
      assert {:ok, {:string, "b"}} = Store.fetch(table, @oid)

      Store.put(table, @oid, :bits, <<0x80>>, writable: true)
      assert :ok = Store.set(@oid, {:octet_string, <<0x40>>}, ctx)
      assert {:ok, {:bits, <<0x40>>}} = Store.fetch(table, @oid)
    end

    test "values that look like match-spec expressions are stored literally", %{
      table: table,
      ctx: ctx
    } do
      Store.put(table, @oid, :ip_address, {10, 0, 0, 1}, writable: true)
      assert :ok = Store.set(@oid, {:ip_address, {10, 0, 0, 2}}, ctx)
      assert {:ok, {:ip_address, {10, 0, 0, 2}}} = Store.fetch(table, @oid)

      Store.put(table, @oid, :object_identifier, [1, 3], writable: true)
      assert :ok = Store.set(@oid, {:oid, [1, 3, 6, 1]}, ctx)
      assert {:ok, {:object_identifier, [1, 3, 6, 1]}} = Store.fetch(table, @oid)

      Store.put(table, @oid, :integer, 1, writable: true)
      assert :ok = Store.set(@oid, {:integer, :"$1"}, ctx)
      assert {:ok, {:integer, :"$1"}} = Store.fetch(table, @oid)
    end

    test "refuses the wrong type, a read-only object and a missing one", %{
      table: table,
      ctx: ctx
    } do
      Store.put(table, @oid, :integer, 1, writable: true)
      assert {:error, :wrong_type} = Store.set(@oid, {:octet_string, "x"}, ctx)
      assert {:ok, {:integer, 1}} = Store.fetch(table, @oid)

      Store.put(table, @oid, :integer, 1)
      assert {:error, :not_writable} = Store.set(@oid, {:integer, 2}, ctx)

      Store.delete(table, @oid)
      assert {:error, :no_creation} = Store.set(@oid, {:integer, 2}, ctx)
    end

    test "concurrent SETs racing a delete/put loop never crash", %{table: table, ctx: ctx} do
      Store.put(table, @oid, :integer, 0, writable: true)

      churn =
        Task.async(fn ->
          for i <- 1..300 do
            Store.delete(table, @oid)
            Store.put(table, @oid, :integer, -i, writable: true)
          end
        end)

      writers =
        for n <- 1..50 do
          Task.async(fn ->
            for i <- 1..100, do: Store.set(@oid, {:integer, n * 1_000 + i}, ctx)
          end)
        end

      results = Enum.flat_map(writers, &Task.await(&1, 10_000))
      Task.await(churn, 10_000)

      assert Enum.all?(results, &(&1 in [:ok, {:error, :no_creation}, {:error, :commit_failed}]))
      assert :ok in results
      assert {:ok, {:integer, final}} = Store.fetch(table, @oid)
      assert is_integer(final)
    end
  end

  describe "to_list" do
    test "lists objects in OID order with function values called", %{table: table} do
      Store.put(table, [1, 3, 2, 0], :integer, fn -> 2 end)
      Store.put(table, [1, 3, 1, 0], :octet_string, "one")

      assert Store.to_list(table) == [
               {[1, 3, 1, 0], :octet_string, "one"},
               {[1, 3, 2, 0], :integer, 2}
             ]

      # the fixtable is released afterwards
      assert :ets.info(table, :fixed) == false
    end
  end
end
