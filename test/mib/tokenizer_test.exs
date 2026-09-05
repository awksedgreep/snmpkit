defmodule SnmpKit.MIB.SnmpTokenizerTest do
  use ExUnit.Case, async: true

  alias SnmpKit.MIB.{Parser, SnmpTokenizer}

  defp tokens(text) do
    {:ok, toks} = SnmpTokenizer.tokenize(String.to_charlist(text), fn -> :eof end)
    # drop the trailing end-of-input marker
    Enum.reject(toks, &match?({:"$end", _}, &1))
  end

  defp mib_with(body) do
    """
    TOK-TEST-MIB DEFINITIONS ::= BEGIN
    IMPORTS OBJECT-TYPE, Integer32 FROM SNMPv2-SMI TruthValue FROM SNMPv2-TC;
    tokTest OBJECT IDENTIFIER ::= { enterprises 99999 }
    #{body}
    END
    """
  end

  defp object(mib, name), do: Enum.find(mib.definitions, &(&1.name == name))

  test "identifiers are emitted as binaries, not atoms" do
    assert [{:atom, 1, "sysDescr"}, {:variable, 1, "DisplayString"}, {:integer, 1, 7}] =
             tokens("sysDescr DisplayString 7")
  end

  test "tokenizing unseen identifiers does not create atoms for them" do
    names =
      for _ <- 1..200, do: "id#{System.unique_integer([:positive])}x#{:rand.uniform(1_000_000)}"

    toks = tokens(Enum.join(names, " "))
    assert length(toks) == 200

    for name <- names do
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end

  test "hex and binary string literals keep their radix suffix" do
    assert [{:quote, 1, ~c"FF"}, {:variable, 1, "H"}, {:quote, 1, ~c"1010"}, {:atom, 1, "b"}] =
             tokens("'FF'H '0101'b")
  end

  test "hex DEFVAL decodes to bytes and the empty hex string to an empty list" do
    {:ok, mib} =
      Parser.parse(
        mib_with("""
        tokHex OBJECT-TYPE
          SYNTAX OCTET STRING (SIZE (0..'FF'H))
          MAX-ACCESS read-write
          STATUS current
          DESCRIPTION "hex"
          DEFVAL { 'C0A8'H }
          ::= { tokTest 1 }
        tokEmpty OBJECT-TYPE
          SYNTAX OCTET STRING
          MAX-ACCESS read-write
          STATUS current
          DESCRIPTION "empty"
          DEFVAL { ''h }
          ::= { tokTest 2 }
        """)
      )

    assert %{kind: {:variable, [defval: [0xC0, 0xA8]]}} = object(mib, "tokHex")
    assert %{kind: {:variable, [defval: []]}} = object(mib, "tokEmpty")
    assert inspect(object(mib, "tokHex").syntax) =~ "255"
  end

  test "enumeration labels named true/false stay strings" do
    {:ok, mib} =
      Parser.parse(
        mib_with("""
        tokFlag OBJECT-TYPE
          SYNTAX INTEGER { true(1), false(2) }
          MAX-ACCESS read-write
          STATUS current
          DESCRIPTION "flag"
          DEFVAL { true }
          ::= { tokTest 3 }
        """)
      )

    assert %{kind: {:variable, [defval: "true"]}} = object(mib, "tokFlag")
  end
end
