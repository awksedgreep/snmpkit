defmodule SnmpKit.SnmpKit.SnmpLib.MIB.Error do
  @moduledoc """
  Enhanced error handling with recovery and detailed diagnostics.

  Provides structured error reporting with context, suggestions, and
  precise location information for MIB compilation errors.
  """

  @type t :: %__MODULE__{
          type: error_type(),
          message: binary(),
          line: integer() | nil,
          column: integer() | nil,
          context: map(),
          suggestions: [binary()]
        }

  @type error_type ::
          :syntax_error
          | :semantic_error
          | :import_error
          | :type_error
          | :constraint_error
          | :duplicate_definition
          | :file_not_found
          | :unterminated_string
          | :unexpected_token
          | :unexpected_eof
          | :invalid_number
          | :invalid_identifier

  defstruct [:type, :message, :line, :column, :context, suggestions: []]

  @doc """
  Create a new error with detailed context and suggestions.

  ## Examples

      iex> SnmpKit.SnmpKit.SnmpLib.MIB.Error.new(:unexpected_token,
      ...>   expected: :max_access,
      ...>   actual: :access,
      ...>   line: 42,
      ...>   column: 10
      ...> )
      %SnmpKit.SnmpKit.SnmpLib.MIB.Error{
        type: :unexpected_token,
        message: "Expected max_access, but found access",
        suggestions: ["Did you mean 'MAX-ACCESS' instead of 'ACCESS'?"]
      }
  """
  @spec new(error_type(), keyword()) :: t()
  def new(type, opts \\ []) do
    %__MODULE__{
      type: type,
      message: generate_message(type, opts),
      line: opts[:line],
      column: opts[:column],
      context: opts[:context] || %{},
      suggestions: generate_suggestions(type, opts)
    }
  end

  @doc """
  Format an error for display with optional color coding.

  ## Examples

      iex> error = SnmpKit.SnmpKit.SnmpLib.MIB.Error.new(:syntax_error, line: 42, column: 10)
      iex> SnmpKit.SnmpKit.SnmpLib.MIB.Error.format(error)
      "Error at line 42, column 10: Syntax error"
  """
  @spec format(t(), keyword()) :: binary()
  def format(%__MODULE__{} = error, _opts \\ []) do
    location = format_location(error)
    suggestions = format_suggestions(error.suggestions)

    base_message =
      case location do
        "" ->
          "#{error.type |> to_string() |> String.replace("_", " ") |> String.capitalize()}: #{error.message}"

        loc ->
          "#{loc}: #{error.message}"
      end

    case suggestions do
      "" -> base_message
      sugg -> "#{base_message}\n#{sugg}"
    end
  end

  # Generate human-readable error messages
  defp generate_message(:unexpected_token, opts) do
    expected = format_token_value(opts[:expected])
    actual = format_token_value(opts[:actual])
    value = opts[:value]
    message = opts[:message]

    cond do
      message != nil -> message
      value != nil -> "Expected #{expected}, but found #{actual} '#{value}'"
      actual == "" or actual == "nil" -> "Expected #{expected}, but found end of input"
      expected == "" or expected == "nil" -> "Unexpected token #{actual}"
      true -> "Expected #{expected}, but found #{actual}"
    end
  end

  defp generate_message(:unexpected_eof, opts) do
    expected = opts[:expected] |> to_string()
    "Unexpected end of file, expected #{expected}"
  end

  defp generate_message(:unterminated_string, _opts) do
    "Unterminated string literal"
  end

  defp generate_message(:invalid_number, opts) do
    value = opts[:value]
    "Invalid number format: '#{value}'"
  end

  defp generate_message(:invalid_identifier, opts) do
    value = opts[:value]
    "Invalid identifier: '#{value}'"
  end

  defp generate_message(:file_not_found, opts) do
    file = opts[:file]
    "File not found: #{file}"
  end

  defp generate_message(:import_error, opts) do
    symbol = opts[:symbol]
    from_module = opts[:from_module]
    "Cannot import '#{symbol}' from '#{from_module}'"
  end

  defp generate_message(:duplicate_definition, opts) do
    name = opts[:name]
    "Duplicate definition of '#{name}'"
  end

  defp generate_message(type, _opts) do
    type |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  # Helper to format token values properly
  defp format_token_value(nil), do: "unknown"
  defp format_token_value(""), do: "unknown"
  defp format_token_value(value) when is_atom(value), do: to_string(value)
  defp format_token_value(value) when is_binary(value), do: value
  defp format_token_value(value), do: inspect(value)

  # Generate helpful suggestions based on error type and context
  defp generate_suggestions(:unexpected_token, opts) do
    case {opts[:expected], opts[:actual]} do
      {:max_access, :access} ->
        ["Did you mean 'MAX-ACCESS' instead of 'ACCESS'?"]

      {:current, :mandatory} ->
        ["'mandatory' is deprecated, use 'current' instead"]

      {:object_type, :object_identity} ->
        ["Check if this should be 'OBJECT-TYPE' or 'OBJECT-IDENTITY'"]

      _ ->
        []
    end
  end

  defp generate_suggestions(:unterminated_string, _opts) do
    ["Check for missing closing quote", "Verify string escaping is correct"]
  end

  defp generate_suggestions(:file_not_found, opts) do
    file = opts[:file]
    suggestions = ["Check if the file path is correct"]

    # Add spelling suggestions if file seems like a common MIB name
    if String.contains?(file, "RFC") or String.contains?(file, "MIB") do
      suggestions ++
        ["Check MIB file naming conventions", "Verify file extension (.txt, .mib, .my)"]
    else
      suggestions
    end
  end

  defp generate_suggestions(:import_error, _opts) do
    [
      "Check if the imported MIB is available",
      "Verify the symbol name is spelled correctly",
      "Ensure import dependencies are in the correct order"
    ]
  end

  defp generate_suggestions(_, _opts), do: []

  # Format location information
  defp format_location(%{line: nil, column: nil}), do: ""
  defp format_location(%{line: line, column: nil}), do: "Line #{line}"
  defp format_location(%{line: nil, column: col}), do: "Column #{col}"
  defp format_location(%{line: line, column: col}), do: "Line #{line}, column #{col}"

  # Format suggestions
  defp format_suggestions([]), do: ""

  defp format_suggestions(suggestions) do
    formatted =
      suggestions
      |> Enum.map(&"  • #{&1}")
      |> Enum.join("\n")

    "Suggestions:\n#{formatted}"
  end
end
