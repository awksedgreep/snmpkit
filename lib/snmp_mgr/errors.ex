defmodule SnmpMgr.Errors do
  @moduledoc """
  SNMP error handling and error code translation.
  
  Provides functions to handle both SNMPv1 and SNMPv2c error conditions
  and translate error codes to human-readable messages.
  """

  # SNMPv1 and SNMPv2c error codes
  @error_codes %{
    0 => :no_error,
    1 => :too_big,
    2 => :no_such_name,
    3 => :bad_value,
    4 => :read_only,
    5 => :gen_err,
    
    # SNMPv2c additional error codes
    6 => :no_access,
    7 => :wrong_type,
    8 => :wrong_length,
    9 => :wrong_encoding,
    10 => :wrong_value,
    11 => :no_creation,
    12 => :inconsistent_value,
    13 => :resource_unavailable,
    14 => :commit_failed,
    15 => :undo_failed,
    16 => :authorization_error,
    17 => :not_writable,
    18 => :inconsistent_name
  }

  @error_descriptions %{
    :no_error => "No error occurred",
    :too_big => "Response too big to fit in message",
    :no_such_name => "Variable name not found",
    :bad_value => "Invalid value for variable",
    :read_only => "Variable is read-only",
    :gen_err => "General error",
    
    # SNMPv2c additional errors
    :no_access => "Access denied",
    :wrong_type => "Wrong data type",
    :wrong_length => "Wrong data length",
    :wrong_encoding => "Wrong encoding",
    :wrong_value => "Wrong value",
    :no_creation => "Cannot create variable",
    :inconsistent_value => "Inconsistent value",
    :resource_unavailable => "Resource unavailable",
    :commit_failed => "Commit failed",
    :undo_failed => "Undo failed",
    :authorization_error => "Authorization failed",
    :not_writable => "Variable not writable",
    :inconsistent_name => "Inconsistent name"
  }

  @doc """
  Translates an SNMP error code to an atom.
  
  Uses SnmpLib.Error for validation and standardization of RFC-compliant error codes.

  ## Examples

      iex> SnmpMgr.Errors.code_to_atom(2)
      :no_such_name

      iex> SnmpMgr.Errors.code_to_atom(0)
      :no_error

      iex> SnmpMgr.Errors.code_to_atom(999)
      :unknown_error
  """
  def code_to_atom(error_code) when is_integer(error_code) do
    # Use SnmpLib.Error for validation and RFC compliance, fall back to our mapping
    case SnmpLib.Error.valid_error_status?(error_code) do
      true -> SnmpLib.Error.error_atom(error_code)
      false -> Map.get(@error_codes, error_code, :unknown_error)
    end
  end

  @doc """
  Translates an SNMP error atom to a human-readable description.

  ## Examples

      iex> SnmpMgr.Errors.description(:no_such_name)
      "Variable name not found"

      iex> SnmpMgr.Errors.description(:too_big)
      "Response too big to fit in message"

      iex> SnmpMgr.Errors.description(:unknown_error)
      "Unknown error"
  """
  def description(error_atom) when is_atom(error_atom) do
    Map.get(@error_descriptions, error_atom, "Unknown error")
  end

  @doc """
  Translates an error code directly to a description.

  ## Examples

      iex> SnmpMgr.Errors.code_to_description(2)
      "Variable name not found"

      iex> SnmpMgr.Errors.code_to_description(18)
      "Inconsistent name"
  """
  def code_to_description(error_code) when is_integer(error_code) do
    error_code
    |> code_to_atom()
    |> description()
  end

  @doc """
  Determines if an error is version-specific.

  ## Examples

      iex> SnmpMgr.Errors.is_v2c_error?(:no_access)
      true

      iex> SnmpMgr.Errors.is_v2c_error?(:no_such_name)
      false
  """
  def is_v2c_error?(error_atom) do
    v2c_errors = [
      :no_access, :wrong_type, :wrong_length, :wrong_encoding,
      :wrong_value, :no_creation, :inconsistent_value, :resource_unavailable,
      :commit_failed, :undo_failed, :authorization_error, :not_writable,
      :inconsistent_name
    ]
    
    error_atom in v2c_errors
  end

  @doc """
  Formats an SNMP error for display.

  ## Examples

      iex> SnmpMgr.Errors.format_error({:snmp_error, 2})
      "SNMP Error (2): Variable name not found"

      iex> SnmpMgr.Errors.format_error({:snmp_error, :no_such_name})
      "SNMP Error: Variable name not found"

      iex> SnmpMgr.Errors.format_error({:v2c_error, :no_access, oid: "1.2.3.4"})
      "SNMPv2c Error: Access denied (OID: 1.2.3.4)"
  """
  def format_error({:snmp_error, error_code}) when is_integer(error_code) do
    error_atom = code_to_atom(error_code)
    desc = description(error_atom)
    "SNMP Error (#{error_code}): #{desc}"
  end

  def format_error({:snmp_error, error_atom}) when is_atom(error_atom) do
    desc = description(error_atom)
    "SNMP Error: #{desc}"
  end

  def format_error({:v2c_error, error_atom}) when is_atom(error_atom) do
    desc = description(error_atom)
    "SNMPv2c Error: #{desc}"
  end

  def format_error({:v2c_error, error_atom, details}) when is_atom(error_atom) do
    desc = description(error_atom)
    detail_str = format_error_details(details)
    "SNMPv2c Error: #{desc}#{detail_str}"
  end

  def format_error({:network_error, reason}) do
    "Network Error: #{inspect(reason)}"
  end

  def format_error({:timeout, _}) do
    "Timeout Error: Request timed out"
  end

  def format_error({:encoding_error, reason}) do
    "Encoding Error: #{inspect(reason)}"
  end

  def format_error({:decoding_error, reason}) do
    "Decoding Error: #{inspect(reason)}"
  end

  def format_error(error) do
    "Unknown Error: #{inspect(error)}"
  end

  @doc """
  Checks if an error is recoverable (can be retried).

  ## Examples

      iex> SnmpMgr.Errors.recoverable?({:network_error, :host_unreachable})
      false

      iex> SnmpMgr.Errors.recoverable?({:snmp_error, :too_big})
      true

      iex> SnmpMgr.Errors.recoverable?(:timeout)
      true
  """
  def recoverable?({:network_error, :host_unreachable}), do: false
  def recoverable?({:network_error, :network_unreachable}), do: false
  def recoverable?({:snmp_error, :no_such_name}), do: false
  def recoverable?({:snmp_error, :bad_value}), do: false
  def recoverable?({:snmp_error, :read_only}), do: false
  def recoverable?({:v2c_error, :no_access}), do: false
  def recoverable?({:v2c_error, :not_writable}), do: false
  def recoverable?({:v2c_error, :wrong_type}), do: false
  def recoverable?(:timeout), do: true
  def recoverable?({:snmp_error, :too_big}), do: true
  def recoverable?({:snmp_error, :gen_err}), do: true
  def recoverable?(_), do: false

  @doc """
  Enhanced error analysis using SnmpLib.Error for SNMP protocol errors.
  
  Provides detailed error information including severity and RFC compliance
  for SNMP protocol errors while preserving our comprehensive network error handling.
  
  ## Examples
  
      iex> SnmpMgr.Errors.analyze_error({:snmp_error, 2})
      %{
        type: :snmp_protocol,
        atom: :no_such_name,
        code: 2,
        severity: :error,
        retriable: false,
        category: :user_error,
        description: "Variable name not found"
      }
      
      iex> SnmpMgr.Errors.analyze_error(:timeout)
      %{
        type: :network,
        atom: :timeout,
        retriable: true,
        category: :transient_error,
        description: "Operation timed out"
      }
  """
  def analyze_error(error) do
    case error do
      # SNMP protocol errors - use SnmpLib.Error for detailed analysis
      {:snmp_error, code} when is_integer(code) ->
        case SnmpLib.Error.valid_error_status?(code) do
          true ->
            atom = SnmpLib.Error.error_atom(code)
            %{
              type: :snmp_protocol,
              atom: atom,
              code: code,
              severity: SnmpLib.Error.error_severity(atom),
              retriable: SnmpLib.Error.retriable_error?(atom),
              rfc_compliant: true,
              category: classify_snmp_error(atom),
              description: description(atom)
            }
          false ->
            %{
              type: :snmp_protocol,
              atom: code_to_atom(code),
              code: code,
              retriable: false,
              rfc_compliant: false,
              category: :unknown_error,
              description: "Unknown SNMP error code"
            }
        end
      
      {:snmp_error, atom} when is_atom(atom) ->
        %{
          type: :snmp_protocol,
          atom: atom,
          code: SnmpLib.Error.error_code(atom),
          severity: SnmpLib.Error.error_severity(atom),
          retriable: SnmpLib.Error.retriable_error?(atom),
          rfc_compliant: true,
          category: classify_snmp_error(atom),
          description: description(atom)
        }
      
      # Network errors - our superior handling
      error_atom when error_atom in [:timeout, :host_unreachable, :network_unreachable, :connection_refused] ->
        %{
          type: :network,
          atom: error_atom,
          retriable: recoverable?(error_atom),
          category: classify_network_error(error_atom),
          description: get_network_error_description(error_atom)
        }
      
      # Other errors
      _ ->
        {category, subcategory} = classify_error(error)
        %{
          type: :other,
          atom: error,
          retriable: recoverable?(error),
          category: category,
          subcategory: subcategory,
          description: format_error(error)
        }
    end
  end
  
  defp classify_snmp_error(atom) do
    case atom do
      atom when atom in [:no_such_name, :bad_value, :wrong_type, :wrong_value] -> :user_error
      atom when atom in [:read_only, :not_writable, :no_access, :authorization_error] -> :security_error  
      atom when atom in [:too_big, :resource_unavailable] -> :resource_error
      atom when atom in [:gen_err, :commit_failed, :undo_failed] -> :device_error
      _ -> :protocol_error
    end
  end
  
  defp classify_network_error(atom) do
    case atom do
      :timeout -> :transient_error
      :host_unreachable -> :configuration_error
      :network_unreachable -> :configuration_error
      :connection_refused -> :service_error
    end
  end
  
  defp get_network_error_description(atom) do
    case atom do
      :timeout -> "Operation timed out"
      :host_unreachable -> "Host is unreachable"
      :network_unreachable -> "Network is unreachable"
      :connection_refused -> "Connection refused by target"
    end
  end

  # Private functions

  defp format_error_details(details) when is_list(details) do
    formatted = 
      details
      |> Enum.map(fn
        {:oid, oid} -> "OID: #{oid}"
        {:index, index} -> "Index: #{index}"
        {:value, value} -> "Value: #{inspect(value)}"
        {key, value} -> "#{key}: #{value}"
      end)
      |> Enum.join(", ")
    
    if formatted != "", do: " (#{formatted})", else: ""
  end

  defp format_error_details(_), do: ""

  @doc """
  Classifies an error into a category for better handling.
  
  ## Examples
  
      iex> SnmpMgr.Errors.classify_error({:snmp_error, :no_such_name}, "Get request")
      {:user_error, :invalid_oid}
      
      iex> SnmpMgr.Errors.classify_error({:network_error, :timeout}, "Network operation")
      {:transient_error, :network_timeout}
      
      iex> SnmpMgr.Errors.classify_error({:snmp_error, :too_big}, "Bulk request")
      {:recoverable_error, :response_too_large}
  """
  def classify_error(error, context \\ nil)
  
  def classify_error({:snmp_error, :no_such_name}, _context) do
    {:user_error, :invalid_oid}
  end
  
  def classify_error({:snmp_error, :bad_value}, _context) do
    {:user_error, :invalid_value}
  end
  
  def classify_error({:snmp_error, :read_only}, _context) do
    {:user_error, :write_to_readonly}
  end
  
  def classify_error({:snmp_error, :too_big}, _context) do
    {:recoverable_error, :response_too_large}
  end
  
  def classify_error({:snmp_error, :gen_err}, _context) do
    {:device_error, :general_failure}
  end
  
  def classify_error({:v2c_error, :no_access}, _context) do
    {:security_error, :access_denied}
  end
  
  def classify_error({:v2c_error, :authorization_error}, _context) do
    {:security_error, :authorization_failed}
  end
  
  def classify_error({:v2c_error, :wrong_type}, _context) do
    {:user_error, :type_mismatch}
  end
  
  def classify_error({:v2c_error, :resource_unavailable}, _context) do
    {:device_error, :resource_exhausted}
  end
  
  def classify_error({:network_error, :timeout}, _context) do
    {:transient_error, :network_timeout}
  end
  
  def classify_error({:network_error, :host_unreachable}, _context) do
    {:configuration_error, :unreachable_host}
  end
  
  def classify_error({:network_error, :network_unreachable}, _context) do
    {:configuration_error, :network_unavailable}
  end
  
  def classify_error({:encoding_error, _reason}, _context) do
    {:protocol_error, :message_encoding_failed}
  end
  
  def classify_error({:decoding_error, _reason}, _context) do
    {:protocol_error, :message_decoding_failed}
  end
  
  def classify_error(:timeout, _context) do
    {:transient_error, :operation_timeout}
  end
  
  def classify_error(:invalid_oid_values, _context) do
    :validation_error
  end

  def classify_error({:snmp_encoding_error, _reason}, _context) do
    :validation_error
  end

  def classify_error(:encoding_failed, _context) do
    :validation_error
  end

  def classify_error(:authentication_error, _context) do
    :authentication_error
  end

  def classify_error(:invalid_community, _context) do
    :invalid_community
  end

  def classify_error(:bad_community, _context) do
    :invalid_community
  end

  def classify_error(:snmp_modules_not_available, _context) do
    :system_error
  end

  def classify_error(error, _context) do
    {:unknown_error, error}
  end

  @doc """
  Formats an error message in a user-friendly way with context.
  
  ## Examples
  
      iex> SnmpMgr.Errors.format_user_friendly_error({:snmp_error, :no_such_name}, "Getting system description")
      "Unable to get system description: The requested OID does not exist on the device"
      
      iex> SnmpMgr.Errors.format_user_friendly_error({:network_error, :timeout}, "Contacting device")
      "Failed contacting device: The device did not respond within the timeout period"
  """
  def format_user_friendly_error(error, context \\ "Operation")
  
  def format_user_friendly_error({:snmp_error, :no_such_name}, context) do
    "#{context} failed: The requested OID does not exist on the device"
  end
  
  def format_user_friendly_error({:snmp_error, :bad_value}, context) do
    "#{context} failed: The provided value is invalid for this OID"
  end
  
  def format_user_friendly_error({:snmp_error, :read_only}, context) do
    "#{context} failed: This OID is read-only and cannot be modified"
  end
  
  def format_user_friendly_error({:snmp_error, :too_big}, context) do
    "#{context} failed: The response is too large. Try requesting fewer OIDs or use BULK operations"
  end
  
  def format_user_friendly_error({:snmp_error, :gen_err}, context) do
    "#{context} failed: The device reported a general error"
  end
  
  def format_user_friendly_error({:v2c_error, :no_access}, context) do
    "#{context} failed: Access denied. Check your community string and device configuration"
  end
  
  def format_user_friendly_error({:v2c_error, :authorization_error}, context) do
    "#{context} failed: Authorization failed. Verify your credentials"
  end
  
  def format_user_friendly_error({:v2c_error, :wrong_type}, context) do
    "#{context} failed: The value type does not match the expected type for this OID"
  end
  
  def format_user_friendly_error({:network_error, :timeout}, context) do
    "#{context} failed: The device did not respond within the timeout period"
  end
  
  def format_user_friendly_error({:network_error, :host_unreachable}, context) do
    "#{context} failed: Cannot reach the device. Check the IP address and network connectivity"
  end
  
  def format_user_friendly_error({:network_error, :network_unreachable}, context) do
    "#{context} failed: Network is unreachable. Check your network configuration"
  end
  
  def format_user_friendly_error(:timeout, context) do
    "#{context} timed out: The operation took too long to complete"
  end
  
  def format_user_friendly_error({:encoding_error, _reason}, context) do
    "#{context} failed: Unable to encode the SNMP message"
  end
  
  def format_user_friendly_error({:decoding_error, _reason}, context) do
    "#{context} failed: Unable to decode the SNMP response"
  end
  
  def format_user_friendly_error(error, context) do
    "#{context} failed: #{inspect(error)}"
  end

  @doc """
  Provides recovery suggestions for common errors.
  
  ## Examples
  
      iex> SnmpMgr.Errors.get_recovery_suggestions({:snmp_error, :no_such_name})
      ["Verify the OID is correct", "Check if the OID is supported by this device", "Try using MIB browser to explore available OIDs"]
      
      iex> SnmpMgr.Errors.get_recovery_suggestions({:network_error, :timeout})
      ["Increase timeout value", "Check network connectivity", "Verify device is responding to ping"]
  """
  def get_recovery_suggestions({:snmp_error, :no_such_name}) do
    [
      "Verify the OID is correct",
      "Check if the OID is supported by this device",
      "Try using MIB browser to explore available OIDs",
      "Ensure you're using the correct SNMP version"
    ]
  end
  
  def get_recovery_suggestions({:snmp_error, :bad_value}) do
    [
      "Check the value format and type",
      "Verify the value is within acceptable range",
      "Ensure the value matches the OID's expected data type",
      "Check device documentation for valid values"
    ]
  end
  
  def get_recovery_suggestions({:snmp_error, :read_only}) do
    [
      "This OID cannot be modified",
      "Use GET operation instead of SET",
      "Check device documentation for writable OIDs",
      "Verify you have the correct OID for writing"
    ]
  end
  
  def get_recovery_suggestions({:snmp_error, :too_big}) do
    [
      "Reduce the number of OIDs in the request",
      "Use GETBULK operation with smaller max-repetitions",
      "Split the request into multiple smaller requests",
      "Check device's maximum PDU size settings"
    ]
  end
  
  def get_recovery_suggestions({:v2c_error, :no_access}) do
    [
      "Verify the community string is correct",
      "Check device SNMP access configuration",
      "Ensure the device allows SNMP access from your IP",
      "Verify SNMP version compatibility (v1/v2c)"
    ]
  end
  
  def get_recovery_suggestions({:network_error, :timeout}) do
    [
      "Increase timeout value",
      "Check network connectivity to the device",
      "Verify device is responding to ping",
      "Check for network congestion or packet loss",
      "Ensure device SNMP service is running"
    ]
  end
  
  def get_recovery_suggestions({:network_error, :host_unreachable}) do
    [
      "Verify the IP address is correct",
      "Check network routing",
      "Ensure device is powered on and connected",
      "Test basic connectivity with ping",
      "Check firewall rules"
    ]
  end
  
  def get_recovery_suggestions({:encoding_error, _reason}) do
    [
      "Check OID format",
      "Verify value types are supported",
      "Ensure SNMP version compatibility",
      "Check for invalid characters in community string"
    ]
  end
  
  def get_recovery_suggestions({:decoding_error, _reason}) do
    [
      "Device may not support SNMP",
      "Check SNMP version compatibility",
      "Verify device is not sending corrupted responses",
      "Try different SNMP version (v1/v2c)"
    ]
  end
  
  def get_recovery_suggestions(:timeout) do
    [
      "Increase operation timeout",
      "Check if operation is too complex",
      "Verify device resources are available",
      "Try simpler operations first"
    ]
  end
  
  def get_recovery_suggestions(_error) do
    [
      "Check device documentation",
      "Verify SNMP configuration",
      "Try basic connectivity tests",
      "Contact device vendor support"
    ]
  end
end