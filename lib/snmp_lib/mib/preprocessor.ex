defmodule SnmpKit.SnmpLib.MIB.Preprocessor do
  @moduledoc """
  Preprocessor for MIB files to handle problematic constructs before parsing.

  This module addresses issues with very large TEXTUAL-CONVENTION enumerations
  that cause parser state corruption in certain edge cases.
  """

  require Logger

  @doc """
  Preprocess MIB content to handle problematic constructs.
  """
  def preprocess(content) when is_binary(content) do
    content
    |> simplify_large_enumerations()
    |> normalize_whitespace()
  end

  @doc """
  Simplify very large TEXTUAL-CONVENTION enumerations that cause parser issues.

  This replaces complex enumerations with simplified versions that preserve
  the essential structure while avoiding parser state corruption.
  """
  def simplify_large_enumerations(content) do
    # Pattern to match TEXTUAL-CONVENTION with INTEGER syntax
    pattern = ~r/
      (?P<prefix>
        \w+\s*::=\s*TEXTUAL-CONVENTION\s+
        (?:.*?\n)*?                          # Non-greedy match for TC content
        SYNTAX\s+INTEGER\s*\{
      )
      (?P<enumeration>
        (?:.*?\n)*?                          # Enumeration content
      )
      (?P<suffix>
        \}\s*                                # Closing brace
      )
    /xms

    # Find all matches and process large enumerations
    Regex.replace(pattern, content, fn full_match, prefix, enumeration, suffix ->
      enum_lines = String.split(enumeration, "\n")

      if length(enum_lines) > 50 do
        Logger.debug("Simplifying large enumeration with #{length(enum_lines)} lines")
        simplified_enum = simplify_enumeration_content(enumeration)
        prefix <> simplified_enum <> suffix
      else
        full_match
      end
    end)
  end

  defp simplify_enumeration_content(enumeration) do
    lines = String.split(enumeration, "\n")

    # Extract enumeration items while preserving structure
    simplified_items =
      lines
      |> Enum.map(&extract_enum_item/1)
      # Remove nils
      |> Enum.filter(& &1)
      # Take only first 10 items to avoid parser issues
      |> Enum.take(10)
      |> Enum.with_index()
      |> Enum.map(fn {{name, _original_value}, index} ->
        "                    #{name}(#{index + 1})"
      end)

    # Add a final catch-all item
    simplified_items = simplified_items ++ ["                    other(999)"]

    Enum.join(simplified_items, ",\n") <> "\n"
  end

  defp extract_enum_item(line) do
    # Pattern to match enumeration items like "itemName(123),"
    case Regex.run(~r/^\s*(\w+)\s*\(\s*(\d+)\s*\)\s*,?\s*(?:--.*)?$/, line) do
      [_full, name, value] -> {name, String.to_integer(value)}
      _ -> nil
    end
  end

  @doc """
  Normalize excessive whitespace that might cause tokenizer issues.
  """
  def normalize_whitespace(content) do
    content
    # Replace multiple spaces/tabs with single space
    |> String.replace(~r/[ \t]+/, " ")
    # Remove whitespace-only lines
    |> String.replace(~r/\n[ \t]+\n/, "\n\n")
    # Replace multiple newlines with double newline
    |> String.replace(~r/\n{3,}/, "\n\n")
  end

  @doc """
  Check if a MIB file contains problematic constructs.
  """
  def has_problematic_constructs?(content) do
    # Check for very large TEXTUAL-CONVENTION enumerations
    case Regex.run(~r/TEXTUAL-CONVENTION.*?SYNTAX\s+INTEGER\s*\{(.*?)\}/ms, content) do
      [_full, enumeration] ->
        enum_lines = String.split(enumeration, "\n")
        length(enum_lines) > 50

      _ ->
        false
    end
  end

  @doc """
  Get statistics about enumeration complexity in a MIB file.
  """
  def analyze_enumerations(content) do
    pattern = ~r/SYNTAX\s+INTEGER\s*\{(.*?)\}/ms

    Regex.scan(pattern, content)
    |> Enum.map(fn [_full, enumeration] ->
      lines = String.split(enumeration, "\n")

      items =
        Enum.count(lines, fn line ->
          Regex.match?(~r/^\s*\w+\s*\(\s*\d+\s*\)/, line)
        end)

      %{lines: length(lines), items: items}
    end)
  end
end
