defmodule SnmpKit.SnmpSim.MIB.SharedProfilesTest do
  @moduledoc """
  SharedProfiles serves reads straight from ETS with an ordered OID index,
  keys tables by arbitrary device-type terms without minting atoms, and frees
  tables when profiles are cleared.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.MIB.SharedProfiles

  setup do
    case Process.whereis(SharedProfiles) do
      nil -> {:ok, _} = SharedProfiles.start_link([])
      _ -> :ok
    end

    :ok = SharedProfiles.clear_all_profiles()
    :ok
  end

  @profile %{
    "1.3.6.1.2.1.1.1.0" => %{type: "STRING", value: "descr"},
    "1.3.6.1.2.1.1.3.0" => %{type: "Timeticks", value: 12_345},
    "1.3.6.1.2.1.2.2.1.10.1" => %{type: "Counter32", value: 100},
    "1.3.6.1.2.1.2.2.1.10.2" => %{type: "Counter32", value: 200},
    "1.3.6.1.2.1.2.2.1.10.10" => %{type: "Counter32", value: 1000},
    "1.3.6.1.2.1.2.2.1.16.1" => %{type: "Counter32", value: 300}
  }

  test "GETNEXT follows numeric OID order, not string order" do
    device = {"string keyed device", 1}
    :ok = SharedProfiles.store_profile(device, @profile, %{})

    # .10.2 must come before .10.10 (string order would put .10.10 first)
    assert {:ok, "1.3.6.1.2.1.2.2.1.10.2"} =
             SharedProfiles.get_next_oid(device, "1.3.6.1.2.1.2.2.1.10.1")

    assert {:ok, "1.3.6.1.2.1.2.2.1.10.10"} =
             SharedProfiles.get_next_oid(device, "1.3.6.1.2.1.2.2.1.10.2")

    assert {:ok, "1.3.6.1.2.1.2.2.1.16.1"} =
             SharedProfiles.get_next_oid(device, "1.3.6.1.2.1.2.2.1.10.10")

    assert :end_of_mib = SharedProfiles.get_next_oid(device, "1.3.6.1.2.1.2.2.1.16.1")

    # A prefix (subtree root) that is not itself an object yields its first descendant
    assert {:ok, "1.3.6.1.2.1.2.2.1.10.1"} =
             SharedProfiles.get_next_oid(device, "1.3.6.1.2.1.2.2")

    # Integer-list OIDs are accepted too
    assert {:ok, "1.3.6.1.2.1.1.1.0"} = SharedProfiles.get_next_oid(device, [1, 3, 6, 1])
    assert {:ok, all} = SharedProfiles.get_all_oids(device)

    assert all ==
             Enum.sort_by(Map.keys(@profile), fn o ->
               o |> String.split(".") |> Enum.map(&String.to_integer/1)
             end)
  end

  test "values are readable by string or list OID and typed" do
    :ok = SharedProfiles.store_profile(:sp_test, @profile, %{})

    assert {:ok, {:octet_string, "descr"}} =
             SharedProfiles.get_oid_value(:sp_test, "1.3.6.1.2.1.1.1.0", %{})

    assert {:ok, {:octet_string, "descr"}} =
             SharedProfiles.get_oid_value(:sp_test, [1, 3, 6, 1, 2, 1, 1, 1, 0], %{})

    assert {:ok, {:counter32, _}} =
             SharedProfiles.get_oid_value(:sp_test, "1.3.6.1.2.1.2.2.1.10.1", %{})

    assert {:error, :no_such_name} =
             SharedProfiles.get_oid_value(:sp_test, "1.3.6.1.2.1.9.9.9", %{})

    assert {:error, :device_type_not_found} = SharedProfiles.get_oid_value(:nope, "1.3.6.1", %{})
  end

  test "GETBULK collects from the index and honours the repetition count" do
    :ok = SharedProfiles.store_profile(:sp_bulk, @profile, %{})

    assert {:ok, rows} = SharedProfiles.get_bulk_oids(:sp_bulk, "1.3.6.1.2.1.2.2", 2)

    assert [{"1.3.6.1.2.1.2.2.1.10.1", :counter32, _}, {"1.3.6.1.2.1.2.2.1.10.2", :counter32, _}] =
             rows

    assert {:ok, rows} = SharedProfiles.get_bulk_oids(:sp_bulk, "1.3.6.1.2.1.2.2.1.16.1", 5)
    assert rows == []
  end

  test "reads do not go through the GenServer" do
    :ok = SharedProfiles.store_profile(:sp_direct, @profile, %{})
    :sys.suspend(SharedProfiles)

    try do
      assert {:ok, _} = SharedProfiles.get_oid_value(:sp_direct, "1.3.6.1.2.1.1.1.0", %{})
      assert {:ok, _} = SharedProfiles.get_next_oid(:sp_direct, "1.3.6.1")
      assert {:ok, _} = SharedProfiles.get_bulk_oids(:sp_direct, "1.3.6.1", 3)
    after
      :sys.resume(SharedProfiles)
    end
  end

  test "device types and value types never mint atoms" do
    # Warm up so lazily loaded modules (DateTime, Inspect, ...) do not count
    :ok =
      SharedProfiles.store_profile(
        "warm_up_type",
        %{"1.3.6.1.4.1.9.9.1.0" => %{type: "WarmUp", value: "x"}},
        %{}
      )

    {:ok, _} = SharedProfiles.get_oid_value("warm_up_type", "1.3.6.1.4.1.9.9.1.0", %{})

    before = :erlang.system_info(:atom_count)
    unique = "device_type_#{System.unique_integer([:positive])}"

    profile = %{
      "1.3.6.1.4.1.9.9.1.0" => %{
        type: "WeirdVendorType#{System.unique_integer([:positive])}",
        value: "x"
      }
    }

    :ok = SharedProfiles.store_profile(unique, profile, %{})

    assert {:ok, {:octet_string, "x"}} =
             SharedProfiles.get_oid_value(unique, "1.3.6.1.4.1.9.9.1.0", %{})

    # Allow a small tolerance for atoms created by unrelated code paths
    assert :erlang.system_info(:atom_count) - before < 5
    assert unique in SharedProfiles.list_profiles()
  end

  test "clear_all_profiles deletes the tables" do
    :ok = SharedProfiles.store_profile(:sp_clear, @profile, %{})
    tables = :ets.lookup(:snmp_sim_profile_registry, :sp_clear) |> hd() |> elem(1)
    assert is_list(:ets.info(tables.profile))

    :ok = SharedProfiles.clear_all_profiles()

    assert :ets.info(tables.profile) == :undefined
    assert :ets.info(tables.index) == :undefined
    assert {:error, :device_type_not_found} = SharedProfiles.get_next_oid(:sp_clear, "1.3")
    assert SharedProfiles.list_profiles() == []
  end
end
