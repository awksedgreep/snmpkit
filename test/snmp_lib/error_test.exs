defmodule SnmpKit.SnmpLib.ErrorTest do
  use ExUnit.Case, async: true
  doctest SnmpKit.SnmpLib.Error

  alias SnmpKit.SnmpLib.Error

  describe "Error.no_error/0" do
    test "returns correct error code" do
      assert Error.no_error() == 0
    end
  end

  describe "Error.too_big/0" do
    test "returns correct error code" do
      assert Error.too_big() == 1
    end
  end

  describe "Error.no_such_name/0" do
    test "returns correct error code" do
      assert Error.no_such_name() == 2
    end
  end

  describe "Error.bad_value/0" do
    test "returns correct error code" do
      assert Error.bad_value() == 3
    end
  end

  describe "Error.read_only/0" do
    test "returns correct error code" do
      assert Error.read_only() == 4
    end
  end

  describe "Error.gen_err/0" do
    test "returns correct error code" do
      assert Error.gen_err() == 5
    end
  end

  describe "Error.error_name/1" do
    test "returns correct names for numeric codes" do
      assert Error.error_name(0) == "no_error"
      assert Error.error_name(1) == "too_big"
      assert Error.error_name(2) == "no_such_name"
      assert Error.error_name(3) == "bad_value"
      assert Error.error_name(4) == "read_only"
      assert Error.error_name(5) == "gen_err"
    end

    test "returns correct names for atom codes" do
      assert Error.error_name(:no_error) == "no_error"
      assert Error.error_name(:too_big) == "too_big"
      assert Error.error_name(:no_such_name) == "no_such_name"
      assert Error.error_name(:bad_value) == "bad_value"
      assert Error.error_name(:read_only) == "read_only"
      assert Error.error_name(:gen_err) == "gen_err"
    end

    test "returns correct names for SNMPv2c codes" do
      assert Error.error_name(6) == "no_access"
      assert Error.error_name(7) == "wrong_type"
      assert Error.error_name(8) == "wrong_length"
      assert Error.error_name(18) == "inconsistent_name"
    end

    test "returns unknown_error for invalid codes" do
      assert Error.error_name(999) == "unknown_error"
      assert Error.error_name(-1) == "unknown_error"
      assert Error.error_name(:invalid) == "unknown_error"
    end
  end

  describe "Error.error_atom/1" do
    test "converts numeric codes to atoms" do
      assert Error.error_atom(0) == :no_error
      assert Error.error_atom(2) == :no_such_name
      assert Error.error_atom(5) == :gen_err
    end

    test "returns atom as-is" do
      assert Error.error_atom(:too_big) == :too_big
      assert Error.error_atom(:bad_value) == :bad_value
    end

    test "converts unknown codes to unknown_error atom" do
      assert Error.error_atom(999) == :unknown_error
    end
  end

  describe "Error.error_code/1" do
    test "converts atoms to numeric codes" do
      assert Error.error_code(:no_error) == 0
      assert Error.error_code(:too_big) == 1
      assert Error.error_code(:no_such_name) == 2
      assert Error.error_code(:bad_value) == 3
      assert Error.error_code(:read_only) == 4
      assert Error.error_code(:gen_err) == 5
    end

    test "converts strings to numeric codes" do
      assert Error.error_code("no_error") == 0
      assert Error.error_code("too_big") == 1
      assert Error.error_code("no_such_name") == 2
    end

    test "converts SNMPv2c atoms to codes" do
      assert Error.error_code(:no_access) == 6
      assert Error.error_code(:wrong_type) == 7
      assert Error.error_code(:inconsistent_name) == 18
    end

    test "returns gen_err for unknown values" do
      assert Error.error_code(:unknown) == 5
      assert Error.error_code("invalid") == 5
    end
  end

  describe "Error.format_error/3" do
    test "formats basic error without varbinds" do
      result = Error.format_error(2, 1, [])
      assert result == "SNMP Error: no_such_name (2) at index 1"
    end

    test "formats error with atom status" do
      result = Error.format_error(:bad_value, 2, [])
      assert result == "SNMP Error: bad_value (3) at index 2"
    end

    test "formats error with varbind information" do
      varbinds = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], "test"},
        {[1, 3, 6, 1, 2, 1, 1, 2, 0], "value"}
      ]

      result = Error.format_error(:no_such_name, 1, varbinds)
      assert result == "SNMP Error: no_such_name (2) at index 1 - OID: 1.3.6.1.2.1.1.1.0"

      result2 = Error.format_error(:bad_value, 2, varbinds)
      assert result2 == "SNMP Error: bad_value (3) at index 2 - OID: 1.3.6.1.2.1.1.2.0"
    end

    test "handles invalid error index gracefully" do
      varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], "test"}]

      result = Error.format_error(:no_such_name, 5, varbinds)
      assert result == "SNMP Error: no_such_name (2) at index 5"
    end

    test "handles zero error index" do
      varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], "test"}]

      result = Error.format_error(:gen_err, 0, varbinds)
      assert result == "SNMP Error: gen_err (5) at index 0"
    end
  end

  describe "Error.retriable_error?/1" do
    test "identifies retriable errors" do
      assert Error.retriable_error?(:too_big) == true
      assert Error.retriable_error?(:gen_err) == true
      assert Error.retriable_error?(:resource_unavailable) == true
      assert Error.retriable_error?(1) == true
      assert Error.retriable_error?(5) == true
    end

    test "identifies non-retriable errors" do
      assert Error.retriable_error?(:no_error) == false
      assert Error.retriable_error?(:no_such_name) == false
      assert Error.retriable_error?(:bad_value) == false
      assert Error.retriable_error?(:read_only) == false
      assert Error.retriable_error?(:no_access) == false
      assert Error.retriable_error?(:authorization_error) == false
      assert Error.retriable_error?(0) == false
      assert Error.retriable_error?(2) == false
    end

    test "handles unknown errors as non-retriable" do
      assert Error.retriable_error?(999) == false
      assert Error.retriable_error?(:unknown) == false
    end
  end

  describe "Error.create_error_response/3" do
    test "creates error response from request PDU" do
      request_pdu = %{
        type: :get_request,
        request_id: 12345,
        varbinds: [
          {[1, 3, 6, 1, 2, 1, 1, 1, 0], :null},
          {[1, 3, 6, 1, 2, 1, 1, 2, 0], :null}
        ]
      }

      {:ok, error_response} = Error.create_error_response(request_pdu, :no_such_name, 1)

      assert error_response.type == :get_response
      assert error_response.request_id == 12345
      assert error_response.error_status == 2
      assert error_response.error_index == 1
      assert error_response.varbinds == request_pdu.varbinds
    end

    test "creates error response with numeric error code" do
      request_pdu = %{
        type: :set_request,
        request_id: 54321,
        varbinds: []
      }

      {:ok, error_response} = Error.create_error_response(request_pdu, 3, 2)

      assert error_response.error_status == 3
      assert error_response.error_index == 2
      assert error_response.request_id == 54321
    end

    test "handles missing request_id gracefully" do
      request_pdu = %{
        type: :get_request,
        varbinds: []
      }

      {:ok, error_response} = Error.create_error_response(request_pdu, :gen_err, 1)

      assert error_response.request_id == 0
    end

    test "handles missing varbinds gracefully" do
      request_pdu = %{
        type: :get_request,
        request_id: 999
      }

      {:ok, error_response} = Error.create_error_response(request_pdu, :gen_err, 1)

      assert error_response.varbinds == []
    end

    test "returns error for invalid request PDU" do
      invalid_pdu = "not a map"

      {:error, reason} = Error.create_error_response(invalid_pdu, :gen_err, 1)
      assert reason == :invalid_request_pdu
    end
  end

  describe "Error.valid_error_status?/1" do
    test "validates numeric error codes" do
      assert Error.valid_error_status?(0) == true
      assert Error.valid_error_status?(1) == true
      assert Error.valid_error_status?(18) == true
      assert Error.valid_error_status?(999) == false
      assert Error.valid_error_status?(-1) == false
    end

    test "validates atom error codes" do
      assert Error.valid_error_status?(:no_error) == true
      assert Error.valid_error_status?(:too_big) == true
      assert Error.valid_error_status?(:inconsistent_name) == true
      assert Error.valid_error_status?(:invalid_atom) == false
    end

    test "rejects invalid types" do
      assert Error.valid_error_status?("string") == false
      assert Error.valid_error_status?([1, 2, 3]) == false
      assert Error.valid_error_status?(nil) == false
    end
  end

  describe "Error.all_error_codes/0" do
    test "returns all standard error codes" do
      codes = Error.all_error_codes()

      assert is_list(codes)
      assert 0 in codes
      assert 5 in codes
      assert 18 in codes
      assert length(codes) == 19
    end
  end

  describe "Error.all_error_atoms/0" do
    test "returns all standard error atoms" do
      atoms = Error.all_error_atoms()

      assert is_list(atoms)
      assert :no_error in atoms
      assert :gen_err in atoms
      assert :inconsistent_name in atoms
      assert length(atoms) == 19
    end
  end

  describe "Error.error_severity/1" do
    test "categorizes no_error as info" do
      assert Error.error_severity(:no_error) == :info
      assert Error.error_severity(0) == :info
    end

    test "categorizes retriable errors as warning" do
      assert Error.error_severity(:too_big) == :warning
      assert Error.error_severity(:gen_err) == :warning
      assert Error.error_severity(:resource_unavailable) == :warning
      assert Error.error_severity(1) == :warning
    end

    test "categorizes non-retriable errors as error" do
      assert Error.error_severity(:no_such_name) == :error
      assert Error.error_severity(:bad_value) == :error
      assert Error.error_severity(:authorization_error) == :error
      assert Error.error_severity(2) == :error
    end

    test "categorizes unknown errors as error" do
      assert Error.error_severity(999) == :error
      assert Error.error_severity(:unknown) == :error
    end
  end

  describe "integration with other modules" do
    test "error codes work with PDU module concepts" do
      # Test that error responses have correct structure for PDU encoding
      request_pdu = %{
        type: :get_request,
        request_id: 123,
        varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :null}]
      }

      {:ok, error_response} = Error.create_error_response(request_pdu, :no_such_name, 1)

      # Verify structure matches what PDU module expects
      assert Map.has_key?(error_response, :type)
      assert Map.has_key?(error_response, :request_id)
      assert Map.has_key?(error_response, :error_status)
      assert Map.has_key?(error_response, :error_index)
      assert Map.has_key?(error_response, :varbinds)
    end

    test "error formatting works with OID module concepts" do
      # Test that OID lists are properly formatted in error messages
      varbinds = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], "sysDescr"},
        {[1, 3, 6, 1, 2, 1, 1, 3, 0], "sysUpTime"}
      ]

      result = Error.format_error(:no_such_name, 2, varbinds)

      assert String.contains?(result, "1.3.6.1.2.1.1.3.0")
    end
  end
end
