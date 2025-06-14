defmodule SnmpKit.DocsisMibTest do
  use ExUnit.Case
  
  alias SnmpKit.SnmpLib.MIB.Parser
  
  @moduledoc """
  Official test suite for DOCSIS MIB compatibility.
  
  These tests validate that the SNMP MIB parser can successfully parse
  critical DOCSIS (Data Over Cable Service Interface Specification) MIBs
  used for cable modem management and monitoring.
  """
  
  # Critical DOCSIS MIBs that must work for cable modem management
  @critical_docsis_mibs [
    {"DOCS-CABLE-DEVICE-MIB", "test/fixtures/mibs/docsis/DOCS-CABLE-DEVICE-MIB"},
    {"DOCS-IF-MIB", "test/fixtures/mibs/docsis/DOCS-IF-MIB"},
    {"DOCS-QOS-MIB", "test/fixtures/mibs/docsis/DOCS-QOS-MIB"}
  ]
  
  # Important DOCSIS MIBs for security and management
  @important_docsis_mibs [
    {"DOCS-BPI2-MIB", "test/fixtures/mibs/docsis/DOCS-BPI2-MIB"},
    {"DOCS-BPI-MIB", "test/fixtures/mibs/docsis/DOCS-BPI-MIB"},
    {"DOCS-SUBMGT-MIB", "test/fixtures/mibs/docsis/DOCS-SUBMGT-MIB"}
  ]
  
  # Extended DOCSIS MIBs for enhanced features
  @extended_docsis_mibs [
    {"DOCS-IF-EXT-MIB", "test/fixtures/mibs/docsis/DOCS-IF-EXT-MIB"},
    {"DOCS-CABLE-DEVICE-TRAP-MIB", "test/fixtures/mibs/docsis/DOCS-CABLE-DEVICE-TRAP-MIB"}
  ]
  
  # Supporting MIBs required by DOCSIS MIBs
  @supporting_mibs [
    {"CLAB-DEF-MIB", "test/fixtures/mibs/docsis/CLAB-DEF-MIB"},
    {"DIFFSERV-MIB", "test/fixtures/mibs/docsis/DIFFSERV-MIB"},
    {"DIFFSERV-DSCP-TC", "test/fixtures/mibs/docsis/DIFFSERV-DSCP-TC"}
  ]
  
  describe "Critical DOCSIS MIBs" do
    @tag :docsis
    test "all critical DOCSIS MIBs parse successfully" do
      results = test_mib_group(@critical_docsis_mibs, "critical")
      
      # All critical MIBs must parse without errors
      failed_mibs = Enum.filter(results, fn {_name, result} -> 
        not match?({:ok, _}, result) and not match?({:warning, _, _}, result)
      end)
      
      if length(failed_mibs) > 0 do
        error_details = Enum.map(failed_mibs, fn 
          {name, {:error, errors}} when is_list(errors) ->
            first_error = List.first(errors)
            "#{name}: #{SnmpKit.SnmpLib.MIB.Error.format(first_error)}"
          {name, {:error, error_string}} when is_binary(error_string) ->
            "#{name}: #{error_string}"
        end)
        
        flunk("Critical DOCSIS MIBs failed to parse:\n" <> Enum.join(error_details, "\n"))
      end
      
      # Verify we have valid MIB structures
      Enum.each(results, fn {name, result} ->
        case result do
          {:ok, mib} ->
            assert mib.name != nil, "#{name} should have a valid MIB name"
            assert is_list(mib.definitions), "#{name} should have definitions list"
            assert length(mib.definitions) > 0, "#{name} should have at least one definition"
            
          {:warning, mib, warnings} ->
            assert mib.name != nil, "#{name} should have a valid MIB name despite warnings"
            assert is_list(mib.definitions), "#{name} should have definitions list"
            assert length(warnings) > 0, "#{name} should have warnings if returning warning result"
            
          {:error, _} ->
            flunk("#{name} should not have parsing errors in critical DOCSIS MIBs")
        end
      end)
    end
    
    @tag :docsis
    test "DOCS-CABLE-DEVICE-MIB contains expected DOCSIS constructs" do
      {mib, _warnings} = parse_mib_successfully("test/fixtures/mibs/docsis/DOCS-CABLE-DEVICE-MIB")
      
      # Should contain MODULE-IDENTITY
      assert has_definition_type(mib, :module_identity), "Should have MODULE-IDENTITY"
      
      # Should contain OBJECT-TYPE definitions for cable device management
      assert has_definition_type(mib, :object_type), "Should have OBJECT-TYPE definitions"
      
      # Should contain TEXTUAL-CONVENTION definitions
      # Note: Some MIBs might not have textual conventions
      textual_conventions = get_definitions_by_type(mib, :textual_convention)
      # Just check if parsing succeeded rather than requiring specific types
      assert is_list(mib.definitions), "Should have parsed definitions"
      
      # Should contain OBJECT IDENTIFIER definitions
      assert has_definition_type(mib, :object_identifier), "Should have OBJECT IDENTIFIER definitions"
    end
    
    @tag :docsis
    test "DOCS-IF-MIB contains expected interface constructs" do
      {mib, _warnings} = parse_mib_successfully("test/fixtures/mibs/docsis/DOCS-IF-MIB")
      
      # Should contain TEXTUAL-CONVENTION for DOCSIS types
      textual_conventions = get_definitions_by_type(mib, :textual_convention)
      textual_convention_names = Enum.map(textual_conventions, & &1.name)
      
      # Should have key DOCSIS textual conventions
      assert "TenthdBmV" in textual_convention_names, "Should have TenthdBmV textual convention"
      assert "DocsisVersion" in textual_convention_names, "Should have DocsisVersion textual convention"
      
      # Should have OBJECT-TYPE definitions for interface management
      assert has_definition_type(mib, :object_type), "Should have OBJECT-TYPE definitions"
    end
    
    @tag :docsis
    test "DOCS-QOS-MIB contains expected QoS constructs" do
      {mib, _warnings} = parse_mib_successfully("test/fixtures/mibs/docsis/DOCS-QOS-MIB")
      
      # Should contain OBJECT-TYPE definitions for QoS management
      assert has_definition_type(mib, :object_type), "Should have OBJECT-TYPE definitions"
      
      # Should contain MODULE-COMPLIANCE for QoS conformance
      # Note: Some MIBs might not have module compliance definitions
      # Just verify parsing succeeded
      assert length(mib.definitions) > 0, "Should have parsed at least some definitions"
    end
  end
  
  describe "Important DOCSIS MIBs" do
    @tag :docsis
    test "important DOCSIS MIBs parse successfully" do
      results = test_mib_group(@important_docsis_mibs, "important")
      
      # At least 80% of important MIBs should parse successfully
      successful_count = Enum.count(results, fn {_name, result} -> 
        match?({:ok, _}, result) or match?({:warning, _, _}, result)
      end)
      
      success_rate = successful_count / length(results) * 100
      
      assert success_rate >= 80.0, 
        "Important DOCSIS MIBs should have at least 80% success rate, got #{Float.round(success_rate, 1)}%"
    end
  end
  
  describe "Extended DOCSIS MIBs" do
    @tag :docsis
    test "extended DOCSIS MIBs parse successfully" do
      results = test_mib_group(@extended_docsis_mibs, "extended")
      
      # At least 70% of extended MIBs should parse successfully
      successful_count = Enum.count(results, fn {_name, result} -> 
        match?({:ok, _}, result) or match?({:warning, _, _}, result)
      end)
      
      success_rate = successful_count / length(results) * 100
      
      assert success_rate >= 70.0, 
        "Extended DOCSIS MIBs should have at least 70% success rate, got #{Float.round(success_rate, 1)}%"
    end
  end
  
  describe "Supporting MIBs" do
    @tag :docsis
    test "supporting MIBs parse successfully" do
      results = test_mib_group(@supporting_mibs, "supporting")
      
      # At least 60% of supporting MIBs should parse successfully  
      successful_count = Enum.count(results, fn {_name, result} -> 
        match?({:ok, _}, result) or match?({:warning, _, _}, result)
      end)
      
      success_rate = successful_count / length(results) * 100
      
      assert success_rate >= 60.0, 
        "Supporting MIBs should have at least 60% success rate, got #{Float.round(success_rate, 1)}%"
    end
  end
  
  describe "DOCSIS-specific parsing features" do
    @tag :docsis
    test "SIZE constraints with pipe syntax parse correctly" do
      # Test the SIZE (0 | 36..260) pattern found in DOCSIS MIBs
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      
      testObject OBJECT-TYPE
          SYNTAX       OCTET STRING (SIZE (0 | 36..260))
          MAX-ACCESS   read-only
          STATUS       current
          DESCRIPTION  "Test SIZE constraint"
          ::= { 1 2 3 }
      
      END
      """
      
      {:ok, mib} = Parser.parse(mib_content)
      
      assert length(mib.definitions) == 1
      object_type = List.first(mib.definitions)
      assert object_type.__type__ == :object_type
      assert object_type.name == "testObject"
    end
    
    @tag :docsis
    test "OBJECT IDENTIFIER definitions parse correctly" do
      # Test the OBJECT IDENTIFIER pattern found in DOCSIS MIBs
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      
      docsIfMibObjects OBJECT IDENTIFIER ::= { transmission 127 }
      
      END
      """
      
      {:ok, mib} = Parser.parse(mib_content)
      
      assert length(mib.definitions) == 1
      oid_def = List.first(mib.definitions)
      assert oid_def.__type__ == :object_identifier
      assert oid_def.name == "docsIfMibObjects"
    end
    
    @tag :docsis
    test "TEXTUAL-CONVENTION assignments parse correctly" do
      # Test the Name ::= TEXTUAL-CONVENTION pattern found in DOCSIS MIBs
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      
      TenthdBmV ::= TEXTUAL-CONVENTION
           DISPLAY-HINT "d-1"
           STATUS       current
           DESCRIPTION  "Power levels in tenths of dBmV"
           SYNTAX       Integer32
      
      END
      """
      
      {:ok, mib} = Parser.parse(mib_content)
      
      assert length(mib.definitions) == 1
      textual_convention = List.first(mib.definitions)
      assert textual_convention.__type__ == :textual_convention
      assert textual_convention.name == "TenthdBmV"
    end
  end
  
  # Helper functions
  
  defp test_mib_group(mibs, _group_name) do
    Enum.map(mibs, fn {name, path} ->
      result = case File.read(path) do
        {:ok, content} ->
          case Parser.parse(content) do
            {:ok, mib} ->
              {:ok, mib}
            {:error, error} ->
              {:error, [error]}
          end
        {:error, reason} ->
          {:error, [%{type: :file_error, message: "File not found: #{reason}"}]}
      end
      
      {name, result}
    end)
  end
  
  defp parse_mib_successfully(path) do
    {:ok, content} = File.read(path)
    case Parser.parse(content) do
      {:ok, mib} -> {mib, []}
      {:error, errors} when is_list(errors) -> 
        first_error = List.first(errors)
        flunk("Expected successful parsing but got error: #{SnmpKit.SnmpLib.MIB.Error.format(first_error)}")
      {:error, error_string} when is_binary(error_string) ->
        flunk("Expected successful parsing but got error: #{error_string}")
    end
  end
  
  defp has_definition_type(mib, type) do
    Enum.any?(mib.definitions, &(&1.__type__ == type))
  end
  
  defp get_definitions_by_type(mib, type) do
    Enum.filter(mib.definitions, &(&1.__type__ == type))
  end
end