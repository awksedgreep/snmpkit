defmodule SnmpKit.AgentRequestTest do
  use ExUnit.Case, async: true

  alias SnmpKit.Agent.{Request, Store, Table}

  @sys_descr [1, 3, 6, 1, 2, 1, 1, 1, 0]
  @flags [1, 3, 6, 1, 4, 1, 99_999, 70, 0]
  @entry [1, 3, 6, 1, 4, 1, 99_999, 71]

  setup do
    table = Store.new_table()
    Store.put(table, @sys_descr, :octet_string, "x")
    Store.put(table, @flags, :bits, <<0x80>>, writable: true)

    {:ok, writes} = Agent.start_link(fn -> %{} end)

    {:ok, table_ctx} =
      Table.init(
        columns: [{1, :bits}, {2, :unsigned32}, {3, :oid}, {4, :string}],
        rows: fn -> [{1, %{1 => <<0x80>>, 2 => 1, 3 => [1, 3], 4 => "a"}}] end,
        set: fn index, column, value ->
          Agent.update(writes, &Map.put(&1, {index, column}, value))
          :ok
        end
      )

    subtrees = [
      %{prefix: @entry, module: Table, ctx: table_ctx},
      %{prefix: [], module: Store, ctx: %{table: table}}
    ]

    %{subtrees: subtrees, table: table, writes: writes}
  end

  defp pdu(type, varbinds, opts \\ []) do
    %{
      version: Keyword.get(opts, :version, 2),
      community: "any",
      type: type,
      request_id: 1,
      error_status: 0,
      error_index: 0,
      varbinds: Enum.map(varbinds, fn {oid, _, value} -> {oid, value} end),
      typed_varbinds: varbinds,
      non_repeaters: 0,
      max_repetitions: 5
    }
  end

  describe "SET type aliases" do
    test "a :bits object takes a :bits or an :octet_string value", %{
      subtrees: subtrees,
      table: table
    } do
      set = pdu(:set_request, [{@flags, :bits, <<0x40>>}])
      assert %{error_status: 0} = Request.handle(set, subtrees, :write)
      assert {:ok, {:bits, <<0x40>>}} = Store.fetch(table, @flags)

      set = pdu(:set_request, [{@flags, :octet_string, <<0x20>>}])
      assert %{error_status: 0} = Request.handle(set, subtrees, :write)
      assert {:ok, {:bits, <<0x20>>}} = Store.fetch(table, @flags)

      # wrongType
      set = pdu(:set_request, [{@flags, :integer, 1}])
      assert %{error_status: 7, error_index: 1} = Request.handle(set, subtrees, :write)
    end

    test "table columns declared with alias spellings accept both spellings", %{
      subtrees: subtrees,
      writes: writes
    } do
      set =
        pdu(:set_request, [
          {@entry ++ [1, 1], :bits, <<0x40>>},
          {@entry ++ [2, 1], :unsigned32, 2},
          {@entry ++ [3, 1], :oid, [1, 3, 6]},
          {@entry ++ [4, 1], :string, "b"}
        ])

      assert %{error_status: 0} = Request.handle(set, subtrees, :write)

      set =
        pdu(:set_request, [
          {@entry ++ [1, 1], :octet_string, <<0x20>>},
          {@entry ++ [2, 1], :gauge32, 3},
          {@entry ++ [3, 1], :object_identifier, [1, 3, 6, 1]},
          {@entry ++ [4, 1], :octet_string, "c"}
        ])

      assert %{error_status: 0} = Request.handle(set, subtrees, :write)

      assert Agent.get(writes, & &1) == %{
               {1, 1} => {:octet_string, <<0x20>>},
               {1, 2} => {:gauge32, 3},
               {1, 3} => {:object_identifier, [1, 3, 6, 1]},
               {1, 4} => {:octet_string, "c"}
             }
    end
  end
end
