defmodule SnmpKit.SnmpLib.MIB.ParserTest do
  use ExUnit.Case, async: true
  doctest SnmpKit.SnmpLib.MIB.Parser

  @moduletag :parsing_edge_cases

  alias SnmpKit.SnmpLib.MIB.Parser

  describe "basic MIB parsing" do
    test "parses minimal MIB structure" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN

      testRoot OBJECT IDENTIFIER ::= { iso 1 }

      END
      """

      assert {:ok, mib} = Parser.parse(mib_content)

      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert mib.imports == []
      assert length(mib.definitions) == 1
    end

    test "parses MIB with imports" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      IMPORTS
          DisplayString FROM SNMPv2-TC;

      testRoot OBJECT IDENTIFIER ::= { iso 1 }

      END
      """

      assert {:ok, mib} = Parser.parse(mib_content)

      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert length(mib.imports) == 1
      assert length(mib.definitions) >= 1
    end

    test "parses simple object identifier assignment" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN

      testObjects OBJECT IDENTIFIER ::= { iso org(3) dod(6) 1 }

      END
      """

      assert {:ok, mib} = Parser.parse(mib_content)

      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert length(mib.definitions) == 1

      [definition] = mib.definitions
      assert definition.name == "testObjects"
    end

    test "parses basic OBJECT-TYPE definition" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN

      testObjects OBJECT IDENTIFIER ::= { iso 1 }

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
      assert length(mib.definitions) == 2

      object_type_def = Enum.find(mib.definitions, fn def -> def.name == "testObject" end)
      assert object_type_def != nil
      assert object_type_def.name == "testObject"
      assert object_type_def.description == "A test object"
    end
  end

  describe "error handling" do
    test "reports syntax errors with position" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      invalid syntax here
      END
      """

      assert {:error, error} = Parser.parse(mib_content)
      assert is_tuple(error)
    end

    test "handles missing required clauses" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      testObject OBJECT-TYPE
          SYNTAX INTEGER
          ::= { testObjects 1 }
      END
      """

      # Should fail due to missing MAX-ACCESS and STATUS
      assert {:error, error} = Parser.parse(mib_content)
      assert is_tuple(error)
    end

    test "handles unterminated MIB" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      testObject OBJECT-TYPE
          SYNTAX INTEGER
      """

      assert {:error, error} = Parser.parse(mib_content)
      assert is_tuple(error)
    end
  end

  describe "complex parsing" do
    test "parses MIB with multiple imports" do
      mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      IMPORTS
          DisplayString, TimeStamp
              FROM SNMPv2-TC
          Counter32, Gauge32
              FROM SNMPv2-SMI;

      testRoot OBJECT IDENTIFIER ::= { iso 1 }

      END
      """

      assert {:ok, mib} = Parser.parse(mib_content)

      assert %{__type__: :mib, name: "TEST-MIB"} = mib
      assert length(mib.imports) >= 1
      assert length(mib.definitions) >= 1
    end

    test "handles comments in MIB content" do
      mib_content = """
      -- This is a test MIB
      TEST-MIB DEFINITIONS ::= BEGIN
      -- Comment before imports
      IMPORTS
          DisplayString FROM SNMPv2-TC; -- Inline comment

      -- Comment before definition
      testRoot OBJECT IDENTIFIER ::= { iso 1 }

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

    test "handles simple MIB gracefully" do
      mib_content = """
      EMPTY-MIB DEFINITIONS ::= BEGIN

      testRoot OBJECT IDENTIFIER ::= { iso 1 }

      END
      """

      assert {:ok, mib} = Parser.parse(mib_content)
      assert %{__type__: :mib, name: "EMPTY-MIB"} = mib
      assert length(mib.definitions) == 1
      assert mib.imports == []
    end
  end
end
