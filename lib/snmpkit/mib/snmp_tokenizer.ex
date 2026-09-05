defmodule SnmpKit.MIB.SnmpTokenizer do
  @moduledoc """
  True 1:1 Elixir port of Erlang SNMP tokenizer (snmpc_tok.erl).

  This is a direct translation of the official Erlang SNMP tokenizer
  from OTP lib/snmp/src/compile/snmpc_tok.erl

  Original copyright: Ericsson AB 1996-2025 (Apache License 2.0)
  """

  use GenServer

  # State record equivalent
  defstruct line: 1, chars: [], get_line_fun: nil, warnings: []

  @type state() :: %__MODULE__{
          line: pos_integer(),
          chars: charlist(),
          get_line_fun: function() | nil
        }

  @typedoc """
  A token is `{category, line}` for reserved words and punctuation, or
  `{category, line, value}` for `:integer`, `:string`, `:variable`,
  `:atom` and `:quote`. Identifier values (`:variable`, `:atom`) are
  binaries, never runtime-created atoms, so an untrusted MIB cannot grow
  the atom table. `:quote` carries the quoted characters as a reversed
  charlist, matching the OTP `snmpc_tok` convention the grammar expects.
  """
  @type token() :: {atom(), pos_integer()} | {atom(), pos_integer(), any()}

  @typedoc "A lexical warning: `{line, message}`. Modelled on libsmi's lexer diagnostics."
  @type warning() :: {non_neg_integer(), String.t()}

  # API Functions - exact equivalents from Erlang

  @doc """
  Start tokenizer gen_server.
  Equivalent to snmpc_tok:start_link/2
  """
  @spec start_link(charlist(), pid()) :: {:ok, pid()} | {:error, term()}
  def start_link(chars, get_line_pid) when is_list(chars) and is_pid(get_line_pid) do
    GenServer.start_link(__MODULE__, {chars, get_line_pid}, [])
  end

  @doc """
  Get next token from tokenizer.
  Equivalent to snmpc_tok:get_token/1
  """
  @spec get_token(pid()) :: {:ok, token()} | {:error, term()}
  def get_token(pid) do
    GenServer.call(pid, :get_token)
  end

  @doc """
  Get all remaining tokens.
  Equivalent to snmpc_tok:get_all_tokens/1
  """
  @spec get_all_tokens(pid()) :: {:ok, [token()]} | {:error, term()}
  def get_all_tokens(pid) do
    GenServer.call(pid, :get_all_tokens)
  end

  @doc """
  Tokenize a string directly.
  Equivalent to snmpc_tok:tokenize/2
  """
  @spec tokenize(charlist(), function()) :: {:ok, [token()]} | {:error, term()}
  def tokenize(chars, _get_line_fun) when is_list(chars) do
    case scan(chars) do
      {:ok, tokens, _warnings} -> {:ok, tokens}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Tokenize MIB text and return lexical warnings alongside the tokens.

  Accepts a binary or a charlist. A binary that is not valid UTF-8 is decoded
  as Latin-1 with a warning instead of failing, since vendor MIBs are often
  saved in legacy code pages. Warnings follow libsmi's lexer checks:
  underscores or trailing hyphens in identifiers, hex strings with an odd
  digit count, binary strings whose length is not a multiple of eight, and
  non-radix characters inside those literals.
  """
  @spec scan(binary() | charlist()) :: {:ok, [token()], [warning()]} | {:error, term()}
  def scan(input) when is_binary(input) do
    {chars, warnings} = decode_input(input)
    do_scan(chars, warnings)
  end

  def scan(chars) when is_list(chars), do: do_scan(chars, [])

  defp do_scan(chars, warnings) do
    state = %__MODULE__{line: 1, chars: chars, get_line_fun: &null_get_line/0, warnings: warnings}

    case tokenize_all_direct(state, []) do
      {:ok, tokens, final_state} ->
        {:ok, Enum.reverse(tokens), Enum.reverse(final_state.warnings)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_input(binary) do
    if String.valid?(binary) do
      {String.to_charlist(binary), []}
    else
      line = invalid_utf8_line(binary, 1)

      {:binary.bin_to_list(binary),
       [{line, "input is not valid UTF-8; bytes decoded as Latin-1"}]}
    end
  end

  defp invalid_utf8_line(<<?\n, rest::binary>>, line), do: invalid_utf8_line(rest, line + 1)
  defp invalid_utf8_line(<<_::utf8, rest::binary>>, line), do: invalid_utf8_line(rest, line)
  defp invalid_utf8_line(_, line), do: line

  defp warn(state, line, message), do: %{state | warnings: [{line, message} | state.warnings]}

  # Direct tokenization without gen_server
  defp tokenize_all_direct(state, acc) do
    case tokenise(state) do
      {{:"$end", _line}, new_state} ->
        {:ok, [{:"$end", state.line} | acc], new_state}

      {{:eof, _line}, new_state} ->
        {:ok, [{:"$end", state.line} | acc], new_state}

      {token, new_state} ->
        tokenize_all_direct(new_state, [token | acc])

      {:error, reason, _new_state} ->
        {:error, reason}
    end
  end

  @doc """
  Stop tokenizer.
  Equivalent to snmpc_tok:stop/1
  """
  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  @doc """
  Format error message.
  Equivalent to snmpc_tok:format_error/1
  """
  @spec format_error(term()) :: charlist()
  def format_error(error) do
    case error do
      {:illegal, char} ->
        :io_lib.format(~c"illegal character '~c'", [char])

      {:illegal, char, line} ->
        :io_lib.format(~c"illegal character '~c' on line ~p", [char, line])

      {:unterminated_string, line} ->
        :io_lib.format(~c"unterminated string starting at line ~p", [line])

      {:unterminated_quote, line} ->
        :io_lib.format(~c"unterminated quote starting at line ~p", [line])

      other ->
        :io_lib.format(~c"~p", [other])
    end
  end

  @doc """
  Null get_line function.
  Equivalent to snmpc_tok:null_get_line/0
  """
  @spec null_get_line() :: :eof
  def null_get_line(), do: :eof

  @doc """
  Test function.
  Equivalent to snmpc_tok:test/0
  """
  def test() do
    test_string =
      ~c"TEST-MIB DEFINITIONS ::= BEGIN testObject OBJECT IDENTIFIER ::= { test 1 } END"

    case tokenize(test_string, &null_get_line/0) do
      {:ok, tokens} ->
        :io.format(~c"Tokens: ~p~n", [tokens])
        :ok

      {:error, reason} ->
        :io.format(~c"Error: ~p~n", [reason])
        :error
    end
  end

  # GenServer callbacks

  @impl true
  def init({chars, get_line_pid}) do
    get_line_fun = fn ->
      case GenServer.call(get_line_pid, :get_line) do
        line when is_list(line) -> line
        :eof -> :eof
        other -> other
      end
    end

    state = %__MODULE__{
      line: 1,
      chars: chars,
      get_line_fun: get_line_fun
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_token, _from, state) do
    case tokenise(state) do
      {token, new_state} ->
        {:reply, {:ok, token}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:get_all_tokens, _from, state) do
    case get_all_tokens_loop(state, []) do
      {:ok, tokens, new_state} ->
        {:reply, {:ok, Enum.reverse(tokens)}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  # Private tokenization functions - direct ports from Erlang

  # Get all tokens loop
  defp get_all_tokens_loop(state, acc) do
    case tokenise(state) do
      {{:eof, _line}, new_state} ->
        {:ok, [{:eof, state.line} | acc], new_state}

      {token, new_state} ->
        get_all_tokens_loop(new_state, [token | acc])

      {:error, reason, new_state} ->
        {:error, reason, new_state}
    end
  end

  # Main tokenization function - direct port from tokenise/1
  defp tokenise(%__MODULE__{chars: []} = state) do
    # For direct tokenization, we've reached the end
    {{:"$end", state.line}, state}
  end

  defp tokenise(%__MODULE__{chars: [?\s | chars]} = state) do
    # Skip whitespace
    new_state = %{state | chars: chars}
    tokenise(new_state)
  end

  defp tokenise(%__MODULE__{chars: [?\t | chars]} = state) do
    # Skip tab
    new_state = %{state | chars: chars}
    tokenise(new_state)
  end

  defp tokenise(%__MODULE__{chars: [?\n | chars]} = state) do
    # Handle newline
    new_state = %{state | chars: chars, line: state.line + 1}
    tokenise(new_state)
  end

  defp tokenise(%__MODULE__{chars: [?\r | chars]} = state) do
    # Skip carriage return
    new_state = %{state | chars: chars}
    tokenise(new_state)
  end

  defp tokenise(%__MODULE__{chars: [?-, ?- | chars]} = state) do
    # Handle comments --
    new_state = %{state | chars: chars}
    skip_comment(new_state)
  end

  defp tokenise(%__MODULE__{chars: [?" | chars]} = state) do
    # Handle string literals
    scan_string(chars, [], state.line, %{state | chars: chars})
  end

  defp tokenise(%__MODULE__{chars: [?' | chars]} = state) do
    # Handle quoted atoms
    scan_quote(chars, [], state.line, %{state | chars: chars})
  end

  defp tokenise(%__MODULE__{chars: [?{ | chars]} = state) do
    # Left brace
    new_state = %{state | chars: chars}
    {{:"{", state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?} | chars]} = state) do
    # Right brace
    new_state = %{state | chars: chars}
    {{:"}", state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?( | chars]} = state) do
    # Left parenthesis
    new_state = %{state | chars: chars}
    {{:"(", state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?) | chars]} = state) do
    # Right parenthesis
    new_state = %{state | chars: chars}
    {{:")", state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?[ | chars]} = state) do
    # Left bracket
    new_state = %{state | chars: chars}
    {{:"[", state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?] | chars]} = state) do
    # Right bracket
    new_state = %{state | chars: chars}
    {{:"]", state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?, | chars]} = state) do
    # Comma
    new_state = %{state | chars: chars}
    {{:",", state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?; | chars]} = state) do
    # Semicolon
    new_state = %{state | chars: chars}
    {{:";", state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?| | chars]} = state) do
    # Pipe
    new_state = %{state | chars: chars}
    {{:|, state.line}, new_state}
  end

  defp tokenise(%__MODULE__{chars: [?: | chars]} = state) do
    # Handle :: and ::=
    case chars do
      [?: | more_chars] ->
        case more_chars do
          [?= | remaining] ->
            # ::=
            new_state = %{state | chars: remaining}
            {{:"::=", state.line}, new_state}

          _ ->
            # ::
            new_state = %{state | chars: more_chars}
            {{:"::", state.line}, new_state}
        end

      _ ->
        # :
        new_state = %{state | chars: chars}
        {{:":", state.line}, new_state}
    end
  end

  defp tokenise(%__MODULE__{chars: [?. | chars]} = state) do
    # Handle .. (range)
    case chars do
      [?. | more_chars] ->
        # ..
        new_state = %{state | chars: more_chars}
        {{:.., state.line}, new_state}

      _ ->
        # .
        new_state = %{state | chars: chars}
        {{:., state.line}, new_state}
    end
  end

  defp tokenise(%__MODULE__{chars: [?- | chars]} = state) do
    # Handle negative numbers or minus
    case chars do
      [digit | _] when digit >= ?0 and digit <= ?9 ->
        scan_integer(state.chars, [], state.line, state)

      _ ->
        # Single minus
        new_state = %{state | chars: chars}
        {{:-, state.line}, new_state}
    end
  end

  defp tokenise(%__MODULE__{chars: [digit | _chars]} = state) when digit >= ?0 and digit <= ?9 do
    # Handle positive integers
    scan_integer(state.chars, [], state.line, state)
  end

  defp tokenise(%__MODULE__{chars: [char | _chars]} = state)
       when (char >= ?a and char <= ?z) or (char >= ?A and char <= ?Z) or char == ?_ do
    # Handle identifiers and atoms
    scan_name(state.chars, [], state.line, state)
  end

  defp tokenise(%__MODULE__{chars: [char | chars]} = state) do
    # Illegal character
    new_state = %{state | chars: chars}
    {:error, {:illegal, char, state.line}, new_state}
  end

  # Skip comment until end of line
  defp skip_comment(%__MODULE__{chars: []} = state) do
    tokenise(state)
  end

  defp skip_comment(%__MODULE__{chars: [?\n | chars]} = state) do
    new_state = %{state | chars: chars, line: state.line + 1}
    tokenise(new_state)
  end

  defp skip_comment(%__MODULE__{chars: [_char | chars]} = state) do
    new_state = %{state | chars: chars}
    skip_comment(new_state)
  end

  # Scan string literal
  defp scan_string([], _acc, start_line, state) do
    {:error, {:unterminated_string, start_line}, state}
  end

  defp scan_string([?" | chars], acc, _start_line, state) do
    # End of string - convert to Elixir string
    string_value = acc |> Enum.reverse() |> List.to_string()
    new_state = %{state | chars: chars}
    {{:string, state.line, string_value}, new_state}
  end

  defp scan_string([?\n | chars], acc, start_line, state) do
    # Newline in string
    new_state = %{state | chars: chars, line: state.line + 1}
    scan_string(chars, [?\n | acc], start_line, new_state)
  end

  defp scan_string([char | chars], acc, start_line, state) do
    # Regular character
    scan_string(chars, [char | acc], start_line, state)
  end

  # Scan quoted atom
  defp scan_quote([], _acc, start_line, state) do
    {:error, {:unterminated_quote, start_line}, state}
  end

  defp scan_quote([?' | chars], acc, _start_line, state) do
    new_state = %{state | chars: chars}

    if radix_suffix?(chars) do
      # 'FF'H / 'FF'h / '0101'B / '0101'b: emit the quoted characters as a
      # :quote token (reversed, as snmpc_tok does) and leave the radix
      # letter in the stream so the grammar sees `quote atom|variable`.
      text = acc |> Enum.reverse() |> List.to_string()
      {{:quote, state.line, acc}, check_radix_literal(new_state, hd(chars), text)}
    else
      {{:atom, state.line, acc |> Enum.reverse() |> List.to_string()}, new_state}
    end
  end

  defp scan_quote([?\\ | chars], acc, start_line, state) do
    # Handle escape sequences in quotes
    case chars do
      [escaped_char | rest] ->
        new_acc = [escaped_char | acc]
        scan_quote(rest, new_acc, start_line, state)

      [] ->
        {:error, {:unterminated_quote, start_line}, state}
    end
  end

  defp scan_quote([char | chars], acc, start_line, state) do
    # Regular character in quote
    scan_quote(chars, [char | acc], start_line, state)
  end

  # A radix letter directly after the closing quote that is itself a
  # complete one-letter name.
  defp radix_suffix?([c]) when c in [?H, ?h, ?B, ?b], do: true

  defp radix_suffix?([c, next | _]) when c in [?H, ?h, ?B, ?b],
    do: not name_char?(next)

  defp radix_suffix?(_), do: false

  # libsmi's ERR_HEX_STRING_MUL2 / ERR_BIN_STRING_MUL8 checks, as warnings
  defp check_radix_literal(state, radix, text) when radix in [?H, ?h] do
    state
    |> warn_unless(
      rem(String.length(text), 2) == 0,
      "length of hexadecimal string '#{text}' is not a multiple of 2"
    )
    |> warn_unless(
      text =~ ~r/^[0-9A-Fa-f]*$/,
      "illegal character in hexadecimal string '#{text}'"
    )
  end

  defp check_radix_literal(state, _radix, text) do
    state
    |> warn_unless(
      rem(String.length(text), 8) == 0,
      "length of binary string '#{text}' is not a multiple of 8"
    )
    |> warn_unless(text =~ ~r/^[01]*$/, "illegal character in binary string '#{text}'")
  end

  defp warn_unless(state, true, _message), do: state
  defp warn_unless(state, false, message), do: warn(state, state.line, message)

  defp name_char?(c),
    do: (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or (c >= ?0 and c <= ?9) or c in [?_, ?-]

  # Scan integer
  defp scan_integer([?- | chars], [], line, state) do
    # Negative number
    scan_integer_digits(chars, [?-], line, state)
  end

  defp scan_integer(chars, [], line, state) do
    # Positive number
    scan_integer_digits(chars, [], line, state)
  end

  defp scan_integer_digits([digit | chars], acc, line, state)
       when (digit >= ?0 and digit <= ?9) or (digit >= ?a and digit <= ?f) or
              (digit >= ?A and digit <= ?F) do
    # Include hex digits in integer scanning for large hex numbers like '7FFFFFFF'
    scan_integer_digits(chars, [digit | acc], line, state)
  end

  defp scan_integer_digits(chars, acc, line, state) do
    # End of integer - determine if it's hex or decimal
    integer_chars = Enum.reverse(acc)

    # Check if it contains hex digits
    has_hex_digits =
      Enum.any?(integer_chars, fn char ->
        (char >= ?a and char <= ?f) or (char >= ?A and char <= ?F)
      end)

    if has_hex_digits do
      # It's a hex number - convert from hex to decimal
      hex_string = List.to_string(integer_chars)

      try do
        integer_value = String.to_integer(hex_string, 16)
        new_state = %{state | chars: chars}
        {{:integer, line, integer_value}, new_state}
      rescue
        _ ->
          # Fall back to an identifier token if hex conversion fails
          new_state = %{state | chars: chars}
          {{:atom, line, hex_string}, new_state}
      end
    else
      # Regular decimal integer
      integer_value = List.to_integer(integer_chars)
      new_state = %{state | chars: chars}
      {{:integer, line, integer_value}, new_state}
    end
  end

  # Scan identifier/atom name. A `--` inside a name starts a comment
  # (libsmi: identifiers are [a-z](-?[a-zA-Z0-9_]+)*), so stop before it.
  defp scan_name([?-, ?- | _] = chars, acc, line, state) when acc != [] do
    finish_name(chars, acc, line, state)
  end

  defp scan_name([char | chars], acc, line, state)
       when (char >= ?a and char <= ?z) or
              (char >= ?A and char <= ?Z) or
              (char >= ?0 and char <= ?9) or
              char == ?_ or char == ?- do
    scan_name(chars, [char | acc], line, state)
  end

  defp scan_name(chars, acc, line, state), do: finish_name(chars, acc, line, state)

  defp finish_name(chars, acc, line, state) do
    name_chars = Enum.reverse(acc)
    name_string = List.to_string(name_chars)

    # Determine if it's a reserved word, variable, or atom
    token =
      case classify_name(name_string, name_chars) do
        {:reserved, atom} ->
          {atom, line}

        {:variable, _} ->
          {:variable, line, name_string}

        {:atom, _} ->
          {:atom, line, name_string}
      end

    new_state = %{state | chars: chars}
    {token, check_identifier(new_state, token, name_string)}
  end

  # libsmi's ERR_UNDERSCORE_IN_IDENTIFIER / ERR_ID_ENDS_IN_HYPHEN, as warnings
  defp check_identifier(state, {kind, line, _}, name) when kind in [:atom, :variable] do
    state
    |> warn_unless(
      not String.contains?(name, "_"),
      "identifier '#{name}' must not contain an underscore"
    )
    |> warn_unless(
      not String.ends_with?(name, "-"),
      "identifier '#{name}' must not end in a hyphen"
    )
    |> then(fn s -> if s.warnings != state.warnings, do: retag_line(s, state, line), else: s end)
  end

  defp check_identifier(state, _token, _name), do: state

  # warn_unless stamps state.line; identifier warnings belong to the token line
  defp retag_line(new_state, old_state, line) do
    added = length(new_state.warnings) - length(old_state.warnings)
    {fresh, rest} = Enum.split(new_state.warnings, added)
    %{new_state | warnings: Enum.map(fresh, fn {_, m} -> {line, m} end) ++ rest}
  end

  # Classify name as reserved word, variable, or atom
  defp classify_name(name_string, name_chars) do
    # Check if it's a reserved word first
    case reserved_word(name_string) do
      nil ->
        # Not a reserved word, check if variable or atom
        case name_chars do
          [first_char | _] when first_char >= ?A and first_char <= ?Z ->
            {:variable, name_string}

          _ ->
            {:atom, name_string}
        end

      reserved_atom ->
        {:reserved, reserved_atom}
    end
  end

  # Reserved words from SNMP/SMI - complete list from Erlang tokenizer
  defp reserved_word(word) do
    case word do
      "DEFINITIONS" -> :DEFINITIONS
      "BEGIN" -> :BEGIN
      "END" -> :END
      "IMPORTS" -> :IMPORTS
      "FROM" -> :FROM
      "EXPORTS" -> :EXPORTS
      "OBJECT" -> :OBJECT
      "IDENTIFIER" -> :IDENTIFIER
      "OBJECT-TYPE" -> :"OBJECT-TYPE"
      "SYNTAX" -> :SYNTAX
      "ACCESS" -> :ACCESS
      "MAX-ACCESS" -> :"MAX-ACCESS"
      "STATUS" -> :STATUS
      "DESCRIPTION" -> :DESCRIPTION
      "REFERENCE" -> :REFERENCE
      "INDEX" -> :INDEX
      "AUGMENTS" -> :AUGMENTS
      "DEFVAL" -> :DEFVAL
      "UNITS" -> :UNITS
      "SEQUENCE" -> :SEQUENCE
      "OF" -> :OF
      "CHOICE" -> :CHOICE
      "SIZE" -> :SIZE
      "INTEGER" -> :INTEGER
      "OCTET" -> :OCTET
      "STRING" -> :STRING
      "NULL" -> :NULL
      "IpAddress" -> :IpAddress
      "Counter" -> :Counter
      "Counter32" -> :Counter32
      "Counter64" -> :Counter64
      "Gauge" -> :Gauge
      "Gauge32" -> :Gauge32
      "TimeTicks" -> :TimeTicks
      "Unsigned32" -> :Unsigned32
      "Integer32" -> :Integer32
      "Opaque" -> :Opaque
      "BITS" -> :BITS
      "MODULE-IDENTITY" -> :"MODULE-IDENTITY"
      "OBJECT-IDENTITY" -> :"OBJECT-IDENTITY"
      "TEXTUAL-CONVENTION" -> :"TEXTUAL-CONVENTION"
      "OBJECT-GROUP" -> :"OBJECT-GROUP"
      "NOTIFICATION-GROUP" -> :"NOTIFICATION-GROUP"
      "MODULE-COMPLIANCE" -> :"MODULE-COMPLIANCE"
      "AGENT-CAPABILITIES" -> :"AGENT-CAPABILITIES"
      "NOTIFICATION-TYPE" -> :"NOTIFICATION-TYPE"
      "TRAP-TYPE" -> :"TRAP-TYPE"
      "LAST-UPDATED" -> :"LAST-UPDATED"
      "ORGANIZATION" -> :ORGANIZATION
      "CONTACT-INFO" -> :"CONTACT-INFO"
      "REVISION" -> :REVISION
      "DISPLAY-HINT" -> :"DISPLAY-HINT"
      "IMPLIED" -> :IMPLIED
      "OBJECTS" -> :OBJECTS
      "NOTIFICATIONS" -> :NOTIFICATIONS
      "MANDATORY-GROUPS" -> :"MANDATORY-GROUPS"
      "GROUP" -> :GROUP
      "MODULE" -> :MODULE
      "WRITE-SYNTAX" -> :"WRITE-SYNTAX"
      "MIN-ACCESS" -> :"MIN-ACCESS"
      "PRODUCT-RELEASE" -> :"PRODUCT-RELEASE"
      "SUPPORTS" -> :SUPPORTS
      "INCLUDES" -> :INCLUDES
      "VARIATION" -> :VARIATION
      "CREATION-REQUIRES" -> :"CREATION-REQUIRES"
      "ENTERPRISE" -> :ENTERPRISE
      "VARIABLES" -> :VARIABLES
      "APPLICATION" -> :APPLICATION
      "IMPLICIT" -> :IMPLICIT
      "EXPLICIT" -> :EXPLICIT
      "UNIVERSAL" -> :UNIVERSAL
      "PRIVATE" -> :PRIVATE
      "MACRO" -> :MACRO
      "TYPE" -> :TYPE
      "NOTATION" -> :NOTATION
      "VALUE" -> :VALUE
      # Status values - removed to let grammar handle context
      # "current" -> :'current'
      # "deprecated" -> :'deprecated'
      # "obsolete" -> :'obsolete'
      # Access values
      "read-only" -> :"read-only"
      "read-write" -> :"read-write"
      "write-only" -> :"write-only"
      "not-accessible" -> :"not-accessible"
      "accessible-for-notify" -> :"accessible-for-notify"
      "read-create" -> :"read-create"
      # Special values - removed to let grammar handle context
      # "mandatory" -> :'mandatory'
      # "optional" -> :'optional'
      _ -> nil
    end
  end
end
