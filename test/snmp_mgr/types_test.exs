defmodule SnmpKit.SnmpMgr.TypesIntegrationTest do
  use ExUnit.Case, async: true
  
  alias SnmpKit.SnmpMgr.{Types}
  alias SnmpKit.SnmpKit.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :types
  @moduletag :snmp_lib_integration

  setup_all do
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}
      error ->
        %{device: nil, setup_error: error}
    end
  end

  describe "Type Inference" do
    test "infers basic types correctly" do
      assert Types.infer_type("hello") == :string
      assert Types.infer_type(42) == :unsigned32
      assert Types.infer_type(-1) == :integer
      assert Types.infer_type(5_000_000_000) == :counter64
      assert Types.infer_type(true) == :boolean
      assert Types.infer_type(nil) == :null
      assert Types.infer_type({192, 168, 1, 1}) == :ipAddress
    end
  end

  describe "Value Encoding" do
    test "encodes values with automatic type inference" do
      assert {:ok, {:string, "hello"}} = Types.encode_value("hello")
      assert {:ok, {:unsigned32, 42}} = Types.encode_value(42)
      assert {:ok, {:integer, -1}} = Types.encode_value(-1)
    end
    
    test "encodes values with explicit type specification" do
      assert {:ok, {:ipAddress, {192, 168, 1, 1}}} = Types.encode_value("192.168.1.1", type: :ipAddress)
      assert {:ok, {:gauge32, 100}} = Types.encode_value(100, type: :gauge32)
    end
  end

  describe "Value Decoding" do
    test "decodes typed values to Elixir terms" do
      assert Types.decode_value({:string, "hello"}) == "hello"
      assert Types.decode_value({:integer, 42}) == 42
      assert Types.decode_value({:ipAddress, {192, 168, 1, 1}}) == "192.168.1.1"
      assert Types.decode_value({:gauge32, 100}) == 100
    end
  end

  describe "Integration with SNMP Operations" do
    test "type encoding works with SET operations", %{device: device} do
      skip_if_no_device(device)
      
      # Test that encoded values work with snmp_lib SET operations
      # Note: SET operations often fail on read-only OIDs, but we test the encoding integration
      case Types.encode_value("test_value") do
        {:ok, encoded_value} ->
          # The encoded value should be in the format expected by snmp_lib
          assert match?({:string, _}, encoded_value)
          
          # Attempt SET operation (may fail due to read-only OID, but tests integration)
          target = SNMPSimulator.device_target(device)
          result = SnmpMgr.set(target, "1.3.6.1.2.1.1.4.0", "test_value", 
                              community: device.community, timeout: 200)
          
          # SET may fail due to permissions, but should not fail due to type encoding
          case result do
            {:ok, _} -> 
              # SET succeeded
              :ok
            {:error, reason} when reason in [:not_writable, :read_only, :no_access, :gen_err] ->
              # Expected permission errors are acceptable
              :ok
            {:error, reason} ->
              flunk("SET failed due to type encoding issue: #{inspect(reason)}")
          end
          
        {:error, reason} ->
          flunk("Type encoding failed: #{inspect(reason)}")
      end
    end
  end
  
  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end
