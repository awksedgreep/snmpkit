defmodule SnmpKit.SnmpSim.EndOfMibSemanticsTest do
  @moduledoc """
  SNMPv1 and SNMPv2c report the end of the MIB differently (RFC 1157 4.1.3 vs
  RFC 3416 4.2.2/4.2.3). The simulator must answer each version its own way
  and keep GETBULK responses bounded.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.Device.{PduProcessor, WalkPduProcessor}
  alias SnmpKit.SnmpSim.MIB.SharedProfiles
  alias SnmpKit.SnmpSim.OIDTree

  @last_oid "1.3.6.1.2.1.2.2.1.16.1"
  @profile %{
    "1.3.6.1.2.1.1.1.0" => %{type: "STRING", value: "descr"},
    "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 100},
    "1.3.6.1.2.1.2.2.1.10.2" => %{type: "Counter32", value: 200},
    @last_oid => %{type: "Counter32", value: 300}
  }

  setup do
    case Process.whereis(SharedProfiles) do
      nil -> {:ok, _} = SharedProfiles.start_link([])
      _ -> :ok
    end

    :ok = SharedProfiles.clear_all_profiles()
    :ok = SharedProfiles.store_profile(:eom_test, @profile, %{})

    state = %{
      device_type: :eom_test,
      has_walk_data: true,
      counters: %{},
      gauges: %{},
      status_vars: %{},
      upgrade: %{},
      upgrade_enabled: false,
      device_id: "eom_1",
      uptime_start: :erlang.monotonic_time()
    }

    {:ok, state: state}
  end

  defp oid(str), do: str |> String.split(".") |> Enum.map(&String.to_integer/1)

  defp getnext(version, oids) do
    %{
      version: version,
      community: "public",
      type: :get_next_request,
      request_id: 7,
      error_status: 0,
      error_index: 0,
      varbinds: Enum.map(oids, &{oid(&1), :null, :null})
    }
  end

  describe "GETNEXT at the end of the MIB" do
    test "SNMPv2c answers with an endOfMibView exception and error-status 0", %{state: state} do
      response = WalkPduProcessor.process_getnext_request(getnext(2, [@last_oid]), state)

      assert response.error_status == 0
      assert [{last, :end_of_mib_view, {:end_of_mib_view, nil}}] = response.varbinds
      assert last == oid(@last_oid)
    end

    test "SNMPv1 answers noSuchName with the request varbinds echoed", %{state: state} do
      request = getnext(1, ["1.3.6.1.2.1.1.1.0", @last_oid])
      response = WalkPduProcessor.process_getnext_request(request, state)

      # noSuchName
      assert response.error_status == 2
      # the second varbind ran off the end
      assert response.error_index == 2
      assert response.varbinds == request.varbinds
    end

    test "SNMPv1 GETNEXT that succeeds carries values", %{state: state} do
      response = WalkPduProcessor.process_getnext_request(getnext(1, ["1.3.6.1.2.1.1"]), state)
      assert response.error_status == 0
      assert [{next, :octet_string, "descr"}] = response.varbinds
      assert next == oid("1.3.6.1.2.1.1.1.0")
    end

    test "legacy processor uses the same version rules", %{state: state} do
      legacy_state = %{state | has_walk_data: false}

      v2 = PduProcessor.process_snmp_pdu(getnext(2, [@last_oid]), legacy_state)
      assert v2.error_status == 0
      assert [{_, :end_of_mib_view, _}] = v2.varbinds

      v1 = PduProcessor.process_snmp_pdu(getnext(1, [@last_oid]), legacy_state)
      assert v1.error_status == 2
      assert v1.error_index == 1
    end
  end

  describe "GETBULK" do
    defp getbulk(version, oids, max_rep, non_rep \\ 0) do
      %{
        version: version,
        community: "public",
        type: :get_bulk_request,
        request_id: 9,
        error_status: 0,
        error_index: 0,
        non_repeaters: non_rep,
        max_repetitions: max_rep,
        varbinds: Enum.map(oids, &{oid(&1), :null, :null})
      }
    end

    test "stops with a single endOfMibView instead of padding", %{state: state} do
      response =
        WalkPduProcessor.process_getbulk_request(
          getbulk(2, ["1.3.6.1.2.1.2.2.1.10.1"], 10),
          state
        )

      types = Enum.map(response.varbinds, &elem(&1, 1))
      assert types == [:counter32, :counter32, :end_of_mib_view]
      assert response.error_status == 0
    end

    test "max-repetitions is honoured as requested, not capped", %{state: state} do
      big = Map.new(1..200, fn i -> {"1.3.6.1.4.1.9.#{i}", %{type: "INTEGER", value: i}} end)
      :ok = SharedProfiles.store_profile(:eom_big, big, %{})
      big_state = %{state | device_type: :eom_big}

      # 120 requested, 200 available: exactly 120 rows
      response =
        WalkPduProcessor.process_getbulk_request(getbulk(2, ["1.3.6.1.4.1.9"], 120), big_state)

      assert length(response.varbinds) == 120
      assert Enum.all?(response.varbinds, &(elem(&1, 1) == :integer))

      # More requested than exist: all 200 plus one endOfMibView
      response =
        WalkPduProcessor.process_getbulk_request(getbulk(2, ["1.3.6.1.4.1.9"], 1_000), big_state)

      assert length(response.varbinds) == 201
      assert elem(List.last(response.varbinds), 1) == :end_of_mib_view

      # OIDTree behaves the same and honours non_repeaters
      tree =
        Enum.reduce(big, OIDTree.new(), fn {o, %{value: v}}, t -> OIDTree.insert(t, o, v) end)

      assert length(OIDTree.bulk_walk(tree, "1.3.6.1.4.1.9", 120)) == 120
      assert length(OIDTree.bulk_walk(tree, "1.3.6.1.4.1.9", 1_000)) == 200
      assert length(OIDTree.bulk_walk(tree, "1.3.6.1.4.1.9", 1_000, 1)) == 1
    end

    test "SNMPv1 has no GETBULK: it behaves like GETNEXT with v1 errors", %{state: state} do
      request = getbulk(1, [@last_oid], 5)
      response = WalkPduProcessor.process_getbulk_request(request, state)
      assert response.error_status == 2
      assert response.error_index == 1
    end
  end
end
