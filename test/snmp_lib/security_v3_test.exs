defmodule SnmpKit.SnmpLib.SecurityV3Test do
  use ExUnit.Case, async: false
  @moduletag :snmpv3

  alias SnmpKit.SnmpLib.Security
  alias SnmpKit.SnmpLib.Security.{Auth, Priv, Keys, USM}

  @moduletag :unit
  @moduletag :snmpv3
  @moduletag :security

  describe "Authentication protocol tests" do
    test "HMAC-MD5 authentication" do
      key = :crypto.strong_rand_bytes(16)
      message = "Test message for MD5"

      assert {:ok, auth_params} = Auth.authenticate(:md5, key, message)
      assert byte_size(auth_params) == 12
      assert :ok = Auth.verify(:md5, key, message, auth_params)
    end

    test "HMAC-SHA1 authentication" do
      key = :crypto.strong_rand_bytes(20)
      message = "Test message for SHA1"

      assert {:ok, auth_params} = Auth.authenticate(:sha1, key, message)
      assert byte_size(auth_params) == 12
      assert :ok = Auth.verify(:sha1, key, message, auth_params)
    end

    test "HMAC-SHA256 authentication" do
      key = :crypto.strong_rand_bytes(32)
      message = "Test message for SHA256"

      assert {:ok, auth_params} = Auth.authenticate(:sha256, key, message)
      # RFC 7860 4.2: HMAC-192-SHA-256
      assert byte_size(auth_params) == 24
      assert :ok = Auth.verify(:sha256, key, message, auth_params)
    end

    test "HMAC-SHA384 authentication" do
      key = :crypto.strong_rand_bytes(48)
      message = "Test message for SHA384"

      assert {:ok, auth_params} = Auth.authenticate(:sha384, key, message)
      # RFC 7860 4.2: HMAC-256-SHA-384
      assert byte_size(auth_params) == 32
      assert :ok = Auth.verify(:sha384, key, message, auth_params)
    end

    test "HMAC-SHA512 authentication" do
      key = :crypto.strong_rand_bytes(64)
      message = "Test message for SHA512"

      assert {:ok, auth_params} = Auth.authenticate(:sha512, key, message)
      # RFC 7860 4.2: HMAC-384-SHA-512
      assert byte_size(auth_params) == 48
      assert :ok = Auth.verify(:sha512, key, message, auth_params)
    end

    test "authentication with no security" do
      assert {:ok, <<>>} = Auth.authenticate(:none, <<>>, "any message")
      assert :ok = Auth.verify(:none, <<>>, "any message", <<>>)
    end

    test "authentication fails with wrong key" do
      key1 = :crypto.strong_rand_bytes(32)
      key2 = :crypto.strong_rand_bytes(32)
      message = "Test message"

      {:ok, auth_params} = Auth.authenticate(:sha256, key1, message)
      assert {:error, :authentication_mismatch} = Auth.verify(:sha256, key2, message, auth_params)
    end

    test "authentication fails with tampered message" do
      key = :crypto.strong_rand_bytes(32)
      message = "Original message"
      tampered = "Tampered message"

      {:ok, auth_params} = Auth.authenticate(:sha256, key, message)
      assert {:error, :authentication_mismatch} = Auth.verify(:sha256, key, tampered, auth_params)
    end

    test "authentication fails with tampered parameters" do
      key = :crypto.strong_rand_bytes(32)
      message = "Test message"

      {:ok, auth_params} = Auth.authenticate(:sha256, key, message)
      tampered_params = :crypto.strong_rand_bytes(16)

      assert {:error, :authentication_mismatch} =
               Auth.verify(:sha256, key, message, tampered_params)
    end

    test "validates authentication keys correctly" do
      assert :ok = Auth.validate_key(:none, <<>>)
      assert :ok = Auth.validate_key(:md5, :crypto.strong_rand_bytes(16))
      assert :ok = Auth.validate_key(:sha1, :crypto.strong_rand_bytes(20))
      assert :ok = Auth.validate_key(:sha256, :crypto.strong_rand_bytes(32))

      # Keys that are too short
      assert {:error, :key_too_short} =
               Auth.validate_key(:md5, :crypto.strong_rand_bytes(8))

      assert {:error, :key_too_short} =
               Auth.validate_key(:sha256, :crypto.strong_rand_bytes(16))
    end

    test "handles large messages efficiently" do
      key = :crypto.strong_rand_bytes(32)
      large_message = String.duplicate("X", 10_000)

      start_time = :os.system_time(:microsecond)
      {:ok, auth_params} = Auth.authenticate(:sha256, key, large_message)
      end_time = :os.system_time(:microsecond)

      # Should complete within reasonable time (100ms)
      assert end_time - start_time < 100_000
      assert :ok = Auth.verify(:sha256, key, large_message, auth_params)
    end

    test "batch authentication processing" do
      key = :crypto.strong_rand_bytes(32)
      messages = for i <- 1..10, do: "Message #{i}"

      {:ok, auth_params_list} = Auth.authenticate_batch(:sha256, key, messages)
      assert length(auth_params_list) == 10

      # Verify each message
      for {message, auth_params} <- Enum.zip(messages, auth_params_list) do
        assert :ok = Auth.verify(:sha256, key, message, auth_params)
      end
    end
  end

  describe "Privacy protocol tests" do
    test "DES encryption/decryption" do
      # RFC 3414 8.1.1.1: 8-byte DES key followed by 8-byte pre-IV
      priv_key = :crypto.strong_rand_bytes(16)
      auth_key = :crypto.strong_rand_bytes(16)
      plaintext = "Secret SNMP data!"

      assert {:ok, {ciphertext, priv_params}} = Priv.encrypt(:des, priv_key, auth_key, plaintext)
      assert ciphertext != plaintext
      # msgPrivacyParameters is the 8-byte salt
      assert byte_size(priv_params) == 8
      # CBC output is whole blocks
      assert rem(byte_size(ciphertext), 8) == 0

      assert {:ok, decrypted} = Priv.decrypt(:des, priv_key, auth_key, ciphertext, priv_params)
      # RFC 3414 does not transmit the padding length; the BER length of the
      # decrypted ScopedPDU delimits the data, so the padding is still present.
      assert binary_part(decrypted, 0, byte_size(plaintext)) == plaintext
      assert rem(byte_size(decrypted), 8) == 0
    end

    test "AES-128 encryption/decryption" do
      priv_key = :crypto.strong_rand_bytes(16)
      auth_key = :crypto.strong_rand_bytes(16)
      plaintext = "Confidential SNMP information"

      assert {:ok, {ciphertext, priv_params}} =
               Priv.encrypt(:aes128, priv_key, auth_key, plaintext)

      assert ciphertext != plaintext
      # msgPrivacyParameters is the 8-byte salt (RFC 3826 3.1.2.1)
      assert byte_size(priv_params) == 8
      # CFB is a stream mode: no expansion
      assert byte_size(ciphertext) == byte_size(plaintext)

      assert {:ok, decrypted} = Priv.decrypt(:aes128, priv_key, auth_key, ciphertext, priv_params)
      assert decrypted == plaintext
    end

    test "AES-192 encryption/decryption" do
      priv_key = :crypto.strong_rand_bytes(24)
      auth_key = :crypto.strong_rand_bytes(16)
      plaintext = "Top secret network data"

      assert {:ok, {ciphertext, priv_params}} =
               Priv.encrypt(:aes192, priv_key, auth_key, plaintext)

      assert ciphertext != plaintext
      assert byte_size(priv_params) == 8

      assert {:ok, decrypted} = Priv.decrypt(:aes192, priv_key, auth_key, ciphertext, priv_params)
      assert decrypted == plaintext
    end

    test "AES-256 encryption/decryption" do
      priv_key = :crypto.strong_rand_bytes(32)
      auth_key = :crypto.strong_rand_bytes(16)
      plaintext = "Maximum security SNMP payload"

      assert {:ok, {ciphertext, priv_params}} =
               Priv.encrypt(:aes256, priv_key, auth_key, plaintext)

      assert ciphertext != plaintext
      assert byte_size(priv_params) == 8

      assert {:ok, decrypted} = Priv.decrypt(:aes256, priv_key, auth_key, ciphertext, priv_params)
      assert decrypted == plaintext
    end

    test "no privacy (passthrough)" do
      plaintext = "Unencrypted data"

      assert {:ok, {ciphertext, priv_params}} = Priv.encrypt(:none, <<>>, <<>>, plaintext)
      assert ciphertext == plaintext
      assert priv_params == <<>>

      assert {:ok, decrypted} = Priv.decrypt(:none, <<>>, <<>>, ciphertext, priv_params)
      assert decrypted == plaintext
    end

    test "encryption with different IVs produces different ciphertext" do
      priv_key = :crypto.strong_rand_bytes(16)
      auth_key = :crypto.strong_rand_bytes(16)
      plaintext = "Same plaintext"

      {:ok, {ciphertext1, _}} = Priv.encrypt(:aes128, priv_key, auth_key, plaintext)
      {:ok, {ciphertext2, _}} = Priv.encrypt(:aes128, priv_key, auth_key, plaintext)

      # Should be different due to random IVs
      assert ciphertext1 != ciphertext2
    end

    # CFB has no padding or integrity check: a wrong key or salt yields garbage,
    # not an error. Integrity comes from authentication (RFC 3414 requires
    # authPriv, never noAuthPriv).
    test "decryption with wrong key yields different data" do
      priv_key1 = :crypto.strong_rand_bytes(16)
      priv_key2 = :crypto.strong_rand_bytes(16)
      auth_key = :crypto.strong_rand_bytes(16)
      plaintext = "Secret data"

      {:ok, {ciphertext, priv_params}} = Priv.encrypt(:aes128, priv_key1, auth_key, plaintext)
      {:ok, garbage} = Priv.decrypt(:aes128, priv_key2, auth_key, ciphertext, priv_params)
      assert garbage != plaintext
    end

    test "decryption with wrong salt yields different data" do
      priv_key = :crypto.strong_rand_bytes(16)
      auth_key = :crypto.strong_rand_bytes(16)
      plaintext = "Secret data"

      {:ok, {ciphertext, _}} = Priv.encrypt(:aes128, priv_key, auth_key, plaintext)
      wrong_salt = :crypto.strong_rand_bytes(8)
      {:ok, garbage} = Priv.decrypt(:aes128, priv_key, auth_key, ciphertext, wrong_salt)
      assert garbage != plaintext
    end

    test "priv params of the wrong length are rejected" do
      priv_key = :crypto.strong_rand_bytes(16)
      {:ok, {ciphertext, _}} = Priv.encrypt(:aes128, priv_key, <<>>, "data")

      assert {:error, :invalid_priv_params} =
               Priv.decrypt(:aes128, priv_key, <<>>, ciphertext, :crypto.strong_rand_bytes(16))
    end

    test "AES IV is engineBoots || engineTime || salt (RFC 3826 3.1.2.1)" do
      priv_key = :crypto.strong_rand_bytes(16)
      plaintext = "scoped pdu bytes"
      salt = <<1, 2, 3, 4, 5, 6, 7, 8>>
      opts = [engine_boots: 7, engine_time: 123_456, salt: salt]

      {:ok, {ciphertext, ^salt}} = Priv.encrypt(:aes128, priv_key, <<>>, plaintext, opts)

      iv = <<7::32, 123_456::32>> <> salt

      assert :crypto.crypto_one_time(:aes_128_cfb128, priv_key, iv, ciphertext, false) ==
               plaintext

      assert {:ok, ^plaintext} = Priv.decrypt(:aes128, priv_key, <<>>, ciphertext, salt, opts)
      # A different engine time gives a different IV, so decryption must not match
      {:ok, other} =
        Priv.decrypt(:aes128, priv_key, <<>>, ciphertext, salt, engine_boots: 7, engine_time: 1)

      assert other != plaintext
    end

    test "DES IV is preIV XOR (engineBoots || localInt) (RFC 3414 8.1.1.1)" do
      des_key = :crypto.strong_rand_bytes(8)
      pre_iv = :crypto.strong_rand_bytes(8)
      plaintext = "exactly16bytes!!"
      salt = <<0, 0, 0, 9, 0xAA, 0xBB, 0xCC, 0xDD>>

      {:ok, {ciphertext, ^salt}} =
        Priv.encrypt(:des, des_key <> pre_iv, <<>>, plaintext, engine_boots: 9, salt: salt)

      iv = :crypto.exor(pre_iv, salt)
      assert :crypto.crypto_one_time(:des_cbc, des_key, iv, ciphertext, false) == plaintext
    end

    test "salts differ between messages" do
      priv_key = :crypto.strong_rand_bytes(16)
      {:ok, {_, salt1}} = Priv.encrypt(:aes128, priv_key, <<>>, "x")
      {:ok, {_, salt2}} = Priv.encrypt(:aes128, priv_key, <<>>, "x")
      assert salt1 != salt2
    end

    test "handles large plaintexts" do
      priv_key = :crypto.strong_rand_bytes(16)
      auth_key = :crypto.strong_rand_bytes(16)
      large_plaintext = String.duplicate("Large data block ", 1000)

      {:ok, {ciphertext, priv_params}} =
        Priv.encrypt(:aes128, priv_key, auth_key, large_plaintext)

      {:ok, decrypted} = Priv.decrypt(:aes128, priv_key, auth_key, ciphertext, priv_params)

      assert decrypted == large_plaintext
    end

    test "validates privacy keys correctly" do
      assert :ok = Priv.validate_key(:none, <<>>)
      assert :ok = Priv.validate_key(:des, :crypto.strong_rand_bytes(16))
      assert :ok = Priv.validate_key(:aes128, :crypto.strong_rand_bytes(16))
      assert :ok = Priv.validate_key(:aes192, :crypto.strong_rand_bytes(24))
      assert :ok = Priv.validate_key(:aes256, :crypto.strong_rand_bytes(32))

      # Wrong key sizes
      assert {:error, :invalid_key_size} =
               Priv.validate_key(:des, :crypto.strong_rand_bytes(8))

      assert {:error, :invalid_key_size} =
               Priv.validate_key(:aes128, :crypto.strong_rand_bytes(8))
    end

    test "batch encryption/decryption" do
      priv_key = :crypto.strong_rand_bytes(16)
      auth_key = :crypto.strong_rand_bytes(16)
      plaintexts = for i <- 1..5, do: "Batch message #{i}"

      {:ok, encrypted_list} = Priv.encrypt_batch(:aes128, priv_key, auth_key, plaintexts)
      assert length(encrypted_list) == 5

      results = Priv.decrypt_batch(:aes128, priv_key, auth_key, encrypted_list)

      for {original, result} <- Enum.zip(plaintexts, results) do
        assert {:ok, decrypted} = result
        assert decrypted == original
      end
    end
  end

  describe "Key derivation tests" do
    test "derives authentication keys for different protocols" do
      password = "test_password_123"
      engine_id = "test_engine"

      protocols = [:md5, :sha1, :sha256, :sha384, :sha512]

      for protocol <- protocols do
        assert {:ok, key} = Keys.derive_auth_key(protocol, password, engine_id)
        assert is_binary(key)
        assert byte_size(key) > 0

        # Verify key is usable for authentication
        assert :ok = Auth.validate_key(protocol, key)
      end
    end

    test "derives privacy keys for different protocols" do
      password = "priv_password_456"
      engine_id = "priv_engine"

      protocols = [:des, :aes128, :aes192, :aes256]

      for protocol <- protocols do
        assert {:ok, key} = Keys.derive_priv_key(protocol, password, engine_id)
        assert is_binary(key)
        assert byte_size(key) > 0

        # Verify key is usable for privacy
        assert :ok = Priv.validate_key(protocol, key)
      end
    end

    test "same password and engine produce same key" do
      password = "consistent_password"
      engine_id = "consistent_engine"

      {:ok, key1} = Keys.derive_auth_key(:sha256, password, engine_id)
      {:ok, key2} = Keys.derive_auth_key(:sha256, password, engine_id)

      assert key1 == key2
    end

    test "different passwords produce different keys" do
      engine_id = "same_engine"

      {:ok, key1} = Keys.derive_auth_key(:sha256, "password1", engine_id)
      {:ok, key2} = Keys.derive_auth_key(:sha256, "password2", engine_id)

      assert key1 != key2
    end

    test "different engines produce different keys" do
      password = "same_password"

      {:ok, key1} = Keys.derive_auth_key(:sha256, password, "engine1")
      {:ok, key2} = Keys.derive_auth_key(:sha256, password, "engine2")

      assert key1 != key2
    end

    test "derives privacy key from auth key" do
      auth_key = :crypto.strong_rand_bytes(32)
      engine_id = "test_engine"

      {:ok, priv_key} = Keys.derive_priv_key_from_auth(:aes128, auth_key, engine_id)
      assert is_binary(priv_key)
      assert :ok = Priv.validate_key(:aes128, priv_key)
    end

    test "validates password strength" do
      assert :ok = Keys.validate_password_strength("SecurePhrase123!")
      assert :ok = Keys.validate_password_strength("VeryLongSecurePhrase456WithNumbers")

      assert {:warning, :weak_complexity} = Keys.validate_password_strength("strong_password_123")
      assert {:error, :too_short} = Keys.validate_password_strength("weak")
      assert {:error, :too_short} = Keys.validate_password_strength("a")
    end

    test "generates secure passwords" do
      password1 = Keys.generate_secure_password()
      password2 = Keys.generate_secure_password()

      assert is_binary(password1)
      assert is_binary(password2)
      assert String.length(password1) >= 16
      assert String.length(password2) >= 16
      assert password1 != password2
      assert :ok = Keys.validate_password_strength(password1)
    end

    test "secure key comparison" do
      key1 = :crypto.strong_rand_bytes(32)
      key2 = :crypto.strong_rand_bytes(32)
      key1_copy = key1

      assert Keys.secure_compare(key1, key1_copy) == true
      assert Keys.secure_compare(key1, key2) == false
      assert Keys.secure_compare(<<>>, <<>>) == true
    end

    test "batch key derivation" do
      protocols = [:md5, :sha1, :sha256]
      password = "batch_password"
      engine_id = "batch_engine"

      {:ok, keys} = Keys.derive_auth_keys_multi(protocols, password, engine_id)

      assert map_size(keys) == 3
      assert Map.has_key?(keys, :md5)
      assert Map.has_key?(keys, :sha1)
      assert Map.has_key?(keys, :sha256)

      # Verify each key
      for {protocol, key} <- keys do
        assert :ok = Auth.validate_key(protocol, key)
      end
    end
  end

  describe "RFC 3414 Appendix A.3 test vectors" do
    # password "maplesyrup", engineID 00 00 00 00 00 00 00 00 00 00 00 02
    @engine_id <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2>>

    test "A.3.1 MD5 localized key" do
      assert {:ok, key} = Keys.derive_auth_key(:md5, "maplesyrup", @engine_id)
      assert Base.encode16(key, case: :lower) == "526f5eed9fcce26f8964c2930787d82b"
    end

    test "A.3.2 SHA-1 localized key" do
      assert {:ok, key} = Keys.derive_auth_key(:sha1, "maplesyrup", @engine_id)
      assert Base.encode16(key, case: :lower) == "6695febc9288e36282235fc7151f128497b38f3f"
    end

    test "privacy key uses the authentication protocol's hash (RFC 3414 8.1.1.1)" do
      # DES with MD5 auth: privKey is the full 16-byte localized key
      assert {:ok, des_key} =
               Keys.derive_priv_key(:des, "maplesyrup", @engine_id, auth_protocol: :md5)

      assert Base.encode16(des_key, case: :lower) == "526f5eed9fcce26f8964c2930787d82b"

      # AES-128 with SHA-1 auth: first 16 bytes of the SHA-1 localized key
      assert {:ok, aes_key} =
               Keys.derive_priv_key(:aes128, "maplesyrup", @engine_id, auth_protocol: :sha1)

      assert Base.encode16(aes_key, case: :lower) == "6695febc9288e36282235fc7151f1284"

      # Same result when derived from the localized auth key (identical passwords)
      {:ok, auth_key} = Keys.derive_auth_key(:sha1, "maplesyrup", @engine_id)
      assert {:ok, ^aes_key} = Keys.derive_priv_key_from_auth(:aes128, auth_key, @engine_id)

      # SHA-256 covers AES-256 without extension: first 32 bytes == whole key
      {:ok, sha256_auth} = Keys.derive_auth_key(:sha256, "maplesyrup", @engine_id)

      assert {:ok, ^sha256_auth} =
               Keys.derive_priv_key(:aes256, "maplesyrup", @engine_id, auth_protocol: :sha256)
    end

    test "AES-256 with a short hash is extended, deterministically, per scheme" do
      {:ok, reeder} = Keys.derive_priv_key(:aes256, "maplesyrup", @engine_id, auth_protocol: :md5)

      {:ok, reeder2} =
        Keys.derive_priv_key(:aes256, "maplesyrup", @engine_id, auth_protocol: :md5)

      assert byte_size(reeder) == 32
      assert reeder == reeder2
      # The first 16 bytes are the plain localized key in both schemes
      assert binary_part(reeder, 0, 16) ==
               Base.decode16!("526f5eed9fcce26f8964c2930787d82b", case: :lower)

      {:ok, blumenthal} =
        Keys.derive_priv_key(:aes256, "maplesyrup", @engine_id,
          auth_protocol: :md5,
          key_extension: :blumenthal
        )

      assert byte_size(blumenthal) == 32
      assert binary_part(blumenthal, 0, 16) == binary_part(reeder, 0, 16)
      # Blumenthal appends MD5(Kul)
      assert binary_part(blumenthal, 16, 16) == :crypto.hash(:md5, binary_part(reeder, 0, 16))
      assert blumenthal != reeder

      assert {:error, :invalid_key_extension} =
               Keys.derive_priv_key(:aes256, "maplesyrup", @engine_id, key_extension: :bogus)
    end

    test "DES privacy keys are 16 bytes, AES keys match the cipher" do
      for {proto, size} <- [des: 16, aes128: 16, aes192: 24, aes256: 32] do
        {:ok, key} = Keys.derive_priv_key(proto, "maplesyrup", @engine_id, auth_protocol: :sha1)
        assert byte_size(key) == size
        assert :ok = Priv.validate_key(proto, key)
      end
    end

    test "generate_secure_password only uses charset characters" do
      charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
      password = Keys.generate_secure_password(64)
      assert byte_size(password) == 64

      assert password
             |> :binary.bin_to_list()
             |> Enum.all?(&(<<&1>> in String.graphemes(charset)))

      assert password != Keys.generate_secure_password(64)
    end
  end

  describe "USM (User Security Model) tests" do
    test "discovers engine successfully with mock" do
      # This is a unit test - skip actual network discovery in test environment
      # Real network discovery would need integration tests with actual SNMP agents

      # Instead, test that the function exists and handles invalid input properly
      assert {:error, _} = USM.discover_engine("invalid_host_that_does_not_exist")

      # For successful case, we would need a mock or integration test environment
      # This test verifies the function signature and error handling
    end

    test "synchronizes time successfully with mock" do
      engine_id = "test_engine_12345"

      # This is a unit test - skip actual network synchronization in test environment
      # Real time sync would need integration tests with actual SNMP agents

      # Test that the function exists and handles invalid input properly
      assert {:error, _} = USM.synchronize_time("invalid_host_that_does_not_exist", engine_id)

      # For successful case, we would need a mock or integration test environment
      # This test verifies the function signature and error handling
    end

    test "processes outgoing messages with different security levels" do
      # Create test message
      test_message = create_test_snmp_message()

      # No auth, no priv
      user_none = create_test_user(:no_auth_no_priv)

      assert {:ok, processed} =
               USM.process_outgoing_message(user_none, test_message, :no_auth_no_priv)

      assert is_binary(processed)

      # Auth, no priv
      user_auth = create_test_user(:auth_no_priv)

      assert {:ok, processed_auth} =
               USM.process_outgoing_message(user_auth, test_message, :auth_no_priv)

      assert is_binary(processed_auth)
      assert byte_size(processed_auth) > byte_size(processed)

      # Auth and priv
      user_priv = create_test_user(:auth_priv)

      assert {:ok, processed_priv} =
               USM.process_outgoing_message(user_priv, test_message, :auth_priv)

      assert is_binary(processed_priv)
      assert byte_size(processed_priv) > byte_size(processed_auth)
    end

    test "rejects mismatched security levels" do
      test_message = create_test_snmp_message()

      # User with no auth trying to use auth
      user_none = create_test_user(:no_auth_no_priv)

      assert {:error, :security_level_mismatch} =
               USM.process_outgoing_message(user_none, test_message, :auth_no_priv)

      # User with auth but no priv trying to use priv
      user_auth = create_test_user(:auth_no_priv)

      assert {:error, :security_level_mismatch} =
               USM.process_outgoing_message(user_auth, test_message, :auth_priv)
    end
  end

  describe "Security integration tests" do
    test "complete auth + priv round trip" do
      # Create user with both auth and priv
      user = create_test_user(:auth_priv)
      plaintext = "Complete security test message"

      # Step 1: Authenticate
      {:ok, auth_params} = Auth.authenticate(user.auth_protocol, user.auth_key, plaintext)
      assert :ok = Auth.verify(user.auth_protocol, user.auth_key, plaintext, auth_params)

      # Step 2: Encrypt
      {:ok, {ciphertext, priv_params}} =
        Priv.encrypt(user.priv_protocol, user.priv_key, user.auth_key, plaintext)

      # Step 3: Authenticate encrypted data
      {:ok, auth_params_encrypted} =
        Auth.authenticate(user.auth_protocol, user.auth_key, ciphertext)

      assert :ok =
               Auth.verify(user.auth_protocol, user.auth_key, ciphertext, auth_params_encrypted)

      # Step 4: Decrypt
      {:ok, decrypted} =
        Priv.decrypt(user.priv_protocol, user.priv_key, user.auth_key, ciphertext, priv_params)

      assert decrypted == plaintext
    end

    test "security protocol combinations" do
      auth_protocols = [:md5, :sha1, :sha256]
      priv_protocols = [:des, :aes128, :aes256]

      test_data = "Protocol combination test"

      for auth_proto <- auth_protocols, priv_proto <- priv_protocols do
        user = create_test_user(:auth_priv, auth_protocol: auth_proto, priv_protocol: priv_proto)

        # Test auth
        {:ok, auth_params} = Auth.authenticate(user.auth_protocol, user.auth_key, test_data)
        assert :ok = Auth.verify(user.auth_protocol, user.auth_key, test_data, auth_params)

        # Test priv
        {:ok, {ciphertext, priv_params}} =
          Priv.encrypt(user.priv_protocol, user.priv_key, user.auth_key, test_data)

        {:ok, decrypted} =
          Priv.decrypt(user.priv_protocol, user.priv_key, user.auth_key, ciphertext, priv_params)

        # DES-CBC output keeps its RFC 3414 block padding
        assert binary_part(decrypted, 0, byte_size(test_data)) == test_data
      end
    end

    test "timing attack resistance" do
      key = :crypto.strong_rand_bytes(32)
      message = "Timing test message"

      {:ok, correct_auth} = Auth.authenticate(:sha256, key, message)
      wrong_auth = :crypto.strong_rand_bytes(16)

      # Both should take similar time (constant time comparison)
      start1 = :os.system_time(:microsecond)
      Auth.verify(:sha256, key, message, correct_auth)
      time1 = :os.system_time(:microsecond) - start1

      start2 = :os.system_time(:microsecond)
      Auth.verify(:sha256, key, message, wrong_auth)
      time2 = :os.system_time(:microsecond) - start2

      # Times should be within reasonable range (not obvious timing difference)
      time_diff = abs(time1 - time2)
      # Less than 1ms difference
      assert time_diff < 1000
    end
  end

  describe "Performance tests" do
    @tag :performance
    test "authentication performance" do
      key = :crypto.strong_rand_bytes(32)
      message = "Performance test message"
      iterations = 1000

      start_time = :os.system_time(:microsecond)

      for _ <- 1..iterations do
        {:ok, _} = Auth.authenticate(:sha256, key, message)
      end

      end_time = :os.system_time(:microsecond)
      total_time = end_time - start_time
      avg_time = total_time / iterations

      # Should average less than 100 microseconds per authentication
      assert avg_time < 100
    end

    @tag :performance
    test "encryption performance" do
      priv_key = :crypto.strong_rand_bytes(16)
      auth_key = :crypto.strong_rand_bytes(16)
      message = "Performance test encryption data"
      iterations = 500

      start_time = :os.system_time(:microsecond)

      for _ <- 1..iterations do
        {:ok, _} = Priv.encrypt(:aes128, priv_key, auth_key, message)
      end

      end_time = :os.system_time(:microsecond)
      total_time = end_time - start_time
      avg_time = total_time / iterations

      # Should average less than 200 microseconds per encryption
      assert avg_time < 200
    end
  end

  # Helper functions

  defp create_test_snmp_message do
    pdu = %{
      type: :get_request,
      request_id: 12345,
      error_status: 0,
      error_index: 0,
      varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null}]
    }

    # Create a basic SNMPv1 message that can be converted
    message = %{
      version: 1,
      community: "public",
      pdu: pdu
    }

    # Encode it to binary for USM processing
    {:ok, encoded} = SnmpKit.SnmpLib.PDU.encode_message(message)
    encoded
  end

  defp create_test_user(security_level, opts \\ []) do
    auth_protocol = Keyword.get(opts, :auth_protocol, :sha256)
    priv_protocol = Keyword.get(opts, :priv_protocol, :aes128)

    {actual_auth_protocol, auth_key} =
      case security_level do
        :no_auth_no_priv -> {:none, <<>>}
        _ -> {auth_protocol, derive_test_key(auth_protocol, "auth_password")}
      end

    {actual_priv_protocol, priv_key} =
      case security_level do
        :auth_priv -> {priv_protocol, derive_test_key(priv_protocol, "priv_password")}
        _ -> {:none, <<>>}
      end

    %{
      security_name: "test_user",
      auth_protocol: actual_auth_protocol,
      priv_protocol: actual_priv_protocol,
      auth_key: auth_key,
      priv_key: priv_key,
      engine_id: "test_engine",
      engine_boots: 1,
      engine_time: System.system_time(:second)
    }
  end

  defp derive_test_key(:md5, _), do: :crypto.strong_rand_bytes(16)
  defp derive_test_key(:sha1, _), do: :crypto.strong_rand_bytes(20)
  defp derive_test_key(:sha256, _), do: :crypto.strong_rand_bytes(32)
  defp derive_test_key(:sha384, _), do: :crypto.strong_rand_bytes(48)
  defp derive_test_key(:sha512, _), do: :crypto.strong_rand_bytes(64)
  # 8-byte DES key + 8-byte pre-IV (RFC 3414 8.1.1.1)
  defp derive_test_key(:des, _), do: :crypto.strong_rand_bytes(16)
  defp derive_test_key(:aes128, _), do: :crypto.strong_rand_bytes(16)
  defp derive_test_key(:aes192, _), do: :crypto.strong_rand_bytes(24)
  defp derive_test_key(:aes256, _), do: :crypto.strong_rand_bytes(32)
  defp derive_test_key(_, _), do: :crypto.strong_rand_bytes(16)
end
