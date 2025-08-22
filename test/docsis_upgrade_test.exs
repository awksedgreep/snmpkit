defmodule SnmpKit.DocsisUpgradeTest do
  use ExUnit.Case, async: false

  alias SnmpKit.TestSupport.SNMPSimulator
  alias SnmpKit.SnmpMgr

  @server_oid   [1,3,6,1,2,1,69,1,3,3,0]
  @filename_oid [1,3,6,1,2,1,69,1,3,4,0]
  @admin_oid    [1,3,6,1,2,1,69,1,3,1,0]
  @oper_oid     [1,3,6,1,2,1,69,1,3,2,0]

  setup do
    {:ok, device} = SNMPSimulator.create_test_device()
    on_exit(fn -> SNMPSimulator.stop_device(device) end)
    :ok = SNMPSimulator.wait_for_device_ready(device)
    %{device: device, target: SNMPSimulator.device_target(device), community: device.community}
  end

  test "happy path: server+filename then trigger leads to completeFromMgt(3)",
       %{target: target, community: community} do
    # Prime server and filename
    assert {:ok, _} = SnmpMgr.set(target, @server_oid, "10.0.0.5", community: community, version: :v2c)
    assert {:ok, _} = SnmpMgr.set(target, @filename_oid, "cm-fw-1.2.3.bin", community: community, version: :v2c)

    # Trigger upgradeFromMgt(1)
    assert {:ok, _} = SnmpMgr.set(target, @admin_oid, 1, community: community, version: :v2c)

    # Poll oper status until completeFromMgt(3) or timeout
    final =
      1..30
      |> Enum.reduce_while(:unknown, fn _i, _acc ->
        Process.sleep(200)
        case SnmpMgr.get_with_type(target, @oper_oid, community: community, version: :v2c) do
          {:ok, {_oid, _type, 3}} -> {:halt, :complete}
          {:ok, _} -> {:cont, :waiting}
          _ -> {:cont, :waiting}
        end
      end)

    assert final == :complete
  end

  test "minimal error: trigger without priming returns an error", %{target: target, community: community} do
    # Attempt to trigger without server/filename set
    res = SnmpMgr.set(target, @admin_oid, 1, community: community, version: :v2c)
    assert match?({:error, _}, res)
  end
end
