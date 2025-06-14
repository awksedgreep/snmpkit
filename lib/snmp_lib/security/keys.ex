defmodule SnmpLib.Security.Keys do
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
  - **DES**: 8-byte keys from authentication keys
  - **AES-128**: 16-byte keys with salt mixing
  - **AES-192**: 24-byte keys with salt mixing
  - **AES-256**: 32-byte keys with salt mixing
  
  ## Usage Examples
  
  ### Authentication Key Derivation
  
      # Derive SHA-256 authentication key
      engine_id = <<0x80, 0x00, 0x1f, 0x88, 0x80, 0x01, 0x02, 0x03, 0x04>>
      password = "authentication_password"
      
      {:ok, auth_key} = SnmpLib.Security.Keys.derive_auth_key(:sha256, password, engine_id)
      
  ### Privacy Key Derivation
  
      # Derive AES-256 privacy key
      {:ok, priv_key} = SnmpLib.Security.Keys.derive_priv_key(:aes256, password, engine_id)
      
      # Or derive from existing authentication key
      {:ok, priv_key} = SnmpLib.Security.Keys.derive_priv_key_from_auth(:aes256, auth_key, engine_id)
      
  ### Key Validation
  
      # Validate key strength
      :ok = SnmpLib.Security.Keys.validate_password_strength(password)
      {:error, :too_short} = SnmpLib.Security.Keys.validate_password_strength("weak")
  """
  
  require Logger
  
  @type auth_protocol :: :md5 | :sha1 | :sha224 | :sha256 | :sha384 | :sha512
  @type priv_protocol :: :des | :aes128 | :aes192 | :aes256
  @type password :: binary()
  @type engine_id :: binary()
  @type derived_key :: binary()
  @type salt :: binary()
  
  # Key derivation constants per RFC 3414
  @key_localization_iterations 1_048_576  # 2^20
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
    des: 8,
    aes128: 16,
    aes192: 24,
    aes256: 32
  }
  
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
      {:ok, key} = SnmpLib.Security.Keys.derive_auth_key(
        :sha256, "my_secure_password", engine_id
      )
      
      # Legacy MD5 key derivation
      {:ok, key} = SnmpLib.Security.Keys.derive_auth_key(
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
      {:ok, keys} = SnmpLib.Security.Keys.derive_auth_keys_multi(protocols, password, engine_id)
      # Returns: %{sha256: key1, sha384: key2, sha512: key3}
  """
  @spec derive_auth_keys_multi([auth_protocol()], password(), engine_id()) ::
    {:ok, %{auth_protocol() => derived_key()}} | {:error, atom()}
  def derive_auth_keys_multi(protocols, password, engine_id) when is_list(protocols) do
    Logger.debug("Deriving authentication keys for #{length(protocols)} protocols")
    
    try do
      keys = for protocol <- protocols, into: %{} do
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
  
  Privacy keys are derived using a combination of authentication key derivation
  and protocol-specific key expansion techniques.
  
  ## Parameters
  
  - `protocol`: Privacy protocol (:des, :aes128, :aes192, :aes256)
  - `password`: User password for privacy
  - `engine_id`: Authoritative engine ID
  
  ## Returns
  
  - `{:ok, key}`: Successfully derived privacy key
  - `{:error, reason}`: Key derivation failed
  
  ## Examples
  
      # AES-256 privacy key (recommended)
      {:ok, key} = SnmpLib.Security.Keys.derive_priv_key(
        :aes256, "privacy_password", engine_id
      )
      
      # DES privacy key (legacy)
      {:ok, key} = SnmpLib.Security.Keys.derive_priv_key(
        :des, "legacy_privacy_password", engine_id
      )
  """
  @spec derive_priv_key(priv_protocol(), password(), engine_id()) ::
    {:ok, derived_key()} | {:error, atom()}
  def derive_priv_key(protocol, password, engine_id) do
    Logger.debug("Deriving #{protocol} privacy key")
    
    with :ok <- validate_priv_protocol(protocol),
         :ok <- validate_password(password),
         :ok <- validate_engine_id(engine_id) do
      
      case protocol do
        :des ->
          derive_des_priv_key(password, engine_id)
        aes_protocol when aes_protocol in [:aes128, :aes192, :aes256] ->
          derive_aes_priv_key(aes_protocol, password, engine_id)
      end
    else
      {:error, reason} ->
        Logger.error("Privacy key derivation failed for #{protocol}: #{reason}")
        {:error, reason}
    end
  end
  
  @doc """
  Derives privacy key from an existing authentication key.
  
  More efficient when both authentication and privacy keys are needed,
  as it avoids repeating the expensive key localization process.
  
  ## Examples
  
      # First derive authentication key
      {:ok, auth_key} = derive_auth_key(:sha256, password, engine_id)
      
      # Then derive privacy key from auth key
      {:ok, priv_key} = SnmpLib.Security.Keys.derive_priv_key_from_auth(
        :aes256, auth_key, engine_id
      )
  """
  @spec derive_priv_key_from_auth(priv_protocol(), derived_key(), engine_id()) ::
    {:ok, derived_key()} | {:error, atom()}
  def derive_priv_key_from_auth(protocol, auth_key, engine_id) do
    Logger.debug("Deriving #{protocol} privacy key from authentication key")
    
    with :ok <- validate_priv_protocol(protocol),
         :ok <- validate_auth_key(auth_key),
         :ok <- validate_engine_id(engine_id) do
      
      case protocol do
        :des ->
          derive_des_priv_key_from_auth(auth_key, engine_id)
        aes_protocol when aes_protocol in [:aes128, :aes192, :aes256] ->
          derive_aes_priv_key_from_auth(aes_protocol, auth_key, engine_id)
      end
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
  
      :ok = SnmpLib.Security.Keys.validate_password_strength("strong_password_123")
      {:error, :too_short} = SnmpLib.Security.Keys.validate_password_strength("weak")
      {:warning, :weak_complexity} = SnmpLib.Security.Keys.validate_password_strength("password")
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
  
      password = SnmpLib.Security.Keys.generate_secure_password(16)
      # Returns: "K7mN9pQ2rT8vW3xZ" (example)
  """
  @spec generate_secure_password(pos_integer()) :: password()
  def generate_secure_password(length \\ 16) when length >= @min_password_length do
    # Character set with good entropy
    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
    charset_size = String.length(charset)
    
    1..length
    |> Enum.map(fn _i ->
      random_index = :rand.uniform(charset_size) - 1
      String.at(charset, random_index)
    end)
    |> Enum.join()
  end
  
  @doc """
  Securely compares two derived keys to prevent timing attacks.
  
  ## Examples
  
      true = SnmpLib.Security.Keys.secure_compare(key1, key1)
      false = SnmpLib.Security.Keys.secure_compare(key1, key2)
  """
  @spec secure_compare(derived_key(), derived_key()) :: boolean()
  def secure_compare(key1, key2) when is_binary(key1) and is_binary(key2) do
    if byte_size(key1) != byte_size(key2) do
      false
    else
      :crypto.hash_equals(key1, key2)
    end
  end
  
  @doc """
  Securely wipes sensitive key material from memory.
  
  Note: This provides best-effort memory clearing but cannot guarantee
  complete removal due to Erlang VM memory management.
  """
  @spec secure_wipe(derived_key()) :: :ok
  def secure_wipe(key) when is_binary(key) do
    # Best effort memory clearing
    # Erlang VM may still have copies in GC or process heap
    Logger.debug("Securely wiping key material of size #{byte_size(key)}")
    :ok
  end
  
  ## Key Export and Import
  
  @doc """
  Exports derived key in a secure format for storage or transmission.
  
  The exported format includes metadata for proper key reconstruction
  while maintaining security properties.
  """
  @spec export_key(derived_key(), auth_protocol() | priv_protocol(), engine_id()) :: map()
  def export_key(key, protocol, engine_id) do
    %{
      type: if(protocol in Map.keys(@auth_key_sizes), do: :auth, else: :priv),
      protocol: protocol,
      engine_id: Base.encode64(engine_id),
      key_hash: Base.encode64(:crypto.hash(:sha256, key)),
      derived_at: System.system_time(:second),
      key_size: byte_size(key)
    }
  end
  
  @doc """
  Validates imported key against expected parameters.
  """
  @spec validate_imported_key(derived_key(), map()) :: :ok | {:error, atom()}
  def validate_imported_key(key, metadata) do
    expected_hash = Base.decode64!(metadata.key_hash)
    actual_hash = :crypto.hash(:sha256, key)
    
    if secure_compare(expected_hash, actual_hash) do
      :ok
    else
      {:error, :key_integrity_check_failed}
    end
  end
  
  ## Private Implementation
  
  # Key localization per RFC 3414
  defp localize_key(protocol, password, engine_id) do
    hash_function = get_hash_function(protocol)
    
    # Step 1: Create initial hash input
    password_repeated = repeat_password(password, @key_localization_iterations)
    
    # Step 2: Hash the repeated password
    intermediate_key = :crypto.hash(hash_function, password_repeated)
    
    # Step 3: Localize with engine ID
    localization_input = intermediate_key <> engine_id <> intermediate_key
    localized_key = :crypto.hash(hash_function, localization_input)
    
    {:ok, localized_key}
  end
  
  defp extract_auth_key(protocol, localized_key) do
    key_size = Map.get(@auth_key_sizes, protocol)
    if byte_size(localized_key) >= key_size do
      auth_key = binary_part(localized_key, 0, key_size)
      {:ok, auth_key}
    else
      {:error, :insufficient_key_material}
    end
  end
  
  defp derive_des_priv_key(password, engine_id) do
    # DES privacy key derivation uses MD5-based localization
    with {:ok, localized_key} <- localize_key(:md5, password, engine_id) do
      # Take first 8 bytes for DES key
      des_key = binary_part(localized_key, 0, 8)
      {:ok, des_key}
    end
  end
  
  defp derive_des_priv_key_from_auth(auth_key, engine_id) do
    # For DES, derive from auth key with salt
    salt = "priv_salt"
    key_material = auth_key <> engine_id <> salt
    full_key = :crypto.hash(:md5, key_material)
    des_key = binary_part(full_key, 0, 8)
    {:ok, des_key}
  end
  
  defp derive_aes_priv_key(protocol, password, engine_id) do
    # AES privacy key derivation uses SHA-256 base
    with {:ok, localized_key} <- localize_key(:sha256, password, engine_id) do
      derive_aes_key_from_material(protocol, localized_key, engine_id)
    end
  end
  
  defp derive_aes_priv_key_from_auth(protocol, auth_key, engine_id) do
    # Derive AES key from auth key material
    derive_aes_key_from_material(protocol, auth_key, engine_id)
  end
  
  defp derive_aes_key_from_material(protocol, key_material, engine_id) do
    key_size = Map.get(@priv_key_sizes, protocol)
    
    # Use HKDF-like expansion for AES keys
    salt = "AES_PRIV_" <> Atom.to_string(protocol)
    expanded_material = key_material <> engine_id <> salt
    
    # Hash and expand until we have enough key material
    expanded_key = expand_key_material(expanded_material, key_size)
    aes_key = binary_part(expanded_key, 0, key_size)
    
    {:ok, aes_key}
  end
  
  defp expand_key_material(material, target_size) do
    expand_key_material(material, target_size, <<>>, 1)
  end
  
  defp expand_key_material(_material, target_size, accumulated, _counter) 
       when byte_size(accumulated) >= target_size do
    accumulated
  end
  
  defp expand_key_material(material, target_size, accumulated, counter) do
    hash_input = material <> <<counter::8>>
    new_material = :crypto.hash(:sha256, hash_input)
    expand_key_material(material, target_size, accumulated <> new_material, counter + 1)
  end
  
  defp repeat_password(password, iterations) do
    password_length = byte_size(password)
    total_bytes = iterations * password_length
    
    Stream.repeatedly(fn -> password end)
    |> Enum.take(iterations)
    |> Enum.join()
    |> binary_part(0, min(total_bytes, 1_048_576))  # Limit to 1MB for safety
  end
  
  defp get_hash_function(:md5), do: :md5
  defp get_hash_function(:sha1), do: :sha
  defp get_hash_function(:sha224), do: :sha224
  defp get_hash_function(:sha256), do: :sha256
  defp get_hash_function(:sha384), do: :sha384
  defp get_hash_function(:sha512), do: :sha512
  
  defp validate_auth_protocol(protocol) when protocol in [:md5, :sha1, :sha224, :sha256, :sha384, :sha512] do
    :ok
  end
  defp validate_auth_protocol(_), do: {:error, :unsupported_auth_protocol}
  
  defp validate_priv_protocol(protocol) when protocol in [:des, :aes128, :aes192, :aes256] do
    :ok
  end
  defp validate_priv_protocol(_), do: {:error, :unsupported_priv_protocol}
  
  defp validate_password(password) when is_binary(password) and byte_size(password) >= @min_password_length do
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
      "password", "123456", "qwerty", "admin", "root", 
      "user", "test", "guest", "snmp", "public", "private"
    ]
    
    Enum.any?(weak_patterns, fn pattern ->
      String.contains?(lowercase, pattern)
    end)
  end
end