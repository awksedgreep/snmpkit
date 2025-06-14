defmodule SnmpLib.Error do
  @moduledoc """
  Standard SNMP error handling and error code utilities.
  
  Provides standardized error codes, error handling utilities, and error response
  generation for SNMP operations. This module centralizes all SNMP-specific error
  handling to ensure consistent error reporting across the library.
  
  ## SNMP Error Codes
  
  Standard SNMP error status values as defined in RFC 1157 and RFC 3416:
  
  - `no_error` (0) - No error occurred
  - `too_big` (1) - Response message would be too large
  - `no_such_name` (2) - Requested OID does not exist
  - `bad_value` (3) - Invalid value for SET operation
  - `read_only` (4) - Attempted to set read-only variable
  - `gen_err` (5) - General error
  
  ## Usage Examples
  
  ### Basic Error Handling
  
      # Check if an error is retriable
      if SnmpLib.Error.retriable_error?(error_code) do
        retry_operation()
      end
      
      # Format error for logging
      error_msg = SnmpLib.Error.format_error(3, 2, varbinds)
      Logger.error(error_msg)
      
  ### Error Response Generation
  
      # Create error response for invalid request
      {:ok, error_response} = SnmpLib.Error.create_error_response(
        request_pdu, 
        :no_such_name, 
        error_index
      )
  """
  
  @type error_status :: 
    :no_error | :too_big | :no_such_name | :bad_value | :read_only | :gen_err |
    non_neg_integer()
    
  @type error_index :: non_neg_integer()
  @type varbind :: {list(), any()}
  @type varbinds :: [varbind()]
  
  # Standard SNMP error status codes (RFC 1157, RFC 3416)
  @no_error 0
  @too_big 1  
  @no_such_name 2
  @bad_value 3
  @read_only 4
  @gen_err 5
  
  # Additional SNMPv2c error codes
  @no_access 6
  @wrong_type 7
  @wrong_length 8
  @wrong_encoding 9
  @wrong_value 10
  @no_creation 11
  @inconsistent_value 12
  @resource_unavailable 13
  @commit_failed 14
  @undo_failed 15
  @authorization_error 16
  @not_writable 17
  @inconsistent_name 18
  
  ## Standard Error Codes
  
  @doc """
  Returns the numeric code for 'no error' status.
  
  ## Examples
  
      iex> SnmpLib.Error.no_error()
      0
  """
  @spec no_error() :: 0
  def no_error(), do: @no_error
  
  @doc """
  Returns the numeric code for 'too big' error status.
  
  The response message would be too large to fit in a single SNMP message.
  
  ## Examples
  
      iex> SnmpLib.Error.too_big()
      1
  """
  @spec too_big() :: 1
  def too_big(), do: @too_big
  
  @doc """
  Returns the numeric code for 'no such name' error status.
  
  The requested OID does not exist on the agent.
  
  ## Examples
  
      iex> SnmpLib.Error.no_such_name()
      2
  """
  @spec no_such_name() :: 2
  def no_such_name(), do: @no_such_name
  
  @doc """
  Returns the numeric code for 'bad value' error status.
  
  The value provided in a SET operation is invalid for the variable.
  
  ## Examples
  
      iex> SnmpLib.Error.bad_value()
      3
  """
  @spec bad_value() :: 3
  def bad_value(), do: @bad_value
  
  @doc """
  Returns the numeric code for 'read only' error status.
  
  Attempted to set a read-only variable.
  
  ## Examples
  
      iex> SnmpLib.Error.read_only()
      4
  """
  @spec read_only() :: 4
  def read_only(), do: @read_only
  
  @doc """
  Returns the numeric code for 'general error' status.
  
  A general error occurred that doesn't fit other categories.
  
  ## Examples
  
      iex> SnmpLib.Error.gen_err()
      5
  """
  @spec gen_err() :: 5
  def gen_err(), do: @gen_err
  
  ## Error Utilities
  
  @doc """
  Returns the human-readable name for an error status code.
  
  ## Parameters
  
  - `code`: Numeric error status code or atom
  
  ## Returns
  
  - String name of the error status
  - "unknown_error" for unrecognized codes
  
  ## Examples
  
      iex> SnmpLib.Error.error_name(0)
      "no_error"
      
      iex> SnmpLib.Error.error_name(:too_big)
      "too_big"
      
      iex> SnmpLib.Error.error_name(999)
      "unknown_error"
  """
  @spec error_name(error_status()) :: String.t()
  def error_name(0), do: "no_error"
  def error_name(:no_error), do: "no_error"
  
  def error_name(1), do: "too_big"  
  def error_name(:too_big), do: "too_big"
  
  def error_name(2), do: "no_such_name"
  def error_name(:no_such_name), do: "no_such_name"
  
  def error_name(3), do: "bad_value"
  def error_name(:bad_value), do: "bad_value"
  
  def error_name(4), do: "read_only"
  def error_name(:read_only), do: "read_only"
  
  def error_name(5), do: "gen_err"
  def error_name(:gen_err), do: "gen_err"
  
  # SNMPv2c additional error codes
  def error_name(6), do: "no_access"
  def error_name(:no_access), do: "no_access"
  def error_name(7), do: "wrong_type"
  def error_name(:wrong_type), do: "wrong_type"
  def error_name(8), do: "wrong_length"
  def error_name(:wrong_length), do: "wrong_length"
  def error_name(9), do: "wrong_encoding"
  def error_name(:wrong_encoding), do: "wrong_encoding"
  def error_name(10), do: "wrong_value"
  def error_name(:wrong_value), do: "wrong_value"
  def error_name(11), do: "no_creation"
  def error_name(:no_creation), do: "no_creation"
  def error_name(12), do: "inconsistent_value"
  def error_name(:inconsistent_value), do: "inconsistent_value"
  def error_name(13), do: "resource_unavailable"
  def error_name(:resource_unavailable), do: "resource_unavailable"
  def error_name(14), do: "commit_failed"
  def error_name(:commit_failed), do: "commit_failed"
  def error_name(15), do: "undo_failed"
  def error_name(:undo_failed), do: "undo_failed"
  def error_name(16), do: "authorization_error"
  def error_name(:authorization_error), do: "authorization_error"
  def error_name(17), do: "not_writable"
  def error_name(:not_writable), do: "not_writable"
  def error_name(18), do: "inconsistent_name"
  def error_name(:inconsistent_name), do: "inconsistent_name"
  
  def error_name(_), do: "unknown_error"
  
  @doc """
  Converts error status code to atom representation.
  
  ## Examples
  
      iex> SnmpLib.Error.error_atom(2)
      :no_such_name
      
      iex> SnmpLib.Error.error_atom(999)
      :unknown_error
  """
  @spec error_atom(error_status()) :: atom()
  def error_atom(code) when is_integer(code) do
    code |> error_name() |> String.to_atom()
  end
  def error_atom(atom) when is_atom(atom), do: atom
  
  @doc """
  Converts error atom or name to numeric code.
  
  ## Examples
  
      iex> SnmpLib.Error.error_code(:no_such_name)
      2
      
      iex> SnmpLib.Error.error_code("bad_value")
      3
  """
  @spec error_code(atom() | String.t()) :: non_neg_integer()
  def error_code(:no_error), do: @no_error
  def error_code(:too_big), do: @too_big
  def error_code(:no_such_name), do: @no_such_name
  def error_code(:bad_value), do: @bad_value
  def error_code(:read_only), do: @read_only
  def error_code(:gen_err), do: @gen_err
  def error_code(:no_access), do: @no_access
  def error_code(:wrong_type), do: @wrong_type
  def error_code(:wrong_length), do: @wrong_length
  def error_code(:wrong_encoding), do: @wrong_encoding
  def error_code(:wrong_value), do: @wrong_value
  def error_code(:no_creation), do: @no_creation
  def error_code(:inconsistent_value), do: @inconsistent_value
  def error_code(:resource_unavailable), do: @resource_unavailable
  def error_code(:commit_failed), do: @commit_failed
  def error_code(:undo_failed), do: @undo_failed
  def error_code(:authorization_error), do: @authorization_error
  def error_code(:not_writable), do: @not_writable
  def error_code(:inconsistent_name), do: @inconsistent_name
  def error_code(name) when is_binary(name) do
    name |> String.to_atom() |> error_code()
  end
  def error_code(_), do: @gen_err
  
  @doc """
  Formats an SNMP error for human-readable display.
  
  ## Parameters
  
  - `error_status`: Error status code (integer or atom)
  - `error_index`: Index of the varbind that caused the error (1-based)
  - `varbinds`: List of varbinds from the request (optional)
  
  ## Returns
  
  Formatted error string suitable for logging or display.
  
  ## Examples
  
      iex> SnmpLib.Error.format_error(2, 1, [])
      "SNMP Error: no_such_name (2) at index 1"
      
      iex> varbinds = [{[1,3,6,1,2,1,1,1,0], "test"}]
      iex> SnmpLib.Error.format_error(:bad_value, 1, varbinds)
      "SNMP Error: bad_value (3) at index 1 - OID: 1.3.6.1.2.1.1.1.0"
  """
  @spec format_error(error_status(), error_index(), varbinds()) :: String.t()
  def format_error(error_status, error_index, varbinds \\ []) do
    error_name_str = error_name(error_status)
    error_code_num = if is_integer(error_status), do: error_status, else: error_code(error_status)
    
    base_msg = "SNMP Error: #{error_name_str} (#{error_code_num}) at index #{error_index}"
    
    case get_error_varbind(varbinds, error_index) do
      nil -> base_msg
      {oid, _value} -> 
        oid_str = oid |> Enum.join(".")
        "#{base_msg} - OID: #{oid_str}"
    end
  end
  
  @doc """
  Determines if an error status indicates a retriable condition.
  
  Some SNMP errors are temporary and operations can be retried, while others
  indicate permanent failures.
  
  ## Retriable Errors
  - `too_big` - Can retry with smaller request
  - `gen_err` - General error, may be temporary
  - `resource_unavailable` - Temporary resource constraint
  
  ## Non-Retriable Errors  
  - `no_such_name` - OID doesn't exist
  - `bad_value` - Invalid value provided
  - `read_only` - Attempted to write read-only variable
  - `no_access` - Access denied
  - Most SNMPv2c specific errors
  
  ## Examples
  
      iex> SnmpLib.Error.retriable_error?(:too_big)
      true
      
      iex> SnmpLib.Error.retriable_error?(:no_such_name)
      false
  """
  @spec retriable_error?(error_status()) :: boolean()
  def retriable_error?(error_status) do
    case error_atom(error_status) do
      :no_error -> false
      :too_big -> true
      :no_such_name -> false
      :bad_value -> false
      :read_only -> false
      :gen_err -> true
      :no_access -> false
      :wrong_type -> false
      :wrong_length -> false
      :wrong_encoding -> false
      :wrong_value -> false
      :no_creation -> false
      :inconsistent_value -> false
      :resource_unavailable -> true
      :commit_failed -> false
      :undo_failed -> false
      :authorization_error -> false
      :not_writable -> false
      :inconsistent_name -> false
      _ -> false
    end
  end
  
  @doc """
  Creates an SNMP error response PDU.
  
  Generates a properly formatted error response based on the original request
  and the error condition that occurred.
  
  ## Parameters
  
  - `request_pdu`: Original request PDU
  - `error_status`: Error status code or atom
  - `error_index`: Index of the varbind that caused the error (1-based)
  
  ## Returns
  
  - `{:ok, error_pdu}`: Successfully created error response
  - `{:error, reason}`: Failed to create error response
  
  ## Examples
  
      request = %{type: :get_request, request_id: 123, varbinds: [...]}
      {:ok, error_response} = SnmpLib.Error.create_error_response(
        request, 
        :no_such_name, 
        1
      )
  """
  @spec create_error_response(map(), error_status(), error_index()) ::
    {:ok, map()} | {:error, atom()}
  def create_error_response(request_pdu, error_status, error_index) do
    case validate_request_pdu(request_pdu) do
      :ok ->
        error_code_num = if is_integer(error_status), do: error_status, else: error_code(error_status)
        
        error_response = %{
          type: :get_response,
          request_id: Map.get(request_pdu, :request_id, 0),
          error_status: error_code_num,
          error_index: error_index,
          varbinds: Map.get(request_pdu, :varbinds, [])
        }
        
        {:ok, error_response}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Validates an error status code.
  
  ## Examples
  
      iex> SnmpLib.Error.valid_error_status?(2)
      true
      
      iex> SnmpLib.Error.valid_error_status?(:no_such_name)
      true
      
      iex> SnmpLib.Error.valid_error_status?(999)
      false
  """
  @spec valid_error_status?(any()) :: boolean()
  def valid_error_status?(status) when is_integer(status) do
    status >= 0 and status <= 18
  end
  def valid_error_status?(status) when is_atom(status) do
    error_name(status) != "unknown_error"
  end
  def valid_error_status?(_), do: false
  
  @doc """
  Returns a list of all standard SNMP error codes.
  
  ## Examples
  
      iex> codes = SnmpLib.Error.all_error_codes()
      iex> 0 in codes
      true
      iex> 5 in codes  
      true
  """
  @spec all_error_codes() :: [non_neg_integer()]
  def all_error_codes do
    0..18 |> Enum.to_list()
  end
  
  @doc """
  Returns a list of all standard SNMP error atoms.
  
  ## Examples
  
      iex> atoms = SnmpLib.Error.all_error_atoms()
      iex> :no_error in atoms
      true
      iex> :gen_err in atoms
      true
  """
  @spec all_error_atoms() :: [atom()]
  def all_error_atoms do
    [
      :no_error, :too_big, :no_such_name, :bad_value, :read_only, :gen_err,
      :no_access, :wrong_type, :wrong_length, :wrong_encoding, :wrong_value,
      :no_creation, :inconsistent_value, :resource_unavailable, :commit_failed,
      :undo_failed, :authorization_error, :not_writable, :inconsistent_name
    ]
  end
  
  @doc """
  Categorizes error by severity level.
  
  ## Returns
  
  - `:info` - No error
  - `:warning` - Retriable errors  
  - `:error` - Non-retriable errors
  
  ## Examples
  
      iex> SnmpLib.Error.error_severity(:no_error)
      :info
      
      iex> SnmpLib.Error.error_severity(:too_big)
      :warning
      
      iex> SnmpLib.Error.error_severity(:no_such_name)
      :error
  """
  @spec error_severity(error_status()) :: :info | :warning | :error
  def error_severity(error_status) do
    case error_atom(error_status) do
      :no_error -> :info
      status when status in [:too_big, :gen_err, :resource_unavailable] -> :warning
      _ -> :error
    end
  end
  
  ## Private Helper Functions
  
  defp validate_request_pdu(request_pdu) when is_map(request_pdu) do
    :ok
  end
  defp validate_request_pdu(_), do: {:error, :invalid_request_pdu}
  
  defp get_error_varbind(varbinds, error_index) when is_list(varbinds) do
    # SNMP error_index is 1-based
    if error_index > 0 and error_index <= length(varbinds) do
      Enum.at(varbinds, error_index - 1)
    else
      nil
    end
  end
  defp get_error_varbind(_, _), do: nil
end