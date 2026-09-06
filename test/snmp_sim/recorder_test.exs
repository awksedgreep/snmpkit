defmodule SnmpKit.SnmpSim.RecorderTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.Recorder

  @scratch System.tmp_dir!()

  test "renders every value type in net-snmp's numeric walk format" do
    assert Recorder.line(%{oid: "1.3.6.1.2.1.1.1.0", type: :octet_string, value: "Router"}) ==
             ".1.3.6.1.2.1.1.1.0 = STRING: \"Router\""

    assert Recorder.line(%{
             oid: "1.3.6.1.2.1.2.2.1.6.1",
             type: :octet_string,
             value: <<0, 26, 43>>
           }) ==
             ".1.3.6.1.2.1.2.2.1.6.1 = Hex-STRING: 00 1A 2B"

    assert Recorder.line(%{
             oid: "1.3.6.1.2.1.1.2.0",
             type: :object_identifier,
             value: [1, 3, 6, 1, 4, 1, 9]
           }) ==
             ".1.3.6.1.2.1.1.2.0 = OID: .1.3.6.1.4.1.9"

    assert Recorder.line(%{
             oid: "1.3.6.1.2.1.4.20.1.1.10.0.0.1",
             type: :ip_address,
             value: <<10, 0, 0, 1>>
           }) ==
             ".1.3.6.1.2.1.4.20.1.1.10.0.0.1 = IpAddress: 10.0.0.1"

    assert Recorder.line(%{oid: "1.3.6.1.2.1.1.3.0", type: :timeticks, value: 123_456}) =~
             ~r/^\.1\.3\.6\.1\.2\.1\.1\.3\.0 = Timeticks: \(123456\) /

    assert Recorder.line(%{oid: "1.3.6.1.2.1.31.1.1.1.6.1", type: :counter64, value: 5}) ==
             ".1.3.6.1.2.1.31.1.1.1.6.1 = Counter64: 5"

    assert Recorder.line(%{oid: "1.3.6.1.2.1.1.9.0", type: :no_such_object, value: nil}) == nil
  end

  test "a recorded device replays with the same values" do
    objects = %{
      "1.3.6.1.2.1.1.1.0" => "Recorded Device",
      "1.3.6.1.2.1.1.2.0" => %{type: "OID", value: "1.3.6.1.4.1.9999.7"},
      "1.3.6.1.2.1.1.5.0" => "rec-1",
      "1.3.6.1.2.1.1.7.0" => 72,
      "1.3.6.1.2.1.2.2.1.6.1" => %{type: "Hex-STRING", value: <<0, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E>>},
      "1.3.6.1.2.1.4.20.1.1.10.0.0.1" => %{type: "IpAddress", value: "10.0.0.1"},
      "1.3.6.1.2.1.31.1.1.1.6.1" => %{type: "Counter64", value: 9_876_543_210}
    }

    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:original, {:manual, objects})
    port = 25_000 + :rand.uniform(5_000)
    {:ok, original} = SnmpKit.Sim.start_device(profile, port: port)

    path = Path.join(@scratch, "snmpkit-recorded-#{port}.walk")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, count} = SnmpKit.Sim.record("127.0.0.1:#{port}", path, timeout: 2_000)
    assert count >= map_size(objects)
    assert File.read!(path) =~ ".1.3.6.1.2.1.1.1.0 = STRING: \"Recorded Device\""
    GenServer.stop(original)

    {:ok, replay_profile} =
      SnmpKit.SnmpSim.ProfileLoader.load_profile(:replay, {:walk_file, path})

    {:ok, _replay} = SnmpKit.Sim.start_device(replay_profile, port: port + 1)
    replay = "127.0.0.1:#{port + 1}"

    assert {:ok, %{value: "Recorded Device"}} = SnmpKit.SNMP.get(replay, "1.3.6.1.2.1.1.1.0")

    assert {:ok, %{value: [1, 3, 6, 1, 4, 1, 9999, 7]}} =
             SnmpKit.SNMP.get(replay, "1.3.6.1.2.1.1.2.0")

    assert {:ok, %{value: 72}} = SnmpKit.SNMP.get(replay, "1.3.6.1.2.1.1.7.0")

    assert {:ok, %{type: :octet_string, value: <<0, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E>>}} =
             SnmpKit.SNMP.get(replay, "1.3.6.1.2.1.2.2.1.6.1")

    assert {:ok, %{type: :ip_address, value: <<10, 0, 0, 1>>}} =
             SnmpKit.SNMP.get(replay, "1.3.6.1.2.1.4.20.1.1.10.0.0.1")

    assert {:ok, %{type: :counter64, value: 9_876_543_210}} =
             SnmpKit.SNMP.get(replay, "1.3.6.1.2.1.31.1.1.1.6.1")
  end
end
