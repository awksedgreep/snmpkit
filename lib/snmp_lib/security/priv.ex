defmodule SnmpLib.Security.Priv do
  @moduledoc """
  Privacy (encryption) protocols for SNMPv3 User Security Model.
  
  Implements encryption protocols as specified in RFC 3414 and RFC 3826,
  providing message confidentiality for SNMPv3 communications.
  
  ## Supported Protocols
  
  - **DES-CBC** (RFC 3414) - 56-bit key, legacy support
  - **AES-128** (RFC 3826) - 128-bit key, good security
  - **AES-192** (RFC 3826) - 192-bit key, enhanced security
  - **AES-256** (RFC 3826) - 256-bit key, maximum security
  
  ## Security Considerations
  
  - DES is deprecated and should only be used for legacy compatibility
  - AES-128 provides adequate security for most applications
  - AES-256 is recommended for high-security environments
  - All encryption uses CBC mode with random initialization vectors
  - Privacy requires authentication (cannot use privacy without authentication)
  
  ## Protocol Selection Guidelines
  
  - **AES-256**: Recommended for high-security environments
  - **AES-128**: Good balance of security and performance for most deployments
  - **DES**: Legacy compatibility only, not recommended for new deployments
  
  ## Technical Details
  
  ### Key Derivation
  Privacy keys are derived from privacy passwords using the same engine ID
  and algorithm as authentication keys, but with different key usage.
  
  ### Initialization Vectors
  Each encryption operation uses a unique initialization vector (IV) to ensure
  that identical plaintexts produce different ciphertexts.
  
  ### Padding
  Block ciphers use PKCS#7 padding to handle messages that don't align
  with block boundaries.
  
  ## Usage Examples
  
  ### Message Encryption
  
      # Encrypt message with AES-256
      priv_key = derived_privacy_key
      auth_key = derived_authentication_key  # Required for IV generation
      plaintext = "confidential SNMP data"
      
      {:ok, {ciphertext, priv_params}} = SnmpLib.Security.Priv.encrypt(
        :aes256, priv_key, auth_key, plaintext
      )
      
      # Decrypt message
      {:ok, decrypted} = SnmpLib.Security.Priv.decrypt(
        :aes256, priv_key, auth_key, ciphertext, priv_params
      )
      
  ### Protocol Information
  
      # Get encryption protocol details
      info = SnmpLib.Security.Priv.protocol_info(:aes256)
      # Returns: %{algorithm: :aes_256_cbc, key_size: 32, block_size: 16, ...}
  """
  
  require Logger
  
  @type priv_protocol :: :none | :des | :aes128 | :aes192 | :aes256
  @type priv_key :: binary()
  @type auth_key :: binary()
  @type priv_params :: binary()
  @type plaintext :: binary()
  @type ciphertext :: binary()
  @type initialization_vector :: binary()
  
  # Protocol specifications per RFC 3414 and RFC 3826
  @protocol_specs %{
    none: %{
      algorithm: :none,
      key_size: 0,
      block_size: 0,
      iv_size: 0,
      secure: false,
      rfc: "N/A"
    },
    des: %{
      algorithm: :des_cbc,
      key_size: 8,        # 56-bit effective + 8 parity bits
      block_size: 8,
      iv_size: 8,
      secure: false,      # Deprecated
      rfc: "RFC 3414"
    },
    aes128: %{
      algorithm: :aes_128_cbc,
      key_size: 16,
      block_size: 16,
      iv_size: 16,
      secure: true,
      rfc: "RFC 3826"
    },
    aes192: %{
      algorithm: :aes_192_cbc,
      key_size: 24,
      block_size: 16,
      iv_size: 16,
      secure: true,
      rfc: "RFC 3826"
    },
    aes256: %{
      algorithm: :aes_256_cbc,
      key_size: 32,
      block_size: 16,
      iv_size: 16,
      secure: true,
      rfc: "RFC 3826"
    }
  }
  
  ## Protocol Information
  
  @doc """
  Returns information about a specific privacy protocol.
  
  ## Examples
  
      iex> SnmpLib.Security.Priv.protocol_info(:aes256)
      %{algorithm: :aes_256_cbc, key_size: 32, block_size: 16, iv_size: 16, secure: true, rfc: "RFC 3826"}
      
      iex> SnmpLib.Security.Priv.protocol_info(:des)
      %{algorithm: :des_cbc, key_size: 8, block_size: 8, iv_size: 8, secure: false, rfc: "RFC 3414"}
  """
  @spec protocol_info(priv_protocol()) :: map() | nil
  def protocol_info(protocol) do
    Map.get(@protocol_specs, protocol)
  end
  
  @doc """
  Returns list of all supported privacy protocols.
  """
  @spec supported_protocols() :: [priv_protocol()]
  def supported_protocols do
    Map.keys(@protocol_specs)
  end
  
  @doc """
  Returns list of cryptographically secure protocols (excludes deprecated ones).
  """
  @spec secure_protocols() :: [priv_protocol()]
  def secure_protocols do
    @protocol_specs
    |> Enum.filter(fn {_protocol, spec} -> spec.secure end)
    |> Enum.map(fn {protocol, _spec} -> protocol end)
  end
  
  @doc """
  Checks if a protocol is considered cryptographically secure.
  """
  @spec secure_protocol?(priv_protocol()) :: boolean()
  def secure_protocol?(protocol) do
    case protocol_info(protocol) do
      %{secure: secure} -> secure
      nil -> false
    end
  end
  
  ## Encryption Operations
  
  @doc """
  Encrypts plaintext using the specified privacy protocol.
  
  ## Parameters
  
  - `protocol`: Privacy protocol to use (:des, :aes128, :aes192, :aes256)
  - `priv_key`: Privacy key (must be correct length for protocol)
  - `auth_key`: Authentication key (used for IV generation in some protocols)
  - `plaintext`: Data to encrypt
  
  ## Returns
  
  - `{:ok, {ciphertext, priv_params}}`: Encryption successful
  - `{:error, reason}`: Encryption failed
  
  ## Examples
  
      # AES-256 encryption (recommended)
      {:ok, {ciphertext, priv_params}} = SnmpLib.Security.Priv.encrypt(
        :aes256, priv_key, auth_key, "secret data"
      )
      
      # DES encryption (legacy)
      {:ok, {ciphertext, priv_params}} = SnmpLib.Security.Priv.encrypt(
        :des, priv_key, auth_key, "legacy data"
      )
  """
  @spec encrypt(priv_protocol(), priv_key(), auth_key(), plaintext()) ::
    {:ok, {ciphertext(), priv_params()}} | {:error, atom()}
  def encrypt(:none, _priv_key, _auth_key, plaintext) do
    {:ok, {plaintext, <<>>}}
  end
  
  def encrypt(protocol, priv_key, auth_key, plaintext) when is_atom(protocol) do
    case protocol_info(protocol) do
      nil ->
        Logger.error("Unsupported privacy protocol: #{protocol}")
        {:error, :unsupported_protocol}
      
      spec ->
        with :ok <- validate_encryption_params(spec, priv_key, plaintext),
             {:ok, iv} <- generate_iv(protocol, spec, auth_key),
             {:ok, padded_plaintext} <- apply_padding(plaintext, spec.block_size),
             {:ok, ciphertext} <- perform_encryption(spec, priv_key, iv, padded_plaintext) do
          
          priv_params = build_privacy_parameters(protocol, iv)
          Logger.debug("Encryption successful with #{protocol}, ciphertext size: #{byte_size(ciphertext)}")
          {:ok, {ciphertext, priv_params}}
        else
          {:error, reason} ->
            Logger.error("Encryption failed for #{protocol}: #{reason}")
            {:error, reason}
        end
    end
  end
  
  def encrypt(protocol, _priv_key, _auth_key, _plaintext) do
    Logger.error("Invalid privacy protocol type: #{inspect(protocol)}")
    {:error, :invalid_protocol_type}
  end
  
  @doc """
  Decrypts ciphertext using the specified privacy protocol.
  
  ## Parameters
  
  - `protocol`: Privacy protocol used for encryption
  - `priv_key`: Privacy key (same as used for encryption)
  - `auth_key`: Authentication key (used for IV validation)
  - `ciphertext`: Encrypted data
  - `priv_params`: Privacy parameters from encryption (contains IV)
  
  ## Returns
  
  - `{:ok, plaintext}`: Decryption successful
  - `{:error, reason}`: Decryption failed
  
  ## Examples
  
      # AES-256 decryption
      {:ok, plaintext} = SnmpLib.Security.Priv.decrypt(
        :aes256, priv_key, auth_key, ciphertext, priv_params
      )
      
      # Handle decryption errors
      case SnmpLib.Security.Priv.decrypt(:des, priv_key, auth_key, ciphertext, priv_params) do
        {:ok, plaintext} -> process_plaintext(plaintext)
        {:error, :decryption_failed} -> handle_corruption()
        {:error, :invalid_padding} -> handle_padding_error()
      end
  """
  @spec decrypt(priv_protocol(), priv_key(), auth_key(), ciphertext(), priv_params()) ::
    {:ok, plaintext()} | {:error, atom()}
  def decrypt(:none, _priv_key, _auth_key, ciphertext, _priv_params) do
    {:ok, ciphertext}
  end
  
  def decrypt(protocol, priv_key, _auth_key, ciphertext, priv_params) when is_atom(protocol) do
    case protocol_info(protocol) do
      nil ->
        Logger.error("Unsupported privacy protocol: #{protocol}")
        {:error, :unsupported_protocol}
      
      spec ->
        with :ok <- validate_decryption_params(spec, priv_key, ciphertext, priv_params),
             {:ok, iv} <- extract_iv(protocol, priv_params),
             {:ok, padded_plaintext} <- perform_decryption(spec, priv_key, iv, ciphertext),
             {:ok, plaintext} <- remove_padding(padded_plaintext, spec.block_size) do
          
          Logger.debug("Decryption successful with #{protocol}, plaintext size: #{byte_size(plaintext)}")
          {:ok, plaintext}
        else
          {:error, reason} ->
            Logger.error("Decryption failed for #{protocol}: #{reason}")
            {:error, reason}
        end
    end
  end
  
  def decrypt(protocol, _priv_key, _auth_key, _ciphertext, _priv_params) do
    Logger.error("Invalid privacy protocol type: #{inspect(protocol)}")
    {:error, :invalid_protocol_type}
  end
  
  ## Key Validation
  
  @doc """
  Validates that a privacy key is appropriate for the specified protocol.
  
  ## Examples
  
      :ok = SnmpLib.Security.Priv.validate_key(:aes256, key_32_bytes)
      {:error, :key_wrong_size} = SnmpLib.Security.Priv.validate_key(:aes128, key_32_bytes)
  """
  @spec validate_key(priv_protocol(), priv_key()) :: :ok | {:error, atom()}
  def validate_key(:none, _key) do
    :ok
  end
  
  def validate_key(protocol, key) when is_atom(protocol) and is_binary(key) do
    case protocol_info(protocol) do
      nil ->
        {:error, :unsupported_protocol}
      
      spec ->
        key_length = byte_size(key)
        expected_length = spec.key_size
        
        cond do
          key_length == 0 ->
            {:error, :empty_key}
          
          key_length != expected_length ->
            Logger.error("Privacy key wrong size for #{protocol}: #{key_length} != #{expected_length}")
            {:error, :key_wrong_size}
          
          not spec.secure ->
            Logger.warning("Using deprecated privacy protocol: #{protocol}")
            :ok
          
          true ->
            :ok
        end
    end
  end
  
  def validate_key(_protocol, _key) do
    {:error, :invalid_parameters}
  end
  
  ## Batch Operations
  
  @doc """
  Encrypts multiple plaintexts using the same protocol and key.
  
  Each plaintext gets a unique IV, ensuring security even for identical plaintexts.
  
  ## Examples
  
      plaintexts = ["data1", "data2", "data3"]
      {:ok, encrypted_list} = SnmpLib.Security.Priv.encrypt_batch(:aes256, priv_key, auth_key, plaintexts)
      # Returns list of {ciphertext, priv_params} tuples
  """
  @spec encrypt_batch(priv_protocol(), priv_key(), auth_key(), [plaintext()]) ::
    {:ok, [{ciphertext(), priv_params()}]} | {:error, atom()}
  def encrypt_batch(protocol, priv_key, auth_key, plaintexts) when is_list(plaintexts) do
    case protocol_info(protocol) do
      nil ->
        {:error, :unsupported_protocol}
      
      _spec ->
        try do
          encrypted_list = Enum.map(plaintexts, fn plaintext ->
            {:ok, {ciphertext, priv_params}} = encrypt(protocol, priv_key, auth_key, plaintext)
            {ciphertext, priv_params}
          end)
          {:ok, encrypted_list}
        rescue
          _error ->
            {:error, :batch_encryption_failed}
        end
    end
  end
  
  @doc """
  Decrypts multiple ciphertexts in batch.
  """
  @spec decrypt_batch(priv_protocol(), priv_key(), auth_key(), [{ciphertext(), priv_params()}]) ::
    [:ok | {:error, atom()}]
  def decrypt_batch(protocol, priv_key, auth_key, encrypted_list) when is_list(encrypted_list) do
    Enum.map(encrypted_list, fn {ciphertext, priv_params} ->
      case decrypt(protocol, priv_key, auth_key, ciphertext, priv_params) do
        {:ok, plaintext} -> {:ok, plaintext}
        {:error, reason} -> {:error, reason}
      end
    end)
  end
  
  ## Performance Testing
  
  @doc """
  Measures encryption/decryption performance for a given protocol.
  """
  @spec benchmark_protocol(priv_protocol(), priv_key(), auth_key(), plaintext(), pos_integer()) :: map()
  def benchmark_protocol(protocol, priv_key, auth_key, test_plaintext, iterations \\ 1000) do
    Logger.info("Benchmarking #{protocol} privacy with #{iterations} iterations")
    
    # Warm up
    {:ok, {test_ciphertext, test_priv_params}} = encrypt(protocol, priv_key, auth_key, test_plaintext)
    
    # Time encryption operations
    {encrypt_time, _} = :timer.tc(fn ->
      Enum.each(1..iterations, fn _i ->
        encrypt(protocol, priv_key, auth_key, test_plaintext)
      end)
    end)
    
    # Time decryption operations
    {decrypt_time, _} = :timer.tc(fn ->
      Enum.each(1..iterations, fn _i ->
        decrypt(protocol, priv_key, auth_key, test_ciphertext, test_priv_params)
      end)
    end)
    
    plaintext_size = byte_size(test_plaintext)
    ciphertext_size = byte_size(test_ciphertext)
    
    %{
      protocol: protocol,
      iterations: iterations,
      plaintext_size: plaintext_size,
      ciphertext_size: ciphertext_size,
      encrypt_time_microseconds: encrypt_time,
      decrypt_time_microseconds: decrypt_time,
      encrypt_ops_per_second: round(iterations / (encrypt_time / 1_000_000)),
      decrypt_ops_per_second: round(iterations / (decrypt_time / 1_000_000)),
      encrypt_throughput_mbps: round((plaintext_size * iterations) / encrypt_time),
      decrypt_throughput_mbps: round((ciphertext_size * iterations) / decrypt_time),
      avg_encrypt_microseconds: round(encrypt_time / iterations),
      avg_decrypt_microseconds: round(decrypt_time / iterations)
    }
  end
  
  ## Private Implementation
  
  defp validate_encryption_params(spec, priv_key, plaintext) do
    with :ok <- validate_key_size(spec, priv_key),
         :ok <- validate_plaintext(plaintext) do
      :ok
    end
  end
  
  defp validate_decryption_params(spec, priv_key, ciphertext, priv_params) do
    with :ok <- validate_key_size(spec, priv_key),
         :ok <- validate_ciphertext(spec, ciphertext),
         :ok <- validate_privacy_params(spec, priv_params) do
      :ok
    end
  end
  
  defp validate_key_size(spec, priv_key) do
    if byte_size(priv_key) == spec.key_size do
      :ok
    else
      {:error, :invalid_key_size}
    end
  end
  
  defp validate_plaintext(plaintext) when is_binary(plaintext) and byte_size(plaintext) > 0 do
    :ok
  end
  defp validate_plaintext(_), do: {:error, :invalid_plaintext}
  
  defp validate_ciphertext(spec, ciphertext) do
    if byte_size(ciphertext) > 0 and rem(byte_size(ciphertext), spec.block_size) == 0 do
      :ok
    else
      {:error, :invalid_ciphertext}
    end
  end
  
  defp validate_privacy_params(spec, priv_params) do
    expected_size = spec.iv_size
    if byte_size(priv_params) >= expected_size do
      :ok
    else
      {:error, :invalid_privacy_params}
    end
  end
  
  defp generate_iv(:des, spec, _auth_key) do
    # DES uses random IV
    iv = :crypto.strong_rand_bytes(spec.iv_size)
    {:ok, iv}
  end
  
  defp generate_iv(protocol, spec, _auth_key) when protocol in [:aes128, :aes192, :aes256] do
    # AES can use auth_key for IV generation or random
    # For simplicity, using random IV (more secure)
    iv = :crypto.strong_rand_bytes(spec.iv_size)
    {:ok, iv}
  end
  
  defp apply_padding(data, block_size) when block_size > 1 do
    # PKCS#7 padding
    padding_length = block_size - rem(byte_size(data), block_size)
    padding = binary_part(<<padding_length::8>>, 0, 1) |> String.duplicate(padding_length)
    {:ok, data <> padding}
  end
  
  defp apply_padding(data, _block_size) do
    {:ok, data}
  end
  
  defp remove_padding(padded_data, block_size) when block_size > 1 do
    if byte_size(padded_data) == 0 do
      {:error, :empty_data}
    else
      # Extract padding length from last byte
      <<padding_length::8>> = binary_part(padded_data, byte_size(padded_data) - 1, 1)
      
      if padding_length > 0 and padding_length <= block_size and 
         padding_length <= byte_size(padded_data) do
        data_length = byte_size(padded_data) - padding_length
        {:ok, binary_part(padded_data, 0, data_length)}
      else
        {:error, :invalid_padding}
      end
    end
  end
  
  defp remove_padding(data, _block_size) do
    {:ok, data}
  end
  
  defp perform_encryption(spec, key, iv, plaintext) do
    try do
      ciphertext = :crypto.crypto_one_time(spec.algorithm, key, iv, plaintext, true)
      {:ok, ciphertext}
    rescue
      _error ->
        {:error, :encryption_failed}
    end
  end
  
  defp perform_decryption(spec, key, iv, ciphertext) do
    try do
      plaintext = :crypto.crypto_one_time(spec.algorithm, key, iv, ciphertext, false)
      {:ok, plaintext}
    rescue
      _error ->
        {:error, :decryption_failed}
    end
  end
  
  defp build_privacy_parameters(_protocol, iv) do
    # Privacy parameters contain the IV for the receiving side
    iv
  end
  
  defp extract_iv(protocol, priv_params) do
    case protocol_info(protocol) do
      %{iv_size: iv_size} when byte_size(priv_params) >= iv_size ->
        iv = binary_part(priv_params, 0, iv_size)
        {:ok, iv}
      _ ->
        {:error, :invalid_iv}
    end
  end
end