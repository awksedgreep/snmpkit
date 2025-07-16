#!/usr/bin/env elixir

# OID Formats Demo
# This example demonstrates how SnmpKit supports both standard OID formats:
# - Traditional format: "1.3.6.1.2.1.1.1.0"
# - Standard format with leading dot: ".1.3.6.1.2.1.1.1.0"

Mix.install([
  {:snmpkit, path: "."}
])

defmodule OIDFormatsDemo do
  @moduledoc """
  Demonstrates OID parsing with different formats in SnmpKit.

  SnmpKit now supports both OID formats:
  1. Without leading dot (Elixir/Erlang style): "1.3.6.1.2.1.1.1.0"
  2. With leading dot (standard SNMP style): ".1.3.6.1.2.1.1.1.0"
  """

  alias SnmpKit.SnmpLib.OID

  def run do
    IO.puts("=" <> String.duplicate("=", 60))
    IO.puts("SnmpKit OID Format Support Demo")
    IO.puts("=" <> String.duplicate("=", 60))
    IO.puts("")

    # Test cases demonstrating various OID formats
    test_cases = [
      # Basic OIDs
      {"1.3.6.1.2.1.1.1.0", "System Description (without leading dot)"},
      {".1.3.6.1.2.1.1.1.0", "System Description (with leading dot)"},

      # Short OIDs
      {"1.3.6.1", "Internet OID (without leading dot)"},
      {".1.3.6.1", "Internet OID (with leading dot)"},

      # Single component
      {"1", "ISO (without leading dot)"},
      {".1", "ISO (with leading dot)"},

      # Enterprise OIDs
      {"1.3.6.1.4.1.9.1.1", "Cisco Enterprise (without leading dot)"},
      {".1.3.6.1.4.1.9.1.1", "Cisco Enterprise (with leading dot)"},

      # Common SNMP OIDs
      {"1.3.6.1.2.1.1.3.0", "System Uptime (without leading dot)"},
      {".1.3.6.1.2.1.1.3.0", "System Uptime (with leading dot)"},

      # Interface table
      {"1.3.6.1.2.1.2.2.1.2.1", "Interface Description (without leading dot)"},
      {".1.3.6.1.2.1.2.2.1.2.1", "Interface Description (with leading dot)"}
    ]

    IO.puts("Testing OID parsing with different formats:")
    IO.puts("")

    for {oid_string, description} <- test_cases do
      case OID.string_to_list(oid_string) do
        {:ok, oid_list} ->
          IO.puts("✓ #{description}")
          IO.puts("  Input:  '#{oid_string}'")
          IO.puts("  Output: #{inspect(oid_list)}")
          IO.puts("")

        {:error, reason} ->
          IO.puts("✗ #{description}")
          IO.puts("  Input:  '#{oid_string}'")
          IO.puts("  Error:  #{reason}")
          IO.puts("")
      end
    end

    # Demonstrate that both formats produce identical results
    IO.puts("Demonstrating format equivalence:")
    IO.puts("")

    equivalent_pairs = [
      {"1.3.6.1.2.1.1.1.0", ".1.3.6.1.2.1.1.1.0"},
      {"1.3.6.1", ".1.3.6.1"},
      {"42", ".42"}
    ]

    for {without_dot, with_dot} <- equivalent_pairs do
      {:ok, result1} = OID.string_to_list(without_dot)
      {:ok, result2} = OID.string_to_list(with_dot)

      equal = result1 == result2
      status = if equal, do: "✓", else: "✗"

      IO.puts("#{status} '#{without_dot}' == '#{with_dot}': #{equal}")
      IO.puts("  Without dot: #{inspect(result1)}")
      IO.puts("  With dot:    #{inspect(result2)}")
      IO.puts("")
    end

    # Test error cases
    IO.puts("Testing error cases:")
    IO.puts("")

    error_cases = [
      {"", "Empty string"},
      {".", "Just a dot"},
      {"   .   ", "Dot with whitespace"},
      {".1.2.3.a.4", "Invalid character with leading dot"},
      {".1..2.3", "Double dot with leading dot"},
      {"1.2.3.", "Trailing dot (without leading dot)"},
      {".1.2.3.", "Trailing dot (with leading dot)"}
    ]

    for {oid_string, description} <- error_cases do
      case OID.string_to_list(oid_string) do
        {:ok, result} ->
          IO.puts("✗ #{description}: Unexpected success")
          IO.puts("  Input:  '#{oid_string}'")
          IO.puts("  Result: #{inspect(result)}")
          IO.puts("")

        {:error, reason} ->
          IO.puts("✓ #{description}: Expected error")
          IO.puts("  Input: '#{oid_string}'")
          IO.puts("  Error: #{reason}")
          IO.puts("")
      end
    end

    # Demonstrate practical usage
    IO.puts("Practical usage example:")
    IO.puts("")

    # Simulate reading OIDs from different sources
    oids_from_config = [
      "1.3.6.1.2.1.1.1.0",  # Traditional format
      "1.3.6.1.2.1.1.3.0"
    ]

    oids_from_snmp_standard = [
      ".1.3.6.1.2.1.1.1.0",  # Standard format with leading dot
      ".1.3.6.1.2.1.1.3.0"
    ]

    IO.puts("Processing OIDs from configuration (traditional format):")
    for oid <- oids_from_config do
      {:ok, parsed} = OID.string_to_list(oid)
      IO.puts("  #{oid} -> #{inspect(parsed)}")
    end

    IO.puts("")
    IO.puts("Processing OIDs from SNMP standards (leading dot format):")
    for oid <- oids_from_snmp_standard do
      {:ok, parsed} = OID.string_to_list(oid)
      IO.puts("  #{oid} -> #{inspect(parsed)}")
    end

    IO.puts("")
    IO.puts("=" <> String.duplicate("=", 60))
    IO.puts("Both formats are now fully supported!")
    IO.puts("Use whichever format is most convenient for your use case.")
    IO.puts("=" <> String.duplicate("=", 60))
  end
end

# Run the demo
OIDFormatsDemo.run()
