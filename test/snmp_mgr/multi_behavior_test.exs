defmodule SnmpKit.SnmpMgr.MultiBehaviorTest do
  use ExUnit.Case, async: false

  @moduletag :unit

  describe "Concurrent Multi defaults and auto-ensure" do
    test "default multi auto-ensures concurrent engine components" do
      # Trigger a simple multi call; components should be ensured automatically
      _ = SnmpKit.SnmpMgr.get_multi([{"invalid.host.test", "sysDescr.0"}], timeout: 50)

      assert Process.whereis(SnmpKit.SnmpMgr.RequestIdGenerator)
      assert Process.whereis(SnmpKit.SnmpMgr.SocketManager)
      assert Process.whereis(SnmpKit.SnmpMgr.EngineV2)
    end

    test "default strategy is :concurrent (EngineV2), returns list of results" do
      results = SnmpKit.SnmpMgr.get_multi([{"invalid.host.test", "sysDescr.0"}], timeout: 50)
      assert Process.whereis(SnmpKit.SnmpMgr.EngineV2)

      assert is_list(results)
      assert length(results) == 1

      case hd(results) do
        {:ok, %{oid: _oid, type: _type, value: _value}} -> :ok
        {:error, _reason} -> :ok
        other -> flunk("unexpected result: #{inspect(other)}")
      end
    end

    test "strategy: :simple uses legacy multi engine and returns list of results" do
      results =
        SnmpKit.SnmpMgr.get_multi(
          [{"invalid.host.test", "sysDescr.0"}],
          timeout: 50,
          strategy: :simple
        )

      # Legacy engine should be started by legacy path
      assert Process.whereis(SnmpKit.SnmpMgr.Engine)

      assert is_list(results)
      assert length(results) == 1

      case hd(results) do
        {:ok, %{oid: _oid, type: _type, value: _value}} -> :ok
        {:error, _reason} -> :ok
        other -> flunk("unexpected result: #{inspect(other)}")
      end
    end

    test "return_format :with_targets and :map are consistent" do
      reqs = [{"invalid.host.test", "sysUpTime.0"}]

      with_targets = SnmpKit.SnmpMgr.get_multi(reqs, timeout: 50, return_format: :with_targets)
      assert [{host, oid, res}] = with_targets
      assert is_binary(host)
      assert is_binary(oid) or is_list(oid)

      case res do
        {:ok, %{oid: _oid, type: _type, value: _value}} -> :ok
        {:error, _reason} -> :ok
        other -> flunk("unexpected with_targets result: #{inspect(other)}")
      end

      map_res = SnmpKit.SnmpMgr.get_multi(reqs, timeout: 50, return_format: :map)
      assert is_map(map_res)
      [{ {host2, oid2}, res2 }] = Map.to_list(map_res)
      assert is_binary(host2)
      assert is_binary(oid2) or is_list(oid2)
      case res2 do
        {:ok, %{oid: _oid, type: _type, value: _value}} -> :ok
        {:error, _reason} -> :ok
        other -> flunk("unexpected map result: #{inspect(other)}")
      end
    end

    test "auto-ensure is idempotent" do
      _ = SnmpKit.SnmpMgr.get_multi([{"invalid.host.test", "sysName.0"}], timeout: 50)
      pid1 = Process.whereis(SnmpKit.SnmpMgr.EngineV2)
      assert is_pid(pid1)

      _ = SnmpKit.SnmpMgr.get_multi([{"invalid.host.test", "sysName.0"}], timeout: 50)
      pid2 = Process.whereis(SnmpKit.SnmpMgr.EngineV2)
      assert pid1 == pid2
    end

    test "get_bulk_multi defaults to concurrent strategy" do
      results =
        SnmpKit.SnmpMgr.get_bulk_multi([{"invalid.host.test", "ifTable"}],
          timeout: 50,
          max_repetitions: 5
        )

      assert Process.whereis(SnmpKit.SnmpMgr.EngineV2)
      assert is_list(results)
      assert length(results) == 1
      case hd(results) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
        other -> flunk("unexpected get_bulk_multi result: #{inspect(other)}")
      end
    end

    test "walk_multi defaults to concurrent strategy" do
      results = SnmpKit.SnmpMgr.walk_multi([{"invalid.host.test", "system"}], timeout: 50)

      assert Process.whereis(SnmpKit.SnmpMgr.EngineV2)
      assert is_list(results)
      assert length(results) == 1
      case hd(results) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
        other -> flunk("unexpected walk_multi result: #{inspect(other)}")
      end
    end
  end
end

