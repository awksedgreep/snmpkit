defmodule SnmpKit.SNMP.RateTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SNMP.Rate

  doctest Rate

  defp vb(oid, type, value, name \\ nil),
    do: %{
      oid: oid,
      oid_list: oid |> String.split(".") |> Enum.map(&String.to_integer/1),
      type: type,
      value: value,
      name: name
    }

  test "counter32 and counter64 deltas wrap" do
    assert {:ok, 1296} = Rate.delta({:counter32, 4_294_967_000}, {:counter32, 1_000})
    assert {:ok, 1} = Rate.delta({:counter32, 4_294_967_295}, {:counter32, 0})
    assert {:ok, 11} = Rate.delta({:counter64, 18_446_744_073_709_551_610}, {:counter64, 5})
    assert {:ok, 500} = Rate.delta({:counter64, 100}, {:counter64, 600})
  end

  test "gauges and integers are plain differences, bare integers need a type" do
    assert {:ok, -30} = Rate.delta({:gauge32, 50}, {:gauge32, 20})
    assert {:ok, 7} = Rate.delta(3, 10, type: :integer)
    assert {:error, :type_required} = Rate.delta(3, 10)
    assert {:error, :type_mismatch} = Rate.delta({:counter32, 1}, {:gauge32, 2})
    assert {:error, {:not_a_sample, "x"}} = Rate.delta("x", {:gauge32, 2})
  end

  test "rate is per second" do
    assert {:ok, 100.0} = Rate.rate({:counter32, 100}, {:counter32, 1_100}, 10_000)
    assert {:ok, rate} = Rate.rate({:counter32, 4_294_967_000}, {:counter32, 1_000}, 1_000)
    assert_in_delta rate, 1296.0, 0.001
    assert {:error, :invalid_interval} = Rate.rate({:counter32, 1}, {:counter32, 2}, 0)
  end

  test "rates pairs walks by OID and reads the interval from sysUpTime" do
    t0 = [
      vb("1.3.6.1.2.1.1.3.0", :timeticks, 1_000, "sysUpTime.0"),
      vb("1.3.6.1.2.1.2.2.1.10.1", :counter32, 4_294_967_000, "ifInOctets.1"),
      vb("1.3.6.1.2.1.2.2.1.16.1", :counter32, 500, "ifOutOctets.1"),
      vb("1.3.6.1.2.1.2.2.1.2.1", :octet_string, "eth0", "ifDescr.1")
    ]

    t1 = [
      vb("1.3.6.1.2.1.1.3.0", :timeticks, 2_000, "sysUpTime.0"),
      vb("1.3.6.1.2.1.2.2.1.10.1", :counter32, 1_000, "ifInOctets.1"),
      vb("1.3.6.1.2.1.2.2.1.16.1", :counter32, 1_500, "ifOutOctets.1"),
      vb("1.3.6.1.2.1.2.2.1.10.2", :counter32, 9, "ifInOctets.2")
    ]

    assert {:ok, results} = Rate.rates(t0, t1)

    # sysUpTime (timeticks) and ifDescr (string) are not rated; ifInOctets.2 has no previous sample
    assert length(results) == 2

    assert %{
             name: "ifInOctets.1",
             delta: 1296,
             rate: 129.6,
             previous: 4_294_967_000,
             current: 1_000
           } =
             Enum.find(results, &(&1.name == "ifInOctets.1"))

    assert %{name: "ifOutOctets.1", delta: 1000, rate: 100.0} =
             Enum.find(results, &(&1.name == "ifOutOctets.1"))

    refute Enum.any?(results, &(&1.name == "ifInOctets.2"))
  end

  test "rates detects a device restart and needs an interval" do
    t0 = [
      vb("1.3.6.1.2.1.1.3.0", :timeticks, 5_000),
      vb("1.3.6.1.2.1.2.2.1.10.1", :counter32, 100)
    ]

    t1 = [vb("1.3.6.1.2.1.1.3.0", :timeticks, 400), vb("1.3.6.1.2.1.2.2.1.10.1", :counter32, 50)]

    assert {:error, :device_restarted} = Rate.rates(t0, t1)
    assert {:ok, [%{delta: 4_294_967_246}]} = Rate.rates(tl(t0), tl(t1), interval_ms: 1_000)
    assert {:error, :no_interval} = Rate.rates(tl(t0), tl(t1))
  end
end
