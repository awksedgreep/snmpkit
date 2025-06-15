defmodule SnmpKit.Integration.HostParserMibStubsIntegrationTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpLib.HostParser
  alias SnmpKit.SnmpMgr.MIB

  @moduletag :integration
  @moduletag :host_parser_mib_stubs

  setup do
    # Ensure MIB registry is started
    case GenServer.whereis(SnmpKit.SnmpMgr.MIB) do
      nil ->
        {:ok, _pid} = SnmpKit.SnmpMgr.MIB.start_link()
        :ok
      _pid ->
        :ok
    end

    :ok
  end

  describe "host parser and MIB stubs integration" do
    test "parse host and resolve MIB objects for complete SNMP operations" do
      # Test host parsing for different formats
      hosts_to_test = [
        "127.0.0.1",
        {127, 0, 0, 1},
        {{127, 0, 0, 1}, 8161},
        "127.0.0.1:8161"
      ]

      # Test MIB objects to resolve
      objects_to_test = [
        "sysDescr.0",
        "sysUpTime.0",
        "ifDescr.1",
        "ifName.1"
      ]

      # Test all combinations
      for host_input <- hosts_to_test do
        # Parse host
        assert {:ok, {ip_tuple, port}} = HostParser.parse(host_input)
        assert is_tuple(ip_tuple)
        assert is_integer(port)
        assert port >= 1 and port <= 65535

        # Verify IP tuple format is compatible with :gen_udp
        assert tuple_size(ip_tuple) in [4, 8]  # IPv4 or IPv6

        for object <- objects_to_test do
          # Resolve MIB object
          assert {:ok, oid_list} = MIB.resolve(object)
          assert is_list(oid_list)
          assert length(oid_list) >= 8  # At least 1.3.6.1.2.1.X.Y.instance

          # Convert to string format that SNMP operations expect
          oid_string = Enum.join(oid_list, ".")
          assert String.match?(oid_string, ~r/^1\.3\.6\.1\.2\.1\./)

          # This combination would be used in real SNMP operations like:
          # SnmpKit.SnmpLib.Manager.get(ip_tuple, oid_string, port: port)
          # We don't actually make the call since we don't have a test device
        end
      end
    end

    test "comprehensive coverage of common monitoring scenarios" do
      # Common monitoring scenarios that should work out of the box
      scenarios = [
        %{
          description: "Basic system monitoring",
          host: "192.168.1.1",
          objects: ["sysDescr.0", "sysUpTime.0", "sysName.0", "sysLocation.0"]
        },
        %{
          description: "Interface statistics",
          host: {192, 168, 1, 1},
          objects: ["ifDescr.1", "ifOperStatus.1", "ifInOctets.1", "ifOutOctets.1"]
        },
        %{
          description: "High-capacity interface monitoring",
          host: "192.168.1.1:8161",
          objects: ["ifName.1", "ifHCInOctets.1", "ifHCOutOctets.1", "ifAlias.1"]
        },
        %{
          description: "SNMP agent statistics",
          host: {{192, 168, 1, 1}, 8161},
          objects: ["snmpInPkts.0", "snmpOutPkts.0", "snmpInBadVersions.0"]
        }
      ]

      for %{description: desc, host: host_input, objects: objects} <- scenarios do
        # Parse host
        assert {:ok, {ip_tuple, port}} = HostParser.parse(host_input)

        # Resolve all objects
        resolved_objects = Enum.map(objects, fn object ->
          assert {:ok, oid_list} = MIB.resolve(object)
          {object, oid_list, Enum.join(oid_list, ".")}
        end)

        # Verify we got valid resolutions
        assert length(resolved_objects) == length(objects)

        # All OIDs should be standard MIB-II
        for {_object, oid_list, _oid_string} <- resolved_objects do
          assert Enum.take(oid_list, 6) == [1, 3, 6, 1, 2, 1]
        end

        # Log successful scenario for visibility
        IO.puts("✓ #{desc}: #{HostParser.format({ip_tuple, port})}")
      end
    end

    test "bulk walk scenarios with group names" do
      # Test scenarios that would be used with bulk_walk_pretty
      bulk_scenarios = [
        {"system", "Complete system information"},
        {"if", "Standard interface table"},
        {"ifX", "Extended interface table"},
        {"snmp", "SNMP agent statistics"},
        {"ip", "IP protocol statistics"}
      ]

      host_formats = [
        "192.168.1.100",
        {192, 168, 1, 100},
        "192.168.1.100:8161"
      ]

      for {group, description} <- bulk_scenarios do
        # Verify group resolves to valid OID prefix
        assert {:ok, oid_prefix} = MIB.resolve(group)
        assert is_list(oid_prefix)
        assert length(oid_prefix) >= 7  # At least 1.3.6.1.2.1.X

        for host_input <- host_formats do
          # Verify host parses correctly
          assert {:ok, {ip_tuple, port}} = HostParser.parse(host_input)

          # This combination would be used like:
          # SnmpKit.SnmpMgr.bulk_walk_pretty(ip_tuple, group, port: port)

          formatted_host = HostParser.format({ip_tuple, port})
          oid_string = Enum.join(oid_prefix, ".")

          # Verify the combination makes sense
          assert String.match?(formatted_host, ~r/^\d+\.\d+\.\d+\.\d+:\d+$/)
          assert String.match?(oid_string, ~r/^1\.3\.6\.1\.2\.1/)
        end
      end
    end

    test "enterprise MIB scenarios" do
      # Test enterprise-specific monitoring scenarios
      enterprise_scenarios = [
        {"cisco", "Cisco equipment monitoring"},
        {"mikrotik", "MikroTik router monitoring"},
        {"hp", "HP equipment monitoring"},
        {"cablelabs", "Cable/DOCSIS equipment root"},
        {"docsis", "DOCSIS protocol monitoring"}
      ]

      test_host = "10.0.0.1:8161"
      assert {:ok, {ip_tuple, port}} = HostParser.parse(test_host)

      for {enterprise, description} <- enterprise_scenarios do
        assert {:ok, oid_prefix} = MIB.resolve(enterprise)
        assert is_list(oid_prefix)

        # Enterprise OIDs should start with 1.3.6.1.4.1 or be in MIB-II for DOCSIS
        enterprise_prefix = Enum.take(oid_prefix, 6)
        assert enterprise_prefix in [[1, 3, 6, 1, 4, 1], [1, 3, 6, 1, 2, 1]]

        # Combination ready for enterprise-specific SNMP operations
        formatted_host = HostParser.format({ip_tuple, port})
        oid_string = Enum.join(oid_prefix, ".")

        IO.puts("✓ #{description}: #{formatted_host} → #{oid_string}")
      end
    end

    test "error handling integration" do
      # Test that both systems handle errors gracefully
      invalid_hosts = [
        "999.999.999.999",
        {256, 0, 0, 0},
        "invalid.host.name.that.does.not.exist.test"
      ]

      invalid_objects = [
        "nonExistentObject",
        "invalidMibName",
        "customObject.0"
      ]

      # Invalid hosts should fail gracefully
      for invalid_host <- invalid_hosts do
        assert {:error, _reason} = HostParser.parse(invalid_host)
      end

      # Invalid objects should fail gracefully
      for invalid_object <- invalid_objects do
        assert {:error, :not_found} = MIB.resolve(invalid_object)
      end

      # Valid host with invalid object - should get partial success
      assert {:ok, {ip_tuple, port}} = HostParser.parse("127.0.0.1")
      assert {:error, :not_found} = MIB.resolve("invalidObject")

      # This would allow applications to handle mixed results appropriately
      assert is_tuple(ip_tuple)
      assert is_integer(port)
    end

    test "performance integration" do
      # Test that both systems are fast enough for real-world use
      host_inputs = [
        "192.168.1.1",
        {192, 168, 1, 1},
        "192.168.1.1:8161",
        {{192, 168, 1, 1}, 8161}
      ]

      mib_objects = [
        "system", "if", "ifX", "sysDescr", "ifName",
        "cisco", "mikrotik", "snmpInPkts"
      ]

      # Measure time for typical batch operations
      start_time = System.monotonic_time(:microsecond)

      for _iteration <- 1..100 do
        for host_input <- host_inputs do
          assert {:ok, _parsed} = HostParser.parse(host_input)
        end

        for object <- mib_objects do
          assert {:ok, _oid} = MIB.resolve(object)
        end
      end

      end_time = System.monotonic_time(:microsecond)
      total_time = end_time - start_time

      # Should complete 1200 operations (400 host parses + 800 MIB resolutions) in under 50ms
      assert total_time < 50_000

      operations_per_ms = 1200 / (total_time / 1000)
      IO.puts("Performance: #{Float.round(operations_per_ms, 1)} operations/ms")
    end

    test "real-world SNMP operation readiness" do
      # Verify the parsed results are exactly what SNMP operations need

      # Test with the original target that had issues
      target_host = "192.168.88.234"
      assert {:ok, {ip_tuple, port}} = HostParser.parse(target_host)

      # Should get exactly what gen_udp expects
      assert ip_tuple == {192, 168, 88, 234}
      assert port == 161

      # Test with common objects that would be queried
      common_queries = [
        "sysDescr.0",
        "sysUpTime.0",
        "ifDescr.1",
        "ifOperStatus.1"
      ]

      for query <- common_queries do
        assert {:ok, oid_list} = MIB.resolve(query)
        oid_string = Enum.join(oid_list, ".")

        # This is exactly what would be passed to SNMP operations:
        # SnmpKit.SnmpLib.Manager.get(ip_tuple, oid_string)
        # or with port override:
        # SnmpKit.SnmpLib.Manager.get(ip_tuple, oid_string, port: port)

        assert is_tuple(ip_tuple)
        assert tuple_size(ip_tuple) == 4
        assert is_binary(oid_string)
        assert String.starts_with?(oid_string, "1.3.6.1.2.1.")
      end

      # Verify format function produces correct string representation
      formatted = HostParser.format({ip_tuple, port})
      assert formatted == "192.168.88.234:161"
    end
  end

  describe "stub system completeness" do
    test "all essential SNMP monitoring objects are available" do
      # Categories of objects that should be available for basic SNMP monitoring
      essential_categories = %{
        "System Information" => [
          "sysDescr.0", "sysUpTime.0", "sysName.0", "sysLocation.0", "sysContact.0"
        ],
        "Interface Basics" => [
          "ifNumber.0", "ifDescr.1", "ifType.1", "ifOperStatus.1", "ifAdminStatus.1"
        ],
        "Interface Counters" => [
          "ifInOctets.1", "ifOutOctets.1", "ifInUcastPkts.1", "ifOutUcastPkts.1"
        ],
        "High-Capacity Counters" => [
          "ifName.1", "ifHCInOctets.1", "ifHCOutOctets.1", "ifHighSpeed.1"
        ],
        "SNMP Statistics" => [
          "snmpInPkts.0", "snmpOutPkts.0", "snmpInBadVersions.0"
        ]
      }

      for {category, objects} <- essential_categories do
        IO.puts("Testing #{category}:")

        for object <- objects do
          assert {:ok, oid_list} = MIB.resolve(object)
          oid_string = Enum.join(oid_list, ".")
          IO.puts("  ✓ #{object} → #{oid_string}")
        end
      end
    end

    test "group names work for bulk operations" do
      # Groups that should be available for bulk walking
      bulk_groups = [
        {"system", "System group (1.3.6.1.2.1.1)"},
        {"if", "Interface group (1.3.6.1.2.1.2)"},
        {"ifX", "Interface Extensions (1.3.6.1.2.1.31)"},
        {"ip", "IP group (1.3.6.1.2.1.4)"},
        {"snmp", "SNMP group (1.3.6.1.2.1.11)"}
      ]

      for {group, description} <- bulk_groups do
        assert {:ok, oid_prefix} = MIB.resolve(group)
        oid_string = Enum.join(oid_prefix, ".")
        IO.puts("✓ #{group}: #{description} → #{oid_string}")

        # Verify it's a valid MIB-II prefix
        assert String.starts_with?(oid_string, "1.3.6.1.2.1.")
      end
    end
  end
end
