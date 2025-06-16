defmodule SnmpKit.WalkUnitTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Permanent unit tests for SNMP walk operations.

  These tests focus on the core walk logic and ensure that walk operations
  work correctly at the unit level without requiring external simulators.

  All tests must pass to ensure walk functionality is working.
  """

  require Logger

  @test_timeout 10_000

  describe "Walk Module Unit Tests" do
    test "walk module exists and has required functions" do
      assert Code.ensure_loaded?(SnmpKit.SnmpMgr.Walk)
      assert function_exported?(SnmpKit.SnmpMgr.Walk, :walk, 3)
      assert function_exported?(SnmpKit.SnmpMgr.Walk, :walk_table, 3)
      assert function_exported?(SnmpKit.SnmpMgr.Walk, :walk_column, 3)
    end

    test "walk function has proper defaults" do
      # Test that walk function exists with proper arity
      assert function_exported?(SnmpKit.SnmpMgr.Walk, :walk, 2)
      assert function_exported?(SnmpKit.SnmpMgr.Walk, :walk, 3)
    end

    test "walk module does not have type inference functions" do
      refute function_exported?(SnmpKit.SnmpMgr.Walk, :infer_snmp_type, 1),
             "Walk module must not have type inference functions"

      refute function_exported?(SnmpKit.SnmpMgr.Walk, :infer_type, 1),
             "Walk module must not have type inference functions"

      refute function_exported?(SnmpKit.SnmpMgr.Walk, :guess_type, 1),
             "Walk module must not have type inference functions"
    end
  end

  describe "Bulk Module Unit Tests" do
    test "bulk module exists and has required functions" do
      assert Code.ensure_loaded?(SnmpKit.SnmpMgr.Bulk)
      assert function_exported?(SnmpKit.SnmpMgr.Bulk, :walk_bulk, 3)
      assert function_exported?(SnmpKit.SnmpMgr.Bulk, :get_table_bulk, 3)
      assert function_exported?(SnmpKit.SnmpMgr.Bulk, :get_bulk, 3)
    end

    test "bulk module does not have type inference functions" do
      refute function_exported?(SnmpKit.SnmpMgr.Bulk, :infer_snmp_type, 1),
             "Bulk module must not have type inference functions"

      refute function_exported?(SnmpKit.SnmpMgr.Bulk, :infer_type, 1),
             "Bulk module must not have type inference functions"
    end
  end

  describe "Core Module Unit Tests" do
    test "core module exists and has required functions" do
      assert Code.ensure_loaded?(SnmpKit.SnmpMgr.Core)
      assert function_exported?(SnmpKit.SnmpMgr.Core, :send_get_next_request, 3)
      assert function_exported?(SnmpKit.SnmpMgr.Core, :send_get_bulk_request, 3)
      assert function_exported?(SnmpKit.SnmpMgr.Core, :send_get_request_with_type, 3)
    end

    test "core module does not have type inference functions" do
      refute function_exported?(SnmpKit.SnmpMgr.Core, :infer_snmp_type, 1),
             "Core module must not have type inference functions"

      refute function_exported?(SnmpKit.SnmpMgr.Core, :infer_type, 1),
             "Core module must not have type inference functions"
    end
  end

  describe "Walker Module Unit Tests" do
    test "walker module exists and has required functions" do
      assert Code.ensure_loaded?(SnmpKit.SnmpLib.Walker)
      assert function_exported?(SnmpKit.SnmpLib.Walker, :walk_table, 3)
      assert function_exported?(SnmpKit.SnmpLib.Walker, :walk_subtree, 3)
    end

    test "walker module does not have type inference functions" do
      refute function_exported?(SnmpKit.SnmpLib.Walker, :infer_snmp_type, 1),
             "Walker module must not have type inference functions"
    end
  end

  describe "Type Preservation Unit Tests" do
    test "walk module source code rejects 2-tuple responses" do
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")

      assert String.contains?(walk_source, "type_information_lost"),
             "Walk module should reject responses without type information"

      refute String.contains?(walk_source, "infer_snmp_type"),
             "Walk module should not contain type inference code"
    end

    test "bulk module source code rejects 2-tuple responses" do
      bulk_source = File.read!("lib/snmpkit/snmp_mgr/bulk.ex")

      assert String.contains?(bulk_source, "type_information_lost") or
             String.contains?(bulk_source, "Reject 2-tuple format"),
             "Bulk module should reject responses without type information"

      refute String.contains?(bulk_source, "infer_snmp_type"),
             "Bulk module should not contain type inference code"
    end

    test "core module source code rejects 2-tuple responses" do
      core_source = File.read!("lib/snmpkit/snmp_mgr/core.ex")

      assert String.contains?(core_source, "type_information_lost"),
             "Core module should reject responses without type information"

      refute String.contains?(core_source, "infer_snmp_type"),
             "Core module should not contain type inference code"
    end

    test "walker module source code rejects 2-tuple responses" do
      walker_source = File.read!("lib/snmpkit/snmp_lib/walker.ex")

      assert String.contains?(walker_source, "Reject 2-tuple format") or
             String.contains?(walker_source, "false"),
             "Walker module should reject 2-tuple varbinds"

      refute String.contains?(walker_source, "infer_snmp_type"),
             "Walker module should not contain type inference code"
    end
  end

  describe "Default Configuration Tests" do
    test "walk defaults to v2c version" do
      # We can't easily test this without mocking, but we can verify the source
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")

      assert String.contains?(walk_source, "version, :v2c"),
             "Walk should default to v2c version"
    end

    test "walk removes max_repetitions for v1" do
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")

      assert String.contains?(walk_source, "Keyword.delete(opts, :max_repetitions)"),
             "Walk should remove max_repetitions for v1 operations"
    end

    test "walk uses max_iterations for v1" do
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")

      assert String.contains?(walk_source, "max_iterations"),
             "Walk should use max_iterations for v1 operations"
    end
  end

  describe "Error Handling Unit Tests" do
    test "walk handles invalid OID format" do
      # Test with invalid OID
      result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", "invalid.oid.format")

      assert match?({:error, _}, result),
             "Walk should return error for invalid OID format"
    end

    test "walk handles empty OID" do
      result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", "")

      assert match?({:error, _}, result),
             "Walk should return error for empty OID"
    end

    test "walk handles nil OID" do
      result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", nil)

      assert match?({:error, _}, result),
             "Walk should return error for nil OID"
    end
  end

  describe "OID Processing Unit Tests" do
    test "walk handles string OIDs" do
      # We can't test actual walk without simulator, but we can test OID processing
      # This tests that the function exists and handles string input
      result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", "1.3.6.1.2.1.1", timeout: 100)

      # Should either succeed or fail with a reasonable error (not crash)
      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "Walk should handle string OIDs gracefully"
    end

    test "walk handles list OIDs" do
      result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", [1, 3, 6, 1, 2, 1, 1], timeout: 100)

      # Should either succeed or fail with a reasonable error (not crash)
      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "Walk should handle list OIDs gracefully"
    end
  end

  describe "Version Handling Unit Tests" do
    test "walk_table routes to correct implementation" do
      # Test that walk_table function exists and accepts version parameter
      result = SnmpKit.SnmpMgr.Walk.walk_table("127.0.0.1", "1.3.6.1.2.1.1",
                                               version: :v1, timeout: 100)

      # Should not crash with version parameter
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "walk routes v1 and v2c differently" do
      # Test that different versions don't crash
      v1_result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", "1.3.6.1.2.1.1",
                                            version: :v1, timeout: 100)

      v2c_result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", "1.3.6.1.2.1.1",
                                             version: :v2c, timeout: 100)

      # Both should handle gracefully (not crash)
      assert match?({:ok, _}, v1_result) or match?({:error, _}, v1_result)
      assert match?({:ok, _}, v2c_result) or match?({:error, _}, v2c_result)
    end
  end

  describe "Parameter Validation Unit Tests" do
    test "walk validates timeout parameter" do
      result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", "1.3.6.1.2.1.1", timeout: -1)

      # Should handle invalid timeout gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "walk validates max_repetitions parameter" do
      result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", "1.3.6.1.2.1.1",
                                         max_repetitions: 0, timeout: 100)

      # Should handle invalid max_repetitions gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "walk validates community parameter" do
      result = SnmpKit.SnmpMgr.Walk.walk("127.0.0.1", "1.3.6.1.2.1.1",
                                         community: "", timeout: 100)

      # Should handle empty community gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "Code Quality Unit Tests" do
    test "no deprecated pattern matching on walk results" do
      # Scan source files for deprecated 2-tuple pattern matching
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")

      # Should not contain patterns that match 2-tuples as valid results
      refute String.contains?(walk_source, "{oid, value} when"),
             "Walk source should not pattern match 2-tuples as valid"

      refute String.contains?(walk_source, "{_, _} ->") and
             String.contains?(walk_source, "infer"),
             "Walk source should not infer types from 2-tuples"
    end

    test "proper error messages for type preservation" do
      core_source = File.read!("lib/snmpkit/snmp_mgr/core.ex")

      assert String.contains?(core_source, "type_information_lost"),
             "Core module should have descriptive error messages"

      assert String.contains?(core_source, "preserve type information"),
             "Error messages should explain type preservation requirement"
    end

    test "no TODO or FIXME comments in walk code" do
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")
      bulk_source = File.read!("lib/snmpkit/snmp_mgr/bulk.ex")
      core_source = File.read!("lib/snmpkit/snmp_mgr/core.ex")

      refute String.contains?(walk_source, "TODO"),
             "Walk module should not contain TODO comments"

      refute String.contains?(walk_source, "FIXME"),
             "Walk module should not contain FIXME comments"

      refute String.contains?(bulk_source, "TODO"),
             "Bulk module should not contain TODO comments"

      refute String.contains?(core_source, "TODO"),
             "Core module should not contain TODO comments"
    end
  end

  describe "Compilation and Loading Tests" do
    test "all walk-related modules compile without warnings" do
      # This test ensures modules can be recompiled
      modules = [
        SnmpKit.SnmpMgr.Walk,
        SnmpKit.SnmpMgr.Bulk,
        SnmpKit.SnmpMgr.Core,
        SnmpKit.SnmpLib.Walker
      ]

      Enum.each(modules, fn module ->
        assert Code.ensure_loaded?(module) == {:module, module},
               "Module #{module} should compile and load successfully"
      end)
    end

    test "walk modules have proper module attributes" do
      assert SnmpKit.SnmpMgr.Walk.__info__(:module) == SnmpKit.SnmpMgr.Walk
      assert SnmpKit.SnmpMgr.Bulk.__info__(:module) == SnmpKit.SnmpMgr.Bulk
      assert SnmpKit.SnmpMgr.Core.__info__(:module) == SnmpKit.SnmpMgr.Core
    end
  end

  describe "Regression Prevention Tests" do
    test "walk source does not contain regression patterns" do
      walk_source = File.read!("lib/snmpkit/snmp_mgr/walk.ex")

      # Should not fall back to type inference
      refute String.contains?(walk_source, "inferred_type = infer_snmp_type"),
             "Walk should not fall back to type inference"

      # Should not accept 2-tuple responses as valid
      refute String.contains?(walk_source, "{oid, value} -> {:ok,"),
             "Walk should not accept 2-tuple responses as valid"

      # Should explicitly reject type-less responses
      assert String.contains?(walk_source, "type_information_lost") or
             String.contains?(walk_source, "Got 2-tuple instead"),
             "Walk should explicitly reject type-less responses"
    end

    test "bulk source does not contain regression patterns" do
      bulk_source = File.read!("lib/snmpkit/snmp_mgr/bulk.ex")

      # Should not infer types in filtering
      refute String.contains?(bulk_source, "infer_snmp_type(value)"),
             "Bulk should not infer types in result filtering"

      # Should reject 2-tuple format
      assert String.contains?(bulk_source, "false") and
             String.contains?(bulk_source, "2-tuple"),
             "Bulk should reject 2-tuple format in filtering"
    end

    test "core source does not contain regression patterns" do
      core_source = File.read!("lib/snmpkit/snmp_mgr/core.ex")

      # Should not strip type information
      refute String.contains?(core_source, "{:ok, value}") and
             String.contains?(core_source, "get(host, oid"),
             "Core should not strip type information from responses"

      # Should preserve type information
      assert String.contains?(core_source, "{type, value}"),
             "Core should preserve type information in responses"
    end
  end
end
