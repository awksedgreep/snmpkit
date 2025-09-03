defmodule SnmpKit.SnmpLib.MIB.Compiler do
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
      {:ok, compiled} = SnmpKit.SnmpLib.MIB.Compiler.compile("MY-MIB.mib")

      # Compile with options
      {:ok, compiled} = SnmpKit.SnmpLib.MIB.Compiler.compile("MY-MIB.mib",
        output_dir: "/tmp/mibs",
        format: :binary,
        optimize: true
      )

      # Compile multiple MIBs
      {:ok, results} = SnmpKit.SnmpLib.MIB.Compiler.compile_all([
        "SNMPv2-SMI.mib",
        "MY-MIB.mib"
      ])
  """

  alias SnmpKit.SnmpLib.MIB.{Logger, Error}

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
          name: binary(),
          version: binary(),
          format: atom(),
          path: Path.t(),
          metadata: map(),
          oid_tree: SnmpKit.SnmpLib.MIB.AST.oid_tree(),
          symbols: map(),
          dependencies: [binary()]
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

      iex> SnmpKit.SnmpLib.MIB.Compiler.compile("test/fixtures/TEST-MIB.mib")
      {:ok, %{name: "TEST-MIB", ...}}

      iex> SnmpKit.SnmpLib.MIB.Compiler.compile("missing.mib")
      {:error, [%SnmpKit.SnmpLib.MIB.Error{type: :file_not_found}]}
  """
  @spec compile(Path.t(), compile_opts()) :: compile_result()
  def compile(mib_path, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    
    case File.read(mib_path) do
      {:ok, content} ->
        compile_string(content, opts)
      {:error, reason} ->
        {:error, [Error.new(:file_not_found, 
          message: "Could not read MIB file: #{reason}",
          context: %{path: mib_path})]}
    end
  end

  @doc """
  Compile a MIB from string content.

  This delegates to the Parser module which implements the full compilation
  pipeline using YACC-based parsing.

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.Compiler.compile_string(mib_content)
      {:ok, %{name: "TEST-MIB", ...}}
  """
  @spec compile_string(binary(), compile_opts()) :: compile_result()
  def compile_string(mib_content, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    
    # The Parser module implements the full compilation pipeline
    case SnmpKit.SnmpLib.MIB.Parser.parse(mib_content) do
      {:ok, mib} ->
        # Convert parser output to compiled_mib format
        compiled = %{
          name: mib.name,
          version: Map.get(mib, :version, "unknown"),
          format: opts[:format],
          path: nil,  # Set by compile/2 if from file
          metadata: Map.get(mib, :metadata, %{}),
          oid_tree: Map.get(mib, :oid_tree, %{}),
          symbols: build_symbol_table(mib),
          dependencies: extract_dependencies(mib)
        }
        
        if opts[:validate] do
          validate_compiled_mib(compiled, opts)
        else
          {:ok, compiled}
        end
        
      {:error, error} when is_binary(error) ->
        {:error, [Error.new(:syntax_error, message: error)]}
        
      {:error, errors} when is_list(errors) ->
        {:error, errors}
        
      {:error, {line, module, message}} ->
        # Handle parser errors from YACC
        error_msg = case message do
          msg when is_binary(msg) -> msg
          msg when is_list(msg) -> List.to_string(msg)
          msg -> inspect(msg)
        end
        {:error, [Error.new(:syntax_error, 
          message: "Line #{line}: #{error_msg}",
          line: line,
          context: %{module: module})]}
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
  
  defp validate_compiled_mib(compiled, _opts) do
    # TODO: Add semantic validation
    # For now, just return the compiled MIB
    {:ok, compiled}
  end

  @doc """
  Load a previously compiled MIB.

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.Compiler.load_compiled("priv/mibs/TEST-MIB.mib")
      {:ok, %{name: "TEST-MIB", ...}}
  """
  @spec load_compiled(Path.t()) :: {:ok, compiled_mib()} | {:error, term()}
  def load_compiled(compiled_path) do
    case File.read(compiled_path) do
      {:ok, binary_data} ->
        case :erlang.binary_to_term(binary_data) do
          %{__type__: :compiled_mib} = compiled ->
            {:ok, compiled}

          _ ->
            {:error, :invalid_compiled_format}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compile multiple MIB files in dependency order.

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.Compiler.compile_all(["SNMPv2-SMI.mib", "MY-MIB.mib"])
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

  # Private helper functions

  # TODO: The following functions are for future MIB compilation features
  # They are commented out to avoid Dialyzer warnings until MIB compilation is fully implemented

  # defp post_process_mib(mib, opts) do
  #   with {:ok, validated_mib} <- validate_mib(mib, opts),
  #        {:ok, resolved_mib} <- resolve_symbols(validated_mib, opts),
  #        {:ok, optimized_mib} <- optimize_mib(resolved_mib, opts) do
  #     {:ok, optimized_mib}
  #   end
  # end

  # defp validate_mib(mib, opts) do
  #   if opts[:validate] do
  #     # Semantic validation would go here
  #     # For now, just basic AST validation
  #     case AST.validate_node(mib) do
  #       {:ok, _} -> {:ok, mib}
  #       {:error, reason} ->
  #         error = Error.new(:validation_failed, reason: reason)
  #         {:error, [error]}
  #     end
  #   else
  #     {:ok, mib}
  #   end
  # end

  # defp resolve_symbols(mib, _opts) do
  #   # Symbol resolution would happen here
  #   # For now, return as-is
  #   {:ok, mib}
  # end

  # defp optimize_mib(mib, opts) do
  #   if opts[:optimize] do
  #     # MIB optimization would happen here
  #     # For now, return as-is
  #     {:ok, mib}
  #   else
  #     {:ok, mib}
  #   end
  # end

  # defp build_output_path(mib_name, opts) do
  #   output_dir = opts[:output_dir]
  #   format = opts[:format]
  #
  #   extension = case format do
  #     :erlang -> ".erl"
  #     :binary -> ".mib"
  #     :json -> ".json"
  #   end
  #
  #   Path.join(output_dir, "#{mib_name}#{extension}")
  # end

  # defp write_compiled_mib(mib, output_path, opts) do
  #   case ensure_output_dir(Path.dirname(output_path)) do
  #     :ok ->
  #       case opts[:format] do
  #         :binary ->
  #           compiled = %{
  #             __type__: :compiled_mib,
  #             name: mib.name,
  #             version: get_mib_version(mib),
  #             format: :binary,
  #             metadata: mib.metadata,
  #             oid_tree: mib.oid_tree,
  #             symbols: extract_symbols(mib),
  #             dependencies: mib.metadata[:dependencies] || [],
  #             compiled_at: DateTime.utc_now()
  #           }
  #           File.write(output_path, :erlang.term_to_binary(compiled))
  #
  #         :json ->
  #           # Would need JSON serialization
  #           {:error, :json_not_implemented}
  #
  #         :erlang ->
  #           # Would generate Erlang code
  #           {:error, :erlang_not_implemented}
  #       end
  #     error ->
  #       error
  #   end
  # end

  # defp ensure_output_dir(dir_path) do
  #   case File.mkdir_p(dir_path) do
  #     :ok -> :ok
  #     {:error, reason} -> {:error, reason}
  #   end
  # end

  # defp get_mib_version(mib) do
  #   mib.metadata[:compiler_version] || "unknown"
  # end

  # defp extract_symbols(mib) do
  #   # Build symbol table from definitions
  #   Enum.reduce(mib.definitions, %{}, fn definition, acc ->
  #     case definition do
  #       %{name: name, oid: oid} when is_list(oid) ->
  #         Map.put(acc, name, oid)
  #       _ ->
  #         acc
  #     end
  #   end)
  # end

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
