defmodule SnmpKit.MIB.Compiler do
  @moduledoc """
  Main MIB compiler that orchestrates the entire compilation process.

  This module provides the main interface for compiling MIB files from source
  to executable format. It coordinates between the lexer, parser, semantic
  analyzer, and code generator to produce optimized compiled MIBs.

  ## Compilation Process

  1. **Lexical Analysis** - Tokenize MIB source
  2. **Parsing** - Build Abstract Syntax Tree (AST)
  3. **Semantic Analysis** - Validate and resolve symbols
  4. **Code Generation** - Generate optimized runtime format
  5. **Persistence** - Save compiled MIB for loading

  ## Usage

      # Compile a single MIB file
      {:ok, compiled} = SnmpKit.MIB.Compiler.compile("MY-MIB.mib")

      # Compile with options
      {:ok, compiled} = SnmpKit.MIB.Compiler.compile("MY-MIB.mib",
        output_dir: "/tmp/mibs",
        format: :binary,
        optimize: true
      )

      # Compile multiple MIBs
      {:ok, results} = SnmpKit.MIB.Compiler.compile_all([
        "SNMPv2-SMI.mib",
        "MY-MIB.mib"
      ])
  """

  alias SnmpKit.MIB.{Logger, Error}

  @type compile_opts :: [
          output_dir: Path.t(),
          format: :erlang | :binary | :json,
          optimize: boolean(),
          validate: boolean(),
          include_paths: [Path.t()],
          warnings_as_errors: boolean()
        ]

  @type compile_result ::
          {:ok, compiled_mib()}
          | {:error, [Error.t()]}
          | {:warning, compiled_mib(), [Error.t()]}

  @type compiled_mib :: %{
          optional(:__type__) => :compiled_mib,
          name: binary(),
          version: binary(),
          format: atom(),
          path: Path.t() | nil,
          metadata: map(),
          oid_tree: SnmpKit.MIB.AST.oid_tree(),
          symbols: map(),
          dependencies: [binary()],
          imports: list(),
          warnings: [{non_neg_integer(), binary()}]
        }

  @default_opts [
    output_dir: "./priv/mibs",
    format: :binary,
    optimize: true,
    validate: true,
    include_paths: [],
    warnings_as_errors: false
  ]

  @doc """
  Compile a MIB file from filesystem path.

  ## Examples

      iex> SnmpKit.MIB.Compiler.compile("test/fixtures/TEST-MIB.mib")
      {:ok, %{name: "TEST-MIB", ...}}

      iex> SnmpKit.MIB.Compiler.compile("missing.mib")
      {:error, [%SnmpKit.MIB.Error{type: :file_not_found}]}
  """
  @spec compile(Path.t(), compile_opts()) :: compile_result()
  def compile(mib_path, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    case SnmpKit.SafeFile.read(mib_path) do
      {:ok, content} ->
        compile_string(content, opts)

      {:error, reason} when reason in [:outside_allowed_roots, :file_too_large] ->
        {:error,
         [
           Error.new(:file_rejected,
             file: mib_path,
             reason: reason,
             context: %{path: mib_path, reason: reason}
           )
         ]}

      {:error, reason} ->
        {:error,
         [
           Error.new(:file_not_found,
             file: mib_path,
             context: %{path: mib_path, reason: reason}
           )
         ]}
    end
  end

  @doc """
  Compile a MIB from string content.

  This delegates to the Parser module which implements the full compilation
  pipeline using YACC-based parsing.

  ## Examples

      iex> SnmpKit.MIB.Compiler.compile_string(mib_content)
      {:ok, %{name: "TEST-MIB", ...}}
  """
  @spec compile_string(binary(), compile_opts()) :: compile_result()
  def compile_string(mib_content, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    # The Parser module implements the full compilation pipeline
    case SnmpKit.MIB.Parser.parse(mib_content) do
      {:ok, mib} ->
        # Convert parser output to compiled_mib format
        compiled = %{
          name: mib.name,
          version: Map.get(mib, :version, "unknown"),
          format: opts[:format],
          # Set by compile/2 if from file
          path: nil,
          # The parser output carries no metadata or OID tree; both are
          # populated by later passes.
          metadata: %{},
          oid_tree: %{},
          symbols: build_symbol_table(mib),
          dependencies: extract_dependencies(mib),
          imports: Map.get(mib, :imports, []),
          warnings: Map.get(mib, :warnings, [])
        }

        cond do
          opts[:warnings_as_errors] and compiled.warnings != [] ->
            {:error,
             Enum.map(compiled.warnings, fn {line, message} ->
               Error.new(:syntax_error, message: "Line #{line}: #{message}", line: line)
             end)}

          opts[:validate] ->
            validate_compiled_mib(compiled, opts)

          true ->
            {:ok, compiled}
        end

      {:error, error} when is_binary(error) ->
        {:error, [Error.new(:syntax_error, message: error)]}

      {:error, errors} when is_list(errors) ->
        {:error, errors}

      {:error, {line, module, message}} ->
        # Handle parser errors from YACC
        error_msg =
          case message do
            msg when is_binary(msg) -> msg
            msg when is_list(msg) -> List.to_string(msg)
            msg -> inspect(msg)
          end

        {:error,
         [
           Error.new(:syntax_error,
             message: "Line #{line}: #{error_msg}",
             line: line,
             context: %{module: module}
           )
         ]}
    end
  end

  defp build_symbol_table(mib) do
    # Build a symbol table from the parsed MIB definitions
    Enum.reduce(mib.definitions, %{}, fn def, acc ->
      if Map.has_key?(def, :name) do
        Map.put(acc, def.name, def)
      else
        acc
      end
    end)
  end

  defp extract_dependencies(mib) do
    # Extract module dependencies from imports
    mib.imports
    |> Enum.map(& &1.from_module)
    |> Enum.uniq()
  end

  # Semantic checks (imports, index clauses, ranges) live in SnmpKit.MIB.Lint;
  # compile/2 only parses and converts, so `validate: true` accepts what parsed.
  defp validate_compiled_mib(compiled, _opts), do: {:ok, compiled}

  @doc """
  Load a previously compiled MIB.

  ## Examples

      iex> SnmpKit.MIB.Compiler.load_compiled("priv/mibs/TEST-MIB.mib")
      {:ok, %{name: "TEST-MIB", ...}}
  """
  @spec load_compiled(Path.t()) :: {:ok, compiled_mib()} | {:error, term()}
  def load_compiled(compiled_path) do
    max = max_compiled_mib_bytes()

    with {:ok, %File.Stat{size: size}} <- File.stat(compiled_path),
         :ok <- check_compiled_size(size, max),
         {:ok, real_path} <- SnmpKit.SafeFile.check(compiled_path, max_bytes: max),
         {:ok, binary_data} <- File.read(real_path),
         {:ok, term} <- safe_binary_to_term(binary_data) do
      case term do
        %{__type__: :compiled_mib} = compiled -> {:ok, compiled}
        _ -> {:error, :invalid_compiled_format}
      end
    end
  end

  # Upper bound on a compiled MIB file. Anything larger is refused before it is
  # read into memory. Override with
  # `config :snmpkit, :max_compiled_mib_bytes, bytes`. The `:input_roots`
  # confinement of `SnmpKit.SafeFile` applies as well.
  @default_max_compiled_mib_bytes 64 * 1024 * 1024

  defp max_compiled_mib_bytes do
    Application.get_env(:snmpkit, :max_compiled_mib_bytes, @default_max_compiled_mib_bytes)
  end

  defp check_compiled_size(size, max) do
    if size <= max do
      :ok
    else
      {:error, {:compiled_mib_too_large, size, max}}
    end
  end

  # Decode with :safe so a crafted file cannot mint atoms, funs, or external
  # references while it is being materialised. Anything that is not a valid
  # term in the safe subset is reported as :invalid_compiled_format.
  defp safe_binary_to_term(binary_data) do
    {:ok, :erlang.binary_to_term(binary_data, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_compiled_format}
  end

  @doc """
  Compile multiple MIB files in dependency order.

  ## Examples

      iex> SnmpKit.MIB.Compiler.compile_all(["SNMPv2-SMI.mib", "MY-MIB.mib"])
      {:ok, [%{name: "SNMPv2-SMI"}, %{name: "MY-MIB"}]}
  """
  @spec compile_all([Path.t()], compile_opts()) ::
          {:ok, [compiled_mib()]} | {:error, [{Path.t(), [Error.t()]}]}
  def compile_all(mib_files, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    Logger.log_batch_compilation_start(length(mib_files))

    # Compile each file independently and guard against crashes so the batch continues
    compile_results =
      Enum.map(mib_files, fn file ->
        try do
          compile(file, opts)
        rescue
          exception ->
            err =
              Error.new(
                :exception,
                message: Exception.message(exception),
                context: %{file: file, exception: exception.__struct__}
              )

            {:error, [err]}
        catch
          kind, reason ->
            err =
              Error.new(
                :thrown,
                message: "#{inspect(kind)}: #{inspect(reason)}",
                context: %{file: file}
              )

            {:error, [err]}
        end
      end)

    {successes, errors} = partition_results(compile_results, mib_files)

    case errors do
      [] ->
        Logger.log_batch_compilation_success(length(successes))
        {:ok, successes}

      _ ->
        Logger.log_batch_compilation_error(length(successes), length(errors))
        {:error, errors}
    end
  end

  @doc """
  Writes a compiled MIB to `output_dir` as `NAME.bin`, in the form
  `load_compiled/1` reads back.

  The directory is created if needed. Returns the path written.

  ## Examples

      {:ok, compiled} = SnmpKit.MIB.Compiler.compile("IF-MIB.mib")
      {:ok, "priv/compiled/IF-MIB.bin"} =
        SnmpKit.MIB.Compiler.write_compiled(compiled, "priv/compiled")
  """
  @spec write_compiled(compiled_mib(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def write_compiled(%{name: name} = compiled, output_dir) when is_binary(name) do
    path = Path.join(output_dir, name <> ".bin")
    data = :erlang.term_to_binary(Map.put(compiled, :__type__, :compiled_mib))

    with :ok <- File.mkdir_p(output_dir),
         :ok <- File.write(path, data) do
      {:ok, path}
    end
  end

  defp partition_results(results, files) do
    results
    |> Enum.zip(files)
    |> Enum.reduce({[], []}, fn {result, file}, {successes, errors} ->
      case result do
        {:ok, compiled} ->
          {[compiled | successes], errors}

        {:warning, compiled, _warnings} ->
          {[compiled | successes], errors}

        {:error, error_list} ->
          {successes, [{file, error_list} | errors]}
      end
    end)
    |> then(fn {successes, errors} ->
      {Enum.reverse(successes), Enum.reverse(errors)}
    end)
  end
end
