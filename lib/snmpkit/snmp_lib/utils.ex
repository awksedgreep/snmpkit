defmodule SnmpKit.SnmpLib.Utils do
  @moduledoc """
  Common utilities for SNMP operations including pretty printing, data formatting,
  timing utilities, and validation functions.

  This module provides helpful utilities for debugging, logging, monitoring, and
  general SNMP data manipulation that are commonly needed across SNMP applications.

  ## Pretty Printing

  Format SNMP data structures for human-readable display in logs, CLI tools,
  and debugging output.

  ## Data Formatting

  Convert between different representations of SNMP data, format numeric values,
  and handle common data transformations.

  ## Timing Utilities

  Measure and format timing information for SNMP operations, useful for
  performance monitoring and debugging.

  ## Validation

  Common validation functions for SNMP-related data.

  ## Usage Examples

  ### Pretty Printing

      # Format PDU for logging
      pdu = %{type: :get_request, request_id: 123, varbinds: [...]}
      Logger.info(SnmpKit.SnmpLib.Utils.pretty_print_pdu(pdu))

      # Format individual values
      value = {:counter32, 12345}
      IO.puts(SnmpKit.SnmpLib.Utils.pretty_print_value(value))

  ### Data Formatting

      # Format large numbers with separators
      SnmpKit.SnmpLib.Utils.format_bytes(1048576)
      # => "1.0 MB"

      # Format hex strings for MAC addresses
      SnmpKit.SnmpLib.Utils.format_hex(<<0x00, 0x1B, 0x21, 0x3C, 0x92, 0xEB>>)
      # => "00:1B:21:3C:92:EB"

  ### Timing

      # Time an operation
      {result, time_us} = SnmpKit.SnmpLib.Utils.measure_request_time(fn ->
        SnmpKit.SnmpLib.PDU.encode_message(pdu)
      end)

      formatted_time = SnmpKit.SnmpLib.Utils.format_response_time(time_us)
  """

  require Logger

  @type oid :: [non_neg_integer()]
  @type snmp_value :: any()
  @type varbind :: {oid(), snmp_value()}
  @type varbinds :: [varbind()]
  @type pdu :: map()

  ## Pretty Printing Functions

  @doc """
  Pretty prints an SNMP PDU for human-readable display.

  Formats the PDU structure with proper indentation and readable field names,
  suitable for logging, debugging, or CLI display.

  ## Parameters

  - `pdu`: SNMP PDU map containing type, request_id, error_status, etc.

  ## Returns

  Formatted string representation of the PDU.

  ## Examples

      iex> pdu = %{type: :get_request, request_id: 123, varbinds: [{[1,3,6,1,2,1,1,1,0], :null}]}
      iex> result = SnmpKit.SnmpLib.Utils.pretty_print_pdu(pdu)
      iex> String.contains?(result, "GET Request")
      true
  """
  @spec pretty_print_pdu(pdu()) :: String.t()
  def pretty_print_pdu(pdu) when is_map(pdu) do
    type_str = format_pdu_type(Map.get(pdu, :type, :unknown))
    request_id = Map.get(pdu, :request_id, 0)

    lines = [
      "#{type_str} (ID: #{request_id})"
    ]

    lines = add_error_info(lines, pdu)
    lines = add_bulk_info(lines, pdu)
    lines = add_varbinds(lines, Map.get(pdu, :varbinds, []))

    Enum.join(lines, "\n")
  end

  def pretty_print_pdu(_), do: "Invalid PDU"

  @doc """
  Pretty prints a list of varbinds for display.

  ## Examples

      iex> varbinds = [{[1,3,6,1,2,1,1,1,0], "Linux server"}]
      iex> result = SnmpKit.SnmpLib.Utils.pretty_print_varbinds(varbinds)
      iex> String.contains?(result, "1.3.6.1.2.1.1.1.0")
      true
  """
  @spec pretty_print_varbinds(varbinds()) :: String.t()
  def pretty_print_varbinds(varbinds) when is_list(varbinds) do
    if length(varbinds) == 0 do
      "  (no varbinds)"
    else
      varbinds
      |> Enum.with_index(1)
      |> Enum.map(fn {{oid, value}, index} ->
        "  #{index}. #{pretty_print_oid(oid)} = #{pretty_print_value(value)}"
      end)
      |> Enum.join("\n")
    end
  end

  def pretty_print_varbinds(_), do: "Invalid varbinds"

  @doc """
  Pretty prints an OID for display.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.pretty_print_oid([1,3,6,1,2,1,1,1,0])
      "1.3.6.1.2.1.1.1.0"

      iex> SnmpKit.SnmpLib.Utils.pretty_print_oid("1.3.6.1.2.1.1.1.0")
      "1.3.6.1.2.1.1.1.0"
  """
  @spec pretty_print_oid(oid() | String.t()) :: String.t()
  def pretty_print_oid(oid) when is_list(oid) do
    Enum.join(oid, ".")
  end

  def pretty_print_oid(oid) when is_binary(oid) do
    oid
  end

  def pretty_print_oid(_), do: "invalid-oid"

  @doc """
  Pretty prints an SNMP value for display.

  Formats SNMP values with appropriate type information and human-readable
  representations.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.pretty_print_value({:counter32, 12345})
      "Counter32: 12,345"

      iex> SnmpKit.SnmpLib.Utils.pretty_print_value({:octet_string, "Hello"})
      "OCTET STRING: \\"Hello\\""

      iex> SnmpKit.SnmpLib.Utils.pretty_print_value(:null)
      "NULL"
  """
  @spec pretty_print_value(snmp_value()) :: String.t()
  def pretty_print_value(:null), do: "NULL"
  def pretty_print_value({:integer, value}), do: "INTEGER: #{value}"

  def pretty_print_value({:octet_string, value}) when is_binary(value) do
    if String.printable?(value) do
      ~s(OCTET STRING: "#{value}")
    else
      hex_str = format_hex(value, " ")
      "OCTET STRING: #{hex_str}"
    end
  end

  def pretty_print_value({:object_identifier, oid}), do: "OID: #{pretty_print_oid(oid)}"
  def pretty_print_value({:counter32, value}), do: "Counter32: #{format_number(value)}"
  def pretty_print_value({:gauge32, value}), do: "Gauge32: #{format_number(value)}"
  def pretty_print_value({:timeticks, value}), do: "TimeTicks: #{format_timeticks(value)}"
  def pretty_print_value({:counter64, value}), do: "Counter64: #{format_number(value)}"
  def pretty_print_value({:ip_address, <<a, b, c, d>>}), do: "IpAddress: #{a}.#{b}.#{c}.#{d}"
  def pretty_print_value({:opaque, data}), do: "Opaque: #{format_hex(data, " ")}"
  def pretty_print_value({:no_such_object, _}), do: "noSuchObject"
  def pretty_print_value({:no_such_instance, _}), do: "noSuchInstance"
  def pretty_print_value({:end_of_mib_view, _}), do: "endOfMibView"
  def pretty_print_value(value) when is_integer(value), do: "INTEGER: #{value}"

  def pretty_print_value(value) when is_binary(value) do
    if String.printable?(value) do
      ~s("#{value}")
    else
      format_hex(value, " ")
    end
  end

  def pretty_print_value(value), do: "#{inspect(value)}"

  ## Data Formatting Functions

  @doc """
  Formats byte counts in human-readable units.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.format_bytes(1024)
      "1.0 KB"

      iex> SnmpKit.SnmpLib.Utils.format_bytes(1048576)
      "1.0 MB"

      iex> SnmpKit.SnmpLib.Utils.format_bytes(512)
      "512 B"
  """
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  def format_bytes(_), do: "Invalid byte count"

  @doc """
  Formats rates with units.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.format_rate(1500, "bps")
      "1.5 Kbps"

      iex> SnmpKit.SnmpLib.Utils.format_rate(45, "pps")
      "45 pps"
  """
  @spec format_rate(number(), String.t()) :: String.t()
  def format_rate(value, unit) when is_number(value) and is_binary(unit) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)} G#{unit}"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)} M#{unit}"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)} K#{unit}"
      true -> "#{value} #{unit}"
    end
  end

  def format_rate(_, _), do: "Invalid rate"

  @doc """
  Truncates a string to maximum length with ellipsis.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.truncate_string("Hello, World!", 10)
      "Hello, ..."

      iex> SnmpKit.SnmpLib.Utils.truncate_string("Short", 10)
      "Short"
  """
  @spec truncate_string(String.t(), pos_integer()) :: String.t()
  def truncate_string(string, max_length)
      when is_binary(string) and is_integer(max_length) and max_length > 3 do
    if String.length(string) <= max_length do
      string
    else
      String.slice(string, 0, max_length - 3) <> "..."
    end
  end

  def truncate_string(string, _) when is_binary(string), do: string
  def truncate_string(_, _), do: ""

  @doc """
  Formats binary data as hexadecimal string.

  ## Parameters

  - `data`: Binary data to format
  - `separator`: String to use between hex bytes (default: ":")

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.format_hex(<<0x00, 0x1B, 0x21>>)
      "00:1B:21"

      iex> SnmpKit.SnmpLib.Utils.format_hex(<<0xDE, 0xAD, 0xBE, 0xEF>>, " ")
      "DE AD BE EF"
  """
  @spec format_hex(binary(), String.t()) :: String.t()
  def format_hex(data, separator \\ ":")

  def format_hex(data, separator) when is_binary(data) and is_binary(separator) do
    data
    |> :binary.bin_to_list()
    |> Enum.map(&String.upcase(Integer.to_string(&1, 16) |> String.pad_leading(2, "0")))
    |> Enum.join(separator)
  end

  def format_hex(data, _) when not is_binary(data), do: "Invalid binary data"
  def format_hex(_, separator) when not is_binary(separator), do: "Invalid binary data"

  @doc """
  Formats large numbers with thousand separators.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.format_number(1234567)
      "1,234,567"

      iex> SnmpKit.SnmpLib.Utils.format_number(42)
      "42"
  """
  @spec format_number(integer()) :: String.t()
  def format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def format_number(_), do: "Invalid number"

  ## Timing Utilities

  @doc """
  Measures the execution time of a function in microseconds.

  ## Parameters

  - `fun`: Function to execute and time

  ## Returns

  Tuple of `{result, time_microseconds}` where result is the function's
  return value and time_microseconds is the execution time.

  ## Examples

      iex> {result, time} = SnmpKit.SnmpLib.Utils.measure_request_time(fn -> :timer.sleep(100); :ok end)
      iex> result
      :ok
      iex> time > 100_000
      true
  """
  @spec measure_request_time(function()) :: {any(), non_neg_integer()}
  def measure_request_time(fun) when is_function(fun) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)
    {result, end_time - start_time}
  end

  @doc """
  Formats response time in human-readable units.

  ## Parameters

  - `microseconds`: Time in microseconds

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.format_response_time(1500)
      "1.50ms"

      iex> SnmpKit.SnmpLib.Utils.format_response_time(2_500_000)
      "2.50s"

      iex> SnmpKit.SnmpLib.Utils.format_response_time(500)
      "500μs"
  """
  @spec format_response_time(non_neg_integer()) :: String.t()
  def format_response_time(microseconds) when is_integer(microseconds) and microseconds >= 0 do
    cond do
      microseconds >= 1_000_000 ->
        "#{:erlang.float_to_binary(microseconds / 1_000_000, [{:decimals, 2}])}s"

      microseconds >= 1_000 ->
        "#{:erlang.float_to_binary(microseconds / 1_000, [{:decimals, 2}])}ms"

      true ->
        "#{microseconds}μs"
    end
  end

  def format_response_time(_), do: "Invalid time"

  ## Target Parsing Functions

  @doc """
  Parses SNMP target specifications into standardized format.

  Accepts various input formats and returns a consistent target map with host and port.
  IP addresses are resolved to tuples when possible, hostnames remain as strings.
  Default port is 161 when not specified.

  ## Parameters

  - `target`: Target specification in various formats

  ## Accepted Input Formats

  - `"192.168.1.1:161"` - IP with port
  - `"192.168.1.1"` - IP without port (uses default 161)
  - `"device.local:162"` - hostname with port
  - `"device.local"` - hostname without port (uses default 161)
  - `{192, 168, 1, 1}` - IP tuple (uses default port 161)
  - `%{host: "192.168.1.1", port: 161}` - already parsed map

  ## Returns

  - `{:ok, %{host: host, port: port}}` - Successfully parsed target
  - `{:error, reason}` - Parse error with reason

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.parse_target("192.168.1.1:161")
      {:ok, %{host: {192, 168, 1, 1}, port: 161}}

      iex> SnmpKit.SnmpLib.Utils.parse_target("192.168.1.1")
      {:ok, %{host: {192, 168, 1, 1}, port: 161}}

      iex> SnmpKit.SnmpLib.Utils.parse_target("device.local:162")
      {:ok, %{host: "device.local", port: 162}}

      iex> SnmpKit.SnmpLib.Utils.parse_target("device.local")
      {:ok, %{host: "device.local", port: 161}}

      iex> SnmpKit.SnmpLib.Utils.parse_target({192, 168, 1, 1})
      {:ok, %{host: {192, 168, 1, 1}, port: 161}}

      iex> SnmpKit.SnmpLib.Utils.parse_target(%{host: "192.168.1.1", port: 161})
      {:ok, %{host: {192, 168, 1, 1}, port: 161}}

      iex> SnmpKit.SnmpLib.Utils.parse_target("invalid:99999")
      {:error, {:invalid_port, "99999"}}
  """
  @spec parse_target(String.t() | tuple() | map()) ::
          {:ok, %{host: :inet.ip_address() | String.t(), port: pos_integer()}} | {:error, any()}
  def parse_target(target) when is_binary(target) do
    # Handle IPv6 addresses that might contain colons
    case parse_host_port_string(target) do
      {host_str, nil} ->
        # No port specified, use default
        parse_host_with_port(host_str, 161)

      {host_str, port_str} ->
        # Port specified, validate it
        case parse_port(port_str) do
          {:ok, port} -> parse_host_with_port(host_str, port)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def parse_target({a, b, c, d} = ip_tuple)
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    if valid_ip_tuple?(ip_tuple) do
      {:ok, %{host: ip_tuple, port: 161}}
    else
      {:error, {:invalid_ip_tuple, ip_tuple}}
    end
  end

  def parse_target({a, b, c, d, e, f, g, h} = ipv6_tuple)
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) and
             is_integer(e) and is_integer(f) and is_integer(g) and is_integer(h) do
    if valid_ipv6_tuple?(ipv6_tuple) do
      {:ok, %{host: ipv6_tuple, port: 161}}
    else
      {:error, {:invalid_ipv6_tuple, ipv6_tuple}}
    end
  end

  def parse_target(%{host: host, port: port}) when is_integer(port) do
    if port > 0 and port <= 65535 do
      case parse_host(host) do
        {:ok, parsed_host} -> {:ok, %{host: parsed_host, port: port}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:invalid_port, Integer.to_string(port)}}
    end
  end

  def parse_target(%{host: host}) do
    case parse_host(host) do
      {:ok, parsed_host} -> {:ok, %{host: parsed_host, port: 161}}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_target(invalid) do
    {:error, {:invalid_target_format, invalid}}
  end

  ## Validation Functions

  @doc """
  Validates an SNMP version number.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.valid_snmp_version?(1)
      true

      iex> SnmpKit.SnmpLib.Utils.valid_snmp_version?(5)
      false
  """
  @spec valid_snmp_version?(any()) :: boolean()
  def valid_snmp_version?(version) when version in [0, 1, 2, 3], do: true
  def valid_snmp_version?(:v1), do: true
  def valid_snmp_version?(:v2c), do: true
  def valid_snmp_version?(:v3), do: true
  def valid_snmp_version?(_), do: false

  @doc """
  Validates an SNMP community string.

  Community strings should be non-empty and contain only printable characters.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.valid_community_string?("public")
      true

      iex> SnmpKit.SnmpLib.Utils.valid_community_string?("")
      false
  """
  @spec valid_community_string?(any()) :: boolean()
  def valid_community_string?(community) when is_binary(community) do
    byte_size(community) > 0 and String.printable?(community)
  end

  def valid_community_string?(_), do: false

  @doc """
  Sanitizes a community string for safe logging.

  Replaces community strings with asterisks to prevent credential leakage
  in logs while preserving length information.

  ## Examples

      iex> SnmpKit.SnmpLib.Utils.sanitize_community("secret123")
      "*********"

      iex> SnmpKit.SnmpLib.Utils.sanitize_community("")
      "<empty>"
  """
  @spec sanitize_community(String.t()) :: String.t()
  def sanitize_community(community) when is_binary(community) do
    case byte_size(community) do
      0 -> "<empty>"
      size -> String.duplicate("*", size)
    end
  end

  def sanitize_community(_), do: "<invalid>"

  ## Private Helper Functions

  # Target parsing helpers
  defp parse_host_port_string(target_str) do
    cond do
      # RFC 3986 bracket notation: [IPv6]:port
      String.starts_with?(target_str, "[") ->
        parse_bracket_notation(target_str)

      # Check if this looks like plain IPv6 (contains :: or multiple colons)
      String.contains?(target_str, "::") or count_colons(target_str) > 1 ->
        # Plain IPv6 address without port
        {target_str, nil}

      # Standard host:port parsing for IPv4 and simple hostnames
      true ->
        case String.split(target_str, ":", parts: 2) do
          [host_str] ->
            {host_str, nil}

          [host_str, port_str] ->
            # Check if host part looks like IPv4 or simple hostname
            if is_ipv4_or_simple_hostname?(host_str) do
              {host_str, port_str}
            else
              # Complex hostname with colons, treat as hostname without port
              {target_str, nil}
            end
        end
    end
  end

  defp parse_bracket_notation("[" <> rest) do
    case String.split(rest, "]:", parts: 2) do
      [ipv6_addr, port_str] ->
        # Valid [IPv6]:port format
        {ipv6_addr, port_str}

      _ ->
        # Check for [IPv6] without port
        case String.split(rest, "]", parts: 2) do
          [ipv6_addr, ""] ->
            # Valid [IPv6] format without port
            {ipv6_addr, nil}

          _ ->
            # Invalid bracket notation, treat as hostname
            {"[" <> rest, nil}
        end
    end
  end

  defp count_colons(str) do
    str |> String.graphemes() |> Enum.count(&(&1 == ":"))
  end

  defp parse_host_with_port(host_str, port) do
    case parse_host(host_str) do
      {:ok, host} -> {:ok, %{host: host, port: port}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_host(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {a, b, c, d}}
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) ->
        # IPv4 address
        {:ok, {a, b, c, d}}

      {:ok, ipv6_tuple} when tuple_size(ipv6_tuple) == 8 ->
        # IPv6 address - return as tuple for proper socket handling
        {:ok, ipv6_tuple}

      {:error, :einval} ->
        # Not an IP, treat as hostname
        {:ok, host}
    end
  end

  defp parse_host({a, b, c, d} = ip_tuple)
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    if valid_ip_tuple?(ip_tuple) do
      {:ok, ip_tuple}
    else
      {:error, {:invalid_ip_tuple, ip_tuple}}
    end
  end

  defp parse_host(invalid) do
    {:error, {:invalid_host_format, invalid}}
  end

  defp parse_port(port_str) when is_binary(port_str) do
    case Integer.parse(port_str) do
      {port, ""} when port > 0 and port <= 65535 -> {:ok, port}
      {_port, ""} -> {:error, {:invalid_port, port_str}}
      _ -> {:error, {:invalid_port_format, port_str}}
    end
  end

  defp valid_ip_tuple?({a, b, c, d})
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    a >= 0 and a <= 255 and
      b >= 0 and b <= 255 and
      c >= 0 and c <= 255 and
      d >= 0 and d <= 255
  end

  defp valid_ip_tuple?(_), do: false

  defp valid_ipv6_tuple?({a, b, c, d, e, f, g, h})
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) and
              is_integer(e) and is_integer(f) and is_integer(g) and is_integer(h) do
    a >= 0 and a <= 65535 and
      b >= 0 and b <= 65535 and
      c >= 0 and c <= 65535 and
      d >= 0 and d <= 65535 and
      e >= 0 and e <= 65535 and
      f >= 0 and f <= 65535 and
      g >= 0 and g <= 65535 and
      h >= 0 and h <= 65535
  end

  defp valid_ipv6_tuple?(_), do: false

  defp is_ipv4_or_simple_hostname?(host_str) do
    # Check if it looks like IPv4 (has 3 dots and only digits/dots)
    case String.split(host_str, ".") do
      [a, b, c, d] ->
        # Looks like IPv4, check if all parts are numeric
        Enum.all?([a, b, c, d], fn part ->
          case Integer.parse(part) do
            {num, ""} when num >= 0 and num <= 255 -> true
            _ -> false
          end
        end)

      _ ->
        # Not IPv4 format, check if it's a simple hostname
        # Exclude anything that looks like IPv6 (contains :: or multiple colons)
        cond do
          # IPv6
          String.contains?(host_str, "::") -> false
          # IPv6 or complex
          host_str |> String.graphemes() |> Enum.count(&(&1 == ":")) > 1 -> false
          # Contains colon, not simple
          String.contains?(host_str, ":") -> false
          # Simple hostname pattern
          true -> String.match?(host_str, ~r/^[a-zA-Z0-9\-\.\_]+$/)
        end
    end
  end

  defp format_pdu_type(:get_request), do: "GET Request"
  defp format_pdu_type(:get_next_request), do: "GET-NEXT Request"
  defp format_pdu_type(:get_bulk_request), do: "GET-BULK Request"
  defp format_pdu_type(:set_request), do: "SET Request"
  defp format_pdu_type(:get_response), do: "Response"
  defp format_pdu_type(:trap), do: "Trap"
  defp format_pdu_type(:inform_request), do: "Inform Request"
  defp format_pdu_type(:snmpv2_trap), do: "SNMPv2 Trap"
  defp format_pdu_type(:report), do: "Report"
  defp format_pdu_type(type), do: "#{type}"

  defp add_error_info(lines, pdu) do
    error_status = Map.get(pdu, :error_status, 0)
    error_index = Map.get(pdu, :error_index, 0)

    if error_status != 0 do
      error_name =
        if function_exported?(SnmpKit.SnmpLib.Error, :error_name, 1) do
          SnmpKit.SnmpLib.Error.error_name(error_status)
        else
          "error_#{error_status}"
        end

      lines ++ ["  Error: #{error_name} (#{error_status}) at index #{error_index}"]
    else
      lines
    end
  end

  defp add_bulk_info(lines, pdu) do
    case Map.get(pdu, :type) do
      :get_bulk_request ->
        non_repeaters = Map.get(pdu, :non_repeaters, 0)
        max_repetitions = Map.get(pdu, :max_repetitions, 0)
        lines ++ ["  Non-repeaters: #{non_repeaters}, Max-repetitions: #{max_repetitions}"]

      _ ->
        lines
    end
  end

  defp add_varbinds(lines, varbinds) do
    varbind_str = pretty_print_varbinds(varbinds)
    lines ++ ["Varbinds:", varbind_str]
  end

  defp format_timeticks(ticks) when is_integer(ticks) do
    # Convert centiseconds to readable time format
    total_seconds = div(ticks, 100)
    days = div(total_seconds, 86400)
    hours = div(rem(total_seconds, 86400), 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    time_parts = []
    time_parts = if days > 0, do: time_parts ++ ["#{days}d"], else: time_parts
    time_parts = if hours > 0, do: time_parts ++ ["#{hours}h"], else: time_parts
    time_parts = if minutes > 0, do: time_parts ++ ["#{minutes}m"], else: time_parts

    time_parts =
      if seconds > 0 or time_parts == [], do: time_parts ++ ["#{seconds}s"], else: time_parts

    "#{format_number(ticks)} (#{Enum.join(time_parts, " ")})"
  end

  defp format_timeticks(_), do: "Invalid timeticks"
end
