defmodule SnmpKit.SnmpLib.MIB.Logger do
  @moduledoc """
  Structured logging for MIB compilation with proper log levels.

  Provides detailed logging throughout the compilation process with
  structured metadata for debugging and monitoring.
  """

  require Logger

  @doc """
  Log the start of MIB compilation with context.
  """
  @spec log_compilation_start(Path.t(), keyword()) :: :ok
  def log_compilation_start(file_path, opts) do
    Logger.info("Starting MIB compilation",
      file: file_path,
      output_dir: opts[:output_dir],
      format: opts[:format],
      optimize: opts[:optimize],
      vendor_quirks: opts[:vendor_quirks]
    )
  end

  @doc """
  Log successful MIB compilation.
  """
  @spec log_compilation_success(binary(), Path.t()) :: :ok
  def log_compilation_success(mib_name, output_path) do
    Logger.info("MIB compilation successful",
      mib: mib_name,
      output: output_path
    )
  end

  @doc """
  Log compilation errors.
  """
  @spec log_compilation_error(binary(), [term()]) :: :ok
  def log_compilation_error(mib_name, errors) do
    Logger.error("MIB compilation failed",
      mib: mib_name,
      error_count: length(errors),
      errors: errors
    )
  end

  @doc """
  Log compilation with warnings.
  """
  @spec log_compilation_warning(binary(), Path.t(), [term()]) :: :ok
  def log_compilation_warning(mib_name, output_path, warnings) do
    Logger.warning("MIB compilation completed with warnings",
      mib: mib_name,
      output: output_path,
      warning_count: length(warnings),
      warnings: warnings
    )
  end

  @doc """
  Log start of batch compilation.
  """
  @spec log_batch_compilation_start(integer()) :: :ok
  def log_batch_compilation_start(file_count) do
    Logger.info("Starting batch MIB compilation",
      file_count: file_count
    )
  end

  @doc """
  Log successful batch compilation.
  """
  @spec log_batch_compilation_success(integer()) :: :ok
  def log_batch_compilation_success(success_count) do
    Logger.info("Batch MIB compilation successful",
      success_count: success_count
    )
  end

  @doc """
  Log batch compilation with errors.
  """
  @spec log_batch_compilation_error(integer(), integer()) :: :ok
  def log_batch_compilation_error(success_count, error_count) do
    Logger.error("Batch MIB compilation completed with errors",
      success_count: success_count,
      error_count: error_count
    )
  end

  @doc """
  Log compilation completion with results.
  """
  @spec log_compilation_complete(binary(), map()) :: :ok
  def log_compilation_complete(mib_name, result) do
    Logger.info("MIB compilation successful",
      mib: mib_name,
      objects: result[:objects_count],
      output_path: result[:output_path],
      duration_ms: result[:compilation_time]
    )
  end

  @doc """
  Log compilation failure with error details.
  """
  @spec log_compilation_failed(Path.t(), [term()]) :: :ok
  def log_compilation_failed(file_path, errors) do
    error_types =
      errors
      |> Enum.map(&extract_error_type/1)
      |> Enum.frequencies()

    Logger.error("MIB compilation failed",
      file: file_path,
      error_count: length(errors),
      error_types: error_types
    )
  end

  @doc """
  Log parsing progress with token/object counts.
  """
  @spec log_parse_progress(binary(), integer()) :: :ok
  def log_parse_progress(phase, count) do
    Logger.debug("Parse progress",
      phase: phase,
      count: count
    )
  end

  @doc """
  Log import resolution with dependency information.
  """
  @spec log_import_resolution(binary(), [binary()]) :: :ok
  def log_import_resolution(mib_name, imported_mibs) do
    Logger.debug("Resolving imports",
      mib: mib_name,
      imports: imported_mibs,
      import_count: length(imported_mibs)
    )
  end

  @doc """
  Log successful import resolution.
  """
  @spec log_imports_resolved(binary(), integer(), integer()) :: :ok
  def log_imports_resolved(mib_name, resolved_count, total_count) do
    Logger.debug("Imports resolved",
      mib: mib_name,
      resolved: resolved_count,
      total: total_count,
      success_rate: resolved_count / max(total_count, 1)
    )
  end

  @doc """
  Log code generation progress and results.
  """
  @spec log_codegen(binary(), integer(), integer()) :: :ok
  def log_codegen(mib_name, objects_count, functions_generated) do
    Logger.info("Code generation complete",
      mib: mib_name,
      objects: objects_count,
      functions: functions_generated,
      functions_per_object: functions_generated / max(objects_count, 1)
    )
  end

  @doc """
  Log tokenization statistics.
  """
  @spec log_tokenization(binary(), integer(), integer()) :: :ok
  def log_tokenization(mib_name, tokens_count, lines_processed) do
    Logger.debug("Tokenization complete",
      mib: mib_name,
      tokens: tokens_count,
      lines: lines_processed,
      tokens_per_line: tokens_count / max(lines_processed, 1)
    )
  end

  @doc """
  Log dependency resolution order.
  """
  @spec log_dependency_order([binary()]) :: :ok
  def log_dependency_order(mib_order) do
    Logger.debug("Dependency resolution complete",
      compilation_order: mib_order,
      mib_count: length(mib_order)
    )
  end

  @doc """
  Log performance metrics.
  """
  @spec log_performance(binary(), keyword()) :: :ok
  def log_performance(phase, metrics) do
    metrics_kw = metrics |> Enum.into([])
    Logger.debug("Performance metrics", [phase: phase] ++ metrics_kw)
  end

  @doc """
  Log warning with context.
  """
  @spec log_warning(binary(), map()) :: :ok
  def log_warning(message, context \\ %{}) do
    context_kw = context |> Enum.into([])
    Logger.warning(message, context_kw)
  end

  @doc """
  Log vendor-specific quirk handling.
  """
  @spec log_vendor_quirk(binary(), binary(), binary()) :: :ok
  def log_vendor_quirk(mib_name, vendor, quirk_description) do
    Logger.debug("Vendor quirk handled",
      mib: mib_name,
      vendor: vendor,
      quirk: quirk_description
    )
  end

  @doc """
  Log batch compilation progress.
  """
  @spec log_batch_progress(integer(), integer()) :: :ok
  def log_batch_progress(completed, total) do
    Logger.info("Batch compilation progress",
      completed: completed,
      total: total,
      progress_percent: completed / max(total, 1) * 100
    )
  end

  # Extract error type for aggregation
  defp extract_error_type(%SnmpKit.SnmpLib.MIB.Error{type: type}), do: type
  defp extract_error_type(%{type: type}), do: type
  defp extract_error_type(error) when is_atom(error), do: error
  defp extract_error_type(_), do: :unknown
end
