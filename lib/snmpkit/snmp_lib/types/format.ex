defmodule SnmpKit.SnmpLib.Types.Format do
  @moduledoc """
  Human-readable formatting and parsing helpers for SNMP values: uptime from TimeTicks, IP addresses, byte counts, rates, hex strings. `SnmpKit.SnmpLib.Types` delegates here.
  """

  @doc """
  @spec encode_value(term(), keyword()) :: {:ok, {snmp_type(), term()}} | {:error, atom()}

  @doc \"""
  Formats TimeTicks as human-readable uptime string.

  ## Parameters

  - `centiseconds`: Time in centiseconds (hundredths of a second)

  ## Returns

  - Human-readable uptime string

  ## Examples

      "42 centiseconds" = SnmpKit.SnmpLib.Types.format_timeticks_uptime(42)
      "1 second 50 centiseconds" = SnmpKit.SnmpLib.Types.format_timeticks_uptime(150)
      "1 minute 30 seconds" = SnmpKit.SnmpLib.Types.format_timeticks_uptime(9000)
      "2 hours 15 minutes 30 seconds" = SnmpKit.SnmpLib.Types.format_timeticks_uptime(81300)
  """
  @spec format_timeticks_uptime(non_neg_integer()) :: binary()
  def format_timeticks_uptime(centiseconds) when is_integer(centiseconds) and centiseconds >= 0 do
    total_seconds = div(centiseconds, 100)
    remaining_centiseconds = rem(centiseconds, 100)

    format_time_components(total_seconds, remaining_centiseconds)
  end

  @doc """
  Formats an IP address from binary format.

  ## Examples

      "192.168.1.1" = SnmpKit.SnmpLib.Types.format_ip_address(<<192, 168, 1, 1>>)
      "0.0.0.0" = SnmpKit.SnmpLib.Types.format_ip_address(<<0, 0, 0, 0>>)
  """
  @spec format_ip_address(binary()) :: binary()
  def format_ip_address(<<a, b, c, d>>) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  def format_ip_address(_), do: "invalid"

  @doc """
  Formats bytes as human-readable size.

  ## Examples

      "1.5 KB" = SnmpKit.SnmpLib.Types.format_bytes(1536)
      "2.3 MB" = SnmpKit.SnmpLib.Types.format_bytes(2400000)
  """
  @spec format_bytes(non_neg_integer()) :: binary()
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes < 1024 ->
        "#{bytes} B"

      bytes < 1024 * 1024 ->
        kb = Float.round(bytes / 1024, 1)
        "#{kb} KB"

      bytes < 1024 * 1024 * 1024 ->
        mb = Float.round(bytes / (1024 * 1024), 1)
        "#{mb} MB"

      true ->
        gb = Float.round(bytes / (1024 * 1024 * 1024), 1)
        "#{gb} GB"
    end
  end

  @doc """
  Formats a rate value with units.

  ## Examples

      "100 bps" = SnmpKit.SnmpLib.Types.format_rate(100, "bps")
      "1.5 Mbps" = SnmpKit.SnmpLib.Types.format_rate(1500000, "bps")
  """
  @spec format_rate(number(), binary()) :: binary()
  def format_rate(value, unit) when is_number(value) and is_binary(unit) do
    cond do
      value < 1_000 ->
        "#{value} #{unit}"

      value < 1_000_000 ->
        k_value = Float.round(value / 1_000, 1)
        "#{k_value} K#{unit}"

      value < 1_000_000_000 ->
        m_value = Float.round(value / 1_000_000, 1)
        "#{m_value} M#{unit}"

      true ->
        g_value = Float.round(value / 1_000_000_000, 1)
        "#{g_value} G#{unit}"
    end
  end

  @doc """
  Truncates a string to a maximum length with ellipsis.

  ## Examples

      "hello" = SnmpKit.SnmpLib.Types.truncate_string("hello", 10)
      "hello..." = SnmpKit.SnmpLib.Types.truncate_string("hello world", 8)
  """
  @spec truncate_string(binary(), pos_integer()) :: binary()
  def truncate_string(string, max_length)
      when is_binary(string) and is_integer(max_length) and max_length > 3 do
    if String.length(string) <= max_length do
      string
    else
      truncated = String.slice(string, 0, max_length - 3)
      "#{truncated}..."
    end
  end

  def truncate_string(string, max_length) when is_binary(string) and is_integer(max_length) do
    String.slice(string, 0, max(max_length, 0))
  end

  @doc """
  Formats binary data as hexadecimal string.

  ## Examples

      "48656C6C6F" = SnmpKit.SnmpLib.Types.format_hex(<<"Hello">>)
      "DEADBEEF" = SnmpKit.SnmpLib.Types.format_hex(<<0xDE, 0xAD, 0xBE, 0xEF>>)
  """
  @spec format_hex(binary()) :: binary()
  def format_hex(binary) when is_binary(binary) do
    Base.encode16(binary)
  end

  @doc """
  Parses a hexadecimal string to binary.

  ## Examples

      {:ok, <<"Hello">>} = SnmpKit.SnmpLib.Types.parse_hex_string("48656C6C6F")
      {:error, :invalid_hex} = SnmpKit.SnmpLib.Types.parse_hex_string("XYZ")
  """
  @spec parse_hex_string(binary()) :: {:ok, binary()} | {:error, atom()}
  def parse_hex_string(hex_string) when is_binary(hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_hex}
    end
  end

  @doc """
  Parses an IP address string into a 4-tuple of integers.

  ## Parameters

  - `ip_string`: IP address as a string like "192.168.1.1"

  ## Returns

  - `{:ok, {a, b, c, d}}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, {192, 168, 1, 1}} = SnmpKit.SnmpLib.Types.parse_ip_address("192.168.1.1")
      {:ok, {127, 0, 0, 1}} = SnmpKit.SnmpLib.Types.parse_ip_address("127.0.0.1")
      {:error, :invalid_format} = SnmpKit.SnmpLib.Types.parse_ip_address("invalid")
  """
  @spec parse_ip_address(binary()) :: {:ok, {0..255, 0..255, 0..255, 0..255}} | {:error, atom()}
  def parse_ip_address(ip_string) when is_binary(ip_string) do
    try do
      case :inet.parse_address(String.to_charlist(ip_string)) do
        {:ok, {a, b, c, d}}
        when a >= 0 and a <= 255 and b >= 0 and b <= 255 and
               c >= 0 and c <= 255 and d >= 0 and d <= 255 ->
          {:ok, {a, b, c, d}}

        {:ok, _} ->
          {:error, :not_ipv4}

        {:error, _} ->
          {:error, :invalid_format}
      end
    rescue
      _ -> {:error, :invalid_format}
    end
  end

  def parse_ip_address(_), do: {:error, :invalid_input}

  defp format_time_components(0, 0), do: "0 centiseconds"
  defp format_time_components(0, centiseconds), do: "#{centiseconds} centiseconds"

  defp format_time_components(total_seconds, centiseconds) do
    days = div(total_seconds, 86400)
    remaining_seconds = rem(total_seconds, 86400)
    hours = div(remaining_seconds, 3600)
    remaining_seconds = rem(remaining_seconds, 3600)
    minutes = div(remaining_seconds, 60)
    seconds = rem(remaining_seconds, 60)

    parts = []
    parts = if days > 0, do: ["#{days} day#{plural(days)}" | parts], else: parts
    parts = if hours > 0, do: ["#{hours} hour#{plural(hours)}" | parts], else: parts
    parts = if minutes > 0, do: ["#{minutes} minute#{plural(minutes)}" | parts], else: parts
    parts = if seconds > 0, do: ["#{seconds} second#{plural(seconds)}" | parts], else: parts

    parts =
      if centiseconds > 0,
        do: ["#{centiseconds} centisecond#{plural(centiseconds)}" | parts],
        else: parts

    case Enum.reverse(parts) do
      [] -> "0 centiseconds"
      [single] -> single
      parts -> Enum.join(parts, " ")
    end
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"
end
