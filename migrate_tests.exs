#!/usr/bin/env elixir

# Script to migrate tests from the three original projects to snmpkit

defmodule TestMigrator do
  @moduledoc """
  Helps migrate tests from snmp_lib, snmp_sim, and snmp_mgr to snmpkit
  """

  @test_mappings %{
    # snmp_lib tests -> snmpkit/test/snmp_lib/
    "snmp_lib" => [
      # Core library tests
      {"test/snmp_lib/asn1_test.exs", "test/snmp_lib/asn1_test.exs"},
      {"test/snmp_lib/cache_test.exs", "test/snmp_lib/cache_test.exs"},
      {"test/snmp_lib/config_test.exs", "test/snmp_lib/config_test.exs"},
      {"test/snmp_lib/dashboard_test.exs", "test/snmp_lib/dashboard_test.exs"},
      {"test/snmp_lib/error_test.exs", "test/snmp_lib/error_test.exs"},
      {"test/snmp_lib/manager_test.exs", "test/snmp_lib/manager_test.exs"},
      {"test/snmp_lib/monitor_test.exs", "test/snmp_lib/monitor_test.exs"},
      {"test/snmp_lib/oid_test.exs", "test/snmp_lib/oid_test.exs"},
      {"test/snmp_lib/pdu_test.exs", "test/snmp_lib/pdu_test.exs"},
      {"test/snmp_lib/pool_test.exs", "test/snmp_lib/pool_test.exs"},
      {"test/snmp_lib/security_test.exs", "test/snmp_lib/security_test.exs"},
      {"test/snmp_lib/transport_test.exs", "test/snmp_lib/transport_test.exs"},
      {"test/snmp_lib/types_test.exs", "test/snmp_lib/types_test.exs"},
      {"test/snmp_lib/utils_test.exs", "test/snmp_lib/utils_test.exs"},
      {"test/snmp_lib/walker_test.exs", "test/snmp_lib/walker_test.exs"},
      # MIB tests
      {"test/snmp_lib/mib/parser_test.exs", "test/snmp_lib/mib/parser_test.exs"},
      {"test/snmp_lib/mib/registry_test.exs", "test/snmp_lib/mib/registry_test.exs"},
      {"test/snmp_lib/mib/comprehensive_mib_test.exs", "test/snmp_lib/mib/comprehensive_mib_test.exs"}
    ],
    
    # snmp_sim tests -> snmpkit/test/snmp_sim/
    "snmp_sim" => [
      # Core simulator tests
      {"test/snmp_sim/config_test.exs", "test/snmp_sim/config_test.exs"},
      {"test/snmp_sim/device_distribution_test.exs", "test/snmp_sim/device_distribution_test.exs"},
      {"test/snmp_sim/error_injector_test.exs", "test/snmp_sim/error_injector_test.exs"},
      {"test/snmp_sim/lazy_device_pool_test.exs", "test/snmp_sim/lazy_device_pool_test.exs"},
      {"test/snmp_sim/oid_tree_test.exs", "test/snmp_sim/oid_tree_test.exs"},
      {"test/snmp_sim/profile_loader_test.exs", "test/snmp_sim/profile_loader_test.exs"},
      {"test/snmp_sim/value_simulator_test.exs", "test/snmp_sim/value_simulator_test.exs"},
      {"test/snmp_sim/walk_parser_test.exs", "test/snmp_sim/walk_parser_test.exs"},
      {"test/snmp_sim/bulk_operations_test.exs", "test/snmp_sim/bulk_operations_test.exs"},
      {"test/snmp_sim/correlation_engine_test.exs", "test/snmp_sim/correlation_engine_test.exs"},
      {"test/snmp_sim/time_patterns_test.exs", "test/snmp_sim/time_patterns_test.exs"},
      # Core server tests
      {"test/snmp_sim/core/server_test.exs", "test/snmp_sim/core/server_test.exs"},
      # MIB behavior tests
      {"test/snmp_sim/mib/behavior_analyzer_test.exs", "test/snmp_sim/mib/behavior_analyzer_test.exs"}
    ],
    
    # snmp_mgr tests -> snmpkit/test/snmp_mgr/
    "snmp_mgr" => [
      # Unit tests
      {"test/unit/adaptive_walk_test.exs", "test/snmp_mgr/adaptive_walk_test.exs"},
      {"test/unit/bulk_operations_test.exs", "test/snmp_mgr/bulk_operations_test.exs"},
      {"test/unit/circuit_breaker_comprehensive_test.exs", "test/snmp_mgr/circuit_breaker_test.exs"},
      {"test/unit/config_comprehensive_test.exs", "test/snmp_mgr/config_test.exs"},
      {"test/unit/core_operations_test.exs", "test/snmp_mgr/core_operations_test.exs"},
      {"test/unit/engine_comprehensive_test.exs", "test/snmp_mgr/engine_test.exs"},
      {"test/unit/error_comprehensive_test.exs", "test/snmp_mgr/error_test.exs"},
      {"test/unit/format_test.exs", "test/snmp_mgr/format_test.exs"},
      {"test/unit/metrics_comprehensive_test.exs", "test/snmp_mgr/metrics_test.exs"},
      {"test/unit/mib_comprehensive_test.exs", "test/snmp_mgr/mib_test.exs"},
      {"test/unit/router_comprehensive_test.exs", "test/snmp_mgr/router_test.exs"},
      {"test/unit/stream_processing_test.exs", "test/snmp_mgr/stream_test.exs"},
      {"test/unit/table_processing_test.exs", "test/snmp_mgr/table_test.exs"},
      {"test/unit/types_comprehensive_test.exs", "test/snmp_mgr/types_test.exs"}
    ],
    
    # Integration tests -> snmpkit/test/integration/
    "integration" => [
      {"snmp_lib/test/integration/phase2_integration_test.exs", "test/integration/snmp_lib_integration_test.exs"},
      {"snmp_sim/test/snmp_sim_integration_test.exs", "test/integration/snmp_sim_integration_test.exs"},
      {"snmp_mgr/test/integration/engine_integration_test.exs", "test/integration/snmp_mgr_engine_test.exs"},
      {"snmp_mgr/test/integration_test.exs", "test/integration/snmp_mgr_integration_test.exs"}
    ]
  }

  def migrate_all do
    IO.puts("Starting test migration to snmpkit...")
    
    # Migrate tests from each project
    @test_mappings
    |> Enum.each(fn {category, test_files} ->
      IO.puts("\nMigrating #{category} tests...")
      
      test_files
      |> Enum.each(fn {source, destination} ->
        source_path = case category do
          "integration" -> Path.join(["/Users/mcotner/Documents/elixir", source])
          project when project in ["snmp_lib", "snmp_sim", "snmp_mgr"] ->
            Path.join(["/Users/mcotner/Documents/elixir", project, source])
          _ -> source
        end
        
        dest_path = Path.join("/Users/mcotner/Documents/elixir/snmpkit", destination)
        
        migrate_test_file(source_path, dest_path)
      end)
    end)
    
    IO.puts("\n✅ Test migration completed!")
  end

  defp migrate_test_file(source_path, dest_path) do
    if File.exists?(source_path) do
      # Ensure destination directory exists
      dest_dir = Path.dirname(dest_path)
      File.mkdir_p!(dest_dir)
      
      # Read source file
      content = File.read!(source_path)
      
      # Update module names and aliases
      updated_content = content
        |> update_module_names()
        |> update_aliases()
        |> update_test_helpers()
      
      # Write to destination
      File.write!(dest_path, updated_content)
      
      IO.puts("  ✓ Migrated: #{Path.basename(source_path)}")
    else
      IO.puts("  ⚠ Source not found: #{source_path}")
    end
  rescue
    error ->
      IO.puts("  ✗ Error migrating #{source_path}: #{inspect(error)}")
  end

  defp update_module_names(content) do
    content
    |> String.replace("defmodule SnmpLib.", "defmodule SnmpKit.SnmpLib.")
    |> String.replace("defmodule SnmpSim.", "defmodule SnmpKit.SnmpSim.")
    |> String.replace("defmodule SnmpMgr.", "defmodule SnmpKit.SnmpMgr.")
  end

  defp update_aliases(content) do
    content
    |> String.replace("alias SnmpLib.", "alias SnmpKit.SnmpLib.")
    |> String.replace("alias SnmpSim.", "alias SnmpKit.SnmpSim.")
    |> String.replace("alias SnmpMgr.", "alias SnmpKit.SnmpMgr.")
    # Update imports as well
    |> String.replace("import SnmpLib.", "import SnmpKit.SnmpLib.")
    |> String.replace("import SnmpSim.", "import SnmpKit.SnmpSim.")
    |> String.replace("import SnmpMgr.", "import SnmpKit.SnmpMgr.")
  end

  defp update_test_helpers(content) do
    content
    |> String.replace("SnmpSim.TestHelpers.SNMPTestHelpers", "SnmpKit.TestHelpers.SNMPTestHelpers")
    |> String.replace("SnmpMgr.TestSupport.SNMPSimulator", "SnmpKit.TestSupport.SNMPSimulator")
  end
end

# Run the migration
TestMigrator.migrate_all()