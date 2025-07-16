defmodule SnmpKit.SnmpLib.SNMPv3IntegrationTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpLib.PDU.V3Encoder
  alias SnmpKit.SnmpLib.Security
  alias SnmpKit.SnmpLib.Security.{Auth, Priv, Keys, USM}

  @moduletag :integration
  @moduletag :snmpv3

  describe "End-to-end SNMPv3 scenarios" do
    test "complete discovery and authentication flow" do
      # Step 1: Engine Discovery
      discovery_msg = V3Encoder.create_discovery_message(1001)
      assert {:ok, discovery_packet} = V3Encoder.encode_message(discovery_msg, nil)

      # Simulate response with engine ID
      mock_response = create_mock_discovery_response(discovery_msg.msg_id, "remote_engine_123")
      assert {:ok, decoded_response} = V3Encoder.decode_message(mock_response, nil)
      engine_id = decoded_response.msg_data.context_engine_id

      # Step 2: Create user with discovered engine
      user = create_authenticated_user(engine_id)

      # Step 3: Send authenticated request
      auth_request = create_authenticated_request(2002, user)
      assert {:ok, auth_packet} = V3Encoder.encode_message(auth_request, user)

      # Step 4: Verify we can decode our own authenticated message
      assert {:ok, decoded_auth} = V3Encoder.decode_message(auth_packet, user)
      assert decoded_auth.msg_flags.auth == true
      assert decoded_auth.msg_flags.priv == false
    end

    test "complete privacy-enabled communication flow" do
      engine_id = "secure_engine_456"
      user = create_encrypted_user(engine_id)

      # Create encrypted request
      encrypted_request = create_encrypted_request(3003, user)
      assert {:ok, encrypted_packet} = V3Encoder.encode_message(encrypted_request, user)

      # Verify encrypted packet is different from plaintext
      plaintext_request = create_authenticated_request(3003, user)
      {:ok, plaintext_packet} = V3Encoder.encode_message(plaintext_request, user)
      assert encrypted_packet != plaintext_packet
      assert byte_size(encrypted_packet) > byte_size(plaintext_packet)

      # Decode encrypted message
      assert {:ok, decoded_encrypted} = V3Encoder.decode_message(encrypted_packet, user)
      assert decoded_encrypted.msg_flags.auth == true
      assert decoded_encrypted.msg_flags.priv == true
      assert decoded_encrypted.msg_data.pdu.type == :get_request
    end

    test "cross-protocol compatibility" do
      engine_id = "compat_engine_789"

      # Test different auth/priv combinations
      test_combinations = [
        {:sha256, :aes128},
        {:sha384, :aes192},
        {:sha512, :aes256},
        {:md5, :des},
        {:sha1, :aes128}
      ]

      for {auth_proto, priv_proto} <- test_combinations do
        user = create_user_with_protocols(engine_id, auth_proto, priv_proto)
        request = create_encrypted_request(4004, user)

        assert {:ok, packet} = V3Encoder.encode_message(request, user)
        assert {:ok, decoded} = V3Encoder.decode_message(packet, user)

        assert decoded.msg_data.pdu.request_id == 4004
        assert decoded.msg_flags.auth == true
        assert decoded.msg_flags.priv == true
      end
    end

    test "bulk request with privacy" do
      engine_id = "bulk_engine_abc"
      user = create_encrypted_user(engine_id)

      # Create bulk request
      bulk_pdu = %{
        type: :get_bulk_request,
        request_id: 5005,
        error_status: 0,
        error_index: 0,
        non_repeaters: 0,
        max_repetitions: 20,
        varbinds: [
          {[1, 3, 6, 1, 2, 1, 2, 2, 1, 1], :null, :null},
          {[1, 3, 6, 1, 2, 1, 2, 2, 1, 2], :null, :null}
        ]
      }

      bulk_request = create_v3_message(5005, bulk_pdu, user, :auth_priv)

      assert {:ok, bulk_packet} = V3Encoder.encode_message(bulk_request, user)
      assert {:ok, decoded_bulk} = V3Encoder.decode_message(bulk_packet, user)

      assert decoded_bulk.msg_data.pdu.type == :get_bulk_request
      assert decoded_bulk.msg_data.pdu.non_repeaters == 0
      assert decoded_bulk.msg_data.pdu.max_repetitions == 20
      assert length(decoded_bulk.msg_data.pdu.varbinds) == 2
    end

    test "large message handling with encryption" do
      engine_id = "large_engine_def"
      user = create_encrypted_user(engine_id)

      # Create request with many varbinds
      large_varbinds =
        for i <- 1..100 do
          {[1, 3, 6, 1, 2, 1, 1, i, 0], :null, :null}
        end

      large_pdu = %{
        type: :get_request,
        request_id: 6006,
        error_status: 0,
        error_index: 0,
        varbinds: large_varbinds
      }

      large_request = create_v3_message(6006, large_pdu, user, :auth_priv)

      # Should handle large messages
      assert {:ok, large_packet} = V3Encoder.encode_message(large_request, user)
      assert byte_size(large_packet) > 1500

      assert {:ok, decoded_large} = V3Encoder.decode_message(large_packet, user)
      assert length(decoded_large.msg_data.pdu.varbinds) == 100
    end

    test "context engine and context name handling" do
      engine_id = "context_engine_ghi"
      user = create_encrypted_user(engine_id)

      # Test with different context configurations
      context_configs = [
        {"", ""},
        {"target_engine_xyz", ""},
        {"target_engine_xyz", "network_context"},
        {"", "management_context"}
      ]

      for {context_engine, context_name} <- context_configs do
        pdu = create_simple_pdu(7007)

        request = %{
          version: 3,
          msg_id: 7007,
          msg_max_size: 65507,
          msg_flags: %{auth: true, priv: true, reportable: true},
          msg_security_model: 3,
          msg_security_parameters: <<>>,
          msg_data: %{
            context_engine_id: context_engine,
            context_name: context_name,
            pdu: pdu
          }
        }

        assert {:ok, packet} = V3Encoder.encode_message(request, user)
        assert {:ok, decoded} = V3Encoder.decode_message(packet, user)

        assert decoded.msg_data.context_engine_id == context_engine
        assert decoded.msg_data.context_name == context_name
      end
    end

    test "error response handling" do
      engine_id = "error_engine_jkl"
      user = create_authenticated_user(engine_id)

      # Create error response
      error_pdu = %{
        type: :get_response,
        request_id: 8008,
        # noSuchName
        error_status: 2,
        error_index: 1,
        varbinds: [{[1, 3, 6, 1, 2, 1, 99, 99, 0], :null, :null}]
      }

      error_response = create_v3_message(8008, error_pdu, user, :auth_no_priv)

      assert {:ok, error_packet} = V3Encoder.encode_message(error_response, user)
      assert {:ok, decoded_error} = V3Encoder.decode_message(error_packet, user)

      assert decoded_error.msg_data.pdu.type == :get_response
      assert decoded_error.msg_data.pdu.error_status == 2
      assert decoded_error.msg_data.pdu.error_index == 1
    end

    test "time synchronization simulation" do
      engine_id = "time_engine_mno"

      # Simulate initial time sync request (no auth)
      sync_user = %{
        security_name: "",
        auth_protocol: :none,
        priv_protocol: :none,
        auth_key: <<>>,
        priv_key: <<>>,
        engine_id: engine_id,
        engine_boots: 0,
        engine_time: 0
      }

      time_sync_pdu = %{
        type: :get_request,
        request_id: 9009,
        error_status: 0,
        error_index: 0,
        # snmpEngineTime
        varbinds: [{[1, 3, 6, 1, 6, 3, 10, 2, 1, 3, 0], :null, :null}]
      }

      time_sync_request = create_v3_message(9009, time_sync_pdu, sync_user, :no_auth_no_priv)

      assert {:ok, sync_packet} = V3Encoder.encode_message(time_sync_request, sync_user)
      assert {:ok, decoded_sync} = V3Encoder.decode_message(sync_packet, sync_user)

      # Should be unauthenticated time sync request
      assert decoded_sync.msg_flags.auth == false
      assert decoded_sync.msg_flags.priv == false
      assert decoded_sync.msg_data.pdu.varbinds == time_sync_pdu.varbinds
    end

    test "reportable flag handling" do
      engine_id = "report_engine_pqr"
      user = create_authenticated_user(engine_id)

      # Test with reportable flag variations
      reportable_values = [true, false]

      for reportable <- reportable_values do
        pdu = create_simple_pdu(10010)

        request = %{
          version: 3,
          msg_id: 10010,
          msg_max_size: 65507,
          msg_flags: %{auth: true, priv: false, reportable: reportable},
          msg_security_model: 3,
          msg_security_parameters: <<>>,
          msg_data: %{
            context_engine_id: engine_id,
            context_name: "",
            pdu: pdu
          }
        }

        assert {:ok, packet} = V3Encoder.encode_message(request, user)
        assert {:ok, decoded} = V3Encoder.decode_message(packet, user)

        assert decoded.msg_flags.reportable == reportable
      end
    end

    test "multiple users with same engine" do
      engine_id = "shared_engine_stu"

      # Create multiple users for the same engine
      user1 = create_user_with_name(engine_id, "user1", :auth_no_priv)
      user2 = create_user_with_name(engine_id, "user2", :auth_priv)
      user3 = create_user_with_name(engine_id, "user3", :no_auth_no_priv)

      users = [user1, user2, user3]
      security_levels = [:auth_no_priv, :auth_priv, :no_auth_no_priv]

      for {user, level} <- Enum.zip(users, security_levels) do
        pdu = create_simple_pdu(11000 + :rand.uniform(999))
        request = create_v3_message(pdu.request_id, pdu, user, level)

        assert {:ok, packet} = V3Encoder.encode_message(request, user)
        assert {:ok, decoded} = V3Encoder.decode_message(packet, user)

        # Each user should only be able to decode their own messages
        # Exception: no-auth messages can be decoded by anyone
        for other_user <- users -- [user] do
          if level != :no_auth_no_priv and other_user.auth_protocol != :none do
            # Should fail authentication for other users (except for no-auth messages)
            assert {:error, _} = V3Encoder.decode_message(packet, other_user)
          else
            # No-auth messages can be decoded by anyone, or no-auth users can't verify others
            # This is expected behavior
            _result = V3Encoder.decode_message(packet, other_user)
          end
        end
      end
    end
  end

  describe "Real-world simulation scenarios" do
    test "network discovery and monitoring flow" do
      # Simulate discovering multiple engines
      engines = [
        "router_engine_001",
        "switch_engine_002",
        "server_engine_003"
      ]

      discovered_engines =
        for {engine_id, index} <- Enum.with_index(engines, 1) do
          discovery_msg = V3Encoder.create_discovery_message(12000 + index)
          {:ok, discovery_packet} = V3Encoder.encode_message(discovery_msg, nil)

          # Simulate response
          mock_response = create_mock_discovery_response(discovery_msg.msg_id, engine_id)
          {:ok, decoded} = V3Encoder.decode_message(mock_response, nil)

          decoded.msg_data.context_engine_id
        end

      assert length(discovered_engines) == 3
      assert "router_engine_001" in discovered_engines
      assert "switch_engine_002" in discovered_engines
      assert "server_engine_003" in discovered_engines
    end

    test "bulk table walking simulation" do
      engine_id = "table_engine_vwx"
      user = create_encrypted_user(engine_id)

      # Simulate walking interface table
      interface_table_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1]

      # First request
      bulk_pdu1 = %{
        type: :get_bulk_request,
        request_id: 13001,
        error_status: 0,
        error_index: 0,
        non_repeaters: 0,
        max_repetitions: 10,
        varbinds: [{interface_table_oid, :null, :null}]
      }

      request1 = create_v3_message(13001, bulk_pdu1, user, :auth_priv)
      assert {:ok, packet1} = V3Encoder.encode_message(request1, user)
      assert {:ok, decoded1} = V3Encoder.decode_message(packet1, user)

      # Simulate continuation with next OID
      # Simulate getting next part of table
      next_oid = interface_table_oid ++ [10, 1]

      bulk_pdu2 = %{
        type: :get_bulk_request,
        request_id: 13002,
        error_status: 0,
        error_index: 0,
        non_repeaters: 0,
        max_repetitions: 10,
        varbinds: [{next_oid, :null, :null}]
      }

      request2 = create_v3_message(13002, bulk_pdu2, user, :auth_priv)
      assert {:ok, packet2} = V3Encoder.encode_message(request2, user)
      assert {:ok, decoded2} = V3Encoder.decode_message(packet2, user)

      # Both requests should be valid bulk requests
      assert decoded1.msg_data.pdu.type == :get_bulk_request
      assert decoded2.msg_data.pdu.type == :get_bulk_request
      assert decoded1.msg_data.pdu.max_repetitions == 10
      assert decoded2.msg_data.pdu.max_repetitions == 10
    end

    test "configuration change scenario" do
      engine_id = "config_engine_yz1"
      user = create_encrypted_user(engine_id)

      # Simulate configuration change with SET request
      set_pdu = %{
        type: :set_request,
        request_id: 14001,
        error_status: 0,
        error_index: 0,
        varbinds: [
          {[1, 3, 6, 1, 2, 1, 1, 5, 0], :octet_string, "New System Name"},
          {[1, 3, 6, 1, 2, 1, 1, 6, 0], :octet_string, "New Location"}
        ]
      }

      set_request = create_v3_message(14001, set_pdu, user, :auth_priv)
      assert {:ok, set_packet} = V3Encoder.encode_message(set_request, user)
      assert {:ok, decoded_set} = V3Encoder.decode_message(set_packet, user)

      assert decoded_set.msg_data.pdu.type == :set_request
      assert length(decoded_set.msg_data.pdu.varbinds) == 2

      [{_, _, name_value}, {_, _, location_value}] = decoded_set.msg_data.pdu.varbinds
      assert name_value == "New System Name"
      assert location_value == "New Location"
    end

    test "security level migration scenario" do
      engine_id = "migration_engine_234"

      # Start with no security
      user_v1 = create_user_with_name(engine_id, "migrating_user", :no_auth_no_priv)

      pdu = create_simple_pdu(15001)
      request_v1 = create_v3_message(15001, pdu, user_v1, :no_auth_no_priv)

      assert {:ok, packet_v1} = V3Encoder.encode_message(request_v1, user_v1)
      assert {:ok, decoded_v1} = V3Encoder.decode_message(packet_v1, user_v1)
      assert decoded_v1.msg_flags.auth == false
      assert decoded_v1.msg_flags.priv == false

      # Migrate to authentication
      user_v2 = create_user_with_name(engine_id, "migrating_user", :auth_no_priv)

      request_v2 = create_v3_message(15002, pdu, user_v2, :auth_no_priv)
      assert {:ok, packet_v2} = V3Encoder.encode_message(request_v2, user_v2)
      assert {:ok, decoded_v2} = V3Encoder.decode_message(packet_v2, user_v2)
      assert decoded_v2.msg_flags.auth == true
      assert decoded_v2.msg_flags.priv == false

      # Migrate to full security
      user_v3 = create_user_with_name(engine_id, "migrating_user", :auth_priv)

      request_v3 = create_v3_message(15003, pdu, user_v3, :auth_priv)
      assert {:ok, packet_v3} = V3Encoder.encode_message(request_v3, user_v3)
      assert {:ok, decoded_v3} = V3Encoder.decode_message(packet_v3, user_v3)
      assert decoded_v3.msg_flags.auth == true
      assert decoded_v3.msg_flags.priv == true

      # Each version should have different packet sizes
      assert byte_size(packet_v1) < byte_size(packet_v2)
      assert byte_size(packet_v2) < byte_size(packet_v3)
    end
  end

  # Helper functions

  defp create_mock_discovery_response(request_id, engine_id) do
    response_pdu = %{
      type: :get_response,
      request_id: request_id,
      error_status: 0,
      error_index: 0,
      varbinds: [{[1, 3, 6, 1, 6, 3, 10, 2, 1, 1, 0], :octet_string, engine_id}]
    }

    response_msg = %{
      version: 3,
      msg_id: request_id,
      msg_max_size: 65507,
      msg_flags: %{auth: false, priv: false, reportable: false},
      msg_security_model: 3,
      msg_security_parameters: <<>>,
      msg_data: %{
        context_engine_id: engine_id,
        context_name: "",
        pdu: response_pdu
      }
    }

    {:ok, encoded} = V3Encoder.encode_message(response_msg, nil)
    encoded
  end

  defp create_simple_pdu(request_id) do
    %{
      type: :get_request,
      request_id: request_id,
      error_status: 0,
      error_index: 0,
      varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null}]
    }
  end

  defp create_authenticated_user(engine_id) do
    %{
      security_name: "auth_user",
      auth_protocol: :sha256,
      priv_protocol: :none,
      auth_key: :crypto.strong_rand_bytes(32),
      priv_key: <<>>,
      engine_id: engine_id,
      engine_boots: 1,
      engine_time: System.system_time(:second)
    }
  end

  defp create_encrypted_user(engine_id) do
    %{
      security_name: "priv_user",
      auth_protocol: :sha256,
      priv_protocol: :aes128,
      auth_key: :crypto.strong_rand_bytes(32),
      priv_key: :crypto.strong_rand_bytes(16),
      engine_id: engine_id,
      engine_boots: 1,
      engine_time: System.system_time(:second)
    }
  end

  defp create_user_with_protocols(engine_id, auth_protocol, priv_protocol) do
    auth_key_size =
      case auth_protocol do
        :md5 -> 16
        :sha1 -> 20
        :sha256 -> 32
        :sha384 -> 48
        :sha512 -> 64
      end

    priv_key_size =
      case priv_protocol do
        :des -> 8
        :aes128 -> 16
        :aes192 -> 24
        :aes256 -> 32
      end

    %{
      security_name: "protocol_user",
      auth_protocol: auth_protocol,
      priv_protocol: priv_protocol,
      auth_key: :crypto.strong_rand_bytes(auth_key_size),
      priv_key: :crypto.strong_rand_bytes(priv_key_size),
      engine_id: engine_id,
      engine_boots: 1,
      engine_time: System.system_time(:second)
    }
  end

  defp create_user_with_name(engine_id, name, security_level) do
    {auth_protocol, auth_key} =
      case security_level do
        :no_auth_no_priv -> {:none, <<>>}
        _ -> {:sha256, :crypto.strong_rand_bytes(32)}
      end

    {priv_protocol, priv_key} =
      case security_level do
        :auth_priv -> {:aes128, :crypto.strong_rand_bytes(16)}
        _ -> {:none, <<>>}
      end

    %{
      security_name: name,
      auth_protocol: auth_protocol,
      priv_protocol: priv_protocol,
      auth_key: auth_key,
      priv_key: priv_key,
      engine_id: engine_id,
      engine_boots: 1,
      engine_time: System.system_time(:second)
    }
  end

  defp create_authenticated_request(request_id, user) do
    pdu = create_simple_pdu(request_id)
    create_v3_message(request_id, pdu, user, :auth_no_priv)
  end

  defp create_encrypted_request(request_id, user) do
    pdu = create_simple_pdu(request_id)
    create_v3_message(request_id, pdu, user, :auth_priv)
  end

  defp create_v3_message(msg_id, pdu, user, security_level) do
    flags =
      case security_level do
        :no_auth_no_priv -> %{auth: false, priv: false, reportable: true}
        :auth_no_priv -> %{auth: true, priv: false, reportable: true}
        :auth_priv -> %{auth: true, priv: true, reportable: true}
      end

    %{
      version: 3,
      msg_id: msg_id,
      msg_max_size: 65507,
      msg_flags: flags,
      msg_security_model: 3,
      msg_security_parameters: <<>>,
      msg_data: %{
        context_engine_id: user.engine_id,
        context_name: "",
        pdu: pdu
      }
    }
  end
end
