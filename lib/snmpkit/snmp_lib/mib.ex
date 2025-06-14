defmodule SnmpKit.SnmpLib.MIB do
  @moduledoc """
  SNMP MIB compiler with enhanced Elixir ergonomics.

  Provides a clean, functional API for compiling MIB files with proper
  error handling, logging, and performance optimizations.

  This module serves as the main entry point for MIB compilation operations.
  """

  alias SnmpKit.SnmpLib.MIB.Compiler

  @type compile_opts :: [
          output_dir: Path.t(),
          include_dirs: [Path.t()],
          log_level: Logger.level(),
          format: :elixir | :erlang | :both,
          optimize: boolean(),
          warnings_as_errors: boolean(),
          vendor_quirks: boolean()
        ]

  @type compiled_mib :: %{
          name: binary(),
          objects_count: non_neg_integer(),
          output_path: Path.t(),
          compilation_time: non_neg_integer(),
          metadata: map()
        }

  @type error :: term()
  @type warning :: term()

  @type compile_result ::
          {:ok, compiled_mib()}
          | {:error, [error()]}
          | {:warning, compiled_mib(), [warning()]}

  @doc """
  Compile a MIB file to Elixir code.

  ## Options

  - `:output_dir` - Directory for generated files (default: "./lib/generated")
  - `:include_dirs` - Directories to search for imported MIBs (default: ["./priv/mibs"])
  - `:log_level` - Logging verbosity (default: `:info`)
  - `:format` - Output format `:elixir`, `:erlang`, or `:both` (default: `:elixir`)
  - `:optimize` - Enable performance optimizations (default: `true`)
  - `:warnings_as_errors` - Treat warnings as compilation errors (default: `false`)
  - `:vendor_quirks` - Enable vendor-specific MIB compatibility (default: `true`)

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.compile("priv/mibs/RFC1213-MIB.txt")
      {:error, [%SnmpKit.SnmpLib.MIB.Error{type: :file_not_found, ...}]}
  """
  @spec compile(Path.t() | binary(), compile_opts()) :: {:error, [SnmpKit.SnmpLib.MIB.Error.t()]}
  def compile(mib_source, opts \\ []) do
    Compiler.compile(mib_source, opts)
  end

  @doc """
  Compile MIB content from a string.

  Useful when the MIB content is already loaded or generated dynamically.

  ## Examples

      iex> mib_content = File.read!("RFC1213-MIB.txt")
      iex> SnmpKit.SnmpLib.MIB.compile_string(mib_content)
      {:ok, %{name: "RFC1213-MIB", ...}}
  """
  @spec compile_string(binary(), compile_opts()) :: {:error, [SnmpKit.SnmpLib.MIB.Error.t()]}
  def compile_string(mib_content, opts \\ []) do
    Compiler.compile_string(mib_content, opts)
  end

  @doc """
  Load a previously compiled MIB module.

  ## Examples

      iex> SnmpKit.SnmpLib.MIB.load_compiled("lib/generated/rfc1213_mib.ex")
      {:ok, %{name: "RFC1213-MIB", ...}}
  """
  @spec load_compiled(Path.t()) :: {:ok, compiled_mib()} | {:error, term()}
  def load_compiled(compiled_path) do
    Compiler.load_compiled(compiled_path)
  end

  @doc """
  Compile multiple MIB files in dependency order.

  Automatically resolves import dependencies and compiles MIBs in the correct order.

  ## Examples

      iex> mibs = ["SNMPv2-SMI.txt", "SNMPv2-TC.txt", "RFC1213-MIB.txt"]
      iex> SnmpKit.SnmpLib.MIB.compile_all(mibs)
      {:ok, [%{name: "SNMPv2-SMI", ...}, %{name: "SNMPv2-TC", ...}, ...]}
  """
  @spec compile_all([Path.t()], compile_opts()) ::
          {:ok, [compiled_mib()]} | {:error, [{Path.t(), [error()]}]}
  def compile_all(mib_files, opts \\ []) do
    Compiler.compile_all(mib_files, opts)
  end
end
