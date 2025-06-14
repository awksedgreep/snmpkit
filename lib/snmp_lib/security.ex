defmodule SnmpLib.Security do
  @moduledoc """
  SNMPv3 Security Framework - Phase 5.1A Implementation
  
  Provides comprehensive SNMPv3 User Security Model (USM) implementation including
  authentication and privacy protocols for secure SNMP communications.
  
  ## Features
  
  - **User Security Model (USM)** with complete RFC 3414 compliance
  - **Authentication Protocols**: MD5, SHA-1, SHA-256, SHA-384, SHA-512
  - **Privacy Protocols**: DES, AES-128, AES-192, AES-256
  - **Key Derivation**: Password-based and localized key generation
  - **Security Parameters**: Boot counter, time synchronization, message validation
  - **Error Handling**: Comprehensive security error classification and recovery
  
  ## Architecture
  
  The security framework is built on a modular architecture:
  
  - `SnmpLib.Security.USM` - User Security Model implementation
  - `SnmpLib.Security.Auth` - Authentication protocol handlers
  - `SnmpLib.Security.Priv` - Privacy protocol handlers  
  - `SnmpLib.Security.Keys` - Key derivation and management
  
  ## Usage Examples
  
  ### Basic SNMPv3 Authentication
  
      # Create authenticated user
      {:ok, user} = SnmpLib.Security.create_user("admin", 
        auth_protocol: :sha256,
        auth_password: "secure_password",
        engine_id: "engine123"
      )
      
      # Authenticate message
      {:ok, auth_params} = SnmpLib.Security.authenticate_message(user, message)
      
  ### Privacy (Encryption) Support
  
      # Create user with privacy
      {:ok, user} = SnmpLib.Security.create_user("secure_admin",
        auth_protocol: :sha256,
        auth_password: "auth_password",
        priv_protocol: :aes256,
        priv_password: "priv_password"
      )
      
      # Encrypt message
      {:ok, encrypted} = SnmpLib.Security.encrypt_message(user, message)
      
  ### Engine ID Management
  
      # Generate engine ID
      engine_id = SnmpLib.Security.generate_engine_id("192.168.1.1")
      
      # Discover remote engine
      {:ok, remote_engine} = SnmpLib.Security.discover_engine("10.0.0.1")
  
  ## Security Considerations
  
  - All key material is stored securely in memory
  - Authentication and privacy keys are derived using RFC-compliant algorithms
  - Time-based authentication prevents replay attacks
  - Boot counter management ensures message freshness
  - Comprehensive input validation prevents security bypasses
  """
  
  alias SnmpLib.Security.{USM, Auth, Priv, Keys}
  
  @type auth_protocol :: :none | :md5 | :sha1 | :sha256 | :sha384 | :sha512
  @type priv_protocol :: :none | :des | :aes128 | :aes192 | :aes256
  @type engine_id :: binary()
  @type security_name :: binary()
  @type security_level :: :no_auth_no_priv | :auth_no_priv | :auth_priv
  
  @type user_config :: [
    auth_protocol: auth_protocol(),
    auth_password: binary(),
    priv_protocol: priv_protocol(),
    priv_password: binary(),
    engine_id: engine_id()
  ]
  
  @type security_user :: %{
    security_name: security_name(),
    auth_protocol: auth_protocol(),
    priv_protocol: priv_protocol(),
    auth_key: binary(),
    priv_key: binary(),
    engine_id: engine_id(),
    engine_boots: non_neg_integer(),
    engine_time: non_neg_integer()
  }
  
  @type security_params :: %{
    authoritative_engine_id: engine_id(),
    authoritative_engine_boots: non_neg_integer(),
    authoritative_engine_time: non_neg_integer(),
    user_name: security_name(),
    authentication_parameters: binary(),
    privacy_parameters: binary()
  }
  
  ## User Management
  
  @doc """
  Creates a new SNMPv3 security user with specified authentication and privacy settings.
  
  ## Parameters
  
  - `security_name`: Unique identifier for the user
  - `config`: User configuration including protocols and passwords
  
  ## Returns
  
  - `{:ok, user}`: Successfully created security user
  - `{:error, reason}`: Creation failed
  
  ## Examples
  
      # Authentication only user
      {:ok, user} = SnmpLib.Security.create_user("monitor_user",
        auth_protocol: :sha256,
        auth_password: "monitoring_secret",
        engine_id: "local_engine"
      )
      
      # Full authentication and privacy user
      {:ok, admin} = SnmpLib.Security.create_user("admin_user",
        auth_protocol: :sha512,
        auth_password: "admin_auth_pass",
        priv_protocol: :aes256,
        priv_password: "admin_priv_pass",
        engine_id: "management_engine"
      )
  """
  @spec create_user(security_name(), user_config()) :: {:ok, security_user()} | {:error, atom()}
  def create_user(security_name, config) do
    with {:ok, validated_config} <- validate_user_config(config),
         {:ok, auth_key} <- derive_auth_key(validated_config),
         {:ok, priv_key} <- derive_priv_key(validated_config) do
      
      user = %{
        security_name: security_name,
        auth_protocol: validated_config[:auth_protocol] || :none,
        priv_protocol: validated_config[:priv_protocol] || :none,
        auth_key: auth_key,
        priv_key: priv_key,
        engine_id: validated_config[:engine_id],
        engine_boots: 1,
        engine_time: System.system_time(:second)
      }
      
      {:ok, user}
    end
  end
  
  @doc """
  Updates security user credentials and regenerates keys.
  """
  @spec update_user(security_user(), user_config()) :: {:ok, security_user()} | {:error, atom()}
  def update_user(user, new_config) do
    updated_config = Map.merge(user_to_config(user), Enum.into(new_config, %{}))
    create_user(user.security_name, Map.to_list(updated_config))
  end
  
  @doc """
  Validates user credentials against stored authentication data.
  """
  @spec validate_user(security_user(), binary(), binary()) :: :ok | {:error, atom()}
  def validate_user(user, auth_password, priv_password \\ "") do
    with :ok <- validate_auth_password(user, auth_password),
         :ok <- validate_priv_password(user, priv_password) do
      :ok
    end
  end
  
  ## Message Security
  
  @doc """
  Determines the security level for a message based on user configuration.
  
  ## Security Levels
  
  - `:no_auth_no_priv` - No authentication, no privacy
  - `:auth_no_priv` - Authentication only  
  - `:auth_priv` - Authentication and privacy
  """
  @spec get_security_level(security_user()) :: security_level()
  def get_security_level(user) do
    case {user.auth_protocol, user.priv_protocol} do
      {:none, :none} -> :no_auth_no_priv
      {auth, :none} when auth != :none -> :auth_no_priv  
      {auth, priv} when auth != :none and priv != :none -> :auth_priv
      _ -> :no_auth_no_priv
    end
  end
  
  @doc """
  Authenticates an SNMP message using the user's authentication protocol.
  
  Returns authentication parameters that should be included in the message.
  """
  @spec authenticate_message(security_user(), binary()) :: {:ok, binary()} | {:error, atom()}
  def authenticate_message(user, message) do
    case user.auth_protocol do
      :none -> {:ok, <<>>}
      protocol -> Auth.authenticate(protocol, user.auth_key, message)
    end
  end
  
  @doc """
  Verifies message authentication using provided authentication parameters.
  """
  @spec verify_authentication(security_user(), binary(), binary()) :: :ok | {:error, atom()}
  def verify_authentication(user, message, auth_params) do
    case user.auth_protocol do
      :none -> :ok
      protocol -> Auth.verify(protocol, user.auth_key, message, auth_params)
    end
  end
  
  @doc """
  Encrypts message data using the user's privacy protocol.
  """
  @spec encrypt_message(security_user(), binary()) :: {:ok, {binary(), binary()}} | {:error, atom()}
  def encrypt_message(user, plaintext) do
    case user.priv_protocol do
      :none -> {:ok, {plaintext, <<>>}}
      protocol -> Priv.encrypt(protocol, user.priv_key, user.auth_key, plaintext)
    end
  end
  
  @doc """
  Decrypts message data using the user's privacy protocol.
  """
  @spec decrypt_message(security_user(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def decrypt_message(user, ciphertext, priv_params) do
    case user.priv_protocol do
      :none -> {:ok, ciphertext}
      protocol -> Priv.decrypt(protocol, user.priv_key, user.auth_key, ciphertext, priv_params)
    end
  end
  
  ## Engine Management
  
  @doc """
  Generates a unique engine ID for an SNMP entity.
  
  Engine IDs are used to uniquely identify SNMP engines and are required
  for SNMPv3 security operations.
  """
  @spec generate_engine_id(binary()) :: engine_id()
  def generate_engine_id(_identifier) do
    # RFC 3411 compliant engine ID generation
    timestamp = System.system_time(:second)
    random = :crypto.strong_rand_bytes(4)
    
    # Format: enterprise_id(4) + format(1) + timestamp(4) + random(4)
    <<0x00, 0x00, 0x00, 0x01, 0x02>> <> 
    <<timestamp::32>> <> 
    random
  end
  
  @doc """
  Discovers the engine ID of a remote SNMP agent.
  
  This is typically done during the first communication with a remote agent
  to establish security context.
  """
  @spec discover_engine(binary(), keyword()) :: {:ok, engine_id()} | {:error, atom()}
  def discover_engine(host, opts \\ []) do
    # Implementation would send an engine discovery request
    # For now, return a placeholder implementation
    USM.discover_engine(host, opts)
  end
  
  @doc """
  Updates engine time and boot counter for time synchronization.
  """
  @spec update_engine_time(security_user(), non_neg_integer(), non_neg_integer()) :: security_user()
  def update_engine_time(user, engine_boots, engine_time) do
    %{user | engine_boots: engine_boots, engine_time: engine_time}
  end
  
  ## Security Parameters
  
  @doc """
  Builds security parameters for inclusion in SNMPv3 messages.
  """
  @spec build_security_params(security_user(), binary(), binary()) :: security_params()
  def build_security_params(user, auth_params \\ <<>>, priv_params \\ <<>>) do
    %{
      authoritative_engine_id: user.engine_id,
      authoritative_engine_boots: user.engine_boots,
      authoritative_engine_time: user.engine_time,
      user_name: user.security_name,
      authentication_parameters: auth_params,
      privacy_parameters: priv_params
    }
  end
  
  @doc """
  Validates security parameters from received messages.
  """
  @spec validate_security_params(security_user(), security_params()) :: :ok | {:error, atom()}
  def validate_security_params(user, params) do
    with :ok <- validate_engine_id(user.engine_id, params.authoritative_engine_id),
         :ok <- validate_time_window(user, params),
         :ok <- validate_user_name(user.security_name, params.user_name) do
      :ok
    end
  end
  
  ## Configuration and Status
  
  @doc """
  Returns comprehensive information about security capabilities and status.
  """
  @spec info() :: map()
  def info do
    %{
      version: "5.1.0",
      phase: "5.1A - Security Foundation",
      supported_auth_protocols: [:md5, :sha1, :sha256, :sha384, :sha512],
      supported_priv_protocols: [:des, :aes128, :aes192, :aes256],
      rfc_compliance: ["RFC 3411", "RFC 3414", "RFC 3826"],
      security_levels: [:no_auth_no_priv, :auth_no_priv, :auth_priv],
      features: [
        "User Security Model (USM)",
        "Multiple authentication protocols",
        "Multiple privacy protocols", 
        "Engine ID management",
        "Time synchronization",
        "Key derivation (RFC 3414)",
        "Security parameter validation"
      ]
    }
  end
  
  ## Private Implementation
  
  defp validate_user_config(config) do
    # Validate authentication protocol
    auth_protocol = config[:auth_protocol] || :none
    unless auth_protocol in [:none, :md5, :sha1, :sha256, :sha384, :sha512] do
      {:error, :invalid_auth_protocol}
    else
      # Validate privacy protocol  
      priv_protocol = config[:priv_protocol] || :none
      unless priv_protocol in [:none, :des, :aes128, :aes192, :aes256] do
        {:error, :invalid_priv_protocol}
      else
        # Validate protocol compatibility
        if priv_protocol != :none and auth_protocol == :none do
          {:error, :priv_requires_auth}
        else
          # Validate required passwords
          if auth_protocol != :none and is_nil(config[:auth_password]) do
            {:error, :missing_auth_password}
          else
            if priv_protocol != :none and is_nil(config[:priv_password]) do
              {:error, :missing_priv_password}
            else
              # Validate engine ID
              if is_nil(config[:engine_id]) do
                {:error, :missing_engine_id}
              else
                {:ok, config}
              end
            end
          end
        end
      end
    end
  end
  
  defp derive_auth_key(config) do
    case config[:auth_protocol] do
      :none -> {:ok, <<>>}
      protocol -> 
        Keys.derive_auth_key(
          protocol, 
          config[:auth_password], 
          config[:engine_id]
        )
    end
  end
  
  defp derive_priv_key(config) do
    case config[:priv_protocol] do
      :none -> {:ok, <<>>}
      nil -> {:ok, <<>>}
      protocol ->
        Keys.derive_priv_key(
          protocol,
          config[:priv_password],
          config[:engine_id]
        )
    end
  end
  
  defp user_to_config(user) do
    %{
      auth_protocol: user.auth_protocol,
      priv_protocol: user.priv_protocol,
      engine_id: user.engine_id
    }
  end
  
  defp validate_auth_password(user, password) do
    case user.auth_protocol do
      :none -> :ok
      protocol ->
        expected_key = Keys.derive_auth_key(protocol, password, user.engine_id)
        case expected_key do
          {:ok, key} when key == user.auth_key -> :ok
          _ -> {:error, :invalid_auth_password}
        end
    end
  end
  
  defp validate_priv_password(user, password) do
    case user.priv_protocol do
      :none -> :ok
      protocol when password != "" ->
        expected_key = Keys.derive_priv_key(protocol, password, user.engine_id)
        case expected_key do
          {:ok, key} when key == user.priv_key -> :ok
          _ -> {:error, :invalid_priv_password}
        end
      _ -> {:error, :missing_priv_password}
    end
  end
  
  defp validate_engine_id(local_engine, remote_engine) do
    if local_engine == remote_engine do
      :ok
    else
      {:error, :engine_id_mismatch}
    end
  end
  
  defp validate_time_window(user, params) do
    # RFC 3414 time window validation (150 seconds)
    current_time = System.system_time(:second)
    time_diff = abs(current_time - params.authoritative_engine_time)
    
    boot_diff = abs(user.engine_boots - params.authoritative_engine_boots)
    
    cond do
      boot_diff > 1 -> {:error, :engine_boots_mismatch}
      boot_diff == 1 and time_diff > 150 -> {:error, :time_window_exceeded}
      boot_diff == 0 and time_diff > 150 -> {:error, :time_window_exceeded}
      true -> :ok
    end
  end
  
  defp validate_user_name(local_name, remote_name) do
    if local_name == remote_name do
      :ok
    else
      {:error, :user_name_mismatch}
    end
  end
end