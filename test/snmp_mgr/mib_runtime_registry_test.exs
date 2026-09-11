defmodule SnmpKit.SnmpMgr.MibRuntimeRegistryTest do
  # Loads MIBs into the shared SnmpKit.SnmpMgr.MIB registry.
  use ExUnit.Case, async: false

  alias SnmpKit.MIB.{Builtin, Registry}
  alias SnmpKit.SnmpLib.Manager
  alias SnmpKit.SnmpMgr.Core

  @moduletag :tmp_dir

  @loaded_mib """
  LOADED-NAME-TEST-MIB DEFINITIONS ::= BEGIN
  IMPORTS OBJECT-TYPE, Integer32, enterprises FROM SNMPv2-SMI;

  ldnTest OBJECT IDENTIFIER ::= { enterprises 99995 }

  ldnValue OBJECT-TYPE
    SYNTAX Integer32
    MAX-ACCESS read-only
    STATUS current
    DESCRIPTION "value"
    ::= { ldnTest 1 }
  END
  """

  @integrated_mib """
  LOADED-INTEGRATE-TEST-MIB DEFINITIONS ::= BEGIN
  IMPORTS OBJECT-TYPE, Integer32, enterprises FROM SNMPv2-SMI;

  ldiTest OBJECT IDENTIFIER ::= { enterprises 99994 }

  ldiValue OBJECT-TYPE
    SYNTAX Integer32
    MAX-ACCESS read-only
    STATUS current
    DESCRIPTION "value"
    ::= { ldiTest 1 }
  END
  """

  @ldn_value_0 [1, 3, 6, 1, 4, 1, 99995, 1, 0]

  setup_all do
    {:ok, compiled} = SnmpKit.MIB.compile_string(@loaded_mib)
    :ok = SnmpKit.MIB.load(compiled)
    :ok
  end

  describe "one built-in name table" do
    test "the static Registry and the runtime registry are seeded from Builtin" do
      assert Registry.standard_mibs() == Builtin.name_to_oid()

      for name <- ["ipAddrTable", "ifName", "hrSystem", "system", "interfaces", "ipRouteTable"] do
        assert {:ok, oid} = Builtin.name_to_oid() |> Map.fetch(name)
        assert {:ok, ^oid} = Registry.resolve_name(name)
        assert {:ok, ^oid} = SnmpKit.SnmpMgr.MIB.resolve(name)
      end
    end

    test "loaded MIB names are visible to the runtime registry only" do
      assert {:ok, [1, 3, 6, 1, 4, 1, 99995, 1]} = SnmpKit.SnmpMgr.MIB.resolve("ldnValue")
      assert {:error, :not_found} = Registry.resolve_name("ldnValue")
    end
  end

  describe "runtime-loaded names on the request paths" do
    test "Core.parse_oid/1 resolves a loaded name with an instance suffix" do
      assert {:ok, @ldn_value_0} = Core.parse_oid("ldnValue.0")
    end

    test "Manager.normalize_oid/1 resolves a loaded name" do
      assert {:ok, @ldn_value_0} = Manager.normalize_oid("ldnValue.0")
    end

    test "Manager.get/3 sends the loaded name's OID on the wire" do
      {:ok, server} = SnmpKit.SnmpLib.Transport.create_server_socket(0, "127.0.0.1")
      {:ok, {_addr, port}} = SnmpKit.SnmpLib.Transport.get_socket_address(server)

      agent =
        Task.async(fn ->
          {:ok, {packet, from_addr, from_port}} =
            SnmpKit.SnmpLib.Transport.receive_packet(server, 1_000)

          {:ok, %{pdu: pdu}} = SnmpKit.SnmpLib.PDU.decode_message(packet)
          [{wire_oid, :null, :null}] = pdu.varbinds

          response =
            SnmpKit.SnmpLib.PDU.build_response(pdu.request_id, 0, 0, [{wire_oid, :integer, 7}])
            |> SnmpKit.SnmpLib.PDU.build_message("public", :v2c)

          {:ok, encoded} = SnmpKit.SnmpLib.PDU.encode_message(response)
          :ok = :gen_udp.send(server, from_addr, from_port, encoded)
          wire_oid
        end)

      assert {:ok, {:integer, 7}} =
               Manager.get("127.0.0.1", "ldnValue.0", port: port, timeout: 1_000, retries: 0)

      assert Task.await(agent, 1_000) == @ldn_value_0
      :ok = SnmpKit.SnmpLib.Transport.close_socket(server)
    end
  end

  describe "load_and_integrate_mib/2" do
    test "compiles, registers and lists the MIB", %{tmp_dir: dir} do
      path = Path.join(dir, "LOADED-INTEGRATE-TEST-MIB.mib")
      File.write!(path, @integrated_mib)

      assert :ok = SnmpKit.MIB.load_and_integrate_mib(path)

      assert {:ok, [1, 3, 6, 1, 4, 1, 99994, 1]} = SnmpKit.SnmpMgr.MIB.resolve("ldiValue")

      assert {:ok, "ldiValue.0"} =
               SnmpKit.SnmpMgr.MIB.reverse_lookup([1, 3, 6, 1, 4, 1, 99994, 1, 0])

      assert {:ok, %{name: "ldiValue", syntax: %{base: :integer}}} =
               SnmpKit.SnmpMgr.MIB.object_info("ldiValue")

      assert "LOADED-INTEGRATE-TEST-MIB" in SnmpKit.SnmpMgr.MIB.loaded_mibs()
      assert "LOADED-NAME-TEST-MIB" in SnmpKit.SnmpMgr.MIB.loaded_mibs()

      # loading the same module again does not duplicate the listing
      assert :ok = SnmpKit.MIB.load_and_integrate_mib(path)

      assert Enum.count(SnmpKit.SnmpMgr.MIB.loaded_mibs(), &(&1 == "LOADED-INTEGRATE-TEST-MIB")) ==
               1
    end

    test "reports compilation errors" do
      assert {:error, {:snmp_lib_compilation_failed, [%SnmpKit.MIB.Error{}]}} =
               SnmpKit.MIB.load_and_integrate_mib("/nonexistent/NOPE-MIB.mib")
    end
  end
end
