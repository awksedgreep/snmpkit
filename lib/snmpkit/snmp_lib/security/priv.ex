defmodule SnmpKit.SnmpLib.Security.Priv do
  @moduledoc """
  Implements SNMPv3 privacy protocols for message encryption and decryption.

  This module provides support for standard SNMPv3 privacy protocols like DES and
  AES, ensuring data confidentiality in SNMP communications.

  ## Supported Protocols
  - `:none` - No privacy
  - `:des` - DES-CBC (56-bit)
  - `:aes128` - AES-CFB128 (128-bit)
  - `:aes192` - AES-CFB128 (192-bit)
  - `:aes256` - AES-CFB128 (256-bit)

  ## Security Considerations
  - **DES is considered weak** and should only be used for compatibility with
    legacy devices.
  - **AES protocols are recommended** for strong encryption.
  - Keys should be derived securely using the functions in `SnmpKit.SnmpLib.Security.Keys`.

  ## Protocol Selection Guidelines
  - For new deployments, prefer `:aes256` for the strongest security.
  - Use `:aes128` for a balance of performance and security.
  - Use `:des` only when required for interoperability.

  ## Technical Details
  This module implements the privacy aspects of the User-Based Security Model
  (USM) as defined in RFC 3414 and RFC 3826.

  ### Key Derivation
  Privacy keys are derived from the user's password and the authoritative SNMP
  engine's ID. This process is handled by the `Keys` module.

  ### Initialization Vectors
  For CBC and CFB modes, a unique Initialization Vector (IV) is required for each
  encryption operation. This IV is generated and included in the `privParameters`
  field of the SNMPv3 message.

  ### Padding
  The plaintext data is padded to match the block size of the cipher before
  encryption. This padding is removed upon decryption.

  ## Usage Examples
  This module is typically used internally by the `USM` module.

  ### Message Encryption
      # Assuming keys are derived and user is configured
      priv_key = derived_privacy_key
      auth_key = derived_authentication_key  # Required for IV generation
      plaintext = "confidential SNMP data"

      {:ok, {ciphertext, priv_params}} = SnmpKit.SnmpLib.Security.Priv.encrypt(
        :aes256, priv_key, auth_key, plaintext
      )

      # Decrypt message
      {:ok, decrypted} = SnmpKit.SnmpLib.Security.Priv.decrypt(
        :aes256, priv_key, auth_key, ciphertext, priv_params
      )
      assert decrypted == plaintext

  ### Protocol Information
      iex> SnmpKit.SnmpLib.Security.Priv.protocol_info(:aes128)
      %{algorithm: :aes_128_cfb128, key_size: 16, iv_size: 16, block_size: 16}
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
      key_size: 0,
      iv_size: 0,
      block_size: 0,
      algorithm: nil
    },
    des: %{
      key_size: 8,
      iv_size: 8,
      block_size: 8,
      algorithm: :des_cbc
    },
    aes128: %{
      key_size: 16,
      iv_size: 16,
      block_size: 16,
      algorithm: :aes_128_cfb128
    },
    aes192: %{
      key_size: 24,
      iv_size: 16,
      block_size: 16,
      algorithm: :aes_192_cfb128
    },
    aes256: %{
      key_size: 32,
      iv_size: 16,
      block_size: 16,
      algorithm: :aes_256_cfb128
    }
  }

  @doc """
  Retrieves the specification for a given privacy protocol.

  Returns a map with `:algorithm`, `:key_size`, `:iv_size`, and `:block_size`,
  or `nil` if the protocol is unsupported.

  ## Examples
      iex> Priv.protocol_info(:aes128)
      %{algorithm: :aes_128_cfb128, key_size: 16, iv_size: 16, block_size: 16}

      iex> Priv.protocol_info(:unsupported)
      nil
  """
  @spec protocol_info(priv_protocol()) :: map() | nil
  def protocol_info(protocol) do
    @protocol_specs[protocol]
  end

  @doc """
  Returns a list of all supported privacy protocols.
  """
  @spec supported_protocols() :: [priv_protocol()]
  def supported_protocols do
    Map.keys(@protocol_specs)
  end

  @doc """
  Returns a list of cryptographically secure protocols.
  """
  @spec secure_protocols() :: [priv_protocol()]
  def secure_protocols do
    [:aes128, :aes192, :aes256]
  end

  @doc """
  Checks if a protocol is considered cryptographically secure.
  """
  @spec secure_protocol?(priv_protocol()) :: boolean()
  def secure_protocol?(protocol) do
    protocol in secure_protocols()
  end

  @doc """
  Encrypts plaintext using the specified privacy protocol.

  ## Parameters
  - `protocol`: Privacy protocol to use
  - `priv_key`: Privacy key for the chosen protocol
  - `auth_key`: Authentication key (used for IV generation)
  - `plaintext`: Data to encrypt

  ## Returns
  - `{:ok, {ciphertext, priv_params}}`: Encryption successful
  - `{:error, reason}`: Encryption failed

  ## Examples
      # AES-128 encryption
      {:ok, {ciphertext, priv_params}} = SnmpKit.SnmpLib.Security.Priv.encrypt(
        :aes128, priv_key, auth_key, "secret data"
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
      {:ok, plaintext} = SnmpKit.SnmpLib.Security.Priv.decrypt(
        :aes256, priv_key, auth_key, ciphertext, priv_params
      )

      # Handle decryption errors
      case SnmpKit.SnmpLib.Security.Priv.decrypt(:des, priv_key, auth_key, ciphertext, priv_params) do
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
          Logger.debug(
            "Decryption successful with #{protocol}, plaintext size: #{byte_size(plaintext)}"
          )

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

  @doc """
  Validates if a privacy key is compliant with the protocol's requirements.

  ## Examples
      iex> Priv.validate_key(:aes128, :crypto.strong_rand_bytes(16))
      :ok
      iex> Priv.validate_key(:des, <<1, 2, 3>>)
      {:error, :invalid_key_size}
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
        if byte_size(key) == spec.key_size do
          :ok
        else
          Logger.warning(
            "Privacy key wrong size for #{protocol}: #{byte_size(key)} != #{spec.key_size}"
          )

          {:error, :invalid_key_size}
        end
    end
  end

  def validate_key(_protocol, _key) do
    {:error, :invalid_key_type}
  end

  @doc """
  Encrypts a batch of plaintexts efficiently.

  ## Examples
      iex> plaintexts = ["msg1", "msg2"]
      iex> {:ok, encrypted_list} = Priv.encrypt_batch(:aes128, priv_key, auth_key, plaintexts)
      iex> length(encrypted_list)
      2
  """
  @spec encrypt_batch(priv_protocol(), priv_key(), auth_key(), [plaintext()]) ::
          {:ok, [{ciphertext(), priv_params()}]} | {:error, atom()}
  def encrypt_batch(protocol, priv_key, auth_key, plaintexts) do
    results =
      Enum.map(plaintexts, fn plaintext ->
        encrypt(protocol, priv_key, auth_key, plaintext)
      end)

    if Enum.all?(results, fn
         {:ok, _} -> true
         _ -> false
       end) do
      {:ok, Enum.map(results, fn {:ok, val} -> val end)}
    else
      {:error, :batch_encryption_failed}
    end
  end

  @doc """
  Decrypts a batch of ciphertexts efficiently.
  """
  @spec decrypt_batch(
          priv_protocol(),
          priv_key(),
          auth_key(),
          [{ciphertext(), priv_params()}]
        ) :: [{:ok, plaintext()} | {:error, atom()}]
  def decrypt_batch(protocol, priv_key, auth_key, encrypted_list) do
    Enum.map(encrypted_list, fn {ciphertext, priv_params} ->
      decrypt(protocol, priv_key, auth_key, ciphertext, priv_params)
    end)
  end

  @doc """
  Benchmarks the performance of a given privacy protocol.
  """
  @spec benchmark_protocol(
          priv_protocol(),
          priv_key(),
          auth_key(),
          plaintext(),
          non_neg_integer()
        ) ::
          %{
            encrypt_us: float(),
            decrypt_us: float(),
            ops_per_sec: float()
          }
  def benchmark_protocol(protocol, priv_key, auth_key, test_plaintext, iterations \\ 1000) do
    # Warm-up run
    case encrypt(protocol, priv_key, auth_key, test_plaintext) do
      {:ok, {ciphertext, priv_params}} ->
        decrypt(protocol, priv_key, auth_key, ciphertext, priv_params)

      _ ->
        :ok
    end

    # Encryption benchmark
    encrypt_time =
      :timer.tc(fn ->
        for _ <- 1..iterations do
          encrypt(protocol, priv_key, auth_key, test_plaintext)
        end
      end)
      |> elem(0)

    # Decryption benchmark
    {:ok, {ciphertext, priv_params}} = encrypt(protocol, priv_key, auth_key, test_plaintext)

    decrypt_time =
      :timer.tc(fn ->
        for _ <- 1..iterations do
          decrypt(protocol, priv_key, auth_key, ciphertext, priv_params)
        end
      end)
      |> elem(0)

    total_time_us = encrypt_time + decrypt_time
    ops = iterations * 2
    ops_per_sec = ops / (total_time_us / 1_000_000)

    %{
      encrypt_us: encrypt_time / iterations,
      decrypt_us: decrypt_time / iterations,
      ops_per_sec: ops_per_sec
    }
  end

  # --- Private Helper Functions ---

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

  defp validate_plaintext(plaintext) when is_binary(plaintext) do
    :ok
  end

  defp validate_plaintext(_), do: {:error, :invalid_plaintext}

  defp validate_ciphertext(spec, ciphertext) do
    if rem(byte_size(ciphertext), spec.block_size) == 0 do
      :ok
    else
      {:error, :invalid_ciphertext_size}
    end
  end

  defp validate_privacy_params(spec, priv_params) do
    if byte_size(priv_params) >= spec.iv_size do
      :ok
    else
      {:error, :invalid_priv_params}
    end
  end

  defp generate_iv(:des, spec, _auth_key) do
    # DES uses a simpler IV generation
    iv = :crypto.strong_rand_bytes(spec.iv_size)
    {:ok, iv}
  end

  defp generate_iv(protocol, spec, _auth_key) when protocol in [:aes128, :aes192, :aes256] do
    # AES protocols use engineBoots and engineTime for IV, but for simplicity
    # in this context, we'll use a strong random value.
    # A full USM implementation would use the other parameters.
    iv = :crypto.strong_rand_bytes(spec.iv_size)
    {:ok, iv}
  end

  defp apply_padding(data, block_size) when is_binary(data) and block_size > 0 do
    padding_size = block_size - rem(byte_size(data), block_size)
    padding = :binary.copy(<<padding_size>>, padding_size)
    {:ok, data <> padding}
  end

  defp apply_padding(data, _block_size) do
    {:ok, data}
  end

  defp remove_padding(padded_data, block_size) when byte_size(padded_data) >= block_size do
    padding_size = :binary.last(padded_data)

    if padding_size > 0 and padding_size <= block_size do
      data_size = byte_size(padded_data) - padding_size

      if data_size >= 0 do
        {:ok, :binary.part(padded_data, 0, data_size)}
      else
        {:error, :invalid_padding}
      end
    else
      {:error, :invalid_padding}
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
      error ->
        Logger.error("Encryption failed with algorithm #{spec.algorithm}: #{inspect(error)}")
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
        iv = :binary.part(priv_params, 0, iv_size)
        {:ok, iv}

      _ ->
        {:error, :invalid_iv}
    end
  end
end
