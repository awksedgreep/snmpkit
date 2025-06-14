defmodule SnmpKit.SnmpLib.MIB.CompilerTest do
  use ExUnit.Case, async: true
  
  alias SnmpKit.SnmpLib.MIB.Compiler
  
  @moduledoc """
  Tests for the MIB Compiler interface.
  
  The Compiler module provides a high-level interface to the MIB compilation
  pipeline, which is implemented via the Parser module using YACC-based parsing.
  """
  
  describe "compile_string/2" do
    test "compiles a minimal MIB successfully" do
      # A valid v1 MIB requires at least one definition
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      
      testNode OBJECT IDENTIFIER ::= { 1 3 6 1 4 1 99999 }
      
      END
      """
      
      assert {:ok, compiled} = Compiler.compile_string(mib_content)
      assert compiled.name == "TEST-MIB"
      assert compiled.format == :binary
      assert map_size(compiled.symbols) == 1
      assert Map.has_key?(compiled.symbols, "testNode")
      assert compiled.dependencies == []
    end
    
    test "compiles a MIB with imports" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      
      IMPORTS
          DisplayString FROM SNMPv2-TC
          enterprises FROM SNMPv2-SMI;
      
      testNode OBJECT IDENTIFIER ::= { enterprises 99999 }
      
      END
      """
      
      assert {:ok, compiled} = Compiler.compile_string(mib_content)
      assert compiled.name == "TEST-MIB"
      assert compiled.dependencies == ["SNMPv2-TC", "SNMPv2-SMI"]
    end
    
    test "compiles a MIB with object definitions" do
      mib_content = "TEST-MIB DEFINITIONS ::= BEGIN\n" <>
                    "testObject OBJECT-TYPE\n" <>
                    "    SYNTAX INTEGER\n" <>
                    "    MAX-ACCESS read-only\n" <>
                    "    STATUS current\n" <>
                    "    DESCRIPTION \"A test object\"\n" <>
                    "    ::= { enterprises 12345 1 }\n" <>
                    "END\n"
      
      assert {:ok, compiled} = Compiler.compile_string(mib_content)
      assert compiled.name == "TEST-MIB"
      assert map_size(compiled.symbols) > 0
      assert Map.has_key?(compiled.symbols, "testObject")
    end
    
    test "returns error for invalid MIB syntax" do
      mib_content = """
      INVALID MIB SYNTAX
      """
      
      assert {:error, errors} = Compiler.compile_string(mib_content)
      assert is_list(errors)
      assert length(errors) > 0
    end
    
    test "respects compile options" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      
      testNode OBJECT IDENTIFIER ::= { 1 3 6 1 4 1 99999 }
      
      END
      """
      
      assert {:ok, compiled} = Compiler.compile_string(mib_content, format: :json)
      assert compiled.format == :json
    end
  end
  
  describe "compile/2" do
    test "compiles a MIB file from disk" do
      # Use a known good MIB file from fixtures
      mib_path = "test/fixtures/mibs/working/RFC1213-MIB.mib"
      
      if File.exists?(mib_path) do
        assert {:ok, compiled} = Compiler.compile(mib_path)
        assert compiled.name == "RFC1213-MIB"
        assert compiled.format == :binary
      else
        # Skip if fixtures aren't available
        :ok
      end
    end
    
    test "returns error for non-existent file" do
      assert {:error, errors} = Compiler.compile("non_existent.mib")
      assert is_list(errors)
      [error | _] = errors
      assert error.type == :file_not_found
    end
  end
  
  describe "integration with Parser" do
    test "Compiler and Parser produce compatible results" do
      mib_content = "TEST-MIB DEFINITIONS ::= BEGIN\n" <>
                    "IMPORTS\n" <>
                    "    DisplayString FROM SNMPv2-TC;\n" <>
                    "\n" <>
                    "testObject OBJECT-TYPE\n" <>
                    "    SYNTAX DisplayString\n" <>
                    "    MAX-ACCESS read-only\n" <>
                    "    STATUS current\n" <>
                    "    DESCRIPTION \"Test object\"\n" <>
                    "    ::= { enterprises 12345 1 }\n" <>
                    "END\n"
      
      # Test that Compiler properly wraps Parser functionality
      assert {:ok, compiled} = Compiler.compile_string(mib_content)
      assert {:ok, parsed} = SnmpKit.SnmpLib.MIB.Parser.parse(mib_content)
      
      # Verify the compiler adds the expected structure
      assert compiled.name == parsed.name
      assert length(compiled.dependencies) == length(parsed.imports)
      assert map_size(compiled.symbols) == length(parsed.definitions)
    end
  end
end