defmodule SnmpLib.Security.Auth do
  @moduledoc """
  Authentication protocols for SNMPv3 User Security Model.
  
  Implements HMAC-based authentication protocols as specified in RFC 3414 and RFC 7860,
  providing message integrity and authentication for SNMPv3 communications.
  
  ## Supported Protocols
  
  - **HMAC-MD5** (RFC 3414) - 16-byte digest, legacy support
  - **HMAC-SHA-1** (RFC 3414) - 20-byte digest, legacy support  
  - **HMAC-SHA-224** (RFC 7860) - 28-byte digest
  - **HMAC-SHA-256** (RFC 7860) - 32-byte digest, recommended
  - **HMAC-SHA-384** (RFC 7860) - 48-byte digest
  - **HMAC-SHA-512** (RFC 7860) - 64-byte digest, highest security
  
  ## Security Considerations
  
  - MD5 and SHA-1 are deprecated for new implementations
  - SHA-256 or higher is recommended for production use
  - Authentication keys must be properly derived using key derivation functions
  - Truncated MACs maintain security properties when properly implemented
  
  ## Protocol Selection Guidelines
  
  - **SHA-256**: Recommended for most deployments (good security/performance balance)
  - **SHA-512**: High security environments with adequate processing power
  - **SHA-384**: Alternative to SHA-512 with smaller digest size
  - **MD5/SHA-1**: Legacy compatibility only, not recommended for new deployments
  
  ## Usage Examples
  
  ### Message Authentication
  
      # Authenticate outgoing message
      auth_key = derived_authentication_key
      message = snmp_message_data
      {:ok, auth_params} = SnmpLib.Security.Auth.authenticate(:sha256, auth_key, message)
      
      # Verify incoming message
      :ok = SnmpLib.Security.Auth.verify(:sha256, auth_key, message, auth_params)
      
  ### Protocol Capabilities
  
      # Get protocol information
      info = SnmpLib.Security.Auth.protocol_info(:sha256)
      # Returns: %{digest_size: 32, truncated_size: 12, secure: true, ...}
      
      # List all supported protocols
      protocols = SnmpLib.Security.Auth.supported_protocols()
  """
  
  require Logger
  
  @type auth_protocol :: :none | :md5 | :sha1 | :sha224 | :sha256 | :sha384 | :sha512
  @type auth_key :: binary()
  @type auth_params :: binary()
  @type message_data :: binary()
  
  # Protocol specifications per RFC 3414 and RFC 7860
  @protocol_specs %{
    none: %{
      algorithm: :none,
      digest_size: 0,
      truncated_size: 0,
      secure: false,
      rfc: "N/A"
    },
    md5: %{
      algorithm: :md5,
      digest_size: 16,
      truncated_size: 12,
      secure: false,  # Deprecated
      rfc: "RFC 3414"
    },
    sha1: %{
      algorithm: :sha,
      digest_size: 20,
      truncated_size: 12,
      secure: false,  # Deprecated
      rfc: "RFC 3414"
    },
    sha224: %{
      algorithm: :sha224,
      digest_size: 28,
      truncated_size: 16,
      secure: true,
      rfc: "RFC 7860"
    },
    sha256: %{
      algorithm: :sha256,
      digest_size: 32,
      truncated_size: 16,
      secure: true,
      rfc: "RFC 7860"
    },
    sha384: %{
      algorithm: :sha384,
      digest_size: 48,
      truncated_size: 24,
      secure: true,
      rfc: "RFC 7860"
    },
    sha512: %{
      algorithm: :sha512,
      digest_size: 64,
      truncated_size: 32,
      secure: true,
      rfc: "RFC 7860"
    }
  }
  
  ## Protocol Information
  
  @doc """
  Returns information about a specific authentication protocol.
  
  ## Examples
  
      iex> SnmpLib.Security.Auth.protocol_info(:sha256)
      %{algorithm: :sha256, digest_size: 32, truncated_size: 16, secure: true, rfc: "RFC 7860"}
      
      iex> SnmpLib.Security.Auth.protocol_info(:md5)
      %{algorithm: :md5, digest_size: 16, truncated_size: 12, secure: false, rfc: "RFC 3414"}
  """
  @spec protocol_info(auth_protocol()) :: map() | nil
  def protocol_info(protocol) do
    Map.get(@protocol_specs, protocol)
  end
  
  @doc """
  Returns list of all supported authentication protocols.
  
  ## Examples
  
      iex> SnmpLib.Security.Auth.supported_protocols()
      [:none, :md5, :sha1, :sha224, :sha256, :sha384, :sha512]
  """
  @spec supported_protocols() :: [auth_protocol()]
  def supported_protocols do
    Map.keys(@protocol_specs)
  end
  
  @doc """
  Returns list of cryptographically secure protocols (excludes deprecated ones).
  
  ## Examples
  
      iex> SnmpLib.Security.Auth.secure_protocols()
      [:sha224, :sha256, :sha384, :sha512]
  """
  @spec secure_protocols() :: [auth_protocol()]
  def secure_protocols do
    @protocol_specs
    |> Enum.filter(fn {_protocol, spec} -> spec.secure end)
    |> Enum.map(fn {protocol, _spec} -> protocol end)
  end
  
  @doc """
  Checks if a protocol is considered cryptographically secure.
  
  ## Examples
  
      iex> SnmpLib.Security.Auth.secure_protocol?(:sha256)
      true
      
      iex> SnmpLib.Security.Auth.secure_protocol?(:md5)
      false
  """
  @spec secure_protocol?(auth_protocol()) :: boolean()
  def secure_protocol?(protocol) do
    case protocol_info(protocol) do
      %{secure: secure} -> secure
      nil -> false
    end
  end
  
  ## Authentication Operations
  
  @doc """
  Authenticates a message using the specified protocol and key.
  
  Generates authentication parameters (truncated HMAC) for inclusion
  in the SNMPv3 message security parameters.
  
  ## Parameters
  
  - `protocol`: Authentication protocol to use
  - `auth_key`: Localized authentication key (derived from password)
  - `message`: Complete message data to authenticate
  
  ## Returns
  
  - `{:ok, auth_params}`: Authentication parameters for message
  - `{:error, reason}`: Authentication failed
  
  ## Examples
  
      # SHA-256 authentication (recommended)
      {:ok, auth_params} = SnmpLib.Security.Auth.authenticate(:sha256, auth_key, message)
      
      # Legacy MD5 authentication
      {:ok, auth_params} = SnmpLib.Security.Auth.authenticate(:md5, auth_key, message)
  """
  @spec authenticate(auth_protocol(), auth_key(), message_data()) :: 
    {:ok, auth_params()} | {:error, atom()}
  def authenticate(:none, _auth_key, _message) do
    {:ok, <<>>}
  end
  
  def authenticate(protocol, auth_key, message) when is_atom(protocol) do
    case protocol_info(protocol) do
      nil ->
        Logger.error("Unsupported authentication protocol: #{protocol}")
        {:error, :unsupported_protocol}
      
      _spec when byte_size(auth_key) == 0 ->
        Logger.error("Empty authentication key for protocol: #{protocol}")
        {:error, :empty_auth_key}
      
      spec ->
        try do
          # Generate HMAC digest
          full_digest = :crypto.mac(:hmac, spec.algorithm, auth_key, message)
          
          # Truncate to protocol-specified length
          auth_params = binary_part(full_digest, 0, spec.truncated_size)
          
          Logger.debug("Authentication successful with #{protocol}, digest size: #{byte_size(auth_params)}")
          {:ok, auth_params}
        rescue
          error ->
            Logger.error("Authentication failed for #{protocol}: #{inspect(error)}")
            {:error, :authentication_failed}
        end
    end
  end
  
  def authenticate(protocol, _auth_key, _message) do
    Logger.error("Invalid authentication protocol type: #{inspect(protocol)}")
    {:error, :invalid_protocol_type}
  end
  
  @doc """
  Verifies message authentication using provided authentication parameters.
  
  Recomputes the expected authentication parameters and compares them
  with the provided parameters using constant-time comparison.
  
  ## Parameters
  
  - `protocol`: Authentication protocol used
  - `auth_key`: Localized authentication key
  - `message`: Message data that was authenticated
  - `provided_params`: Authentication parameters from received message
  
  ## Returns
  
  - `:ok`: Authentication verification successful
  - `{:error, reason}`: Verification failed
  
  ## Examples
  
      # Verify SHA-256 authentication
      :ok = SnmpLib.Security.Auth.verify(:sha256, auth_key, message, auth_params)
      
      # Failed verification
      {:error, :authentication_mismatch} = SnmpLib.Security.Auth.verify(:md5, wrong_key, message, auth_params)
  """
  @spec verify(auth_protocol(), auth_key(), message_data(), auth_params()) ::
    :ok | {:error, atom()}
  def verify(:none, _auth_key, _message, _provided_params) do
    :ok
  end
  
  def verify(protocol, auth_key, message, provided_params) when is_atom(protocol) do
    case authenticate(protocol, auth_key, message) do
      {:ok, expected_params} ->
        if secure_compare(expected_params, provided_params) do
          Logger.debug("Authentication verification successful for #{protocol}")
          :ok
        else
          Logger.warning("Authentication mismatch for #{protocol}")
          {:error, :authentication_mismatch}
        end
      
      {:error, reason} ->
        Logger.error("Authentication verification failed for #{protocol}: #{reason}")
        {:error, reason}
    end
  end
  
  def verify(protocol, _auth_key, _message, _provided_params) do
    Logger.error("Invalid authentication protocol type: #{inspect(protocol)}")
    {:error, :invalid_protocol_type}
  end
  
  ## Key Validation
  
  @doc """
  Validates that an authentication key is appropriate for the specified protocol.
  
  Checks key length requirements and provides warnings for weak protocols.
  
  ## Examples
  
      :ok = SnmpLib.Security.Auth.validate_key(:sha256, auth_key)
      {:error, :key_too_short} = SnmpLib.Security.Auth.validate_key(:sha512, short_key)
  """
  @spec validate_key(auth_protocol(), auth_key()) :: :ok | {:error, atom()}
  def validate_key(:none, _key) do
    :ok
  end
  
  def validate_key(protocol, key) when is_atom(protocol) and is_binary(key) do
    case protocol_info(protocol) do
      nil ->
        {:error, :unsupported_protocol}
      
      spec ->
        key_length = byte_size(key)
        min_length = spec.digest_size
        
        cond do
          key_length == 0 ->
            {:error, :empty_key}
          
          key_length < min_length ->
            Logger.warning("Authentication key shorter than recommended for #{protocol}: #{key_length} < #{min_length}")
            {:error, :key_too_short}
          
          not spec.secure ->
            Logger.warning("Using deprecated authentication protocol: #{protocol}")
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
  Authenticates multiple messages using the same protocol and key.
  
  More efficient than individual authentication calls when processing
  multiple messages with the same authentication configuration.
  
  ## Examples
  
      messages = [msg1, msg2, msg3]
      {:ok, auth_params_list} = SnmpLib.Security.Auth.authenticate_batch(:sha256, auth_key, messages)
  """
  @spec authenticate_batch(auth_protocol(), auth_key(), [message_data()]) ::
    {:ok, [auth_params()]} | {:error, atom()}
  def authenticate_batch(protocol, auth_key, messages) when is_list(messages) do
    case protocol_info(protocol) do
      nil ->
        {:error, :unsupported_protocol}
      
      _spec ->
        try do
          auth_params_list = Enum.map(messages, fn message ->
            {:ok, params} = authenticate(protocol, auth_key, message)
            params
          end)
          {:ok, auth_params_list}
        rescue
          _error ->
            {:error, :batch_authentication_failed}
        end
    end
  end
  
  @doc """
  Verifies authentication for multiple messages in batch.
  
  ## Examples
  
      results = SnmpLib.Security.Auth.verify_batch(:sha256, auth_key, messages, auth_params_list)
      # Returns: [:ok, :ok, {:error, :authentication_mismatch}]
  """
  @spec verify_batch(auth_protocol(), auth_key(), [message_data()], [auth_params()]) ::
    [:ok | {:error, atom()}]
  def verify_batch(protocol, auth_key, messages, auth_params_list) 
      when is_list(messages) and is_list(auth_params_list) do
    
    if length(messages) != length(auth_params_list) do
      List.duplicate({:error, :parameter_length_mismatch}, length(messages))
    else
      Enum.zip(messages, auth_params_list)
      |> Enum.map(fn {message, auth_params} ->
        verify(protocol, auth_key, message, auth_params)
      end)
    end
  end
  
  ## Performance and Statistics
  
  @doc """
  Measures authentication performance for a given protocol.
  
  Useful for performance tuning and protocol selection in high-throughput environments.
  
  ## Examples
  
      stats = SnmpLib.Security.Auth.benchmark_protocol(:sha256, test_key, test_message, 1000)
      # Returns timing and throughput statistics
  """
  @spec benchmark_protocol(auth_protocol(), auth_key(), message_data(), pos_integer()) :: map()
  def benchmark_protocol(protocol, auth_key, test_message, iterations \\ 1000) do
    Logger.info("Benchmarking #{protocol} authentication with #{iterations} iterations")
    
    # Warm up
    authenticate(protocol, auth_key, test_message)
    
    # Time authentication operations
    {auth_time, _} = :timer.tc(fn ->
      Enum.each(1..iterations, fn _i ->
        authenticate(protocol, auth_key, test_message)
      end)
    end)
    
    # Time verification operations  
    {:ok, auth_params} = authenticate(protocol, auth_key, test_message)
    {verify_time, _} = :timer.tc(fn ->
      Enum.each(1..iterations, fn _i ->
        verify(protocol, auth_key, test_message, auth_params)
      end)
    end)
    
    %{
      protocol: protocol,
      iterations: iterations,
      auth_time_microseconds: auth_time,
      verify_time_microseconds: verify_time,
      auth_ops_per_second: round(iterations / (auth_time / 1_000_000)),
      verify_ops_per_second: round(iterations / (verify_time / 1_000_000)),
      avg_auth_microseconds: round(auth_time / iterations),
      avg_verify_microseconds: round(verify_time / iterations)
    }
  end
  
  ## Private Helper Functions
  
  # Constant-time comparison to prevent timing attacks
  defp secure_compare(a, b) when byte_size(a) != byte_size(b) do
    false
  end
  
  defp secure_compare(a, b) do
    :crypto.hash_equals(a, b)
  end
end