defmodule SnmpKit.SNMPv3EndToEndTest do
  @moduledoc "Manager <-> simulated agent over SNMPv3 (USM), every security level."
  use ExUnit.Case, async: false

  @users [
    %{name: "guest"},
    %{name: "md5user", auth: :md5, auth_password: "md5-auth-pass"},
    %{name: "sha1user", auth: :sha1, auth_password: "sha1-auth-pass"},
    %{name: "sha256user", auth: :sha256, auth_password: "sha256-auth-pass"},
    %{name: "sha512user", auth: :sha512, auth_password: "sha512-auth-pass"},
    %{
      name: "desuser",
      auth: :sha1,
      auth_password: "des-auth-pass",
      priv: :des,
      priv_password: "des-priv-pass"
    },
    %{
      name: "aes128user",
      auth: :sha256,
      auth_password: "aes-auth-pass",
      priv: :aes128,
      priv_password: "aes-priv-pass"
    },
    %{
      name: "aes192user",
      auth: :sha256,
      auth_password: "aes-auth-pass",
      priv: :aes192,
      priv_password: "aes-priv-pass"
    },
    %{
      name: "aes256user",
      auth: :sha512,
      auth_password: "aes-auth-pass",
      priv: :aes256,
      priv_password: "aes-priv-pass"
    }
  ]

  setup_all do
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    port = 28_000 + :rand.uniform(5_000)

    {:ok, device} =
      SnmpKit.Sim.start_device(profile, port: port, v3_users: @users, device_id: "v3-router")

    on_exit(fn -> if Process.alive?(device), do: GenServer.stop(device) end)
    SnmpKit.SnmpLib.Security.EngineCache.clear()
    %{target: "127.0.0.1:#{port}", port: port}
  end

  defp v3(user) do
    spec = Enum.find(@users, &(&1.name == user))

    [version: :v3, security_name: user, timeout: 2_000]
    |> Keyword.merge(
      if spec[:auth], do: [auth_protocol: spec.auth, auth_password: spec.auth_password], else: []
    )
    |> Keyword.merge(
      if spec[:priv], do: [priv_protocol: spec.priv, priv_password: spec.priv_password], else: []
    )
  end

  test "engine discovery returns the device's engine id", %{port: port} do
    assert {:ok, engine_id} =
             SnmpKit.SnmpLib.Security.USM.discover_engine("127.0.0.1", port: port, timeout: 2_000)

    assert engine_id == SnmpKit.SnmpSim.Core.UsmAgent.derive_engine_id("v3-router")
  end

  test "noAuthNoPriv", %{target: target} do
    assert {:ok, %{name: "sysDescr.0", value: value}} =
             SnmpKit.SNMP.get(target, "sysDescr.0", v3("guest"))

    assert is_binary(value)
  end

  for user <- ["md5user", "sha1user", "sha256user", "sha512user"] do
    test "authNoPriv with #{user}", %{target: target} do
      assert {:ok, %{name: "sysName.0"}} =
               SnmpKit.SNMP.get(target, "sysName.0", v3(unquote(user)))
    end
  end

  for user <- ["desuser", "aes128user", "aes192user", "aes256user"] do
    test "authPriv with #{user}", %{target: target} do
      assert {:ok, %{name: "sysDescr.0", value: value}} =
               SnmpKit.SNMP.get(target, "sysDescr.0", v3(unquote(user)))

      assert is_binary(value)
    end
  end

  test "walks, bulk walks and multi-object gets work over authPriv", %{target: target} do
    assert {:ok, rows} = SnmpKit.SNMP.walk(target, "system", v3("aes128user"))
    assert length(rows) > 3
    assert {:ok, bulk} = SnmpKit.SNMP.bulk_walk(target, "interfaces", v3("aes256user"))
    assert length(bulk) > 5

    assert {:ok, [%{name: "sysDescr.0"}, %{name: "sysUpTime.0"}]} =
             SnmpKit.SNMP.get(target, ["sysDescr.0", "sysUpTime.0"], v3("desuser"))
  end

  test "a wrong password is rejected with a wrongDigests report", %{target: target} do
    opts = Keyword.merge(v3("sha256user"), auth_password: "not-the-password", retries: 0)

    assert {:error, {:usm_report, :usm_stats_wrong_digests}} =
             SnmpKit.SNMP.get(target, "sysDescr.0", opts)
  end

  test "a wrong privacy password fails", %{target: target} do
    opts = Keyword.merge(v3("aes128user"), priv_password: "wrong-priv-pass", retries: 0)
    assert {:error, _} = SnmpKit.SNMP.get(target, "sysDescr.0", opts)
  end

  test "an unknown user is rejected with an unknownUserNames report", %{target: target} do
    opts = [version: :v3, security_name: "nobody", timeout: 1_000, retries: 0]

    assert {:error, {:usm_report, :usm_stats_unknown_user_names}} =
             SnmpKit.SNMP.get(target, "sysDescr.0", opts)
  end

  test "a request below the user's security level is refused", %{target: target} do
    opts = [version: :v3, security_name: "aes128user", timeout: 1_000, retries: 0]

    assert {:error, {:usm_report, :usm_stats_unsupported_sec_levels}} =
             SnmpKit.SNMP.get(target, "sysDescr.0", opts)
  end

  test "time synchronisation recovers after the cache goes stale", %{target: target, port: port} do
    key = {{127, 0, 0, 1}, port}

    entry =
      SnmpKit.SnmpLib.Security.EngineCache.lookup(key) ||
        (SnmpKit.SNMP.get(target, "sysDescr.0", v3("sha256user")) &&
           SnmpKit.SnmpLib.Security.EngineCache.lookup(key))

    # pretend the agent's clock is 10 minutes ahead of what we remember
    SnmpKit.SnmpLib.Security.EngineCache.store(key, entry.engine_id, entry.engine_boots, 100_000)
    assert {:ok, %{name: "sysDescr.0"}} = SnmpKit.SNMP.get(target, "sysDescr.0", v3("sha256user"))
  end

  test "v3 is refused by a device without users and the community path still works", %{
    target: target
  } do
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:switch)
    port = 33_000 + :rand.uniform(2_000)
    {:ok, plain} = SnmpKit.Sim.start_device(profile, port: port)
    on_exit(fn -> if Process.alive?(plain), do: GenServer.stop(plain) end)

    assert {:error, :timeout} =
             SnmpKit.SNMP.get("127.0.0.1:#{port}", "sysDescr.0",
               version: :v3,
               security_name: "guest",
               timeout: 300,
               retries: 0
             )

    assert {:ok, _} = SnmpKit.SNMP.get(target, "sysDescr.0", timeout: 2_000)
  end
end
