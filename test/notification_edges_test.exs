defmodule SnmpKit.NotificationEdgesTest do
  # Notifications never go out as a version other than the one asked for,
  # the receiver counts handlers that raise, and an engine timeout names its
  # target.
  use ExUnit.Case, async: false

  test "send_trap and send_inform refuse versions other than v1 and v2c" do
    assert {:error, {:unsupported_operation, :notification_requires_v1_or_v2c}} =
             SnmpKit.SNMP.send_trap("127.0.0.1:1", "coldStart", [], version: :v3)

    assert {:error, {:unsupported_operation, :notification_requires_v1_or_v2c}} =
             SnmpKit.SNMP.send_inform("127.0.0.1:1", "coldStart", [], version: :v3, timeout: 50)

    assert {:error, {:unsupported_operation, :inform_requires_v2c}} =
             SnmpKit.SNMP.send_inform("127.0.0.1:1", "coldStart", [], version: :v1)
  end

  test "a raising handler is counted in the receiver's handler_errors" do
    test_pid = self()

    handler = fn _notification ->
      send(test_pid, :handler_called)
      raise "boom"
    end

    {:ok, receiver} =
      SnmpKit.Trap.start_link(port: 0, bind_address: "127.0.0.1", handler: handler)

    port = SnmpKit.Trap.port(receiver)

    :ok = SnmpKit.SNMP.send_trap("127.0.0.1:#{port}", "coldStart")
    assert_receive :handler_called, 2000

    assert eventually(fn -> SnmpKit.Trap.stats(receiver).handler_errors == 1 end)
    GenServer.stop(receiver)
  end

  test "an engine timeout event carries the target it was registered with" do
    :ok = SnmpKit.SnmpMgr.ensure_started()
    handler_id = {__MODULE__, :timeout_target}
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:snmpkit, :engine, :timeout],
      fn _event, _measurements, metadata, _config ->
        send(test_pid, {:timeout_event, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, request_id} =
      SnmpKit.SnmpMgr.Engine.register_next_request(SnmpKit.SnmpMgr.Engine, self(), 20,
        target: %{host: "192.0.2.1", port: 161}
      )

    assert_receive {:snmp_timeout, ^request_id}, 1000

    assert_receive {:timeout_event, %{request_id: ^request_id, target: %{host: "192.0.2.1"}}},
                   1000
  end

  defp eventually(fun, attempts \\ 20) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(50) && eventually(fun, attempts - 1)
    end
  end
end
