defmodule SnmpKit.TelemetryTest do
  use ExUnit.Case, async: false

  @events [
    [:snmpkit, :request, :start],
    [:snmpkit, :request, :stop],
    [:snmpkit, :walk, :stop],
    [:snmpkit, :multi, :stop],
    [:snmpkit, :engine, :timeout],
    [:snmpkit, :trap, :received],
    [:snmpkit, :trap, :rejected],
    [:snmpkit, :sim, :request]
  ]

  setup do
    test_pid = self()
    id = "telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      id,
      @events,
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    port = 20_000 + :rand.uniform(20_000)
    {:ok, _device} = SnmpKit.Sim.start_device(profile, port: port, device_id: "telemetry-router")
    %{target: "127.0.0.1:#{port}"}
  end

  test "single-target requests are spanned with operation, target and result", %{target: target} do
    {:ok, _} = SnmpKit.SNMP.get(target, "sysDescr.0")

    assert_receive {:telemetry, [:snmpkit, :request, :start], %{system_time: _},
                    %{operation: :get, target: ^target}}

    assert_receive {:telemetry, [:snmpkit, :request, :stop], %{duration: d},
                    %{operation: :get, result: :ok, oid: "sysDescr.0"}}

    assert is_integer(d)
  end

  test "failed requests carry the reason" do
    {:error, :timeout} = SnmpKit.SNMP.get("127.0.0.1:1", "sysDescr.0", timeout: 100, retries: 0)

    assert_receive {:telemetry, [:snmpkit, :request, :stop], _,
                    %{result: :error, reason: :timeout}}
  end

  test "walks report the varbind count", %{target: target} do
    {:ok, rows} = SnmpKit.SNMP.walk(target, "system")
    count = length(rows)

    assert_receive {:telemetry, [:snmpkit, :walk, :stop], _,
                    %{operation: :walk, result: :ok, count: ^count}}

    {:ok, _} = SnmpKit.SNMP.bulk_walk(target, "system")

    assert_receive {:telemetry, [:snmpkit, :walk, :stop], _,
                    %{operation: :bulk_walk, result: :ok}}
  end

  test "multi-target calls report ok and error counts", %{target: target} do
    _ =
      SnmpKit.SNMP.get_multi([
        {target, "sysDescr.0"},
        {"127.0.0.1:1", "sysDescr.0", timeout: 100, retries: 0}
      ])

    assert_receive {:telemetry, [:snmpkit, :multi, :stop], _,
                    %{operation: :get, request_count: 2, ok_count: 1, error_count: 1}},
                   3_000

    assert_receive {:telemetry, [:snmpkit, :engine, :timeout], %{count: 1}, %{request_id: _}},
                   3_000
  end

  test "trap receiver emits received and rejected events" do
    {:ok, receiver} =
      SnmpKit.Trap.start_link(port: 0, bind_address: "127.0.0.1", communities: ["ok"])

    on_exit(fn -> if Process.alive?(receiver), do: SnmpKit.Trap.stop(receiver) end)
    target = "127.0.0.1:#{SnmpKit.Trap.port(receiver)}"

    :ok = SnmpKit.SNMP.send_trap(target, "linkDown", [], community: "ok")

    assert_receive {:telemetry, [:snmpkit, :trap, :received], %{count: 1},
                    %{kind: :trap, trap_name: "linkDown", community: "ok"}},
                   2_000

    :ok = SnmpKit.SNMP.send_trap(target, "linkDown", [], community: "bad")

    assert_receive {:telemetry, [:snmpkit, :trap, :rejected], %{count: 1}, %{reason: :community}},
                   2_000
  end

  test "simulated devices time each request they answer", %{target: target} do
    {:ok, _} = SnmpKit.SNMP.get(target, "sysName.0")

    assert_receive {:telemetry, [:snmpkit, :sim, :request], %{duration: _},
                    %{device_id: "telemetry-router", pdu_type: :get_request, result: :ok}}
  end
end
