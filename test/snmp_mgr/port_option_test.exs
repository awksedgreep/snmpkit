defmodule SnmpKit.SnmpMgr.PortOptionTest do
  @moduledoc """
  The :port option must be honoured when the target has no port of its own,
  while a port in the target string keeps winning. Several request paths used
  to overwrite the option with the default 161.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.TestSupport.SNMPSimulator

  setup_all do
    {:ok, device} = SNMPSimulator.create_test_device()
    on_exit(fn -> SNMPSimulator.stop_device(device) end)
    %{port: device.port, community: device.community}
  end

  @sys_descr "1.3.6.1.2.1.1.1.0"

  test "get, get_next, get_bulk and walk honour port:", %{port: port, community: c} do
    opts = [port: port, community: c, timeout: 2_000]

    assert {:ok, %{oid: @sys_descr, value: v}} = SnmpKit.SNMP.get("127.0.0.1", @sys_descr, opts)
    assert is_binary(v)

    assert {:ok, %{oid: @sys_descr}} = SnmpKit.SNMP.get_next("127.0.0.1", "1.3.6.1.2.1.1", opts)

    assert {:ok, [_ | _]} =
             SnmpKit.SNMP.get_bulk("127.0.0.1", "1.3.6.1.2.1.1", [{:max_repetitions, 3} | opts])

    assert {:ok, [_ | _]} = SnmpKit.SNMP.walk("127.0.0.1", "1.3.6.1.2.1.1", opts)
  end

  test "a port in the target string wins over port:", %{port: port, community: c} do
    # port: points at a closed port; the target string carries the real one
    opts = [port: port + 1, community: c, timeout: 2_000, retries: 0]
    assert {:ok, %{oid: @sys_descr}} = SnmpKit.SNMP.get("127.0.0.1:#{port}", @sys_descr, opts)

    assert {:ok, %{oid: @sys_descr}} =
             SnmpKit.SNMP.get_next("127.0.0.1:#{port}", "1.3.6.1.2.1.1", opts)
  end
end
