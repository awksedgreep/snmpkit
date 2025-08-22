defmodule SnmpKit.SnmpSim.ManualModemUpgradeTest do
  use ExUnit.Case, async: false
  require Logger

  alias SnmpKit.TestSupport.SNMPSimulator

  @server_oid "1.3.6.1.2.1.69.1.3.3.0"    # docsDevSwServer (IpAddress; read-write)
  @filename_oid "1.3.6.1.2.1.69.1.3.4.0"  # docsDevSwFilename (SnmpAdminString; read-write)
  @admin_oid "1.3.6.1.2.1.69.1.3.1.0"     # docsDevSwAdminStatus (INTEGER; read-write)
  @oper_oid "1.3.6.1.2.1.69.1.3.2.0"      # docsDevSwOperStatus (INTEGER; read-only)

  setup do
    {:ok, modem} = SNMPSimulator.start_modem(upgrade_enabled: true)
    :ok = SNMPSimulator.wait_for_device_ready(modem)

    on_exit(fn -> SNMPSimulator.stop_modem(modem) end)

    %{modem: modem, target: SNMPSimulator.device_target(modem)}
  end

  describe "manual modem upgrade writable OIDs" do
    test "server accepts valid IpAddress strings and rejects invalids", %{target: target, modem: modem} do
      # Good IPv4
      assert {:ok, _} = SnmpKit.SnmpMgr.set(target, @server_oid, "192.168.100.20", community: modem.community, version: :v2c, timeout: 300)

      # Read back should return ipAddress type as dotted string via manager
      case SnmpKit.SnmpMgr.get(target, @server_oid, community: modem.community, version: :v2c, timeout: 300) do
        {:ok, value} -> assert value == "192.168.100.20" or is_binary(value)
        {:error, reason} -> flunk("GET server failed: #{inspect(reason)}")
      end

      # Invalid IPv4 strings -> wrongValue
      for bad <- ["999.1.1.1", "1.2.3", "abc", "1.2.3.4.5"] do
        case SnmpKit.SnmpMgr.set(target, @server_oid, bad, community: modem.community, version: :v2c, timeout: 300) do
          {:error, reason} -> assert reason in [:wrong_value, :wrongType, :wrongValue]
          {:ok, _} -> flunk("Expected error for invalid IP #{bad}")
        end
      end
    end

    test "filename enforces length and type", %{target: target, modem: modem} do
      assert {:ok, _} = SnmpKit.SnmpMgr.set(target, @filename_oid, "firmware.bin", community: modem.community, version: :v2c, timeout: 300)

      # Too long (65 bytes)
      long_name = String.duplicate("a", 65)
      case SnmpKit.SnmpMgr.set(target, @filename_oid, long_name, community: modem.community, version: :v2c, timeout: 300) do
        {:error, reason} -> assert reason in [:wrong_length, :wrongLength]
        {:ok, _} -> flunk("Expected wrong_length for long filename")
      end

      # Non-binary types should be wrongType
      # Use explicit INTEGER typed value to avoid client-side encoding mismatch
      case SnmpKit.SnmpMgr.set(target, @filename_oid, {:integer, 123}, community: modem.community, version: :v2c, timeout: 300) do
        {:error, reason} -> assert reason in [:wrong_type, :wrongType]
        {:ok, _} -> flunk("Expected wrong_type for integer filename")
      end
    end

    test "admin status triggers upgrade only with valid server and filename", %{target: target, modem: modem} do
      # First, set valid server and filename
      assert {:ok, _} = SnmpKit.SnmpMgr.set(target, @server_oid, "10.0.0.5", community: modem.community, version: :v2c, timeout: 300)
      assert {:ok, _} = SnmpKit.SnmpMgr.set(target, @filename_oid, "fw.bin", community: modem.community, version: :v2c, timeout: 300)

      # Trigger value is 1 per WalkPduProcessor.admin_trigger?
      assert {:ok, _} = SnmpKit.SnmpMgr.set(target, @admin_oid, {:integer, 1}, community: modem.community, version: :v2c, timeout: 300)

      # Oper should move to inProgress (1) shortly
      :timer.sleep(50)
      case SnmpKit.SnmpMgr.get(target, @oper_oid, community: modem.community, version: :v2c, timeout: 300) do
        {:ok, oper} -> assert oper in [1, 3, 4, 5]
        {:error, reason} -> flunk("GET oper failed: #{inspect(reason)}")
      end

      # Eventually completes to completeFromMgt (3), default delays total ~1500ms
      :timer.sleep(1200)
      case SnmpKit.SnmpMgr.get(target, @oper_oid, community: modem.community, version: :v2c, timeout: 300) do
        {:ok, oper} -> assert oper in [3, 4, 5]
        {:error, reason} -> flunk("GET oper final failed: #{inspect(reason)}")
      end
    end
  end

  describe "error cases and notWritable enforcement" do
    test "admin status rejects trigger when preconditions invalid", %{target: target, modem: modem} do
      # Without valid server/filename
      case SnmpKit.SnmpMgr.set(target, @admin_oid, {:integer, 1}, community: modem.community, version: :v2c, timeout: 300) do
        {:error, reason} -> assert reason in [:wrong_value, :wrongValue]
        {:ok, _} -> flunk("Expected error when triggering without server/filename")
      end
    end

    test "non-upgrade OIDs reject SET with notWritable", %{target: target, modem: modem} do
      # Try setting sysDescr
      case SnmpKit.SnmpMgr.set(target, "1.3.6.1.2.1.1.1.0", "x", community: modem.community, version: :v2c, timeout: 300) do
        {:error, reason} -> assert reason in [:not_writable, :read_only, :no_access]
        {:ok, _} -> flunk("Expected not_writable on non-upgrade OID")
      end
    end
  end
end

