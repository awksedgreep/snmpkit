defmodule SnmpKit.SnmpLib.MIB.ParserTest do
  use ExUnit.Case, async: true
  doctest SnmpKit.SnmpLib.MIB.Parser
  
  @moduletag :parsing_edge_cases
  
  alias SnmpKit.SnmpLib.MIB.{Parser, Error}
  
  describe "basic MIB parsing" do
    test "parses minimal MIB structure" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      
      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert mib.imports == []
      assert mib.definitions == []
    end
    
    test "parses MIB with imports" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      IMPORTS
          DisplayString FROM SNMPv2-TC;
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      
      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert length(mib.imports) == 1
      
      [import] = mib.imports
      assert %{__type__: :import, symbols: ["DisplayString"], from_module: "SNMPv2-TC"} = import
    end
    
    test "parses simple object identifier assignment" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      testObjects ::= { iso org(3) dod(6) 1 }
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      
      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert length(mib.definitions) == 1
      
      [definition] = mib.definitions
      assert %{__type__: :object_identifier_assignment, name: "testObjects"} = definition
    end
    
    test "parses basic OBJECT-TYPE definition" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      testObject OBJECT-TYPE
          SYNTAX INTEGER
          MAX-ACCESS read-only
          STATUS current
          DESCRIPTION "A test object"
          ::= { testObjects 1 }
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      
      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert length(mib.definitions) == 1
      
      [definition] = mib.definitions
      assert %{
        __type__: :object_type,
        name: "testObject",
        syntax: :integer,
        max_access: :read_only,
        status: :current,
        description: "A test object"
      } = definition
    end
  end
  
  describe "error handling" do
    test "reports syntax errors with position" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      invalid syntax here
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      assert {:error, errors} = Parser.parse(mib_content)
      
      assert is_list(errors)
      assert length(errors) > 0
      
      error = hd(errors)
      assert %Error{type: :unexpected_token} = error
    end
    
    test "handles missing required clauses" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      testObject OBJECT-TYPE
          SYNTAX INTEGER
          ::= { testObjects 1 }
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      # Should fail due to missing MAX-ACCESS and STATUS
      assert {:error, errors} = Parser.parse(mib_content)
      assert is_list(errors)
    end
    
    test "handles unterminated MIB" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      testObject OBJECT-TYPE
          SYNTAX INTEGER
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      assert {:error, errors} = Parser.parse(mib_content)
      assert is_list(errors)
    end
  end
  
  describe "complex parsing" do
    test "parses MIB with multiple imports" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      IMPORTS
          DisplayString, TimeStamp FROM SNMPv2-TC,
          Counter32, Gauge32 FROM SNMPv2-SMI;
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      
      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert length(mib.imports) == 2
      
      [import1, import2] = mib.imports
      assert import1.from_module in ["SNMPv2-TC", "SNMPv2-SMI"]
      assert import2.from_module in ["SNMPv2-TC", "SNMPv2-SMI"]
    end
    
    test "handles comments in MIB content" do
      mib_content = """
      -- This is a test MIB
      TEST-MIB DEFINITIONS ::= BEGIN
      -- Comment before imports
      IMPORTS
          DisplayString FROM SNMPv2-TC; -- Inline comment
      -- Comment before end
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      
      assert %{__type__: :mib, name: "TEST-MIB"} = mib
    end
  end
  
  describe "full parsing integration" do
    test "parses MIB content with OBJECT-TYPE definitions" do
      mib_content = """
      SIMPLE-MIB DEFINITIONS ::= BEGIN
      simpleObject OBJECT-TYPE
          SYNTAX DisplayString
          MAX-ACCESS read-only
          STATUS current
          DESCRIPTION "Simple test object"
          ::= { iso 1 }
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      assert %{__type__: :mib, name: "SIMPLE-MIB"} = mib
      assert length(mib.definitions) == 1
    end
    
    test "handles empty MIB gracefully" do
      mib_content = """
      EMPTY-MIB DEFINITIONS ::= BEGIN
      END
      """
      
      assert {:ok, mib} = Parser.parse(mib_content)
      assert %{__type__: :mib, name: "EMPTY-MIB"} = mib
      assert mib.definitions == []
      assert mib.imports == []
    end
  end
end