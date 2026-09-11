defmodule SnmpKit.SnmpSim.DeviceDynamicsTest do
  # What a device started through the public API does over time and on the
  # wire: counters with a behavior advance, update_counter/3 builds on the
  # profile value and wraps, port 0 is reported as the bound port, and the
  # bundled walks parse into distinct objects.
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.{Device, ProfileLoader, WalkParser}

  @if_in_octets "1.3.6.1.2.1.2.2.1.10.1"

  defp start_walk_device do
    {:ok, profile} =
      ProfileLoader.load_profile(
        :cable_modem,
        {:walk_file, ProfileLoader.bundled_walk(:cable_modem)}
      )

    {:ok, device} = SnmpKit.Sim.start_device(profile, port: 0)
    %{port: port} = Device.get_info(device)
    on_exit(fn -> if Process.alive?(device), do: SnmpKit.Sim.stop_device(device) end)
    {device, "127.0.0.1:#{port}"}
  end

  defp get_value(target, oid) do
    {:ok, %{value: value}} = SnmpKit.SNMP.get(target, oid, timeout: 2000)
    value
  end

  describe "values over time" do
    test "a counter with a behavior advances between polls, and walks agree with GETs" do
      {_device, target} = start_walk_device()

      first = get_value(target, "ifInOctets.1")
      Process.sleep(1100)
      second = get_value(target, "ifInOctets.1")
      assert second > first

      {:ok, walked} = SnmpKit.SNMP.walk(target, "ifInOctets", timeout: 2000)
      %{value: from_walk} = Enum.find(walked, &(&1.oid == @if_in_octets))
      assert from_walk >= second

      # Objects without a behavior keep their profile value.
      assert get_value(target, "sysDescr.0") == get_value(target, "sysDescr.0")
    end

    test "update_counter/3 starts from the profile value and wraps like a Counter32" do
      {:ok, profile} =
        ProfileLoader.load_profile(
          :custom,
          {:manual, %{@if_in_octets => %{type: "Counter32", value: 4_294_967_000}}}
        )

      {:ok, device} = SnmpKit.Sim.start_device(profile, port: 0)
      %{port: port} = Device.get_info(device)
      target = "127.0.0.1:#{port}"

      :ok = Device.update_counter(device, @if_in_octets, 100)
      assert get_value(target, @if_in_octets) == 4_294_967_100

      :ok = Device.update_counter(device, @if_in_octets, 1_000)
      # 4_294_968_100 - 2^32
      assert get_value(target, @if_in_octets) == 804

      SnmpKit.Sim.stop_device(device)
    end
  end

  describe "ports" do
    test "a device started on port 0 reports the port it was given" do
      {device, target} = start_walk_device()
      %{port: port} = Device.get_info(device)

      assert port > 0
      assert target == "127.0.0.1:#{port}"
      assert is_binary(get_value(target, "sysDescr.0"))
    end
  end

  describe "bundled walks" do
    test "IP-MIB objects in the router walk parse to their own OIDs" do
      {:ok, oid_map} = WalkParser.parse_walk_file(ProfileLoader.bundled_walk(:router))

      # ipForwarding.0, ipInReceives.0 and friends used to collapse onto 1.3.6.1.2.1.4.1.0
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.4.1.0")
      assert Map.has_key?(oid_map, "1.3.6.1.2.1.4.3.0")
      assert %{type: "Counter32"} = oid_map["1.3.6.1.2.1.4.3.0"]
      assert %{type: "INTEGER"} = oid_map["1.3.6.1.2.1.4.1.0"]

      lines =
        ProfileLoader.bundled_walk(:router)
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.count(&String.contains?(&1, " = "))

      assert map_size(oid_map) == lines
    end
  end
end
