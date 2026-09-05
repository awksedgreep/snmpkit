defmodule SnmpKit.SnmpLib.Security.Priv do
  @moduledoc """
  Implements SNMPv3 privacy protocols for message encryption and decryption.

  This module provides support for standard SNMPv3 privacy protocols like DES and
  AES, ensuring data confidentiality in SNMP communications.

  ## Supported Protocols
  - `:none` - No privacy
  - `:des` - DES-CBC (56-bit), RFC 3414 section 8
  - `:aes128` - AES-CFB128 (128-bit), RFC 3826
  - `:aes192` - AES-CFB128 (192-bit), draft-blumenthal-aes-usm / draft-reeder-snmpv3-usm-3desede
  - `:aes256` - AES-CFB128 (256-bit), same as above

  ## Security Considerations
  - **DES is considered weak** and should only be used for compatibility with
    legacy devices.
  - **AES protocols are recommended** for strong encryption.
  - Keys should be derived securely using the functions in `SnmpKit.SnmpLib.Security.Keys`.
  - Privacy provides confidentiality only. Integrity comes from authentication;
    CFB-mode decryption with a wrong key silently yields garbage, which is why
    SNMPv3 forbids `priv` without `auth`.

  ## Protocol Selection Guidelines
  - For new deployments, prefer `:aes256` for the strongest security.
  - Use `:aes128` for a balance of performance and security.
  - Use `:des` only when required for interoperability.

  ## Technical Details
  This module implements the privacy aspects of the User-Based Security Model
  (USM) as defined in RFC 3414 and RFC 3826.

  ### Keys
  Privacy keys are localized keys produced by `SnmpKit.SnmpLib.Security.Keys`.

  - DES uses a 16-octet key: the first 8 octets are the DES key, the last 8
    octets are the "pre-IV" (RFC 3414 section 8.1.1.1).
  - AES uses a 16, 24 or 32 octet key.

  ### Initialization Vectors and `privParameters`
  IVs are *not* random. They are derived from the authoritative engine's
  `snmpEngineBoots` / `snmpEngineTime` and a per-message salt, and only the salt
  travels on the wire as `msgPrivacyParameters` (8 octets for every protocol):

  - DES (RFC 3414 section 8.1.1.1): `salt = engineBoots(4) || localInt(4)`,
    `IV = preIV XOR salt`.
  - AES (RFC 3826 section 3.1.2.1): `IV = engineBoots(4) || engineTime(4) || salt(8)`.

  The local integer is a 64-bit counter seeded randomly at first use and
  incremented for every message, so a `(key, IV)` pair is never reused.

  ### Padding
  DES-CBC requires the plaintext to be a multiple of 8 octets. RFC 3414 pads
  with arbitrary octets and does *not* transmit the padding length; the receiver
  relies on the BER length of the decrypted ScopedPDU. `decrypt/6` therefore
  returns the padded plaintext for DES, and callers decode it as a BER SEQUENCE
  (trailing octets are ignored). AES-CFB is a stream mode and needs no padding.

  ## Usage Examples
  This module is typically used internally by the `USM` module.

  ### Message Encryption
      {:ok, {ciphertext, priv_params}} = SnmpKit.SnmpLib.Security.Priv.encrypt(
        :aes256, priv_key, auth_key, scoped_pdu,
        engine_boots: boots, engine_time: time
      )

      {:ok, decrypted} = SnmpKit.SnmpLib.Security.Priv.decrypt(
        :aes256, priv_key, auth_key, ciphertext, priv_params,
        engine_boots: boots, engine_time: time
      )

  ### Protocol Information
      iex> SnmpKit.SnmpLib.Security.Priv.protocol_info(:aes128)
      %{algorithm: :aes_128_cfb128, key_size: 16, iv_size: 16, block_size: 16, priv_params_size: 8}
  """

  import Bitwise
  require Logger

  @type priv_protocol :: :none | :des | :aes128 | :aes192 | :aes256
  @type priv_key :: binary()
  @type auth_key :: binary()
  @type priv_params :: binary()
  @type plaintext :: binary()
  @type ciphertext :: binary()
  @type initialization_vector :: binary()
  @type priv_opts :: [
          engine_boots: non_neg_integer(),
          engine_time: non_neg_integer(),
          salt: binary() | non_neg_integer()
        ]

  # Protocol specifications per RFC 3414 and RFC 3826
  @protocol_specs %{
    none: %{
      key_size: 0,
      iv_size: 0,
      block_size: 0,
      priv_params_size: 0,
      algorithm: nil
    },
    des: %{
      # 8 octets DES key + 8 octets pre-IV
      key_size: 16,
      iv_size: 8,
      block_size: 8,
      priv_params_size: 8,
      algorithm: :des_cbc
    },
    aes128: %{
      key_size: 16,
      iv_size: 16,
      # CFB is a stream mode; block_size is informational only
      block_size: 16,
      priv_params_size: 8,
      algorithm: :aes_128_cfb128
    },
    aes192: %{
      key_size: 24,
      iv_size: 16,
      block_size: 16,
      priv_params_size: 8,
      algorithm: :aes_192_cfb128
    },
    aes256: %{
      key_size: 32,
      iv_size: 16,
      block_size: 16,
      priv_params_size: 8,
      algorithm: :aes_256_cfb128
    }
  }

  @aes_protocols [:aes128, :aes192, :aes256]

  @doc """
  Retrieves the specification for a given privacy protocol.

  Returns a map with `:algorithm`, `:key_size`, `:iv_size`, `:block_size` and
  `:priv_params_size`, or `nil` if the protocol is unsupported.

  ## Examples
      iex> Priv.protocol_info(:aes128)
      %{algorithm: :aes_128_cfb128, key_size: 16, iv_size: 16, block_size: 16, priv_params_size: 8}

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
    @aes_protocols
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
  - `priv_key`: Localized privacy key for the chosen protocol
  - `auth_key`: Authentication key (unused by the RFC algorithms, kept for API compatibility)
  - `plaintext`: Data to encrypt (normally the BER-encoded ScopedPDU)
  - `opts`:
    - `:engine_boots` - authoritative `snmpEngineBoots` placed in the message (default 0)
    - `:engine_time` - authoritative `snmpEngineTime` placed in the message (default 0)
    - `:salt` - explicit 8-octet salt / 64-bit integer, mainly for tests; a fresh
      counter value is used when omitted

  ## Returns
  - `{:ok, {ciphertext, priv_params}}`: Encryption successful. `priv_params` is
    the 8-octet salt to send as `msgPrivacyParameters`.
  - `{:error, reason}`: Encryption failed

  ## Examples
      {:ok, {ciphertext, priv_params}} = SnmpKit.SnmpLib.Security.Priv.encrypt(
        :aes128, priv_key, auth_key, scoped_pdu, engine_boots: 3, engine_time: 1200
      )
  """
  @spec encrypt(priv_protocol(), priv_key(), auth_key(), plaintext(), priv_opts()) ::
          {:ok, {ciphertext(), priv_params()}} | {:error, atom()}
  def encrypt(protocol, priv_key, auth_key, plaintext, opts \\ [])

  def encrypt(:none, _priv_key, _auth_key, plaintext, _opts) do
    {:ok, {plaintext, <<>>}}
  end

  def encrypt(protocol, priv_key, _auth_key, plaintext, opts) when is_atom(protocol) do
    case protocol_info(protocol) do
      nil ->
        Logger.error("Unsupported privacy protocol: #{protocol}")
        {:error, :unsupported_protocol}

      spec ->
        with :ok <- validate_key_size(spec, priv_key),
             :ok <- validate_plaintext(plaintext),
             {:ok, salt} <- resolve_salt(opts),
             {:ok, iv, cipher_key} <- build_iv(protocol, spec, priv_key, salt, opts),
             {:ok, padded} <- apply_padding(protocol, plaintext, spec.block_size),
             {:ok, ciphertext} <- perform_encryption(spec, cipher_key, iv, padded) do
          {:ok, {ciphertext, salt}}
        else
          {:error, reason} ->
            Logger.error("Encryption failed for #{protocol}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  def encrypt(protocol, _priv_key, _auth_key, _plaintext, _opts) do
    Logger.error("Invalid privacy protocol type: #{inspect(protocol)}")
    {:error, :invalid_protocol_type}
  end

  @doc """
  Decrypts ciphertext using the specified privacy protocol.

  ## Parameters

  - `protocol`: Privacy protocol used for encryption
  - `priv_key`: Localized privacy key (same as used for encryption)
  - `auth_key`: Authentication key (unused by the RFC algorithms, kept for API compatibility)
  - `ciphertext`: Encrypted data
  - `priv_params`: The 8-octet `msgPrivacyParameters` salt from the received message
  - `opts`: `:engine_boots` / `:engine_time` as carried in the received
    `msgAuthoritativeEngineBoots` / `msgAuthoritativeEngineTime` (needed for AES)

  ## Returns

  - `{:ok, plaintext}`: Decryption successful. For DES the result still carries
    the RFC 3414 block padding; decode it as a BER SEQUENCE and ignore the tail.
  - `{:error, reason}`: Decryption failed

  Note that a wrong key cannot be detected here: CFB and unpadded CBC produce
  garbage rather than an error. Verify authentication before decrypting.
  """
  @spec decrypt(priv_protocol(), priv_key(), auth_key(), ciphertext(), priv_params(), priv_opts()) ::
          {:ok, plaintext()} | {:error, atom()}
  def decrypt(protocol, priv_key, auth_key, ciphertext, priv_params, opts \\ [])

  def decrypt(:none, _priv_key, _auth_key, ciphertext, _priv_params, _opts) do
    {:ok, ciphertext}
  end

  def decrypt(protocol, priv_key, _auth_key, ciphertext, priv_params, opts)
      when is_atom(protocol) do
    case protocol_info(protocol) do
      nil ->
        Logger.error("Unsupported privacy protocol: #{protocol}")
        {:error, :unsupported_protocol}

      spec ->
        with :ok <- validate_key_size(spec, priv_key),
             :ok <- validate_ciphertext(protocol, spec, ciphertext),
             :ok <- validate_privacy_params(spec, priv_params),
             {:ok, iv, cipher_key} <- build_iv(protocol, spec, priv_key, priv_params, opts),
             {:ok, plaintext} <- perform_decryption(spec, cipher_key, iv, ciphertext) do
          {:ok, plaintext}
        else
          {:error, reason} ->
            Logger.error("Decryption failed for #{protocol}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  def decrypt(protocol, _priv_key, _auth_key, _ciphertext, _priv_params, _opts) do
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
  @spec encrypt_batch(priv_protocol(), priv_key(), auth_key(), [plaintext()], priv_opts()) ::
          {:ok, [{ciphertext(), priv_params()}]} | {:error, atom()}
  def encrypt_batch(protocol, priv_key, auth_key, plaintexts, opts \\ []) do
    results =
      Enum.map(plaintexts, fn plaintext ->
        encrypt(protocol, priv_key, auth_key, plaintext, opts)
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
          [{ciphertext(), priv_params()}],
          priv_opts()
        ) :: [{:ok, plaintext()} | {:error, atom()}]
  def decrypt_batch(protocol, priv_key, auth_key, encrypted_list, opts \\ []) do
    Enum.map(encrypted_list, fn {ciphertext, priv_params} ->
      decrypt(protocol, priv_key, auth_key, ciphertext, priv_params, opts)
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

  defp validate_key_size(spec, priv_key) when is_binary(priv_key) do
    if byte_size(priv_key) == spec.key_size do
      :ok
    else
      {:error, :invalid_key_size}
    end
  end

  defp validate_key_size(_spec, _priv_key), do: {:error, :invalid_key_type}

  defp validate_plaintext(plaintext) when is_binary(plaintext), do: :ok
  defp validate_plaintext(_), do: {:error, :invalid_plaintext}

  # DES-CBC ciphertext must be whole blocks; CFB output has the plaintext's length.
  defp validate_ciphertext(:des, spec, ciphertext) when is_binary(ciphertext) do
    if byte_size(ciphertext) > 0 and rem(byte_size(ciphertext), spec.block_size) == 0 do
      :ok
    else
      {:error, :invalid_ciphertext_size}
    end
  end

  defp validate_ciphertext(_protocol, _spec, ciphertext) when is_binary(ciphertext), do: :ok
  defp validate_ciphertext(_protocol, _spec, _ciphertext), do: {:error, :invalid_ciphertext}

  defp validate_privacy_params(spec, priv_params) when is_binary(priv_params) do
    if byte_size(priv_params) == spec.priv_params_size do
      :ok
    else
      {:error, :invalid_priv_params}
    end
  end

  defp validate_privacy_params(_spec, _priv_params), do: {:error, :invalid_priv_params}

  # Salt handling -------------------------------------------------------------

  defp resolve_salt(opts) do
    case Keyword.get(opts, :salt) do
      nil -> {:ok, <<next_salt_counter()::unsigned-big-64>>}
      salt when is_binary(salt) and byte_size(salt) == 8 -> {:ok, salt}
      salt when is_integer(salt) and salt >= 0 -> {:ok, <<salt::unsigned-big-64>>}
      _ -> {:error, :invalid_salt}
    end
  end

  # RFC 3414 8.1.1.1 / RFC 3826 3.1.2.1: the local integer part of the salt is
  # initialised to a random value and incremented for every encrypted message.
  # One VM-wide 64-bit counter shared by every protocol satisfies that for all
  # users; the DES path folds it to 32 bits.
  @salt_counter_key {__MODULE__, :salt_counter}

  defp next_salt_counter do
    :atomics.add_get(salt_counter_ref(), 1, 1) |> band(0xFFFFFFFFFFFFFFFF)
  end

  defp salt_counter_ref do
    case :persistent_term.get(@salt_counter_key, nil) do
      nil ->
        ref = :atomics.new(1, signed: false)
        <<seed::unsigned-big-64>> = :crypto.strong_rand_bytes(8)
        :atomics.put(ref, 1, seed)
        :persistent_term.put(@salt_counter_key, ref)
        :persistent_term.get(@salt_counter_key)

      ref ->
        ref
    end
  end

  # IV construction -----------------------------------------------------------

  # RFC 3414 8.1.1.1: privKey(16) = desKey(8) || preIV(8);
  # salt = engineBoots(4) || localInt(4); IV = preIV XOR salt.
  defp build_iv(:des, _spec, <<des_key::binary-8, pre_iv::binary-8>>, salt, opts) do
    engine_boots = engine_value(opts, :engine_boots)
    <<_::binary-4, local_int::binary-4>> = salt
    des_salt = <<engine_boots::unsigned-big-32>> <> local_int
    {:ok, :crypto.exor(pre_iv, des_salt), des_key}
  end

  # RFC 3826 3.1.2.1: IV = engineBoots(4) || engineTime(4) || salt(8)
  defp build_iv(protocol, _spec, priv_key, salt, opts) when protocol in @aes_protocols do
    engine_boots = engine_value(opts, :engine_boots)
    engine_time = engine_value(opts, :engine_time)
    iv = <<engine_boots::unsigned-big-32, engine_time::unsigned-big-32>> <> salt
    {:ok, iv, priv_key}
  end

  defp build_iv(_protocol, _spec, _priv_key, _salt, _opts), do: {:error, :invalid_key_size}

  defp engine_value(opts, key) do
    case Keyword.get(opts, key, 0) do
      value when is_integer(value) and value >= 0 -> band(value, 0xFFFFFFFF)
      _ -> 0
    end
  end

  # Padding -------------------------------------------------------------------

  # RFC 3414 8.1.1.2: DES plaintext is padded to a block multiple; the padding
  # content is unspecified and the receiver uses the BER length to find the end.
  defp apply_padding(:des, data, block_size) do
    case rem(byte_size(data), block_size) do
      0 -> {:ok, data}
      r -> {:ok, data <> :binary.copy(<<0>>, block_size - r)}
    end
  end

  # CFB is a stream mode: no padding.
  defp apply_padding(_protocol, data, _block_size), do: {:ok, data}

  # Cipher --------------------------------------------------------------------

  defp perform_encryption(spec, key, iv, plaintext) do
    try do
      {:ok, :crypto.crypto_one_time(spec.algorithm, key, iv, plaintext, true)}
    rescue
      error ->
        Logger.error("Encryption failed with algorithm #{spec.algorithm}: #{inspect(error)}")
        {:error, :encryption_failed}
    end
  end

  defp perform_decryption(spec, key, iv, ciphertext) do
    try do
      {:ok, :crypto.crypto_one_time(spec.algorithm, key, iv, ciphertext, false)}
    rescue
      _error ->
        {:error, :decryption_failed}
    end
  end
end
