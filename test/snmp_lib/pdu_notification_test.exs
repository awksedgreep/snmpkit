defmodule SnmpKit.SnmpLib.PDUNotificationTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpLib.PDU

  @sys_uptime [1, 3, 6, 1, 2, 1, 1, 3, 0]
  @snmp_trap_oid [1, 3, 6, 1, 6, 3, 1, 1, 4, 1, 0]
  @link_down [1, 3, 6, 1, 6, 3, 1, 1, 5, 3]

  describe "SNMPv2c trap" do
    test "build_trap_v2 prepends sysUpTime.0 and snmpTrapOID.0" do
      pdu =
        PDU.build_trap_v2(
          1234,
          @link_down,
          [{[1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 3], :integer, 3}],
          99
        )

      assert pdu.type == :snmpv2_trap
      assert pdu.request_id == 99
      assert pdu.error_status == 0

      assert [
               {@sys_uptime, :timeticks, 1234},
               {@snmp_trap_oid, :object_identifier, @link_down},
               {[1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 3], :integer, 3}
             ] = pdu.varbinds
    end

    test "encodes with tag 0xA7 and decodes back" do
      pdu = PDU.build_trap_v2(1234, "1.3.6.1.6.3.1.1.5.3", [], 5)
      {:ok, bin} = PDU.encode_message(PDU.build_message(pdu, "public", :v2c))

      # message SEQUENCE, version INTEGER, community OCTET STRING, then the PDU tag
      assert <<0x30, _len, 0x02, 0x01, 0x01, 0x04, 6, "public", 0xA7, _::binary>> = bin

      assert {:ok, %{version: 1, community: "public", pdu: decoded}} = PDU.decode_message(bin)
      assert decoded.type == :snmpv2_trap
      assert decoded.request_id == 5

      assert [{@sys_uptime, :timeticks, 1234}, {@snmp_trap_oid, :object_identifier, @link_down}] =
               decoded.varbinds
    end

    test "cannot be sent in an SNMPv1 message" do
      pdu = PDU.build_trap_v2(0, @link_down)

      assert_raise ArgumentError, ~r/require SNMPv2c/, fn ->
        PDU.build_message(pdu, "public", :v1)
      end
    end
  end

  describe "inform and report" do
    test "inform round trip uses tag 0xA6" do
      pdu =
        PDU.build_inform(
          10,
          @link_down,
          [{[1, 3, 6, 1, 2, 1, 1, 5, 0], :octet_string, "r1"}],
          4242
        )

      {:ok, bin} = PDU.encode_message(PDU.build_message(pdu, "traps", :v2c))
      assert :binary.match(bin, <<0xA6>>) != :nomatch

      assert {:ok,
              %{
                pdu: %{
                  type: :inform_request,
                  request_id: 4242,
                  varbinds: [_, _, {_, :octet_string, "r1"}]
                }
              }} =
               PDU.decode_message(bin)
    end

    test "report round trip uses tag 0xA8" do
      pdu = %{
        type: :report,
        request_id: 1,
        error_status: 0,
        error_index: 0,
        varbinds: [{[1, 3, 6, 1, 6, 3, 15, 1, 1, 4, 0], :counter32, 3}]
      }

      {:ok, bin} = PDU.encode_message(PDU.build_message(pdu, "", :v2c))

      assert {:ok, %{pdu: %{type: :report, varbinds: [{_, :counter32, 3}]}}} =
               PDU.decode_message(bin)
    end
  end

  describe "SNMPv1 trap" do
    test "build_trap_v1 validates the generic trap" do
      assert_raise ArgumentError, fn ->
        PDU.build_trap_v1([1, 3, 6, 1, 4, 1, 9], {10, 0, 0, 1}, 7, 0, 0)
      end
    end

    test "encodes with tag 0xA4 and decodes all fields" do
      pdu =
        PDU.build_trap_v1([1, 3, 6, 1, 4, 1, 9999], {10, 0, 0, 1}, 6, 7, 5000, [
          {[1, 3, 6, 1, 4, 1, 9999, 1, 0], :integer, 1}
        ])

      {:ok, bin} = PDU.encode_message(PDU.build_message(pdu, "public", :v1))
      assert <<0x30, _len, 0x02, 0x01, 0x00, 0x04, 6, "public", 0xA4, _::binary>> = bin

      assert {:ok, %{version: 0, pdu: decoded}} = PDU.decode_message(bin)

      assert %{
               type: :trap,
               enterprise: [1, 3, 6, 1, 4, 1, 9999],
               agent_addr: <<10, 0, 0, 1>>,
               generic_trap: 6,
               specific_trap: 7,
               time_stamp: 5000,
               varbinds: [{[1, 3, 6, 1, 4, 1, 9999, 1, 0], :integer, 1}]
             } = decoded
    end

    test "accepts the agent address as bytes too" do
      pdu = PDU.build_trap_v1([1, 3, 6, 1, 4, 1, 9], <<192, 168, 0, 1>>, 0, 0, 0)
      {:ok, bin} = PDU.encode_message(PDU.build_message(pdu, "public", :v1))

      assert {:ok, %{pdu: %{agent_addr: <<192, 168, 0, 1>>, generic_trap: 0}}} =
               PDU.decode_message(bin)
    end

    test "cannot be sent in an SNMPv2c message" do
      pdu = PDU.build_trap_v1([1, 3, 6, 1, 4, 1, 9], {10, 0, 0, 1}, 0, 0, 0)

      assert_raise ArgumentError, ~r/SNMPv1 messages/, fn ->
        PDU.build_message(pdu, "public", :v2c)
      end
    end

    test "a truncated Trap-PDU is an error, not a partial trap" do
      pdu = PDU.build_trap_v1([1, 3, 6, 1, 4, 1, 9], {10, 0, 0, 1}, 0, 0, 0)
      {:ok, bin} = PDU.encode_message(PDU.build_message(pdu, "public", :v1))
      truncated = binary_part(bin, 0, byte_size(bin) - 6)
      assert {:error, _} = PDU.decode_message(truncated)
    end
  end
end
