defmodule SnmpKit.SnmpLib.TypesTest do
  use ExUnit.Case, async: true
  
  alias SnmpKit.SnmpLib.Types
  
  @moduletag :unit
  @moduletag :protocol
  @moduletag :phase_2

  describe "Counter32 validation" do
    test "validates correct Counter32 values" do
      assert :ok = Types.validate_counter32(0)
      assert :ok = Types.validate_counter32(42)
      assert :ok = Types.validate_counter32(4_294_967_295)
    end

    test "rejects invalid Counter32 values" do
      assert {:error, :out_of_range} = Types.validate_counter32(-1)
      assert {:error, :out_of_range} = Types.validate_counter32(4_294_967_296)
      assert {:error, :not_integer} = Types.validate_counter32("42")
      assert {:error, :not_integer} = Types.validate_counter32(42.5)
    end
  end

  describe "Gauge32 validation" do
    test "validates correct Gauge32 values" do
      assert :ok = Types.validate_gauge32(0)
      assert :ok = Types.validate_gauge32(42)
      assert :ok = Types.validate_gauge32(4_294_967_295)
    end

    test "rejects invalid Gauge32 values" do
      assert {:error, :out_of_range} = Types.validate_gauge32(-1)
      assert {:error, :out_of_range} = Types.validate_gauge32(4_294_967_296)
      assert {:error, :not_integer} = Types.validate_gauge32("42")
    end
  end

  describe "TimeTicks validation" do
    test "validates correct TimeTicks values" do
      assert :ok = Types.validate_timeticks(0)
      assert :ok = Types.validate_timeticks(100)
      assert :ok = Types.validate_timeticks(4_294_967_295)
    end

    test "rejects invalid TimeTicks values" do
      assert {:error, :out_of_range} = Types.validate_timeticks(-1)
      assert {:error, :out_of_range} = Types.validate_timeticks(4_294_967_296)
      assert {:error, :not_integer} = Types.validate_timeticks(:not_integer)
    end
  end

  describe "Counter64 validation" do
    test "validates correct Counter64 values" do
      assert :ok = Types.validate_counter64(0)
      assert :ok = Types.validate_counter64(42)
      assert :ok = Types.validate_counter64(18_446_744_073_709_551_615)
    end

    test "rejects invalid Counter64 values" do
      assert {:error, :out_of_range} = Types.validate_counter64(-1)
      assert {:error, :not_integer} = Types.validate_counter64("42")
    end
  end

  describe "IP address validation" do
    test "validates correct IP addresses as binary" do
      assert :ok = Types.validate_ip_address(<<192, 168, 1, 1>>)
      assert :ok = Types.validate_ip_address(<<0, 0, 0, 0>>)
      assert :ok = Types.validate_ip_address(<<255, 255, 255, 255>>)
    end

    test "validates correct IP addresses as tuple" do
      assert :ok = Types.validate_ip_address({192, 168, 1, 1})
      assert :ok = Types.validate_ip_address({0, 0, 0, 0})
      assert :ok = Types.validate_ip_address({255, 255, 255, 255})
    end

    test "rejects invalid IP addresses" do
      assert {:error, :invalid_length} = Types.validate_ip_address(<<192, 168, 1>>)
      assert {:error, :invalid_length} = Types.validate_ip_address(<<192, 168, 1, 1, 1>>)
      assert {:error, :invalid_format} = Types.validate_ip_address({256, 1, 1, 1})
      assert {:error, :invalid_format} = Types.validate_ip_address({1, 2, 3})
      assert {:error, :invalid_format} = Types.validate_ip_address("192.168.1.1")
    end
  end

  describe "Integer validation" do
    test "validates correct integers" do
      assert :ok = Types.validate_integer(0)
      assert :ok = Types.validate_integer(42)
      assert :ok = Types.validate_integer(-42)
      assert :ok = Types.validate_integer(2_147_483_647)
      assert :ok = Types.validate_integer(-2_147_483_648)
    end

    test "rejects out of range integers" do
      assert {:error, :out_of_range} = Types.validate_integer(2_147_483_648)
      assert {:error, :out_of_range} = Types.validate_integer(-2_147_483_649)
      assert {:error, :not_integer} = Types.validate_integer(42.5)
    end
  end

  describe "OCTET STRING validation" do
    test "validates correct octet strings" do
      assert :ok = Types.validate_octet_string("")
      assert :ok = Types.validate_octet_string("Hello")
      assert :ok = Types.validate_octet_string(<<1, 2, 3, 4, 5>>)
    end

    test "rejects too long octet strings" do
      long_string = String.duplicate("A", 65536)
      assert {:error, :too_long} = Types.validate_octet_string(long_string)
      assert {:error, :not_binary} = Types.validate_octet_string(12345)
    end
  end

  describe "OID validation" do
    test "validates correct OIDs" do
      assert :ok = Types.validate_oid([1, 3, 6, 1, 2, 1, 1, 1, 0])
      assert :ok = Types.validate_oid([1])
      assert :ok = Types.validate_oid([0, 0])
    end

    test "rejects invalid OIDs" do
      assert {:error, :empty_oid} = Types.validate_oid([])
      assert {:error, :invalid_component} = Types.validate_oid([1, 3, -1, 4])
      assert {:error, :not_list} = Types.validate_oid("1.3.6.1")
    end
  end

  describe "Opaque validation" do
    test "validates correct opaque values" do
      assert :ok = Types.validate_opaque("")
      assert :ok = Types.validate_opaque("arbitrary data")
      assert :ok = Types.validate_opaque(<<1, 2, 3, 255, 0>>)
    end

    test "rejects invalid opaque values" do
      long_data = String.duplicate("A", 65536)
      assert {:error, :too_long} = Types.validate_opaque(long_data)
      assert {:error, :not_binary} = Types.validate_opaque(12345)
    end
  end

  describe "TimeTicks formatting" do
    test "formats centiseconds correctly" do
      assert Types.format_timeticks_uptime(0) == "0 centiseconds"
      assert Types.format_timeticks_uptime(42) == "42 centiseconds"
      assert Types.format_timeticks_uptime(100) == "1 second"
      assert Types.format_timeticks_uptime(150) == "1 second 50 centiseconds"
    end

    test "formats larger time periods correctly" do
      assert Types.format_timeticks_uptime(6000) == "1 minute"
      assert Types.format_timeticks_uptime(6150) == "1 minute 1 second 50 centiseconds"
      assert Types.format_timeticks_uptime(360000) == "1 hour"
      assert Types.format_timeticks_uptime(8640000) == "1 day"
    end

    test "handles plural forms correctly" do
      assert Types.format_timeticks_uptime(200) == "2 seconds"
      assert Types.format_timeticks_uptime(12000) == "2 minutes"
      assert Types.format_timeticks_uptime(720000) == "2 hours"
      assert Types.format_timeticks_uptime(17280000) == "2 days"
    end

    test "formats complex time periods" do
      # 2 days, 3 hours, 15 minutes, 30 seconds, 50 centiseconds
      complex_time = 2 * 24 * 60 * 60 * 100 + 3 * 60 * 60 * 100 + 15 * 60 * 100 + 30 * 100 + 50
      result = Types.format_timeticks_uptime(complex_time)
      assert String.contains?(result, "2 days")
      assert String.contains?(result, "3 hours")
      assert String.contains?(result, "15 minutes")
      assert String.contains?(result, "30 seconds")
      assert String.contains?(result, "50 centiseconds")
    end
  end

  describe "Counter64 formatting" do
    test "formats small numbers without commas" do
      assert Types.format_counter64(42) == "42"
      assert Types.format_counter64(999) == "999"
    end

    test "formats large numbers with commas" do
      assert Types.format_counter64(1000) == "1,000"
      assert Types.format_counter64(1234567) == "1,234,567"
      assert Types.format_counter64(18_446_744_073_709_551_615) == "18,446,744,073,709,551,615"
    end
  end

  describe "IP address formatting" do
    test "formats IP addresses correctly" do
      assert Types.format_ip_address(<<192, 168, 1, 1>>) == "192.168.1.1"
      assert Types.format_ip_address(<<0, 0, 0, 0>>) == "0.0.0.0"
      assert Types.format_ip_address(<<255, 255, 255, 255>>) == "255.255.255.255"
      assert Types.format_ip_address(<<127, 0, 0, 1>>) == "127.0.0.1"
    end

    test "handles invalid IP address format" do
      assert Types.format_ip_address(<<1, 2, 3>>) == "invalid"
      assert Types.format_ip_address("not binary") == "invalid"
    end
  end

  describe "Byte formatting" do
    test "formats bytes correctly" do
      assert Types.format_bytes(0) == "0 B"
      assert Types.format_bytes(512) == "512 B"
      assert Types.format_bytes(1024) == "1.0 KB"
      assert Types.format_bytes(1536) == "1.5 KB"
      assert Types.format_bytes(1_048_576) == "1.0 MB"
      assert Types.format_bytes(2_400_000) == "2.3 MB"
      assert Types.format_bytes(1_073_741_824) == "1.0 GB"
    end
  end

  describe "Rate formatting" do
    test "formats rates correctly" do
      assert Types.format_rate(100, "bps") == "100 bps"
      assert Types.format_rate(1500, "bps") == "1.5 Kbps"
      assert Types.format_rate(1_500_000, "bps") == "1.5 Mbps"
      assert Types.format_rate(1_500_000_000, "bps") == "1.5 Gbps"
    end

    test "handles different units" do
      assert Types.format_rate(1000, "pps") == "1.0 Kpps"
      assert Types.format_rate(50, "Hz") == "50 Hz"
    end
  end

  describe "String truncation" do
    test "truncates long strings correctly" do
      assert Types.truncate_string("hello", 10) == "hello"
      assert Types.truncate_string("hello world", 8) == "hello..."
      assert Types.truncate_string("test", 3) == "tes"
      assert Types.truncate_string("ab", 1) == "a"
    end

    test "handles edge cases in truncation" do
      assert Types.truncate_string("", 5) == ""
      assert Types.truncate_string("test", 0) == ""
      assert Types.truncate_string("test", 4) == "test"
    end
  end

  describe "Hex formatting" do
    test "formats binary as hex correctly" do
      assert Types.format_hex(<<"Hello">>) == "48656C6C6F"
      assert Types.format_hex(<<0xDE, 0xAD, 0xBE, 0xEF>>) == "DEADBEEF"
      assert Types.format_hex(<<>>) == ""
    end

    test "parses hex string correctly" do
      {:ok, result} = Types.parse_hex_string("48656C6C6F")
      assert result == <<"Hello">>
      
      {:ok, result} = Types.parse_hex_string("DEADBEEF")
      assert result == <<0xDE, 0xAD, 0xBE, 0xEF>>
      
      {:ok, result} = Types.parse_hex_string("")
      assert result == <<>>
    end

    test "handles mixed case hex strings" do
      {:ok, result} = Types.parse_hex_string("DeAdBeEf")
      assert result == <<0xDE, 0xAD, 0xBE, 0xEF>>
    end

    test "rejects invalid hex strings" do
      assert {:error, :invalid_hex} = Types.parse_hex_string("XYZ")
      assert {:error, :invalid_hex} = Types.parse_hex_string("ABCDEFG")
      assert {:error, :invalid_hex} = Types.parse_hex_string("123")  # Odd number of chars
    end
  end

  describe "Type coercion" do
    test "coerces integer values correctly" do
      {:ok, result} = Types.coerce_value(:integer, 42)
      assert result == 42
      
      assert {:error, :out_of_range} = Types.coerce_value(:integer, 3_000_000_000)
    end

    test "coerces string values correctly" do
      {:ok, result} = Types.coerce_value(:string, "test")
      assert result == {:string, "test"}
      
      {:ok, result} = Types.coerce_value(:string, <<1, 2, 3>>)
      assert result == {:string, <<1, 2, 3>>}
    end

    test "coerces null values correctly" do
      {:ok, result} = Types.coerce_value(:null, "anything")
      assert result == :null
      
      {:ok, result} = Types.coerce_value(:null, nil)
      assert result == :null
    end

    test "coerces OID values correctly" do
      {:ok, result} = Types.coerce_value(:oid, [1, 3, 6, 1])
      assert result == [1, 3, 6, 1]
      
      {:ok, result} = Types.coerce_value(:oid, "1.3.6.1")
      assert result == [1, 3, 6, 1]
    end

    test "coerces Counter32 values correctly" do
      {:ok, result} = Types.coerce_value(:counter32, 42)
      assert result == {:counter32, 42}
      
      assert {:error, :out_of_range} = Types.coerce_value(:counter32, -1)
    end

    test "coerces Gauge32 values correctly" do
      {:ok, result} = Types.coerce_value(:gauge32, 42)
      assert result == {:gauge32, 42}
    end

    test "coerces TimeTicks values correctly" do
      {:ok, result} = Types.coerce_value(:timeticks, 42)
      assert result == {:timeticks, 42}
    end

    test "coerces Counter64 values correctly" do
      {:ok, result} = Types.coerce_value(:counter64, 42)
      assert result == {:counter64, 42}
    end

    test "coerces IP address values correctly" do
      {:ok, result} = Types.coerce_value(:ip_address, <<192, 168, 1, 1>>)
      assert result == {:ip_address, <<192, 168, 1, 1>>}
      
      {:ok, result} = Types.coerce_value(:ip_address, {192, 168, 1, 1})
      assert result == {:ip_address, <<192, 168, 1, 1>>}
    end

    test "coerces opaque values correctly" do
      {:ok, result} = Types.coerce_value(:opaque, "arbitrary data")
      assert result == {:opaque, "arbitrary data"}
    end

    test "coerces exception types correctly" do
      {:ok, result} = Types.coerce_value(:no_such_object, "anything")
      assert result == {:no_such_object, nil}
      
      {:ok, result} = Types.coerce_value(:no_such_instance, "anything")
      assert result == {:no_such_instance, nil}
      
      {:ok, result} = Types.coerce_value(:end_of_mib_view, "anything")
      assert result == {:end_of_mib_view, nil}
    end

    test "rejects unsupported type coercion" do
      assert {:error, :unsupported_type} = Types.coerce_value(:unknown_type, 42)
    end
  end

  describe "Type normalization" do
    test "normalizes atom types" do
      assert Types.normalize_type(:integer) == :integer
      assert Types.normalize_type(:counter32) == :counter32
    end

    test "normalizes string types" do
      assert Types.normalize_type("integer") == :integer
      assert Types.normalize_type("string") == :string
      assert Types.normalize_type("octet_string") == :string
      assert Types.normalize_type("counter32") == :counter32
      assert Types.normalize_type("object_identifier") == :object_identifier
      assert Types.normalize_type("ipaddress") == :ip_address
    end

    test "returns unknown for invalid types" do
      assert Types.normalize_type("invalid_type") == :unknown
      assert Types.normalize_type(12345) == :unknown
    end
  end

  describe "Type classification utilities" do
    test "identifies numeric types correctly" do
      assert Types.is_numeric_type?(:integer) == true
      assert Types.is_numeric_type?(:counter32) == true
      assert Types.is_numeric_type?(:gauge32) == true
      assert Types.is_numeric_type?(:timeticks) == true
      assert Types.is_numeric_type?(:counter64) == true
      
      assert Types.is_numeric_type?(:string) == false
      assert Types.is_numeric_type?(:oid) == false
    end

    test "identifies binary types correctly" do
      assert Types.is_binary_type?(:string) == true
      assert Types.is_binary_type?(:opaque) == true
      assert Types.is_binary_type?(:ip_address) == true
      
      assert Types.is_binary_type?(:integer) == false
      assert Types.is_binary_type?(:counter32) == false
    end

    test "identifies exception types correctly" do
      assert Types.is_exception_type?(:no_such_object) == true
      assert Types.is_exception_type?(:no_such_instance) == true
      assert Types.is_exception_type?(:end_of_mib_view) == true
      
      assert Types.is_exception_type?(:integer) == false
      assert Types.is_exception_type?(:string) == false
    end
  end

  describe "Type value ranges" do
    test "returns correct maximum values" do
      assert Types.max_value(:integer) == 2_147_483_647
      assert Types.max_value(:counter32) == 4_294_967_295
      assert Types.max_value(:gauge32) == 4_294_967_295
      assert Types.max_value(:timeticks) == 4_294_967_295
      assert Types.max_value(:counter64) == 18_446_744_073_709_551_615
      assert Types.max_value(:string) == nil
    end

    test "returns correct minimum values" do
      assert Types.min_value(:integer) == -2_147_483_648
      assert Types.min_value(:counter32) == 0
      assert Types.min_value(:gauge32) == 0
      assert Types.min_value(:timeticks) == 0
      assert Types.min_value(:counter64) == 0
      assert Types.min_value(:string) == nil
    end
  end

  describe "Error handling and edge cases" do
    test "handles concurrent type operations" do
      # Test thread safety of type operations
      tasks = for i <- 1..50 do
        Task.async(fn ->
          value = rem(i, 1000)
          {:ok, coerced} = Types.coerce_value(:counter32, value)
          formatted = Types.format_counter64(value)
          {i, coerced, formatted}
        end)
      end
      
      results = Task.await_many(tasks, 1000)
      
      # Verify all operations completed successfully
      assert length(results) == 50
      for {i, {:counter32, value}, formatted} <- results do
        expected_value = rem(i, 1000)
        assert value == expected_value
        assert is_binary(formatted)
      end
    end

    test "handles boundary values correctly" do
      # Test maximum values for each type
      assert :ok = Types.validate_counter32(4_294_967_295)
      assert {:error, :out_of_range} = Types.validate_counter32(4_294_967_296)
      
      assert :ok = Types.validate_integer(2_147_483_647)
      assert {:error, :out_of_range} = Types.validate_integer(2_147_483_648)
      
      assert :ok = Types.validate_integer(-2_147_483_648)
      assert {:error, :out_of_range} = Types.validate_integer(-2_147_483_649)
    end

    test "handles zero and negative values appropriately" do
      # Counter types should accept zero but not negative
      assert :ok = Types.validate_counter32(0)
      assert {:error, :out_of_range} = Types.validate_counter32(-1)
      
      # Integer should accept negative values
      assert :ok = Types.validate_integer(-42)
      assert :ok = Types.validate_integer(0)
      assert :ok = Types.validate_integer(42)
    end
  end
end