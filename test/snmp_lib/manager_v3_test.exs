defmodule SnmpKit.SnmpLib.ManagerV3Test do
  @moduledoc """
  The manager's SNMPv3 request path off the happy path: option validation,
  the explicit `engine_id:` option, and an agent that never lets the manager
  synchronise.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpLib.PDU.V3Encoder
  alias SnmpKit.SnmpLib.Security.EngineCache
  alias SnmpKit.SNMP

  @user %{name: "ops", auth: :sha256, auth_password: "ops-auth-secret"}
  @usm_stats [1, 3, 6, 1, 6, 3, 15, 1, 1]

  setup_all do
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    port = 32_000 + :rand.uniform(2_000)

    {:ok, device} =
      SnmpKit.Sim.start_device(profile, port: port, v3_users: [@user], device_id: "manager-v3")

    on_exit(fn -> if Process.alive?(device), do: GenServer.stop(device) end)
    %{target: "127.0.0.1:#{port}", port: port}
  end

  defp ops(extra \\ []) do
    Keyword.merge(
      [
        version: :v3,
        security_name: "ops",
        auth_protocol: :sha256,
        auth_password: "ops-auth-secret",
        timeout: 2_000,
        retries: 0
      ],
      extra
    )
  end

  describe "option validation" do
    test "a v3 request needs a security name", %{target: target} do
      assert {:error, :security_name_required} =
               SNMP.get(target, "sysDescr.0", ops() |> Keyword.delete(:security_name))

      assert {:error, :security_name_required} =
               SNMP.get(target, "sysDescr.0", ops(security_name: ""))
    end

    test "an explicit security level must be backed by protocols", %{target: target} do
      assert {:error, :priv_protocol_required} =
               SNMP.get(target, "sysDescr.0", ops(security_level: :auth_priv))

      assert {:error, :auth_protocol_required} =
               SNMP.get(
                 target,
                 "sysDescr.0",
                 ops(security_level: :auth_no_priv)
                 |> Keyword.drop([:auth_protocol, :auth_password])
               )

      assert {:error, {:invalid_security_level, :bogus}} =
               SNMP.get(target, "sysDescr.0", ops(security_level: :bogus))
    end

    test "an explicit level below the protocols given is honoured", %{target: target} do
      # the user is authNoPriv; asking noAuthNoPriv with auth options present is refused by the agent
      assert {:error, {:usm_report, :usm_stats_unsupported_sec_levels}} =
               SNMP.get(target, "sysDescr.0", ops(security_level: :no_auth_no_priv))
    end
  end

  describe "engine id" do
    test "engine_id: skips discovery and still synchronises time", %{target: target, port: port} do
      EngineCache.clear({{127, 0, 0, 1}, port})
      {:ok, engine_id} = SnmpKit.SnmpLib.Security.USM.discover_engine("127.0.0.1", port: port)
      EngineCache.clear({{127, 0, 0, 1}, port})

      assert {:ok, %{name: "sysDescr.0"}} =
               SNMP.get(target, "sysDescr.0", ops(engine_id: engine_id))

      assert %{engine_id: ^engine_id} = EngineCache.lookup({{127, 0, 0, 1}, port})
    end

    test "a wrong engine_id: is corrected by the agent's report", %{target: target, port: port} do
      EngineCache.clear({{127, 0, 0, 1}, port})

      assert {:ok, %{name: "sysDescr.0"}} =
               SNMP.get(target, "sysDescr.0", ops(engine_id: <<0x80, 0, 0, 0, 0, 4, "wrong">>))
    end
  end

  describe "an agent that never synchronises" do
    test "gives up after the report retries instead of looping", %{} do
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}, {:ip, {127, 0, 0, 1}}])
      {:ok, port} = :inet.port(socket)
      responder = spawn_link(fn -> flapping_engine(socket) end)
      :gen_udp.controlling_process(socket, responder)
      EngineCache.clear({{127, 0, 0, 1}, port})

      assert {:error, :too_many_reports} =
               SNMP.get("127.0.0.1:#{port}", "sysDescr.0", ops(timeout: 1_000))

      Process.exit(responder, :kill)
    end
  end

  # Answers every message with an unknownEngineIDs report naming a different
  # engine, so the manager can never settle on one.
  defp flapping_engine(socket) do
    case :gen_udp.recv(socket, 0, 10_000) do
      {:ok, {ip, port, packet}} ->
        {:ok, header} = V3Encoder.decode_message_header(packet)
        engine_id = <<0x80, 0, 0, 0, 0, 4>> <> :crypto.strong_rand_bytes(8)

        user = %{
          security_name: "",
          auth_protocol: :none,
          priv_protocol: :none,
          auth_key: <<>>,
          priv_key: <<>>,
          engine_id: engine_id,
          engine_boots: 1,
          engine_time: 1
        }

        message = %{
          version: 3,
          msg_id: header.msg_id,
          msg_max_size: 65_507,
          msg_flags: %{auth: false, priv: false, reportable: false},
          msg_security_model: 3,
          msg_security_parameters: <<>>,
          msg_data: %{
            context_engine_id: engine_id,
            context_name: "",
            pdu: %{
              type: :report,
              request_id: 0,
              error_status: 0,
              error_index: 0,
              varbinds: [{@usm_stats ++ [4, 0], :counter32, 1}]
            }
          }
        }

        {:ok, reply} = V3Encoder.encode_message(message, user)
        :gen_udp.send(socket, ip, port, reply)
        flapping_engine(socket)

      {:error, _} ->
        :ok
    end
  end
end
