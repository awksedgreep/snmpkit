defmodule SnmpKit.SnmpLib.Security.Keys do
  @moduledoc """
  Key derivation and management for SNMPv3 User Security Model.

  Implements RFC 3414 compliant key derivation functions for converting
  user passwords into cryptographic keys suitable for authentication
  and privacy operations.

  ## Key Derivation Process

  SNMPv3 uses a two-step key derivation process:

  1. **Password Localization**: Transform user password into a localized key
     using the authoritative engine ID
  2. **Key Expansion**: Derive authentication and privacy keys from the
     localized key based on protocol requirements

  ## Security Properties

  - Keys are derived deterministically from passwords and engine IDs
  - Different engine IDs produce different keys for the same password
  - Key derivation uses cryptographic hash functions for security
  - Derived keys cannot be used to recover original passwords
  - Each protocol type (auth/priv) uses different key derivation parameters

  ## Supported Algorithms

  ### Authentication Key Derivation
  - **MD5**: RFC 3414 compliant (deprecated)
  - **SHA-1**: RFC 3414 compliant (deprecated)
  - **SHA-224**: RFC 7860 compliant
  - **SHA-256**: RFC 7860 compliant (recommended)
  - **SHA-384**: RFC 7860 compliant
  - **SHA-512**: RFC 7860 compliant

  ### Privacy Key Derivation
  Per RFC 3414 section 8.1.1.1 and RFC 3826 section 1.2 the privacy key is the
  *authentication protocol's* password-to-key algorithm applied to the privacy
  password and localized with the engine ID, truncated to the cipher's key size:

  - **DES**: 16 bytes (8-byte DES key followed by the 8-byte pre-IV)
  - **AES-128**: 16 bytes
  - **AES-192**: 24 bytes
  - **AES-256**: 32 bytes

  When the hash output is shorter than the cipher key (e.g. MD5/SHA-1 with
  AES-192/256) the key is extended. Two extension schemes exist in the wild:
  `:reeder` (draft-reeder-snmpv3-usm-3desede, the net-snmp default) and
  `:blumenthal` (draft-blumenthal-aes-usm). Pass `key_extension:` to choose;
  the default is `:reeder`.

  ## Usage Examples

  ### Authentication Key Derivation

      # Derive SHA-256 authentication key
      engine_id = <<0x80, 0x00, 0x1f, 0x88, 0x80, 0x01, 0x02, 0x03, 0x04>>
      password = "authentication_password"

      {:ok, auth_key} = SnmpKit.SnmpLib.Security.Keys.derive_auth_key(:sha256, password, engine_id)

  ### Privacy Key Derivation

      # Derive AES-256 privacy key for a user authenticating with SHA-256
      {:ok, priv_key} = SnmpKit.SnmpLib.Security.Keys.derive_priv_key(
        :aes256, password, engine_id, auth_protocol: :sha256
      )

      # Or reuse the localized authentication key when both passwords are the same
      {:ok, priv_key} = SnmpKit.SnmpLib.Security.Keys.derive_priv_key_from_auth(:aes256, auth_key, engine_id)

  ### Key Validation

      # Validate key strength
      :ok = SnmpKit.SnmpLib.Security.Keys.validate_password_strength(password)
      {:error, :too_short} = SnmpKit.SnmpLib.Security.Keys.validate_password_strength("weak")
  """

  require Logger

  @type auth_protocol :: :md5 | :sha1 | :sha224 | :sha256 | :sha384 | :sha512
  @type priv_protocol :: :des | :aes128 | :aes192 | :aes256
  @type password :: binary()
  @type engine_id :: binary()
  @type derived_key :: binary()
  @type salt :: binary()

  # Key derivation constants per RFC 3414
  # 2^20
  @key_localization_iterations 1_048_576
  @min_password_length 8
  @min_engine_id_length 5
  @max_engine_id_length 32

  # Protocol-specific key sizes
  @auth_key_sizes %{
    md5: 16,
    sha1: 20,
    sha224: 28,
    sha256: 32,
    sha384: 48,
    sha512: 64
  }

  @priv_key_sizes %{
    # 8-byte DES key + 8-byte pre-IV (RFC 3414 8.1.1.1)
    des: 16,
    aes128: 16,
    aes192: 24,
    aes256: 32
  }

  # Hash function used when a caller does not say which authentication protocol
  # the user has. RFC 3414 defines the algorithm in terms of MD5.
  @default_priv_auth_protocol :md5
  @default_key_extension :reeder

  # Chunk of the 1 MiB password stream hashed per update (bytes, rounded to a
  # whole number of password repetitions).
  @password_stream_chunk 65_536

  ## Authentication Key Derivation

  @doc """
  Derives authentication key from password and engine ID.

  Implements RFC 3414 key localization algorithm for authentication protocols.
  The derived key is specific to the combination of password, protocol, and engine ID.

  ## Parameters

  - `protocol`: Authentication protocol (:md5, :sha1, :sha256, etc.)
  - `password`: User password (minimum 8 characters recommended)
  - `engine_id`: Authoritative engine ID (5-32 bytes)

  ## Returns

  - `{:ok, key}`: Successfully derived authentication key
  - `{:error, reason}`: Key derivation failed

  ## Examples

      # SHA-256 authentication key (recommended)
      {:ok, key} = SnmpKit.SnmpLib.Security.Keys.derive_auth_key(
        :sha256, "my_secure_password", engine_id
      )

      # Legacy MD5 key derivation
      {:ok, key} = SnmpKit.SnmpLib.Security.Keys.derive_auth_key(
        :md5, "legacy_password", engine_id
      )
  """
  @spec derive_auth_key(auth_protocol(), password(), engine_id()) ::
          {:ok, derived_key()} | {:error, atom()}
  def derive_auth_key(protocol, password, engine_id) do
    Logger.debug("Deriving #{protocol} authentication key")

    with :ok <- validate_auth_protocol(protocol),
         :ok <- validate_password(password),
         :ok <- validate_engine_id(engine_id),
         {:ok, localized_key} <- localize_key(protocol, password, engine_id),
         {:ok, auth_key} <- extract_auth_key(protocol, localized_key) do
      Logger.debug("Authentication key derivation successful for #{protocol}")
      {:ok, auth_key}
    else
      {:error, reason} ->
        Logger.error("Authentication key derivation failed for #{protocol}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Derives multiple authentication keys for different protocols from the same password.

  Useful when supporting multiple authentication protocols simultaneously.

  ## Examples

      protocols = [:sha256, :sha384, :sha512]
      {:ok, keys} = SnmpKit.SnmpLib.Security.Keys.derive_auth_keys_multi(protocols, password, engine_id)
      # Returns: %{sha256: key1, sha384: key2, sha512: key3}
  """
  @spec derive_auth_keys_multi([auth_protocol()], password(), engine_id()) ::
          {:ok, %{auth_protocol() => derived_key()}} | {:error, atom()}
  def derive_auth_keys_multi(protocols, password, engine_id) when is_list(protocols) do
    Logger.debug("Deriving authentication keys for #{length(protocols)} protocols")

    try do
      keys =
        for protocol <- protocols, into: %{} do
          case derive_auth_key(protocol, password, engine_id) do
            {:ok, key} -> {protocol, key}
            {:error, reason} -> throw({:error, reason})
          end
        end

      {:ok, keys}
    rescue
      _error ->
        {:error, :multi_key_derivation_failed}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  ## Privacy Key Derivation

  @doc """
  Derives privacy key from password and engine ID.

  Implements RFC 3414 section 8.1.1.1 / RFC 3826 section 1.2: the privacy
  password is run through the *authentication* protocol's password-to-key
  algorithm, localized with the engine ID, and cut (or extended) to the cipher
  key size.

  ## Parameters

  - `protocol`: Privacy protocol (:des, :aes128, :aes192, :aes256)
  - `password`: User password for privacy
  - `engine_id`: Authoritative engine ID
  - `opts`:
    - `:auth_protocol` - the user's authentication protocol, which selects the
      hash (default `:md5`, the RFC 3414 baseline)
    - `:key_extension` - `:reeder` (default, net-snmp compatible) or
      `:blumenthal` for AES keys longer than the hash output

  ## Returns

  - `{:ok, key}`: Successfully derived privacy key
  - `{:error, reason}`: Key derivation failed

  ## Examples

      # AES-256 privacy key for a SHA-256 user (recommended)
      {:ok, key} = SnmpKit.SnmpLib.Security.Keys.derive_priv_key(
        :aes256, "privacy_password", engine_id, auth_protocol: :sha256
      )

      # DES privacy key (legacy, MD5 based)
      {:ok, key} = SnmpKit.SnmpLib.Security.Keys.derive_priv_key(
        :des, "legacy_privacy_password", engine_id
      )
  """
  @spec derive_priv_key(priv_protocol(), password(), engine_id(), keyword()) ::
          {:ok, derived_key()} | {:error, atom()}
  def derive_priv_key(protocol, password, engine_id, opts \\ []) do
    Logger.debug("Deriving #{protocol} privacy key")

    auth_protocol = Keyword.get(opts, :auth_protocol, @default_priv_auth_protocol)
    extension = Keyword.get(opts, :key_extension, @default_key_extension)

    with :ok <- validate_priv_protocol(protocol),
         :ok <- validate_auth_protocol(auth_protocol),
         :ok <- validate_key_extension(extension),
         :ok <- validate_password(password),
         :ok <- validate_engine_id(engine_id),
         {:ok, localized_key} <- localize_key(auth_protocol, password, engine_id) do
      hash = get_hash_function(auth_protocol)
      {:ok, fit_priv_key(localized_key, @priv_key_sizes[protocol], hash, engine_id, extension)}
    else
      {:error, reason} ->
        Logger.error("Privacy key derivation failed for #{protocol}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Derives privacy key from an existing localized authentication key.

  Only valid when the privacy password equals the authentication password: the
  localized key is then the same for both, and this skips the expensive
  password-to-key step. The hash used for key extension is inferred from the
  key length unless `auth_protocol:` is given.

  ## Examples

      {:ok, auth_key} = derive_auth_key(:sha256, password, engine_id)

      {:ok, priv_key} = SnmpKit.SnmpLib.Security.Keys.derive_priv_key_from_auth(
        :aes256, auth_key, engine_id
      )
  """
  @spec derive_priv_key_from_auth(priv_protocol(), derived_key(), engine_id(), keyword()) ::
          {:ok, derived_key()} | {:error, atom()}
  def derive_priv_key_from_auth(protocol, auth_key, engine_id, opts \\ []) do
    Logger.debug("Deriving #{protocol} privacy key from authentication key")

    extension = Keyword.get(opts, :key_extension, @default_key_extension)

    with :ok <- validate_priv_protocol(protocol),
         :ok <- validate_auth_key(auth_key),
         :ok <- validate_engine_id(engine_id),
         :ok <- validate_key_extension(extension),
         {:ok, hash} <- hash_for_localized_key(auth_key, Keyword.get(opts, :auth_protocol)) do
      {:ok, fit_priv_key(auth_key, @priv_key_sizes[protocol], hash, engine_id, extension)}
    end
  end

  ## Key Validation and Utilities

  @doc """
  Validates password strength according to SNMPv3 security guidelines.

  ## Requirements

  - Minimum 8 characters (RFC recommendation)
  - Should contain mix of character types for security
  - Should not be based on dictionary words

  ## Examples

      :ok = SnmpKit.SnmpLib.Security.Keys.validate_password_strength("strong_password_123")
      {:error, :too_short} = SnmpKit.SnmpLib.Security.Keys.validate_password_strength("weak")
      {:warning, :weak_complexity} = SnmpKit.SnmpLib.Security.Keys.validate_password_strength("password")
  """
  @spec validate_password_strength(password()) :: :ok | {:error, atom()} | {:warning, atom()}
  def validate_password_strength(password) when is_binary(password) do
    length = String.length(password)

    cond do
      length < @min_password_length ->
        {:error, :too_short}

      length < 12 ->
        {:warning, :short_length}

      is_weak_password?(password) ->
        {:warning, :weak_complexity}

      true ->
        :ok
    end
  end

  @doc """
  Generates a cryptographically secure random password.

  ## Examples

      password = SnmpKit.SnmpLib.Security.Keys.generate_secure_password(16)
      # Returns: "K7mN9pQ2rT8vW3xZ" (example)
  """
  @spec generate_secure_password(pos_integer()) :: password()
  def generate_secure_password(length \\ 16) when length >= @min_password_length do
    # Character set with good entropy
    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
    charset_size = byte_size(charset)
    # Largest multiple of charset_size that fits in a byte; values at or above it
    # are rejected so every character is equally likely.
    limit = div(256, charset_size) * charset_size

    Stream.repeatedly(fn -> :binary.first(:crypto.strong_rand_bytes(1)) end)
    |> Stream.reject(&(&1 >= limit))
    |> Stream.map(&:binary.at(charset, rem(&1, charset_size)))
    |> Enum.take(length)
    |> :binary.list_to_bin()
  end

  @doc """
  Securely compares two derived keys to prevent timing attacks.

  ## Examples

      true = SnmpKit.SnmpLib.Security.Keys.secure_compare(key1, key1)
      false = SnmpKit.SnmpLib.Security.Keys.secure_compare(key1, key2)
  """
  @spec secure_compare(derived_key(), derived_key()) :: boolean()
  def secure_compare(key1, key2) when is_binary(key1) and is_binary(key2) do
    if byte_size(key1) != byte_size(key2) do
      false
    else
      :crypto.hash_equals(key1, key2)
    end
  end

  ## Private Implementation

  # Password-to-key and localization per RFC 3414 A.2 / RFC 7860 9.3:
  #   Ku  = H(first 1 MiB of the password repeated)
  #   Kul = H(Ku || engineID || Ku)
  defp localize_key(protocol, password, engine_id) do
    hash = get_hash_function(protocol)
    ku = password_to_key(hash, password)
    {:ok, :crypto.hash(hash, ku <> engine_id <> ku)}
  end

  # Streams exactly 1 MiB of the cyclically repeated password through the hash
  # in ~64 KiB chunks, so memory stays bounded regardless of password length.
  defp password_to_key(hash, password) do
    len = byte_size(password)
    reps = max(1, div(@password_stream_chunk, len))
    chunk = :binary.copy(password, reps)
    chunk_size = byte_size(chunk)

    hash
    |> :crypto.hash_init()
    |> feed_password_stream(chunk, chunk_size, @key_localization_iterations)
    |> :crypto.hash_final()
  end

  defp feed_password_stream(ctx, _chunk, _chunk_size, 0), do: ctx

  defp feed_password_stream(ctx, chunk, chunk_size, remaining) when remaining >= chunk_size do
    ctx
    |> :crypto.hash_update(chunk)
    |> feed_password_stream(chunk, chunk_size, remaining - chunk_size)
  end

  defp feed_password_stream(ctx, chunk, _chunk_size, remaining) do
    :crypto.hash_update(ctx, binary_part(chunk, 0, remaining))
  end

  defp extract_auth_key(protocol, localized_key) do
    key_size = Map.get(@auth_key_sizes, protocol)

    if byte_size(localized_key) >= key_size do
      {:ok, binary_part(localized_key, 0, key_size)}
    else
      {:error, :insufficient_key_material}
    end
  end

  # Cut or extend a localized key to the cipher's key size.
  defp fit_priv_key(localized_key, key_size, _hash, _engine_id, _extension)
       when byte_size(localized_key) >= key_size do
    binary_part(localized_key, 0, key_size)
  end

  defp fit_priv_key(localized_key, key_size, hash, engine_id, extension) do
    localized_key
    |> extend_key(key_size, hash, engine_id, extension, localized_key)
    |> binary_part(0, key_size)
  end

  defp extend_key(acc, key_size, _hash, _engine_id, _extension, _last)
       when byte_size(acc) >= key_size,
       do: acc

  # draft-reeder-snmpv3-usm-3desede 2.1: treat the previous localized key as a
  # password, run password-to-key + localization again, append.
  defp extend_key(acc, key_size, hash, engine_id, :reeder, last) do
    ku = password_to_key(hash, last)
    next = :crypto.hash(hash, ku <> engine_id <> ku)
    extend_key(acc <> next, key_size, hash, engine_id, :reeder, next)
  end

  # draft-blumenthal-aes-usm-04 3.1.2.1: append H(previous chunk).
  defp extend_key(acc, key_size, hash, engine_id, :blumenthal, last) do
    next = :crypto.hash(hash, last)
    extend_key(acc <> next, key_size, hash, engine_id, :blumenthal, next)
  end

  defp hash_for_localized_key(_key, auth_protocol) when auth_protocol != nil do
    with :ok <- validate_auth_protocol(auth_protocol), do: {:ok, get_hash_function(auth_protocol)}
  end

  defp hash_for_localized_key(key, nil) do
    case byte_size(key) do
      16 -> {:ok, :md5}
      20 -> {:ok, :sha}
      28 -> {:ok, :sha224}
      32 -> {:ok, :sha256}
      48 -> {:ok, :sha384}
      64 -> {:ok, :sha512}
      _ -> {:error, :cannot_infer_auth_protocol}
    end
  end

  defp validate_key_extension(extension) when extension in [:reeder, :blumenthal], do: :ok
  defp validate_key_extension(_), do: {:error, :invalid_key_extension}

  defp get_hash_function(:md5), do: :md5
  defp get_hash_function(:sha1), do: :sha
  defp get_hash_function(:sha224), do: :sha224
  defp get_hash_function(:sha256), do: :sha256
  defp get_hash_function(:sha384), do: :sha384
  defp get_hash_function(:sha512), do: :sha512

  defp validate_auth_protocol(protocol)
       when protocol in [:md5, :sha1, :sha224, :sha256, :sha384, :sha512] do
    :ok
  end

  defp validate_auth_protocol(_), do: {:error, :unsupported_auth_protocol}

  defp validate_priv_protocol(protocol) when protocol in [:des, :aes128, :aes192, :aes256] do
    :ok
  end

  defp validate_priv_protocol(_), do: {:error, :unsupported_priv_protocol}

  defp validate_password(password)
       when is_binary(password) and byte_size(password) >= @min_password_length do
    :ok
  end

  defp validate_password(password) when is_binary(password) do
    {:error, :password_too_short}
  end

  defp validate_password(_), do: {:error, :invalid_password}

  defp validate_engine_id(engine_id) when is_binary(engine_id) do
    size = byte_size(engine_id)

    if size >= @min_engine_id_length and size <= @max_engine_id_length do
      :ok
    else
      {:error, :invalid_engine_id_size}
    end
  end

  defp validate_engine_id(_), do: {:error, :invalid_engine_id}

  defp validate_auth_key(key) when is_binary(key) and byte_size(key) >= 8 do
    :ok
  end

  defp validate_auth_key(_), do: {:error, :invalid_auth_key}

  defp is_weak_password?(password) do
    # Check for common weak patterns
    lowercase = String.downcase(password)

    weak_patterns = [
      "password",
      "123456",
      "qwerty",
      "admin",
      "root",
      "user",
      "test",
      "guest",
      "snmp",
      "public",
      "private"
    ]

    Enum.any?(weak_patterns, fn pattern ->
      String.contains?(lowercase, pattern)
    end)
  end
end
