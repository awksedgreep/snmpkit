defmodule SnmpKit.SnmpMgr.AutoStartConfigTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpMgr.Config

  @moduletag :unit
  @moduletag :config

  setup do
    # Ensure a clean slate for each test
    # Stop services if running
    for name <- [SnmpKit.SnmpMgr.EngineV2, SnmpKit.SnmpMgr.SocketManager, SnmpKit.SnmpMgr.RequestIdGenerator] do
      case Process.whereis(name) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid), else: :ok
      end
    end

    # Start Config server if not running
    case GenServer.whereis(Config) do
      nil -> {:ok, _} = Config.start_link()
      _ -> :ok
    end

    on_exit(fn ->
      # Reset defaults after each test
      Config.reset()
      for name <- [SnmpKit.SnmpMgr.EngineV2, SnmpKit.SnmpMgr.SocketManager, SnmpKit.SnmpMgr.RequestIdGenerator] do
        case Process.whereis(name) do
          nil -> :ok
          pid -> if Process.alive?(pid), do: GenServer.stop(pid), else: :ok
        end
      end
    end)

    :ok
  end

  test "with auto_start_services: false, multi operations do not auto-start services" do
    Config.set_default_auto_start_services(false)

    # Sanity: ensure not running
    assert Process.whereis(SnmpKit.SnmpMgr.EngineV2) == nil
    assert Process.whereis(SnmpKit.SnmpMgr.SocketManager) == nil
    assert Process.whereis(SnmpKit.SnmpMgr.RequestIdGenerator) == nil

    # Run a no-op multi call (empty list) to avoid network, but would auto-start if enabled
    _ = SnmpKit.SnmpMgr.MultiV2.get_multi([])

    # Should still be not running
    assert Process.whereis(SnmpKit.SnmpMgr.EngineV2) == nil
    assert Process.whereis(SnmpKit.SnmpMgr.SocketManager) == nil
    assert Process.whereis(SnmpKit.SnmpMgr.RequestIdGenerator) == nil
  end

  test "ensure_started/0 explicitly starts services" do
    Config.set_default_auto_start_services(false)

    # Explicit start
    :ok = SnmpKit.SnmpMgr.ensure_started()

    # Verify
    assert is_pid(Process.whereis(SnmpKit.SnmpMgr.EngineV2))
    assert is_pid(Process.whereis(SnmpKit.SnmpMgr.SocketManager))
    assert is_pid(Process.whereis(SnmpKit.SnmpMgr.RequestIdGenerator))
  end

  test "with auto_start_services: true, multi operations auto-start services" do
    Config.set_default_auto_start_services(true)

    # Ensure stopped first
    for name <- [SnmpKit.SnmpMgr.EngineV2, SnmpKit.SnmpMgr.SocketManager, SnmpKit.SnmpMgr.RequestIdGenerator] do
      case Process.whereis(name) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid), else: :ok
      end
    end

    # Trigger auto-start via no-op call
    _ = SnmpKit.SnmpMgr.MultiV2.get_multi([])

    # Should be running now
    assert is_pid(Process.whereis(SnmpKit.SnmpMgr.EngineV2))
    assert is_pid(Process.whereis(SnmpKit.SnmpMgr.SocketManager))
    assert is_pid(Process.whereis(SnmpKit.SnmpMgr.RequestIdGenerator))
  end
end
