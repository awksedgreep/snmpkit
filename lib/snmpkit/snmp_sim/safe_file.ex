defmodule SnmpKit.SnmpSim.SafeFile do
  @moduledoc """
  Guarded file access for simulator inputs (walk files, JSON/YAML profiles,
  MIB sources, compiled MIBs).

  Two limits apply to every read:

  * **Size** - files larger than `:snmpkit, :max_input_file_bytes` (default
    64 MiB) are refused before they are read into memory.
  * **Location** - when `:snmpkit, :input_roots` is set to a list of
    directories, the expanded path (symlinks resolved) must live under one of
    them; anything else is refused with `{:error, :outside_allowed_roots}`.
    The default is `nil`, i.e. no confinement, which keeps existing
    deployments that load profiles from arbitrary paths working.

      config :snmpkit,
        max_input_file_bytes: 16 * 1024 * 1024,
        input_roots: ["/srv/snmp/profiles", "priv/walks"]
  """

  @default_max_bytes 64 * 1024 * 1024

  @type reason :: :file_too_large | :outside_allowed_roots | File.posix()

  @doc """
  Reads a whole file after checking its location and size.
  """
  @spec read(Path.t(), keyword()) :: {:ok, binary()} | {:error, reason()}
  def read(path, opts \\ []) do
    with {:ok, real} <- check(path, opts) do
      File.read(real)
    end
  end

  @doc """
  Opens a line stream over a file after checking its location and size.
  """
  @spec stream(Path.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, reason()}
  def stream(path, opts \\ []) do
    with {:ok, real} <- check(path, opts) do
      {:ok, File.stream!(real)}
    end
  end

  @doc """
  Validates a path against the configured roots and size limit and returns the
  resolved path to use.
  """
  @spec check(Path.t(), keyword()) :: {:ok, Path.t()} | {:error, reason()}
  def check(path, opts \\ []) when is_binary(path) do
    max_bytes = Keyword.get(opts, :max_bytes, configured_max_bytes())
    roots = Keyword.get(opts, :roots, configured_roots())

    with {:ok, real} <- resolve(path),
         :ok <- check_roots(real, roots),
         {:ok, %File.Stat{type: :regular, size: size}} <- File.stat(real),
         :ok <- check_size(size, max_bytes) do
      {:ok, real}
    else
      {:ok, %File.Stat{}} -> {:error, :eisdir}
      {:error, _} = error -> error
    end
  end

  @doc "The configured size limit in bytes."
  @spec configured_max_bytes() :: pos_integer()
  def configured_max_bytes do
    Application.get_env(:snmpkit, :max_input_file_bytes, @default_max_bytes)
  end

  @doc "The configured allowed roots, or nil when unconfined."
  @spec configured_roots() :: [Path.t()] | nil
  def configured_roots do
    Application.get_env(:snmpkit, :input_roots)
  end

  # Expand the path and follow symlinks (bounded) so a link inside an allowed
  # root cannot point outside it.
  defp resolve(path, hops \\ 8)

  defp resolve(_path, 0), do: {:error, :eloop}

  defp resolve(path, hops) do
    expanded = Path.expand(path)

    case File.read_link(expanded) do
      {:ok, target} ->
        target
        |> Path.expand(Path.dirname(expanded))
        |> resolve(hops - 1)

      {:error, _} ->
        {:ok, expanded}
    end
  end

  defp check_roots(_real, nil), do: :ok
  defp check_roots(_real, []), do: :ok

  defp check_roots(real, roots) when is_list(roots) do
    allowed =
      Enum.any?(roots, fn root ->
        root = Path.expand(root)
        real == root or String.starts_with?(real, root <> "/")
      end)

    if allowed, do: :ok, else: {:error, :outside_allowed_roots}
  end

  defp check_size(size, max_bytes) when size <= max_bytes, do: :ok
  defp check_size(_size, _max_bytes), do: {:error, :file_too_large}
end
